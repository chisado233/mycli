const state = {
  snapshot: null,
  selectedConversationId: 'all',
  expandedChannels: {},
  configs: {},
  actionOutput: ''
};

const $ = (id) => document.getElementById(id);

function fmtTime(value) {
  if (!value) return '--';
  const date = new Date(value);
  if (!Number.isNaN(date.getTime())) return date.toLocaleString('zh-CN', { hour12: false });
  return value;
}

function shortTime(value) {
  if (!value) return '';
  const date = new Date(value);
  if (!Number.isNaN(date.getTime())) return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
  return String(value).slice(6, 16);
}

function channelName(id) {
  return state.snapshot?.channels?.find((item) => item.id === id)?.name || id;
}

function escapeHtml(text) {
  return String(text ?? '').replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
}

function renderChannels() {
  const el = $('channelStatus');
  const groups = state.snapshot.channelGroups || state.snapshot.channels.map(channel => ({ ...channel, conversations: state.snapshot.conversations.filter(conv => conv.channelId === channel.id) }));
  if (!Object.keys(state.expandedChannels).length) {
    for (const group of groups) state.expandedChannels[group.id] = true;
  }
  el.innerHTML = `<div class="section-caption">频道</div>` + groups.map(group => `
    <div class="channel-group ${group.online ? 'online' : ''}">
      <div class="channel-card" data-channel-toggle="${escapeHtml(group.id)}">
        <div class="channel-icon">${group.id === 'qq' ? 'Q' : 'C'}</div>
        <div>
          <div class="name">${escapeHtml(group.name)}</div>
          <div class="kind">${escapeHtml(group.kind)} · ${group.conversations.length} 个子频道</div>
        </div>
        <span class="chevron">${state.expandedChannels[group.id] ? '⌄' : '›'}</span>
        <span class="pill"><span class="dot"></span>${group.online ? '在线' : '离线'}</span>
      </div>
      <div class="subchannel-list ${state.expandedChannels[group.id] ? '' : 'collapsed'}">
        ${group.conversations.map(conv => `
          <div class="subchannel-item ${conv.id === state.selectedConversationId ? 'active' : ''}" data-conv="${escapeHtml(conv.id)}">
            <div class="subchannel-title-row">
              <span class="subchannel-title">${escapeHtml(conv.title)}</span>
              <span class="conversation-time">${shortTime(conv.lastTime)}</span>
            </div>
            <div class="conversation-last">${escapeHtml(conv.lastText || '')}</div>
          </div>
        `).join('') || '<div class="empty-subchannel">暂无子频道</div>'}
      </div>
    </div>
  `).join('');
  document.querySelectorAll('[data-channel-toggle]').forEach(item => {
    item.addEventListener('click', () => {
      const id = item.dataset.channelToggle;
      state.expandedChannels[id] = !state.expandedChannels[id];
      renderChannels();
    });
  });
  document.querySelectorAll('.subchannel-item').forEach(item => {
    item.addEventListener('click', (event) => {
      event.stopPropagation();
      state.selectedConversationId = item.dataset.conv;
      render();
    });
  });
}

function renderConversations() {
  const all = { id: 'all', title: '全部消息', lastText: '显示所有 channel 的消息', lastTime: state.snapshot.generatedAt, channelId: 'all' };
  $('conversationList').innerHTML = `<div class="section-caption">总览</div>
    <div class="conversation-item ${state.selectedConversationId === 'all' ? 'active' : ''}" data-conv="all">
      <div class="conversation-title-row">
        <div class="conversation-title">${escapeHtml(all.title)}</div>
        <div class="conversation-time">${shortTime(all.lastTime)}</div>
      </div>
      <div class="conversation-last">${escapeHtml(all.lastText)}</div>
    </div>
  `;
  document.querySelectorAll('.conversation-item').forEach(item => {
    item.addEventListener('click', () => {
      state.selectedConversationId = item.dataset.conv;
      render();
    });
  });
}

