const WebSocket = require('ws');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const STATE_DIR = path.join(ROOT, 'state');
const LOG_DIR = path.join(ROOT, 'logs');
const LOG_FILE = path.join(LOG_DIR, 'qq-bridge.log');
const CONFIG_FILE = path.join(ROOT, 'bridge.config.json');

const DEFAULT_CONFIG = {
  napcatWsUrl: 'ws://127.0.0.1:3001',
  token: 'chisado',
  wakeWord: '彩叶',
  closeWord: 'close',
  newSessionWord: 'new session',
  agent: 'opencode/private-assistant',
  model: 'MoreCode/gpt-5.4-nano',
  directReply: true,
  cwd: 'D:\\agent_workspace',
  mycli: 'D:\\agent_workspace\\capability-library\\mycli\\mycli.ps1',
  sessionName: 'qq-caiye-channel',
  returnMode: 'silent',
  cooldownMs: 1000,
  maxPromptChars: 6000,
  agentTimeoutMs: 120000,
  requireWakePrefix: true,
  continuousAfterWake: false,
  defaultGroup: '895102465',
  botQQ: '3279329186',
  maxGroupContextMessages: 15,
  maxGroupBufferMessages: 200
};

fs.mkdirSync(STATE_DIR, { recursive: true });
fs.mkdirSync(LOG_DIR, { recursive: true });
if (!fs.existsSync(CONFIG_FILE)) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(DEFAULT_CONFIG, null, 2), 'utf8');
}
const config = { ...DEFAULT_CONFIG, ...JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')) };
const sessionFile = path.join(STATE_DIR, 'agent-session.json');

let ws = null;
let seq = 1;
let active = false;
let running = false;
let queue = [];
let lastHandledAt = 0;
const groupMessageBuffers = new Map();

function log(...args) {
  const line = `[${new Date().toISOString()}] ${args.map(a => typeof a === 'string' ? a : JSON.stringify(a)).join(' ')}`;
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + '\n', 'utf8');
}

function loadSessionId() {
  try {
    const data = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
    return data.sessionId || '';
  } catch {
    return '';
  }
}

function saveSessionId(sessionId) {
  if (!sessionId) return;
  fs.writeFileSync(sessionFile, JSON.stringify({ sessionId, updatedAt: new Date().toISOString() }, null, 2), 'utf8');
}

function clearSessionId() {
  try {
    fs.rmSync(sessionFile, { force: true });
  } catch {}
}

function plainText(message) {
  if (typeof message === 'string') return message;
  if (Array.isArray(message)) {
    return message.map(seg => {
      if (!seg) return '';
      if (seg.type === 'text') return seg.data?.text || '';
      if (seg.type === 'at') return `[at:${seg.data?.qq || ''}]`;
      if (seg.type) {
        const data = seg.data || {};
        const details = [];
        for (const key of ['text', 'title', 'summary', 'content', 'url', 'file', 'file_id', 'name', 'id', 'qq']) {
          if (data[key]) details.push(`${key}=${data[key]}`);
        }
        if (details.length) return `[${seg.type}:${details.join(',')}]`;
        const dataText = Object.keys(data).length ? `:${JSON.stringify(data)}` : '';
        return `[${seg.type}${dataText}]`;
      }
      return '';
    }).join('');
  }
  return '';
}

function fieldText(value) {
  return String(value ?? '')
    .replace(/\r\n/g, '\\n')
    .replace(/[\r\n]+/g, '\\n')
    .replace(/[\t ]+/g, ' ')
    .trim();
}

function rawMessageText(event) {
  return String(event.raw_message || '').trim();
}

function messageSpecificText(event) {
  const message = event.message;
  if (!Array.isArray(message)) return '';
  const parts = [];
  for (const seg of message) {
    if (!seg || !seg.type || seg.type === 'text' || seg.type === 'at') continue;
    const data = seg.data || {};
    if (seg.type === 'video') {
      parts.push(`视频=${data.url || data.file || data.file_id || '无可用链接'}`);
    } else if (seg.type === 'image') {
      parts.push(`图片=${data.url || data.file || data.file_id || '无可用链接'}`);
    } else if (seg.type === 'file') {
      parts.push(`文件=${data.name || data.file || data.file_id || '无文件名'}`);
    } else if (seg.type === 'record') {
      parts.push(`语音=${data.url || data.file || data.file_id || '无可用链接'}`);
    } else if (seg.type === 'reply') {
      parts.push(`回复消息ID=${data.id || '未知'}`);
    } else if (seg.type === 'face') {
      parts.push(`表情=${data.id || JSON.stringify(data) || '未知'}`);
    } else {
      parts.push(`${seg.type}=${Object.keys(data).length ? JSON.stringify(data) : '无详细数据'}`);
    }
  }
  return parts.join(' ');
}

