const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const PUBLIC_DIR = path.join(__dirname, 'public');
const PORT = Number(process.env.CHANNEL_MONITOR_PORT || process.argv[2] || 45990);

const CHANNELS = [
  {
    id: 'qq',
    name: 'QQ',
    kind: 'NapCat OneBot',
    root: path.join(ROOT, 'QQ'),
    pidFile: path.join(ROOT, 'QQ', 'state', 'qq-channel-pids.json'),
    logs: {
      bridge: path.join(ROOT, 'QQ', 'logs', 'bridge.detached.out.log'),
      bridgeLegacy: path.join(ROOT, 'QQ', 'logs', 'qq-bridge.log'),
      napcat: path.join(ROOT, 'QQ', 'logs', 'napcat.detached.out.log'),
      bridgeErr: path.join(ROOT, 'QQ', 'logs', 'bridge.detached.err.log'),
      napcatErr: path.join(ROOT, 'QQ', 'logs', 'napcat.detached.err.log')
    },
    ports: [3001, 6099],
    statusCommand: ['channels', 'QQ', 'status-detached'],
    startCommand: ['channels', 'QQ', 'start-detached'],
    stopCommand: ['channels', 'QQ', 'stop-detached'],
    configFile: path.join(ROOT, 'QQ', 'bridge.config.json'),
    configEditableKeys: ['napcatWsUrl', 'token', 'wakeWord', 'closeWord', 'newSessionWord', 'agent', 'model', 'cwd', 'sessionName', 'returnMode', 'cooldownMs', 'maxPromptChars', 'agentTimeoutMs', 'requireWakePrefix', 'continuousAfterWake', 'defaultGroup', 'defaultPrivateUser', 'ackMessage', 'directReply', 'botQQ', 'maxGroupContextMessages', 'maxGroupBufferMessages'],
    notes: ['QQ 启动后如果不是已登录状态，需要在弹出的 QQ/NapCat 登录窗口扫码。', '扫码登录完成后本界面的 3001 / 6099 状态会变为可用。']
  },
  {
    id: 'chat-soft',
    name: 'Chat Soft',
    kind: 'Mobile / cloud / local agent',
    root: path.join(ROOT, 'chat-soft'),
    pidFile: path.join(ROOT, 'chat-soft', 'state', 'chat-soft-pids.json'),
    logs: {
      stdout: path.join(ROOT, 'chat-soft', 'logs', 'local-agent.detached.out.log'),
      stderr: path.join(ROOT, 'chat-soft', 'logs', 'local-agent.detached.err.log')
    },
    ports: [45888],
    healthUrls: ['http://127.0.0.1:45888/health', 'http://39.106.125.149:3000/health'],
    apiBase: 'http://39.106.125.149:3000',
    localAgentBase: 'http://127.0.0.1:45888',
    statusCommand: ['channels', 'chat-soft', 'status-detached'],
    startCommand: ['channels', 'chat-soft', 'start-detached'],
    stopCommand: ['channels', 'chat-soft', 'stop-detached'],
    configFile: null,
    configEditableKeys: [],
    notes: ['Chat Soft stop 只会停止本机 local agent bridge，不会停止云服务器服务。']
  }
];

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

function fileMtime(file) {
  try { return fs.statSync(file).mtime.toISOString(); } catch { return null; }
}

