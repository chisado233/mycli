const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = __dirname;
const PACKAGE_ROOT = path.resolve(ROOT, '..');
const MYCLI_ROOT = path.resolve(PACKAGE_ROOT, '..');
const PUBLIC_DIR = path.join(ROOT, 'public');
const PORT = Number(process.env.AGENT_CLI_UI_PORT || process.argv[2] || 46030);
const RUNS_DIR = 'D:\\agent_workspace\\var\\mycli\\agent-cli\\runs';

function mycliPath() { return path.join(MYCLI_ROOT, 'mycli.ps1'); }

function runMycli(args) {
  return new Promise(resolve => {
    const child = spawn('pwsh.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', mycliPath(), ...args], { cwd: 'D:\\agent_workspace', windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', d => stdout += d.toString('utf8'));
    child.stderr.on('data', d => stderr += d.toString('utf8'));
    child.on('error', error => resolve({ ok: false, code: -1, stdout, stderr: error.message || String(error) }));
    child.on('close', code => resolve({ ok: code === 0, code, stdout, stderr }));
  });
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

function writeSse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

async function snapshot() {
  const agents = await runMycli(['agent-cli', 'agents']);
  const current = await runMycli(['agent-cli', 'current']);
  return {
    generatedAt: new Date().toISOString(),
    defaultAgent: 'remote-opencode/private-assistant',
    defaultCwd: 'D:\\agent_workspace',
    agentsText: agents.stdout || agents.stderr || '',
    currentText: current.stdout || current.stderr || '',
    ok: agents.ok && current.ok
  };
}

function parseAgents(text) {
  const agents = [];
  for (const line of String(text || '').split(/\r?\n/)) {
    const match = line.match(/^\s*[* ]\s+([^\s].*?\/[^\s]+.*?)\s*$/);
    if (match) agents.push(match[1].trim());
  }
  return [...new Set(agents)].sort((a, b) => a.localeCompare(b));
}

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

function recentSessions() {
  if (!fs.existsSync(RUNS_DIR)) return [];
  const items = [];
  for (const name of fs.readdirSync(RUNS_DIR)) {
    if (!name.endsWith('.meta.json')) continue;
    const meta = readJson(path.join(RUNS_DIR, name));
    if (!meta || !meta.session_id) continue;
    items.push({
      sessionId: meta.session_id,
      agent: meta.agent || '',
      source: meta.source || '',
      prompt: meta.prompt || '',
      status: meta.status || '',
      startedAt: meta.started_at_utc || '',
      finishedAt: meta.finished_at_utc || '',
      round: meta.round || 1
    });
  }
  const byId = new Map();
  for (const item of items.sort((a, b) => String(a.startedAt).localeCompare(String(b.startedAt)))) byId.set(item.sessionId, item);
  return [...byId.values()].sort((a, b) => String(b.startedAt).localeCompare(String(a.startedAt))).slice(0, 30);
}

async function options() {
  const agents = await runMycli(['agent-cli', 'agents']);
  const current = await runMycli(['agent-cli', 'current']);
  const agentNames = parseAgents(agents.stdout || agents.stderr || '');
  if (!agentNames.includes('remote-opencode/private-assistant')) agentNames.unshift('remote-opencode/private-assistant');
  return {
    generatedAt: new Date().toISOString(),
    agents: agentNames,
    currentAgent: (current.stdout || '').split(/\r?\n/)[0].trim() || 'remote-opencode/private-assistant',
    models: ['MoreCode/gpt-5.5', 'MoreCode/gpt-5.4', 'MoreCode/gpt-5.4-A', 'MoreCode/gemini-3-flash', ''],
    sessions: recentSessions(),
    defaultCwd: 'D:\\agent_workspace'
  };
}

function normalizeOpenCodeEvent(line) {
  try {
    const parsed = JSON.parse(line);
    if (parsed && parsed.type === 'text' && parsed.part && typeof parsed.part.text === 'string') {
      return { kind: 'assistant_text', text: parsed.part.text, raw: parsed };
    }
    if (parsed && parsed.type) return { kind: String(parsed.type), raw: parsed };
    return { kind: 'json', raw: parsed };
  } catch {
    return { kind: 'raw', text: line };
  }
}

function streamRun(req, res) {
  readBody(req).then(body => {
    const agent = body.agent || 'remote-opencode/private-assistant';
    const cwd = body.cwd || 'D:\\agent_workspace';
    const prompt = body.prompt || '';
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', mycliPath(), 'agent-cli', 'run', '--agent', agent, '--cwd', cwd, '--return_mode', 'stream'];
    if (body.model) args.push('--model', String(body.model));
    if (body.sessionName) args.push('--session_name', String(body.sessionName));
    if (body.session) args.push('--session', String(body.session));
    if (body.continueSession) args.push('--continue');
    if (body.fork) args.push('--fork');
    if (prompt) args.push('--prompt', String(prompt));

    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store',
      connection: 'keep-alive',
      'x-accel-buffering': 'no'
    });
    writeSse(res, 'start', { agent, cwd, command: ['pwsh.exe', ...args] });
    const child = spawn('pwsh.exe', args, { cwd: 'D:\\agent_workspace', windowsHide: true });
    let buffer = '';
    let sessionId = '';
    function onText(chunk, streamName) {
      buffer += chunk.toString('utf8');
      const parts = buffer.split(/\r?\n/);
      buffer = parts.pop() || '';
      for (const line of parts) {
        if (!line) continue;
        const normalized = normalizeOpenCodeEvent(line);
        if (normalized.raw && normalized.raw.sessionID && !sessionId) sessionId = normalized.raw.sessionID;
        writeSse(res, streamName === 'stderr' ? 'stderr' : 'event', { line, normalized });
      }
    }
    child.stdout.on('data', d => onText(d, 'stdout'));
    child.stderr.on('data', d => onText(d, 'stderr'));
    child.on('error', error => writeSse(res, 'error', { error: error.message || String(error) }));
    child.on('close', code => { if (buffer) writeSse(res, 'event', { line: buffer, normalized: normalizeOpenCodeEvent(buffer) }); writeSse(res, 'done', { code, sessionId }); res.end(); });
    req.on('close', () => { if (!child.killed) child.kill(); });
  }).catch(error => sendJson(res, 400, { ok: false, error: error.message || String(error) }));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (url.pathname === '/api/snapshot') { sendJson(res, 200, await snapshot()); return; }
    if (url.pathname === '/api/options') { sendJson(res, 200, await options()); return; }
    if (url.pathname === '/api/run' && req.method === 'POST') { streamRun(req, res); return; }
    const pathname = url.pathname === '/' ? '/index.html' : url.pathname;
    const file = path.normalize(path.join(PUBLIC_DIR, pathname));
    if (!file.startsWith(PUBLIC_DIR)) { res.writeHead(403); res.end('forbidden'); return; }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, { 'content-type': contentType(file) });
      res.end(data);
    });
  } catch (error) {
    sendJson(res, 500, { ok: false, error: error.message || String(error) });
  }
});

server.listen(PORT, '127.0.0.1', () => console.log(`Agent CLI UI: http://127.0.0.1:${PORT}`));
