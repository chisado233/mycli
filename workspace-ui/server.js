const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');
const { spawn } = require('child_process');

const ROOT = __dirname;
const MYCLI_ROOT = path.resolve(ROOT, '..');
const WORKSPACE_ROOT = path.resolve(MYCLI_ROOT, '..', '..');
const CAPABILITY_ROOT = path.join(WORKSPACE_ROOT, 'capability-library');
const PROJECTS_ROOT = path.join(WORKSPACE_ROOT, 'projects');
const PUBLIC_DIR = path.join(ROOT, 'public');
const PORT = Number(process.env.WORKSPACE_UI_PORT || process.argv[2] || 46000);
const MANIFEST_NAMES = new Set(['.agent-ui.json', 'ui.manifest.json']);
const EXCLUDED_DIRS = new Set(['node_modules', '.venv', 'dist', 'build', '.git', 'logs', 'state']);

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

function existsDir(dir) {
  try { return fs.statSync(dir).isDirectory(); } catch { return false; }
}

function safeReaddir(dir) {
  try { return fs.readdirSync(dir, { withFileTypes: true }); } catch { return []; }
}

function toId(input) {
  return String(input).replace(/^[a-zA-Z]:/, '').replace(/[\\/]+/g, '.').replace(/[^a-zA-Z0-9_.-]+/g, '-').replace(/^\.+|\.+$/g, '');
}

function findManifest(dir) {
  for (const name of MANIFEST_NAMES) {
    const file = path.join(dir, name);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

async function checkUrl(url, timeoutMs = 1200) {
  if (!url) return { ok: false, skipped: true };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    return { ok: res.ok, status: res.status };
  } catch (error) {
    return { ok: false, error: error.message || String(error) };
  } finally {
    clearTimeout(timer);
  }
}

function checkPort(port) {
  return new Promise(resolve => {
    if (!port) { resolve(false); return; }
    const socket = net.createConnection({ host: '127.0.0.1', port: Number(port), timeout: 700 });
    socket.on('connect', () => { socket.destroy(); resolve(true); });
    socket.on('timeout', () => { socket.destroy(); resolve(false); });
    socket.on('error', () => resolve(false));
  });
}

function normalizeManifest(raw, manifestPath, nodeDir) {
  if (!raw || typeof raw !== 'object') return null;
  const id = raw.id || toId(path.relative(WORKSPACE_ROOT, nodeDir));
  const url = raw.url || (raw.entry && raw.entry.url) || '';
  const commands = raw.commands || {};
  return {
    ...raw,
    id,
    name: raw.name || path.basename(nodeDir),
    description: raw.description || '',
    type: raw.type || 'workspace-node-ui',
    url,
    commands,
    manifestPath,
    root: raw.root || nodeDir
  };
}

function directoryNode({ id, name, kind, fullPath, relPath, children = [] }) {
  const manifestPath = findManifest(fullPath);
  const manifest = manifestPath ? normalizeManifest(readJson(manifestPath), manifestPath, fullPath) : null;
  return {
    id,
    name,
    kind,
    path: fullPath,
    relPath,
    hasUi: Boolean(manifest),
    manifest,
    children
  };
}

function buildMycliTree() {
  const utilityDirs = new Set(['scripts', 'public', 'state', 'logs', 'tasks', 'config', 'docs', 'tmp', 'references', 'agents', 'source']);
  function walk(dir, relParts, depth) {
    const name = relParts.length ? relParts[relParts.length - 1] : 'mycli';
    const relPath = path.relative(WORKSPACE_ROOT, dir);
    const children = [];
    if (depth < 5) {
      for (const ent of safeReaddir(dir)) {
        if (!ent.isDirectory() || EXCLUDED_DIRS.has(ent.name)) continue;
        const childDir = path.join(dir, ent.name);
        const hasPackage = fs.existsSync(path.join(childDir, 'cli.package.json'));
        const hasManifest = Boolean(findManifest(childDir));
        if (!hasPackage && !hasManifest && utilityDirs.has(ent.name)) continue;
        if (!hasPackage && !hasManifest && depth > 1) continue;
        children.push(walk(childDir, [...relParts, ent.name], depth + 1));
      }
    }
    children.sort((a, b) => Number(b.hasUi) - Number(a.hasUi) || a.name.localeCompare(b.name));
    return directoryNode({ id: `mycli:${relParts.join('/') || 'root'}`, name, kind: 'mycli-package', fullPath: dir, relPath, children });
  }
  return walk(MYCLI_ROOT, [], 0);
}

function buildProjectsTree() {
  const children = safeReaddir(PROJECTS_ROOT)
    .filter(ent => ent.isDirectory() && !EXCLUDED_DIRS.has(ent.name))
    .map(ent => {
      const dir = path.join(PROJECTS_ROOT, ent.name);
      return directoryNode({
        id: `project:${ent.name}`,
        name: ent.name,
        kind: 'project',
        fullPath: dir,
        relPath: path.relative(WORKSPACE_ROOT, dir),
        children: []
      });
    })
    .sort((a, b) => Number(b.hasUi) - Number(a.hasUi) || a.name.localeCompare(b.name));
  return directoryNode({ id: 'projects:root', name: 'projects', kind: 'project-root', fullPath: PROJECTS_ROOT, relPath: 'projects', children });
}

function buildTree() {
  return directoryNode({
    id: 'workspace:root',
    name: 'agent-workspace',
    kind: 'workspace',
    fullPath: WORKSPACE_ROOT,
    relPath: '.',
    children: [
      directoryNode({
        id: 'capability-library:root',
        name: 'capability-library',
        kind: 'capability-root',
        fullPath: CAPABILITY_ROOT,
        relPath: 'capability-library',
        children: [buildMycliTree()]
      }),
      buildProjectsTree()
    ]
  });
}

function flatten(node, map = new Map()) {
  map.set(node.id, node);
  for (const child of node.children || []) flatten(child, map);
  return map;
}

function mycliPath() {
  return path.join(MYCLI_ROOT, 'mycli.ps1');
}

function commandToSpawn(command, cwd) {
  if (Array.isArray(command)) {
    return {
      file: 'pwsh.exe',
      args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', mycliPath(), ...command.map(String)],
      cwd: cwd || MYCLI_ROOT
    };
  }
  if (typeof command === 'string') {
    const trimmed = command.trim();
    if (/^mycli(\.ps1|\.cmd)?\s+/i.test(trimmed)) {
      return { file: 'pwsh.exe', args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', trimmed], cwd: cwd || MYCLI_ROOT };
    }
    return { file: 'pwsh.exe', args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', trimmed], cwd: cwd || WORKSPACE_ROOT };
  }
  return null;
}

function runCommand(command, cwd) {
  return new Promise(resolve => {
    const spec = commandToSpawn(command, cwd);
    if (!spec) { resolve({ ok: false, code: -1, output: 'missing command' }); return; }
    const child = spawn(spec.file, spec.args, { cwd: spec.cwd, windowsHide: true });
    let output = '';
    child.stdout.on('data', d => output += d.toString('utf8'));
    child.stderr.on('data', d => output += d.toString('utf8'));
    child.on('error', error => resolve({ ok: false, code: -1, output: error.message || String(error) }));
    child.on('close', code => resolve({ ok: code === 0, code, output }));
  });
}

async function enrichNode(node) {
  const copy = JSON.parse(JSON.stringify(node));
  if (copy.manifest) {
    const healthUrl = copy.manifest.health && copy.manifest.health.url;
    const urlHealth = await checkUrl(healthUrl || copy.manifest.url);
    let portOpen = false;
    try {
      const u = copy.manifest.url ? new URL(copy.manifest.url) : null;
      portOpen = u ? await checkPort(u.port || (u.protocol === 'https:' ? 443 : 80)) : false;
    } catch {}
    copy.uiStatus = { online: Boolean(urlHealth.ok || portOpen), health: urlHealth, portOpen };
  }
  return copy;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString('utf8');
      if (body.length > 1024 * 1024) { reject(new Error('request body too large')); req.destroy(); }
    });
    req.on('end', () => {
      if (!body.trim()) { resolve({}); return; }
      try { resolve(JSON.parse(body)); } catch (error) { reject(error); }
    });
    req.on('error', reject);
  });
}