function tail(file, maxBytes = 256 * 1024) {
  try {
    const stat = fs.statSync(file);
    const start = Math.max(0, stat.size - maxBytes);
    const fd = fs.openSync(file, 'r');
    const buf = Buffer.alloc(stat.size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    fs.closeSync(fd);
    return buf.toString('utf8');
  } catch {
    return '';
  }
}

function ansiStrip(text) {
  return String(text || '').replace(/\x1b\[[0-9;]*m/g, '');
}

function parseTimestamp(line) {
  const iso = line.match(/^\[([^\]]+)\]/);
  if (iso) return iso[1];
  const nap = line.match(/^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s/);
  if (nap) return nap[1];
  return '';
}

function qqConversationId(item) {
  if (item.group_id) return `group:${item.group_id}`;
  if (item.user_id) return `private:${item.user_id}`;
  return 'system:qq';
}

function qqConversationTitle(item) {
  if (item.group_id) return `群 ${item.group_id}`;
  if (item.user_id) return `私聊 ${item.user_id}`;
  return 'QQ 系统';
}

function parseParenId(text) {
  return (String(text || '').match(/\((\d+)\)/) || [])[1] || String(text || '');
}

function qqDirectionFromSender(sender) {
  const text = String(sender || '');
  return /酒寄彩叶|彩叶|3279329186/.test(text) ? 'out' : 'in';
}

function parseQqBridgeLog() {
  const files = [CHANNELS[0].logs.bridge, CHANNELS[0].logs.bridgeLegacy];
  const messages = [];
  const events = [];
  const seen = new Set();
  for (const file of files) {
    const lines = tail(file).split(/\r?\n/).filter(Boolean);
    for (const rawLine of lines) {
      const line = ansiStrip(rawLine);
      const ts = parseTimestamp(line);
      const jsonMatch = line.match(/Accepted message\s+(\{.*\})/);
      if (jsonMatch) {
        try {
          const item = JSON.parse(jsonMatch[1]);
          const key = `bridge:${ts}:${item.message_type || ''}:${item.user_id || ''}:${item.group_id || ''}:${item.prompt || ''}`;
          if (seen.has(key)) continue;
          seen.add(key);
          messages.push({
            id: `qq:${ts}:${messages.length}`,
            channelId: 'qq',
            conversationId: `qq:${qqConversationId(item)}`,
            conversationTitle: qqConversationTitle(item),
            direction: 'in',
            sender: item.user_id ? String(item.user_id) : 'unknown',
            time: ts,
            text: item.prompt || item.promptPreview || '[message]',
            raw: item
          });
          continue;
        } catch {}
      }
      if (/Connected to NapCat|websocket closed|websocket error|Cannot send action|Agent exited|Agent error|Starting agent/.test(line)) {
        events.push({ id: `qq-event:${ts}:${events.length}`, channelId: 'qq', time: ts, text: line.replace(/^\[[^\]]+\]\s*/, '') });
      }
    }
  }

  const napLines = tail(CHANNELS[0].logs.napcat).split(/\r?\n/).filter(Boolean);
  for (const rawLine of napLines) {
    const line = ansiStrip(rawLine);
    const m = line.match(/^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}).*?\|\s+(?:(接收\s+<-|发送\s+->)\s+)?(群聊|私聊)\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s*(.*)$/);
    if (!m) continue;
    const verb = m[2] || '';
    const type = m[3];
    const groupOrUser = m[4];
    const sender = m[5];
    const text = m[6] || '[媒体/事件]';
    const idNum = parseParenId(groupOrUser);
    const direction = verb.startsWith('发送') ? 'out' : (verb.startsWith('接收') ? 'in' : qqDirectionFromSender(sender));
    const key = `napcat:${m[1]}:${verb}:${idNum}:${sender}:${text}`;
    if (seen.has(key)) continue;
    seen.add(key);
    messages.push({
      id: `qq-napcat:${m[1]}:${messages.length}`,
      channelId: 'qq',
      conversationId: `qq:${type === '群聊' ? 'group' : 'private'}:${idNum}`,
      conversationTitle: groupOrUser,
      direction,
      sender,
      time: m[1],
      text
    });
  }
  return { messages, events };
}

function textForChatSoftMessage(message) {
  if (!message) return '';
  if (message.kind === 'text') return message.text || '';
  return `[${message.kind}] ${message.fileName || message.mediaUrl || ''}`.trim();
}

async function fetchJson(url, timeoutMs = 2500) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    return { ok: res.ok, status: res.status, data };
  } catch (error) {
    return { ok: false, error: error.message || String(error) };
  } finally {
    clearTimeout(timer);
  }
}