function renderMessages() {
  const list = $('messageList');
  const wasNearBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 120;
  const previousScrollTop = list.scrollTop;
  let messages = state.snapshot.messages;
  if (state.selectedConversationId !== 'all') messages = messages.filter(msg => msg.conversationId === state.selectedConversationId);
  const conv = state.snapshot.conversations.find(item => item.id === state.selectedConversationId);
  $('chatTitle').textContent = state.selectedConversationId === 'all' ? '全部消息' : (conv?.title || state.selectedConversationId);
  $('chatSubtitle').textContent = state.selectedConversationId === 'all' ? 'QQ / Chat Soft 收发消息与连通状态' : `${channelName(conv?.channelId)} · ${messages.length} 条消息`;
  list.innerHTML = messages.map(msg => {
    const out = msg.direction === 'out';
    const avatar = out ? '我' : (msg.channelId === 'qq' ? 'Q' : 'C');
    const text = msg.text || '[空消息]';
    const isMedia = /^\[[^\]]+\]/.test(text);
    return `
      <div class="message-row ${out ? 'out' : 'in'}">
        <div class="message-avatar">${avatar}</div>
        <div class="bubble-wrap">
          <div class="meta">${escapeHtml(channelName(msg.channelId))} · ${escapeHtml(msg.sender || '')} · ${fmtTime(msg.time)} ${msg.status ? '· ' + escapeHtml(msg.status) : ''}</div>
          <div class="bubble ${isMedia ? 'media-bubble' : ''}">${escapeHtml(text)}</div>
        </div>
      </div>
    `;
  }).join('') || '<div class="conversation-last">暂无消息</div>';
  if (wasNearBottom) list.scrollTop = list.scrollHeight;
  else list.scrollTop = previousScrollTop;
}

function renderInspector() {
  $('inspectorStatus').innerHTML = state.snapshot.channels.map(channel => {
    const ports = Object.entries(channel.ports || {}).map(([port, ok]) => `${port}: ${ok ? 'OK' : 'FAIL'}`).join(' / ') || '--';
    const processes = Object.entries(channel.processes || {}).map(([key, item]) => `${key}=${item.pid} ${item.alive ? 'alive' : 'dead'}`).join('<br>') || '--';
    const health = Object.entries(channel.health || {}).map(([url, item]) => `${url}: ${item.ok ? 'OK ' + item.status : 'FAIL'}`).join('<br>') || '--';
    return `
      <div class="status-card ${channel.online ? 'online' : ''}">
        <div class="status-line"><strong>${escapeHtml(channel.name)}</strong><span class="pill"><span class="dot"></span>${channel.online ? '在线' : '离线'}</span></div>
        <div class="status-line"><span>端口</span><span class="mono">${escapeHtml(ports)}</span></div>
        <div class="status-line"><span>进程</span><span class="mono">${processes}</span></div>
        <div class="status-line"><span>Health</span><span class="mono">${health}</span></div>
      </div>
    `;
  }).join('');
  $('eventList').innerHTML = state.snapshot.events.map(evt => `
    <div class="event-item">
      <div class="event-time">${fmtTime(evt.time)}</div>
      <div>${escapeHtml(evt.text)}</div>
    </div>
  `).join('') || '<div class="conversation-last">暂无事件</div>';
  renderControls();
}

function inputTypeFor(value) {
  if (typeof value === 'boolean') return 'checkbox';
  if (typeof value === 'number') return 'number';
  return 'text';
}

function renderConfigFields(channel) {
  if (!channel.hasConfig) return '<div class="note">这个 channel 当前没有可编辑配置文件。</div>';
  const config = state.configs[channel.id];
  if (!config) return `<button class="secondary" data-load-config="${channel.id}">加载配置</button>`;
  return Object.entries(config.values || {}).map(([key, value]) => {
    const type = inputTypeFor(value);
    if (typeof value === 'boolean') {
      return `<div class="field"><label>${escapeHtml(key)}</label><select data-config-channel="${channel.id}" data-config-key="${escapeHtml(key)}"><option value="true" ${value ? 'selected' : ''}>true</option><option value="false" ${!value ? 'selected' : ''}>false</option></select></div>`;
    }
    const stringValue = value == null ? '' : String(value);
    const input = stringValue.length > 80
      ? `<textarea data-config-channel="${channel.id}" data-config-key="${escapeHtml(key)}">${escapeHtml(stringValue)}</textarea>`
      : `<input type="${type}" value="${escapeHtml(stringValue)}" data-config-channel="${channel.id}" data-config-key="${escapeHtml(key)}" />`;
    return `<div class="field"><label>${escapeHtml(key)}</label>${input}</div>`;
  }).join('') + `<div class="button-row"><button data-save-config="${channel.id}">保存配置</button><button class="secondary" data-load-config="${channel.id}">重新加载</button></div><div class="note">配置保存后通常需要重启对应 channel 才会生效。</div>`;
}

