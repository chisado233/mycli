import { CliError, ConfigError } from '@jackwener/opencli/errors';

export const BASE_URL = 'https://api.mytokenland.com';
const DEFAULT_USERNAME = 'chisado';
const DEFAULT_TIMEOUT_MS = 30_000;

function env(name) {
  return typeof process !== 'undefined' && process.env ? process.env[name] : undefined;
}

export function getCredentials() {
  const username = env('MYTOKENLAND_USERNAME') || DEFAULT_USERNAME;
  const password = env('MYTOKENLAND_PASSWORD');
  if (!password) {
    throw new ConfigError(
      'Missing MYTOKENLAND_PASSWORD',
      'Set MYTOKENLAND_PASSWORD in the environment before running mytokenland commands. The adapter intentionally does not store passwords in source code.',
    );
  }
  return { username, password };
}

async function parseResponse(resp) {
  const text = await resp.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function responseMessage(data, fallback) {
  if (data && typeof data.message === 'string' && data.message) return data.message;
  if (data && data.error && typeof data.error.message === 'string') return data.error.message;
  return fallback;
}

export async function apiRequest(path, options = {}) {
  const url = path.startsWith('http') ? path : `${BASE_URL}${path}`;
  const resp = await fetch(url, {
    ...options,
    signal: options.signal ?? AbortSignal.timeout(DEFAULT_TIMEOUT_MS),
    headers: {
      Accept: 'application/json',
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers || {}),
    },
  });
  const data = await parseResponse(resp);
  if (!resp.ok) {
    throw new CliError('FETCH_ERROR', `${url} HTTP ${resp.status}`, responseMessage(data, 'Check the endpoint or try again later'));
  }
  return { data, resp };
}

function cookieHeader(resp) {
  if (typeof resp.headers.getSetCookie === 'function') {
    return resp.headers.getSetCookie().map(v => v.split(';')[0]).join('; ');
  }
  const setCookie = resp.headers.get('set-cookie') || '';
  return setCookie.split(/,(?=\s*[^;,=]+=[^;,]+)/).map(v => v.split(';')[0].trim()).filter(Boolean).join('; ');
}

export async function login() {
  const { username, password } = getCredentials();
  const { data, resp } = await apiRequest('/api/user/login', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });

  if (!data.success) {
    throw new CliError('AUTH_FAILED', 'MyTokenLand login failed', responseMessage(data, 'Check MYTOKENLAND_USERNAME and MYTOKENLAND_PASSWORD'));
  }
  if (data.data?.require_2fa) {
    throw new CliError('AUTH_2FA_REQUIRED', 'MyTokenLand login requires 2FA', 'Log in through the website or add a dedicated token-based adapter later.');
  }

  const user = data.data || {};
  const cookie = cookieHeader(resp);
  if (!user.id || !cookie) {
    throw new CliError('AUTH_FAILED', 'MyTokenLand login did not return a usable session', 'The site login response changed; inspect /api/user/login.');
  }

  return { user, cookie };
}

export async function authenticatedRequest(path, options = {}) {
  const session = await login();
  const { data } = await apiRequest(path, {
    ...options,
    headers: {
      Cookie: session.cookie,
      'New-API-User': String(session.user.id),
      ...(options.headers || {}),
    },
  });

  if (data && data.success === false) {
    throw new CliError('API_ERROR', responseMessage(data, 'MyTokenLand API returned success=false'));
  }
  return { data, session };
}

export async function getStatus() {
  const { data } = await apiRequest('/api/status');
  if (!data.success) throw new CliError('API_ERROR', responseMessage(data, 'Failed to load MyTokenLand status'));
  return data.data || {};
}

export function quotaToUsd(quota, quotaPerUnit) {
  const value = Number(quota);
  const unit = Number(quotaPerUnit);
  if (!Number.isFinite(value) || !Number.isFinite(unit) || unit <= 0) return null;
  return value / unit;
}

export function formatUsd(value, digits = 4) {
  if (!Number.isFinite(value)) return '';
  return `$${value.toFixed(digits)}`;
}

export function pricingKind(item) {
  return Number(item?.quota_type) === 1 || Number(item?.model_price || 0) > 0 ? 'fixed' : 'ratio';
}

export function pricingText(item, quotaPerUnit) {
  if (pricingKind(item) === 'fixed') {
    const usd = quotaToUsd(Number(item.model_price || 0), quotaPerUnit);
    return `${item.model_price ?? 0} quota/call${usd == null ? '' : ` (${formatUsd(usd)}/call)`}`;
  }
  const inputRatio = item.model_ratio ?? '';
  const outputRatio = item.completion_ratio ?? '';
  const cacheRatio = item.cache_ratio ?? '';
  return `input ${inputRatio}x, output ${outputRatio}x${cacheRatio !== '' ? `, cache ${cacheRatio}x` : ''}`;
}

export async function getPricingData() {
  const status = await getStatus();
  const { data } = await apiRequest('/api/pricing');
  const items = Array.isArray(data.data) ? data.data : [];
  return { status, items };
}

export function filterItems(items, query, limit) {
  const q = String(query || '').trim().toLowerCase();
  const max = Math.max(1, Math.min(Number(limit) || 50, 1000));
  const filtered = q
    ? items.filter(item => String(item.model_name || item.model || '').toLowerCase().includes(q))
    : items;
  return filtered.slice(0, max);
}