function contentType(file) {
  if (file.endsWith('.html')) return 'text/html; charset=utf-8';
  if (file.endsWith('.css')) return 'text/css; charset=utf-8';
  if (file.endsWith('.js')) return 'application/javascript; charset=utf-8';
  if (file.endsWith('.json')) return 'application/json; charset=utf-8';
  if (file.endsWith('.svg')) return 'image/svg+xml; charset=utf-8';
  return 'application/octet-stream';
}

function sendJson(res, status, data) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(data));
}

async function handleApi(req, res, url) {
  const tree = buildTree();
  const nodeMap = flatten(tree);
  if (url.pathname === '/api/tree') { sendJson(res, 200, { generatedAt: new Date().toISOString(), tree }); return; }
  if (url.pathname === '/api/snapshot') {
    const nodes = [...nodeMap.values()];
    sendJson(res, 200, { generatedAt: new Date().toISOString(), totalNodes: nodes.length, uiNodes: nodes.filter(n => n.hasUi).length, tree });
    return;
  }
  const nodeMatch = url.pathname.match(/^\/api\/nodes\/([^/]+)(?:\/(start|stop|open|refresh))?$/);
  if (nodeMatch) {
    const id = decodeURIComponent(nodeMatch[1]);
    const action = nodeMatch[2];
    const node = nodeMap.get(id);
    if (!node) { sendJson(res, 404, { ok: false, error: 'node not found' }); return; }
    if (!action || req.method === 'GET') { sendJson(res, 200, { ok: true, node: await enrichNode(node) }); return; }
    if (req.method !== 'POST') { sendJson(res, 405, { ok: false, error: 'method not allowed' }); return; }
    await readBody(req).catch(() => ({}));
    if (!node.manifest) { sendJson(res, 400, { ok: false, error: 'node has no UI manifest' }); return; }
    if (action === 'refresh') { sendJson(res, 200, { ok: true, node: await enrichNode(node) }); return; }
    if (action === 'open' && !node.manifest.commands.open) {
      sendJson(res, 200, { ok: true, openedBy: 'browser', url: node.manifest.url, node: await enrichNode(node) });
      return;
    }
    const command = node.manifest.commands && node.manifest.commands[action];
    if (!command) { sendJson(res, 400, { ok: false, error: `missing ${action} command` }); return; }
    const result = await runCommand(command, node.manifest.cwd || node.path);
    const enriched = await enrichNode(node);
    sendJson(res, 200, { ok: result.ok, action, result, url: node.manifest.url, node: enriched });
    return;
  }
  sendJson(res, 404, { ok: false, error: 'api not found' });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname.startsWith('/api/')) {
    try { await handleApi(req, res, url); } catch (error) { sendJson(res, 500, { ok: false, error: error.message || String(error) }); }
    return;
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

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Workspace UI: http://127.0.0.1:${PORT}`);
});