function eventText(event) {
  const raw = rawMessageText(event);
  const plain = plainText(event.message).trim();
  const specific = messageSpecificText(event).trim();
  let merged = '';
  if (!plain) merged = raw;
  else if (!raw) merged = plain;
  else if (plain.includes(raw)) merged = plain;
  else if (raw.includes(plain)) merged = raw;
  else merged = `${raw} ${plain}`.trim();
  if (specific && !merged.includes(specific)) merged = `${merged} ${specific}`.trim();
  return merged;
}

function speakerName(event) {
  const sender = event.sender || {};
  return sender.card || sender.nickname || String(event.user_id || '未知');
}

function senderNickname(event) {
  return event.sender?.nickname || '';
}

function sourceLabel(event) {
  return event.message_type === 'group' ? '群聊' : '私聊';
}

function sourceId(event) {
  return event.message_type === 'group'
    ? String(event.group_id || '')
    : String(event.user_id || '');
}

function sourceName(event) {
  return event.group_name || event.sender?.group_name || '';
}

function qqInputPrompt(event, body) {
  const parts = [
    `来源=${fieldText(sourceLabel(event))}`,
    `来源ID=${fieldText(sourceId(event))}`,
    `群号=${fieldText(event.group_id || '')}`,
    `私聊号=${fieldText(event.message_type === 'private' ? event.user_id || '' : '')}`,
    `发送者QQ=${fieldText(event.user_id || '')}`,
    `昵称名=${fieldText(speakerName(event))}`,
    `QQ昵称=${fieldText(senderNickname(event))}`,
    `群名=${fieldText(sourceName(event))}`,
    `消息ID=${fieldText(event.message_id || event.message_seq || '')}`,
    `时间=${fieldText(event.time || '')}`,
    `内容类型=${fieldText(contentLabel(event.message))}`,
    `正文=${fieldText(body) || '（空正文）'}`
  ];
  return parts.join('；');
}

function groupMessagePrompt(item, index) {
  return `消息${index + 1}={${qqInputPrompt(item.event, item.body)}}`;
}

function isBotMessage(event) {
  const botIds = [event.self_id, config.botQQ].filter(Boolean).map(String);
  return botIds.includes(String(event.user_id || ''));
}

function rememberGroupMessage(event, body) {
  if (event.message_type !== 'group') return;
  if (isBotMessage(event)) return;
  const groupId = String(event.group_id || config.defaultGroup || '');
  if (!groupId) return;
  const item = {
    event,
    body: String(body || '').trim() || plainText(event.message).trim() || `[${contentLabel(event.message)}]`
  };
  const buf = groupMessageBuffers.get(groupId) || [];
  buf.push(item);
  const max = Number(config.maxGroupBufferMessages || 200);
  if (buf.length > max) buf.splice(0, buf.length - max);
  groupMessageBuffers.set(groupId, buf);
}

function buildGroupContextPrompt(event) {
  const groupId = String(event.group_id || config.defaultGroup || '');
  const buf = groupMessageBuffers.get(groupId) || [];
  const limit = Number(config.maxGroupContextMessages || 15);
  const selected = buf.slice(-limit);
  groupMessageBuffers.set(groupId, []);
  if (!selected.length) return qqInputPrompt(event, cleanBody(stripWake(eventText(event))) || '你好');
  const currentBody = cleanBody(stripWake(eventText(event))) || '你好';
  const header = [
    `群聊上下文=从上次彩叶唤起后到本次唤起前后，最新${selected.length}条非彩叶自己消息`,
    `回复目标=群聊`,
    `群号=${fieldText(event.group_id || '')}`,
    `群名=${fieldText(sourceName(event))}`,
    `本次唤起者QQ=${fieldText(event.user_id || '')}`,
    `本次唤起者昵称=${fieldText(speakerName(event))}`,
    `本次正文=${fieldText(currentBody) || '（空正文）'}`
  ].join('；');
  const messages = selected.map(groupMessagePrompt).join('；');
  return `${header}；${messages}；规则=每个“消息N={...正文=...}”都是一条具体群聊消息，最后一条通常是本次唤起消息；“本次正文”和每条消息里的“正文=”都是有效正文。请结合上下文自然回复，不要说没正文。`;
}

