const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = __dirname;
const PACKAGE_ROOT = path.resolve(ROOT, '..');
const MYCLI_ROOT = path.resolve(PACKAGE_ROOT, '..');
const PUBLIC_DIR = path.join(ROOT, 'public');
const PORT = Number(process.env.CRON_UI_PORT || process.argv[2] || 46010);

function mycliPath() { return path.join(MYCLI_ROOT, 'mycli.ps1'); }

function runMycli(args) {
  return new Promise(resolve => {
    const child = spawn('pwsh.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', mycliPath(), ...args], { cwd: MYCLI_ROOT, windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', d => stdout += d.toString('utf8'));
    child.stderr.on('data', d => stderr += d.toString('utf8'));
    child.on('error', error => resolve({ ok: false, code: -1, stdout, stderr: error.message || String(error) }));
    child.on('close', code => resolve({ ok: code === 0, code, stdout, stderr }));
  });
}

function parseJsonOutput(text, fallback) {
  const trimmed = String(text || '').trim();
  if (!trimmed) return fallback;
  try { return JSON.parse(trimmed); } catch { return fallback; }
}

function arrayify(value) {
  if (Array.isArray(value)) return value;
  if (value === null || typeof value === 'undefined' || value === '') return [];
  return [value];
}

async function taskList() {
  const result = await runMycli(['cron', 'task-list', '--json']);
  const items = arrayify(parseJsonOutput(result.stdout, []));
  return { result, items };
}

async function taskDetail(id) {
  const [show, logs] = await Promise.all([
    runMycli(['cron', 'show', id]),
    runMycli(['cron', 'logs', id, '--last', '8'])
  ]);
  return { task: parseJsonOutput(show.stdout, null), logs: logs.stdout || logs.stderr || '', show, logsResult: logs };
}

async function snapshot() {
  const list = await taskList();
  const items = list.items;
  const counts = {
    total: items.length,
    enabled: items.filter(t => t.status === 'enabled').length,
    disabled: items.filter(t => t.status === 'disabled').length,
    temp: items.filter(t => t.kind === 'temp').length,
    persistent: items.filter(t => t.kind === 'persistent').length,
    failedLastRun: items.filter(t => Number(t.lastExitCode) > 0).length
  };
  return { generatedAt: new Date().toISOString(), counts, tasks: items, raw: list.result.ok ? null : list.result };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk.toString('utf8'); if (body.length > 1024 * 1024) reject(new Error('request body too large')); });
    req.on('end', () => { try { resolve(body.trim() ? JSON.parse(body) : {}); } catch (error) { reject(error); } });
    req.on('error', reject);
  });
}

function sendJson(res, status, data) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(data));
}

function contentType(file) {
  if (file.endsWith('.html')) return 'text/html; charset=utf-8';
  if (file.endsWith('.css')) return 'text/css; charset=utf-8';
  if (file.endsWith('.js')) return 'application/javascript; charset=utf-8';
  return 'application/octet-stream';
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === '/api/snapshot') { sendJson(res, 200, await snapshot()); return; }
  const taskMatch = url.pathname.match(/^\/api\/tasks\/([^/]+)(?:\/(show|logs|enable|disable|run))?$/);
  if (taskMatch) {
    const id = decodeURIComponent(taskMatch[1]);
    const action = taskMatch[2] || 'show';
    try {
      if (req.method === 'POST') await readBody(req);
      if (action === 'show' && req.method === 'GET') { sendJson(res, 200, { ok: true, ...(await taskDetail(id)) }); return; }
      if (action === 'logs' && req.method === 'GET') { const logs = await runMycli(['cron', 'logs', id, '--last', '12']); sendJson(res, 200, { ok: logs.ok, output: logs.stdout || logs.stderr, result: logs }); return; }
      if (req.method !== 'POST') { sendJson(res, 405, { ok: false, error: 'method not allowed' }); return; }
      if (!['enable', 'disable', 'run'].includes(action)) { sendJson(res, 400, { ok: false, error: 'invalid action' }); return; }
      const result = await runMycli(['cron', action, id]);
      sendJson(res, 200, { ok: result.ok, action, result, snapshot: await snapshot() });
      return;
    } catch (error) { sendJson(res, 500, { ok: false, error: error.message || String(error) }); return; }
  }
  const pathname = url.pathname === '/' ? '/index.html' : url.pathname;
  const file = path.normalize(path.join(PUBLIC_DIR, pathname));
  if (!file.startsWith(PUBLIC_DIR)) { res.writeHead(403); res.end('forbidden'); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': contentType(file) });
    res.end(data);
  });
});

server.listen(PORT, '127.0.0.1', () => console.log(`Cron UI: http://127.0.0.1:${PORT}`));