async function chatSoftMessages() {
  const bases = ['http://127.0.0.1:45888', 'http://39.106.125.149:3000'];
  let conversations = [];
  let messages = [];
  for (const base of bases) {
    const recent = await fetchJson(`${base}/api/messages/recent`, 1800);
    if (recent.ok && recent.data && Array.isArray(recent.data.messages)) {
      messages = recent.data.messages;
      const conv = await fetchJson(`${base}/api/conversations`, 1800);
      if (conv.ok && conv.data && Array.isArray(conv.data.conversations)) conversations = conv.data.conversations;
      break;
    }
  }
  const convMap = new Map(conversations.map(c => [c.conversationId, c]));
  return messages.map((message, index) => {
    const conv = convMap.get(message.conversationId) || {};
    const isAgent = String(message.senderDeviceId || '').includes('agent') || String(message.senderDeviceId || '').includes('assistant');
    return {
      id: `chat-soft:${message.id || index}`,
      channelId: 'chat-soft',
      conversationId: `chat-soft:${message.conversationId || 'primary'}`,
      conversationTitle: conv.title || message.conversationId || 'Chat Soft',
      direction: isAgent ? 'out' : 'in',
      sender: message.senderDeviceId || 'device',
      time: message.createdAt || '',
      status: message.status || '',
      text: textForChatSoftMessage(message),
      raw: message
    };
  });
}

function pidAlive(pid) {
  if (!pid) return false;
  try { process.kill(Number(pid), 0); return true; } catch { return false; }
}

function checkPort(port) {
  return new Promise(resolve => {
    const socket = require('net').createConnection({ host: '127.0.0.1', port, timeout: 700 });
    socket.on('connect', () => { socket.destroy(); resolve(true); });
    socket.on('timeout', () => { socket.destroy(); resolve(false); });
    socket.on('error', () => resolve(false));
  });
}

async function channelStatus(channel) {
  const pidState = readJson(channel.pidFile);
  const ports = {};
  for (const port of channel.ports || []) ports[port] = await checkPort(port);
  const health = {};
  for (const url of channel.healthUrls || []) health[url] = await fetchJson(url, 1600);
  const pidValues = Object.entries(pidState || {}).filter(([key, value]) => /pid/i.test(key) && Number(value));
  const processes = Object.fromEntries(pidValues.map(([key, value]) => [key, { pid: value, alive: pidAlive(value) }]));
  const logMtimes = Object.fromEntries(Object.entries(channel.logs || {}).map(([key, file]) => [key, fileMtime(file)]));
  const hasGoodPort = Object.values(ports).some(Boolean);
  const hasGoodHealth = Object.values(health).some(item => item && item.ok);
  const hasAlivePid = Object.values(processes).some(item => item.alive);
  return {
    id: channel.id,
    name: channel.name,
    kind: channel.kind,
    hasConfig: Boolean(channel.configFile),
    notes: channel.notes || [],
    online: hasGoodPort || hasGoodHealth || hasAlivePid,
    pidState,
    processes,
    ports,
    health,
    logMtimes
  };
}

function mycliPath() {
  return path.resolve(ROOT, '..', 'mycli.ps1');
}

function runMycli(args, extraArgs = []) {
  return new Promise((resolve) => {
    const child = spawn('pwsh.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', mycliPath(), ...args, ...extraArgs], {
      cwd: path.resolve(ROOT, '..'),
      windowsHide: false,
      detached: true
    });
    let output = '';
    child.stdout.on('data', d => output += d.toString('utf8'));
    child.stderr.on('data', d => output += d.toString('utf8'));
    child.on('error', error => resolve({ code: -1, output: error.message || String(error) }));
    child.on('close', code => resolve({ code, output }));
  });
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString('utf8');
      if (body.length > 1024 * 1024) {
        reject(new Error('request body too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!body.trim()) { resolve({}); return; }
      try { resolve(JSON.parse(body)); } catch (error) { reject(error); }
    });
    req.on('error', reject);
  });
}

function publicConfig(channel) {
  if (!channel.configFile) return null;
  const data = readJson(channel.configFile) || {};
  const values = {};
  for (const key of channel.configEditableKeys || []) values[key] = data[key];
  return { channelId: channel.id, path: channel.configFile, values, editableKeys: channel.configEditableKeys || [] };
}

function savePublicConfig(channel, nextValues) {
  if (!channel.configFile) throw new Error('this channel has no editable config');
  const current = readJson(channel.configFile) || {};
  const allowed = new Set(channel.configEditableKeys || []);
  for (const [key, value] of Object.entries(nextValues || {})) {
    if (!allowed.has(key)) continue;
    current[key] = value;
  }
  fs.writeFileSync(channel.configFile, `${JSON.stringify(current, null, 2)}\n`, 'utf8');
  return publicConfig(channel);
}

