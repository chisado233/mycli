const $ = id => document.getElementById(id);
const state = { agents: [], models: [], sessions: [], agent: 'remote-opencode/private-assistant', model: '', session: '' };
const messages = $('messages');

function setStatus(text) { $('status').textContent = text; }
function closeMenus() { ['agentMenu', 'modelMenu', 'sessionMenu'].forEach(id => $(id).classList.add('hidden')); }
function updateActive() {
  $('activeAgent').textContent = state.agent || 'remote-opencode/private-assistant';
  const bits = [$('cwd').value.trim() || 'D:\\agent_workspace'];
  if (state.model) bits.push(state.model);
  if (state.session) bits.push(state.session);
  $('activeMeta').textContent = bits.join('  |  ');
}
function addMessage(text, cls = 'raw') {
  const div = document.createElement('div');
  div.className = `msg ${cls}`;
  div.textContent = text;
  messages.appendChild(div);
  messages.scrollTop = messages.scrollHeight;
}
function optionButton(label, subtext, onClick) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'option';
  btn.textContent = label || '(default)';
  if (subtext) {
    const small = document.createElement('small');
    small.textContent = subtext;
    btn.appendChild(small);
  }
  btn.addEventListener('click', () => { onClick(); closeMenus(); updateActive(); });
  return btn;
}
function renderMenu(id, items, make) {
  const menu = $(id);
  menu.replaceChildren();
  items.forEach(item => menu.appendChild(make(item)));
}
function renderOptions() {
  renderMenu('agentMenu', state.agents, name => optionButton(name, '', () => {
    state.agent = name;
    $('agentPicker').textContent = name;
    $('agentPicker').classList.toggle('muted', !name);
  }));
  renderMenu('modelMenu', state.models, model => optionButton(model || '默认模型', model ? '' : '使用 agent 文件里的 model', () => {
    state.model = model || '';
    $('modelPicker').textContent = model || '默认模型';
    $('modelPicker').classList.toggle('muted', !model);
  }));
  const sessionItems = [{ sessionId: '', agent: '', prompt: 'Start a new session', startedAt: '' }, ...state.sessions];
  renderMenu('sessionMenu', sessionItems, s => optionButton(s.sessionId || '新会话', s.sessionId ? `${s.agent || ''} ${s.startedAt || ''}\n${s.prompt || ''}` : s.prompt, () => {
    state.session = s.sessionId || '';
    $('session').value = state.session;
    $('sessionPicker').textContent = state.session || '新会话';
    $('sessionPicker').classList.toggle('muted', !state.session);
  }));
}
async function refresh() {
  setStatus('loading options');
  const res = await fetch('/api/options');
  const data = await res.json();
  state.agents = data.agents || [];
  state.models = data.models || [];
  state.sessions = data.sessions || [];
  state.agent = state.agents.includes('remote-opencode/private-assistant') ? 'remote-opencode/private-assistant' : (data.currentAgent || state.agents[0] || state.agent);
  $('agentPicker').textContent = state.agent;
  if (data.defaultCwd) $('cwd').value = data.defaultCwd;
  renderOptions();
  updateActive();
  setStatus(`ready | ${state.agents.length} agents | ${state.sessions.length} sessions`);
}
async function run() {
  const prompt = $('prompt').value.trim();
  if (!prompt) return;
  $('run').disabled = true;
  setStatus('running');
  addMessage(prompt, 'user');
  state.session = $('session').value.trim();
  const body = {
    agent: state.agent,
    cwd: $('cwd').value.trim(),
    model: state.model,
    session: state.session,
    sessionName: $('sessionName').value.trim(),
    continueSession: $('continueSession').checked,
    fork: $('fork').checked,
    prompt
  };
  const res = await fetch('/api/run', { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(body) });
  if (!res.ok || !res.body) { addMessage(await res.text(), 'error'); $('run').disabled = false; setStatus('error'); return; }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  function handleBlock(block) {
    const lines = block.split('\n');
    const dataLine = lines.find(l => l.startsWith('data: '));
    const eventLine = lines.find(l => l.startsWith('event: '));
    if (!dataLine) return;
    const name = eventLine ? eventLine.slice(7) : 'message';
    const data = JSON.parse(dataLine.slice(6));
    if (name === 'start') addMessage(`started ${data.agent}\ncwd=${data.cwd}`, 'meta');
    else if (name === 'done') {
      addMessage(`done code=${data.code} session=${data.sessionId || ''}`, data.code === 0 ? 'meta' : 'error');
      if (data.sessionId) { state.session = data.sessionId; $('session').value = data.sessionId; $('sessionPicker').textContent = data.sessionId; $('sessionPicker').classList.remove('muted'); }
      setStatus(data.code === 0 ? 'done' : 'failed');
    } else if (name === 'stderr') addMessage(data.line, 'stderr');
    else if (data.normalized?.kind === 'assistant_text') addMessage(data.normalized.text, 'assistant');
    else if (data.normalized?.kind === 'error') addMessage(data.line || JSON.stringify(data.normalized.raw), 'error');
    else if (data.normalized?.kind === 'step_start' || data.normalized?.kind === 'step_finish') addMessage(data.normalized.kind, 'meta');
    else addMessage(data.line || JSON.stringify(data), 'raw');
  }
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream:true });
    const blocks = buf.split('\n\n');
    buf = blocks.pop() || '';
    blocks.forEach(handleBlock);
  }
  $('run').disabled = false;
  $('prompt').value = '';
  updateActive();
  refresh().catch(() => {});
}

$('agentPicker').addEventListener('click', e => { e.stopPropagation(); closeMenus(); $('agentMenu').classList.toggle('hidden'); });
$('modelPicker').addEventListener('click', e => { e.stopPropagation(); closeMenus(); $('modelMenu').classList.toggle('hidden'); });
$('sessionPicker').addEventListener('click', e => { e.stopPropagation(); closeMenus(); $('sessionMenu').classList.toggle('hidden'); });
document.addEventListener('click', closeMenus);
$('refresh').addEventListener('click', () => refresh().catch(e => addMessage(String(e), 'error')));
$('clear').addEventListener('click', () => messages.replaceChildren());
$('run').addEventListener('click', run);
$('prompt').addEventListener('keydown', e => { if (e.ctrlKey && e.key === 'Enter') run(); });
['cwd', 'session'].forEach(id => $(id).addEventListener('input', () => { if (id === 'session') state.session = $(id).value.trim(); updateActive(); }));
refresh().catch(e => { addMessage(String(e), 'error'); setStatus('error'); });
