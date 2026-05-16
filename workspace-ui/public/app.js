const state = { tree: null, selected: null, expanded: new Set(['workspace:root', 'capability-library:root', 'mycli:root', 'projects:root']), filter: '', uiOnly: false };

const $ = id => document.getElementById(id);

function log(message, data) {
  const now = new Date().toLocaleTimeString();
  const text = typeof data === 'undefined' ? '' : `\n${typeof data === 'string' ? data : JSON.stringify(data, null, 2)}`;
  $('consoleLog').textContent = `[${now}] ${message}${text}\n\n` + $('consoleLog').textContent;
}

function iconFor(node) {
  if (node.kind === 'workspace') return '◎';
  if (node.kind === 'capability-root') return '◆';
  if (node.kind === 'project-root') return '▣';
  if (node.kind === 'project') return '◧';
  if (node.hasUi) return '✦';
  return '◇';
}

function matchesFilter(node) {
  const matchesUiOnly = !state.uiOnly || node.hasUi || (node.children || []).some(matchesUiBranch);
  if (!matchesUiOnly) return false;
  if (!state.filter) return true;
  const hay = `${node.name} ${node.path || ''} ${node.manifest?.name || ''}`.toLowerCase();
  if (hay.includes(state.filter)) return true;
  return (node.children || []).some(matchesFilter);
}

function matchesUiBranch(node) {
  return Boolean(node.hasUi || (node.children || []).some(matchesUiBranch));
}

function renderTreeNode(node) {
  if (!matchesFilter(node)) return null;
  const wrap = document.createElement('div');
  wrap.className = 'tree-node';
  const row = document.createElement('button');
  row.className = `tree-row ${state.selected?.id === node.id ? 'active' : ''}`;
  const hasChildren = (node.children || []).length > 0;
  const expanded = state.expanded.has(node.id) || Boolean(state.filter) || state.uiOnly;
  row.innerHTML = `<span class="twisty">${hasChildren ? (expanded ? '▾' : '▸') : '·'}</span><span>${iconFor(node)}</span><span class="name">${node.name}</span><span class="dot ${node.hasUi ? 'ui' : ''}"></span>`;
  row.onclick = () => {
    state.selected = node;
    if (hasChildren) expanded ? state.expanded.delete(node.id) : state.expanded.add(node.id);
    renderTree();
    showNode(node);
  };
  wrap.appendChild(row);
  if (hasChildren && expanded) {
    const children = document.createElement('div');
    children.className = 'children';
    for (const child of node.children) {
      const el = renderTreeNode(child);
      if (el) children.appendChild(el);
    }
    wrap.appendChild(children);
  }
  return wrap;
}

function renderTree() {
  const root = $('tree');
  root.innerHTML = '';
  if (!state.tree) return;
  root.appendChild(renderTreeNode(state.tree));
}

async function fetchJson(url, options) {
  const res = await fetch(url, options);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

async function loadTree() {
  const data = await fetchJson('/api/tree');
  state.tree = data.tree;
  if (!state.selected) state.selected = state.tree;
  renderTree();
  await showNode(state.selected);
}

async function showNode(node) {
  let current = node;
  try {
    const data = await fetchJson(`/api/nodes/${encodeURIComponent(node.id)}`);
    current = data.node;
    state.selected = current;
  } catch (error) {
    log('读取节点详情失败', error.message);
  }
  $('nodeTitle').textContent = current.manifest?.name || current.name;
  $('nodeSubtitle').textContent = current.manifest?.description || (current.hasUi ? '这个节点声明了子 UI。' : '普通目录节点：用于定位能力或项目。');
  $('nodePath').textContent = current.path || '-';
  $('nodeKind').textContent = current.kind || '-';
  $('kindBadge').textContent = current.kind || 'node';
  $('manifestPath').textContent = current.manifest?.manifestPath || '未接入';
  $('uiDescription').textContent = current.manifest?.description || '这个节点没有声明子 UI。项目目录仍会显示在左侧，但只有存在 .agent-ui.json 时才可启动或打开。';
  $('uiUrl').textContent = current.manifest?.url || 'No UI URL';
  const hasUi = Boolean(current.manifest);
  $('startBtn').disabled = !hasUi || !current.manifest.commands?.start;
  $('stopBtn').disabled = !hasUi || !current.manifest.commands?.stop;
  $('openBtn').disabled = !hasUi || (!current.manifest.commands?.open && !current.manifest.url);
  const badge = $('onlineBadge');
  badge.className = 'badge muted';
  if (!hasUi) badge.textContent = '未接入';
  else if (current.uiStatus?.online) { badge.textContent = '运行中'; badge.className = 'badge online'; }
  else { badge.textContent = '可启动'; badge.className = 'badge offline'; }
}

async function action(name) {
  const node = state.selected;
  if (!node?.manifest) return;
  log(`执行 ${name}: ${node.manifest.name || node.name}`);
  try {
    const data = await fetchJson(`/api/nodes/${encodeURIComponent(node.id)}/${name}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    if (name === 'open' && data.url && data.openedBy === 'browser') window.open(data.url, '_blank', 'noopener');
    log(`${name} 完成 ok=${data.ok}`, data.result?.output || data);
    await showNode(node);
  } catch (error) {
    log(`${name} 失败`, error.message);
  }
}

$('startBtn').onclick = () => action('start');
$('stopBtn').onclick = () => action('stop');
$('openBtn').onclick = () => action('open');
$('refreshTree').onclick = () => loadTree().then(() => log('目录已刷新'));
$('clearLog').onclick = () => $('consoleLog').textContent = '日志已清空。';
$('search').oninput = event => { state.filter = event.target.value.trim().toLowerCase(); renderTree(); };
$('uiOnly').onchange = event => {
  state.uiOnly = event.target.checked;
  renderTree();
  log(state.uiOnly ? '已隐藏未接入 UI 的目录' : '已显示全部目录');
};

setInterval(() => { $('clock').textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }); }, 1000);
loadTree().catch(error => log('初始化失败', error.message));