function clampPrompt(prompt) {
  const text = String(prompt || '');
  const max = Number(config.maxPromptChars || 6000);
  if (!max || max <= 0 || text.length <= max) return text;
  return `${text.slice(0, max)}；提示=以上群聊上下文因长度限制已截断。`;
}

function promptPreview(prompt) {
  return String(prompt || '').replace(/\s+/g, ' ').slice(0, 1200);
}

function groupContextCount(event) {
  const groupId = String(event.group_id || config.defaultGroup || '');
  const buf = groupMessageBuffers.get(groupId) || [];
  return Math.min(buf.length, Number(config.maxGroupContextMessages || 15));
}

function contentLabel(message) {
  if (typeof message === 'string') return '正文';
  if (!Array.isArray(message)) return '正文';
  const types = [...new Set(message.map(seg => seg && seg.type).filter(Boolean))];
  const nonTextTypes = types.filter(type => type !== 'text' && type !== 'at');
  if (!nonTextTypes.length) return '正文';
  const labelMap = {
    image: '图片',
    video: '视频',
    file: '文件',
    record: '语音',
    face: '表情',
    reply: '回复',
    json: 'JSON消息',
    markdown: 'Markdown消息'
  };
  return nonTextTypes.map(type => labelMap[type] || type).join('+');
}

function sendAction(action, params) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    log('Cannot send action, websocket not open', action);
    return;
  }
  ws.send(JSON.stringify({ action, params, echo: String(seq++) }));
}

function sendReply(event, text) {
  const safe = String(text || '').trim() || '（没有输出）';
  log('Sending reply', { message_type: event.message_type, user_id: event.user_id, group_id: event.group_id, preview: safe.slice(0, 300) });
  if (event.message_type === 'group') {
    sendAction('send_group_msg', { group_id: event.group_id, message: safe });
  } else if (event.message_type === 'private') {
    sendAction('send_private_msg', { user_id: event.user_id, message: safe });
  } else {
    log('Unknown message_type, cannot reply', event.message_type);
  }
}

function stripWake(text) {
  let t = text.trim();
  if (t.startsWith(config.wakeWord)) t = t.slice(config.wakeWord.length).trim();
  t = cleanBody(t);
  return t;
}

function cleanBody(text) {
  return String(text || '').replace(/^[\s,，:：;；、。.!！?？]+/, '').trim();
}

function extractFinalOutput(stdout, prompt = '') {
  let text = stdout.replace(/\r\n/g, '\n').trim();
  if (!text) return '';
  const normalizedPrompt = String(prompt || '').replace(/\r\n/g, '\n').trim();
  if (normalizedPrompt) {
    const promptIndex = text.lastIndexOf(normalizedPrompt);
    if (promptIndex >= 0) {
      text = text.slice(promptIndex + normalizedPrompt.length).trim();
    }
  }
  const jsonTextParts = [];
  const nonJsonLines = [];
  let jsonLineCount = 0;
  let controlJsonLineCount = 0;
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (!trimmed.startsWith('{')) {
      nonJsonLines.push(trimmed);
      continue;
    }
    try {
      const evt = JSON.parse(trimmed);
      jsonLineCount += 1;
      const part = evt.part || {};
      if (evt.type === 'text') {
        if (typeof part.text === 'string') jsonTextParts.push(part.text);
        else if (typeof evt.text === 'string') jsonTextParts.push(evt.text);
      } else if (part.type === 'text' && typeof part.text === 'string') {
        jsonTextParts.push(part.text);
      } else if (evt.type === 'message' && typeof evt.text === 'string') {
        jsonTextParts.push(evt.text);
      } else if (evt.type === 'assistant' && typeof evt.content === 'string') {
        jsonTextParts.push(evt.content);
      } else {
        controlJsonLineCount += 1;
      }
    } catch {
      nonJsonLines.push(trimmed);
    }
  }
  const extracted = jsonTextParts.join('').trim();
  if (extracted) return extracted;

  const contentLines = nonJsonLines.filter(line => {
    if (/^sessionID:\s*/.test(line) || /^round:\s*/.test(line)) return false;
    if (/^\[Image\s+\d+\]/i.test(line)) return false;
    if (/^(>|[-=]{3,}|\$\s+)/.test(line)) return false;
    if (/^[▫◦▪■□]\s+.*·\s+gpt-/i.test(line)) return false;
    if (/群聊上下文=|消息\d+=\{|规则=|请结合上下文|不要说没正文/.test(line)) return false;
    if (looksLikeProtocolJson(line)) return false;
    return true;
  });
  if (contentLines.length) return contentLines.join('\n').trim();

  if (jsonLineCount > 0) {
    log('No assistant text found in opencode JSON output', { jsonLineCount, controlJsonLineCount, firstLine: text.split('\n')[0]?.slice(0, 300) });
    return '';
  }
  return text;
}