function renderControls() {
  $('controlPanel').innerHTML = state.snapshot.channels.map(channel => `
    <div class="control-card">
      <div class="control-title"><span>${escapeHtml(channel.name)}</span><span class="pill ${channel.online ? 'online' : ''}"><span class="dot"></span>${channel.online ? '在线' : '离线'}</span></div>
      ${(channel.notes || []).map(note => `<div class="note">${escapeHtml(note)}</div>`).join('')}
      ${channel.id === 'qq' ? '<div class="field"><label>启动 QQ 号（留空用默认）</label><input id="qqStartNumber" placeholder="3279329186" /></div>' : ''}
      <div class="button-row">
        <button data-action="start" data-channel="${channel.id}">启动</button>
        <button class="danger" data-action="stop" data-channel="${channel.id}">关闭</button>
        <button class="warning" data-action="restart" data-channel="${channel.id}">重启</button>
      </div>
      <details>
        <summary>配置更改</summary>
        ${renderConfigFields(channel)}
      </details>
    </div>
  `).join('') + (state.actionOutput ? `<div class="action-output">${escapeHtml(state.actionOutput)}</div>` : '');

  document.querySelectorAll('[data-action]').forEach(button => {
    button.addEventListener('click', () => runChannelAction(button.dataset.channel, button.dataset.action));
  });
  document.querySelectorAll('[data-load-config]').forEach(button => {
    button.addEventListener('click', () => loadConfig(button.dataset.loadConfig));
  });
  document.querySelectorAll('[data-save-config]').forEach(button => {
    button.addEventListener('click', () => saveConfig(button.dataset.saveConfig));
  });
}

async function runChannelAction(channelId, action) {
  const channel = state.snapshot.channels.find(item => item.id === channelId);
  const label = `${channel?.name || channelId} ${action}`;
  const qq = document.getElementById('qqStartNumber')?.value?.trim();
  if (channelId === 'qq' && (action === 'start' || action === 'restart')) {
    const ok = confirm('QQ 启动后如果没有保持登录，会弹出登录窗口，需要你扫码二维码。继续吗？');
    if (!ok) return;
  }
  state.actionOutput = `正在执行：${label} ...`;
  renderControls();
  try {
    const response = await fetch('/api/channel-action', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ channelId, action, qq })
    });
    const payload = await response.json();
    state.actionOutput = payload.outputs
      ? payload.outputs.map(item => `[${item.action}] exit=${item.code}\n${item.output || ''}`).join('\n---\n')
      : JSON.stringify(payload, null, 2);
    await refresh();
  } catch (error) {
    state.actionOutput = `执行失败：${error.message || error}`;
    renderControls();
  }
}

async function loadConfig(channelId) {
  const response = await fetch(`/api/channel-config?channel=${encodeURIComponent(channelId)}`, { cache: 'no-store' });
  const payload = await response.json();
  if (payload.ok && payload.config) state.configs[channelId] = payload.config;
  renderControls();
}

function coerceConfigValue(original, value) {
  if (typeof original === 'boolean') return value === 'true';
  if (typeof original === 'number') return Number(value);
  return value;
}

async function saveConfig(channelId) {
  const config = state.configs[channelId];
  if (!config) return;
  const values = { ...config.values };
  document.querySelectorAll(`[data-config-channel="${channelId}"]`).forEach(input => {
    const key = input.dataset.configKey;
    values[key] = coerceConfigValue(config.values[key], input.value);
  });
  const response = await fetch(`/api/channel-config?channel=${encodeURIComponent(channelId)}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ values })
  });
  const payload = await response.json();
  if (payload.ok && payload.config) {
    state.configs[channelId] = payload.config;
    state.actionOutput = `${channelName(channelId)} 配置已保存。需要重启 channel 才会生效。`;
  } else {
    state.actionOutput = `保存失败：${payload.error || 'unknown error'}`;
  }
  renderControls();
}

function render() {
  if (!state.snapshot) return;
  $('updatedAt').textContent = `更新：${fmtTime(state.snapshot.generatedAt)}`;
  renderChannels();
  renderConversations();
  renderMessages();
  renderInspector();
}

async function refresh() {
  $('refreshButton').disabled = true;
  try {
    const response = await fetch('/api/snapshot', { cache: 'no-store' });
    state.snapshot = await response.json();
    render();
  } catch (error) {
    console.error(error);
  } finally {
    $('refreshButton').disabled = false;
  }
}

$('refreshButton').addEventListener('click', refresh);
refresh();
setInterval(refresh, 5000);