function conversationsFromMessages(messages) {
  const map = new Map();
  for (const msg of messages) {
    const id = msg.conversationId || `${msg.channelId}:default`;
    const current = map.get(id) || { id, channelId: msg.channelId, title: msg.conversationTitle || id, lastText: '', lastTime: '', unread: 0, count: 0 };
    current.lastText = msg.text || current.lastText;
    current.lastTime = msg.time || current.lastTime;
    current.count += 1;
    if (msg.direction === 'in') current.unread += 1;
    map.set(id, current);
  }
  return [...map.values()].sort((a, b) => String(b.lastTime).localeCompare(String(a.lastTime)));
}

function channelGroups(channels, conversations) {
  return channels.map(channel => ({
    id: channel.id,
    name: channel.name,
    kind: channel.kind,
    online: channel.online,
    conversations: conversations.filter(conv => conv.channelId === channel.id)
  }));
}

async function snapshot() {
  const qq = parseQqBridgeLog();
  const chatMessages = await chatSoftMessages();
  const messages = [...qq.messages, ...chatMessages].sort((a, b) => String(a.time).localeCompare(String(b.time))).slice(-500);
  const statuses = [];
  for (const channel of CHANNELS) statuses.push(await channelStatus(channel));
  const conversations = conversationsFromMessages(messages);
  return { generatedAt: new Date().toISOString(), channels: statuses, channelGroups: channelGroups(statuses, conversations), conversations, messages, events: qq.events.slice(-80) };
}

function contentType(file) {
  if (file.endsWith('.html')) return 'text/html; charset=utf-8';
  if (file.endsWith('.css')) return 'text/css; charset=utf-8';
  if (file.endsWith('.js')) return 'application/javascript; charset=utf-8';
  if (file.endsWith('.json')) return 'application/json; charset=utf-8';
  return 'application/octet-stream';
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === '/api/snapshot') {
    const data = await snapshot();
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    res.end(JSON.stringify(data));
    return;
  }
  if (url.pathname === '/api/channel-action' && req.method === 'POST') {
    try {
      const body = await readRequestBody(req);
      const channel = CHANNELS.find(item => item.id === body.channelId);
      const action = String(body.action || '');
      if (!channel || !['start', 'stop', 'restart'].includes(action)) {
        res.writeHead(400, { 'content-type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ ok: false, error: 'invalid channel/action' }));
        return;
      }
      const outputs = [];
      if (action === 'stop' || action === 'restart') outputs.push({ action: 'stop', ...(await runMycli(channel.stopCommand || [])) });
      if (action === 'start' || action === 'restart') {
        const extraArgs = [];
        if (channel.id === 'qq' && body.qq) extraArgs.push(String(body.qq));
        outputs.push({ action: 'start', ...(await runMycli(channel.startCommand || [], extraArgs)) });
      }
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: outputs.every(item => item.code === 0), outputs }));
    } catch (error) {
      res.writeHead(500, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: false, error: error.message || String(error) }));
    }
    return;
  }
  if (url.pathname === '/api/channel-config') {
    const channel = CHANNELS.find(item => item.id === url.searchParams.get('channel'));
    if (!channel) { res.writeHead(404); res.end('not found'); return; }
    if (req.method === 'GET') {
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, config: publicConfig(channel) }));
      return;
    }
    if (req.method === 'POST') {
      try {
        const body = await readRequestBody(req);
        const config = savePublicConfig(channel, body.values || {});
        res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ ok: true, config }));
      } catch (error) {
        res.writeHead(500, { 'content-type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ ok: false, error: error.message || String(error) }));
      }
      return;
    }
  }
  if (url.pathname === '/api/run-status') {
    const channel = CHANNELS.find(item => item.id === url.searchParams.get('channel'));
    if (!channel) { res.writeHead(404); res.end('not found'); return; }
    const mycli = mycliPath();
    const child = spawn('pwsh.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', mycli, ...channel.statusCommand], { cwd: path.resolve(ROOT, '..'), windowsHide: true });
    let out = '';
    child.stdout.on('data', d => out += d.toString('utf8'));
    child.stderr.on('data', d => out += d.toString('utf8'));
    child.on('close', code => {
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ code, output: out }));
    });
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
  console.log(`Channel monitor UI: http://127.0.0.1:${PORT}`);
});