function extractSessionId(stdout) {
  const direct = stdout.match(/^sessionID:\s*(\S+)/m);
  if (direct) return direct[1];
  for (const line of stdout.replace(/\r\n/g, '\n').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('{')) continue;
    try {
      const evt = JSON.parse(trimmed);
      if (evt.sessionID) return evt.sessionID;
    } catch {}
  }
  return '';
}

function looksLikeProtocolJson(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed.startsWith('{')) return false;
  try {
    const evt = JSON.parse(trimmed.split(/\r?\n/)[0]);
    return Boolean(evt && typeof evt === 'object' && (evt.type || evt.sessionID || evt.part));
  } catch {
    return /^\{"type":"(step_start|step_finish|text|tool)/.test(trimmed);
  }
}

function killProcessTree(pid, reason) {
  if (!pid) return;
  log('Killing agent process tree', { pid, reason });
  try {
    const killer = spawn('taskkill.exe', ['/PID', String(pid), '/T', '/F'], {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stderr = '';
    killer.stderr.on('data', d => { stderr += d.toString('utf8'); });
    killer.on('close', code => {
      if (code !== 0) log('taskkill finished with non-zero code', { pid, code, stderr: stderr.trim().slice(-500) });
    });
    killer.on('error', err => log('taskkill failed', { pid, error: err.message }));
  } catch (err) {
    log('Failed to start taskkill', { pid, error: err.message });
    try { process.kill(pid, 'SIGKILL'); } catch {}
  }
}

function runAgent(prompt) {
  return new Promise((resolve, reject) => {
    const sessionId = loadSessionId();
    const opencodeArgs = ['opencode', 'run'];
    if (sessionId) {
      opencodeArgs.push('--session', sessionId);
    }
    opencodeArgs.push(prompt);
    opencodeArgs.push('--agent', config.agent.replace(/^opencode\//, ''));
    if (config.model) {
      opencodeArgs.push('--model', config.model);
    }
    opencodeArgs.push('--dir', config.cwd);
    opencodeArgs.push('--format', 'json');
    if (!sessionId && config.sessionName) {
      opencodeArgs.push('--title', config.sessionName);
    }

    log('Starting agent', sessionId ? `session=${sessionId}` : `session_name=${config.sessionName}`);
    const child = spawn('cmd.exe', ['/c', ...opencodeArgs], {
      cwd: config.cwd,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: {
        ...process.env,
        CI: 'true',
        GIT_TERMINAL_PROMPT: '0',
        GCM_INTERACTIVE: 'never',
        PIP_NO_INPUT: '1',
        PYTHONIOENCODING: 'utf-8'
      }
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    const timeoutMs = Number(config.agentTimeoutMs || 0);
    const timer = timeoutMs > 0 ? setTimeout(() => {
      if (settled) return;
      settled = true;
      const stdoutPreview = stdout.trim().slice(-1000);
      const stderrPreview = stderr.trim().slice(-1000);
      log('Agent timed out', { pid: child.pid, timeoutMs, stdoutPreview, stderrPreview });
      killProcessTree(child.pid, `agent timed out after ${timeoutMs}ms`);
      reject(new Error(`agent timed out after ${timeoutMs}ms`));
    }, timeoutMs) : null;
    if (timer && typeof timer.unref === 'function') timer.unref();
    child.stdout.on('data', d => { stdout += d.toString('utf8'); });
    child.stderr.on('data', d => { stderr += d.toString('utf8'); });
    child.on('error', err => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      reject(err);
    });
    child.on('close', code => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      log('Agent exited', { code, stderr: stderr.trim().slice(-1000) });
      const newSession = extractSessionId(stdout);
      if (newSession) saveSessionId(newSession);
      if (code !== 0) {
        reject(new Error((stderr || stdout || `agent exited with ${code}`).trim()));
        return;
      }
      const output = extractFinalOutput(stdout, prompt);
      if (!output || looksLikeProtocolJson(output)) {
        log('Agent produced no safe reply text', { stdoutPreview: stdout.trim().slice(0, 1000), stderrPreview: stderr.trim().slice(0, 500) });
        reject(new Error('agent produced no reply text'));
        return;
      }
      log('Agent final output extracted', { length: output.length, preview: output.slice(0, 500) });
      resolve(output);
    });
  });
}
async function processQueue() {
  if (running) return;
  running = true;
  try {
    while (queue.length) {
      const { event, prompt } = queue.shift();
      if (config.ackMessage) sendReply(event, config.ackMessage);
      try {
        const answer = config.directReply ? directReply(prompt) : await runAgent(prompt);
        sendReply(event, answer.slice(0, 3500));
      } catch (err) {
        log('Agent error', err.stack || err.message);
        sendReply(event, `彩叶调用 agent 失败：${err.message || err}`.slice(0, 1000));
      }
    }
  } finally {
    running = false;
  }
}

function handleMessage(event) {
  if (event.post_type !== 'message') return;
  if (event.message_type !== 'private' && event.message_type !== 'group') return;
  const now = Date.now();
  const text = eventText(event).trim();
  if (!text) return;

  const hasWake = text.startsWith(config.wakeWord);
  if (now - lastHandledAt < config.cooldownMs && hasWake) return;

  if (text === config.closeWord || text.endsWith(` ${config.closeWord}`) || text === `${config.wakeWord} ${config.closeWord}`) {
    active = false;
    sendReply(event, '彩叶已关闭唤起。之后需要用“彩叶 ……”重新唤起。');
    return;
  }

  if (!hasWake) {
    rememberGroupMessage(event, cleanBody(text).slice(0, config.maxPromptChars));
    if (config.requireWakePrefix) return;
    if (!active) return;
  }

  active = Boolean(config.continuousAfterWake);
  lastHandledAt = now;
  const body = (cleanBody(stripWake(text)).slice(0, config.maxPromptChars).trim() || '你好');

  if (body.toLowerCase() === String(config.newSessionWord || 'new session').toLowerCase()) {
    clearSessionId();
    log('Cleared agent session by command', { user_id: event.user_id, group_id: event.group_id });
    sendReply(event, '已开新 session，下条“彩叶 ……”会从新上下文开始。');
    return;
  }

  if (event.message_type === 'group') {
    rememberGroupMessage(event, body);
  }
  const contextMessages = event.message_type === 'group' ? groupContextCount(event) : 0;
  const prompt = clampPrompt(event.message_type === 'group' ? buildGroupContextPrompt(event) : qqInputPrompt(event, body));
  log('Accepted message', { message_type: event.message_type, user_id: event.user_id, group_id: event.group_id, prompt: body, contextMessages, promptPreview: promptPreview(prompt) });
  queue.push({ event, prompt });
  processQueue();
}

function connect() {
  const url = `${config.napcatWsUrl}?access_token=${encodeURIComponent(config.token)}`;
  log('Connecting to NapCat', url.replace(config.token, '***'));
  ws = new WebSocket(url);
  ws.on('open', () => log('Connected to NapCat WebSocket'));
  ws.on('message', data => {
    try {
      const event = JSON.parse(data.toString());
      if (event.echo) return;
      handleMessage(event);
    } catch (err) {
      log('Bad websocket message', err.message);
    }
  });
  ws.on('close', (code, reason) => {
    log('NapCat websocket closed', code, reason.toString());
    setTimeout(connect, 5000);
  });
  ws.on('error', err => log('NapCat websocket error', err.message));
}

connect();









