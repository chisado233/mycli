#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const WebSocket = require('./node_modules/ws');

const ROOT = __dirname;
const CONFIG_FILE = path.join(ROOT, 'bridge.config.json');
const config = fs.existsSync(CONFIG_FILE) ? JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')) : {};

function usage() {
  console.log(`Usage:
  mycli channels QQ members [group-id] [--format json|table|md] [--out <file>] [--raw]

Arguments:
  group-id           QQ group id. Defaults to bridge.config.json defaultGroup.

Options:
  --format <format>  Output format: json, table, or md. Defaults to table.
  --out <file>       Write output to a file instead of stdout.
  --raw              Print the full raw OneBot response JSON.
  --ws <url>         NapCat WebSocket URL. Defaults to bridge.config.json napcatWsUrl.
  --token <token>    NapCat access token. Defaults to bridge.config.json token.
  --help             Show this help.

Examples:
  mycli channels QQ members
  mycli channels QQ members 895102465 --format json
  mycli channels QQ members 895102465 --format md --out D:\\agent_workspace\\tmp\\qq-members.md
`);
}

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      out[key] = next && !next.startsWith('--') ? argv[++i] : true;
    } else {
      out._.push(a);
    }
  }
  return out;
}

function request(action, params, opts) {
  const wsUrl = opts.ws || config.napcatWsUrl || 'ws://127.0.0.1:3001';
  const token = opts.token ?? config.token ?? 'chisado';
  const url = token ? `${wsUrl}?access_token=${encodeURIComponent(token)}` : wsUrl;
  const echo = `qq-members-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const timer = setTimeout(() => {
      try { ws.close(); } catch {}
      reject(new Error('Timed out waiting for NapCat response'));
    }, Number(opts.timeout || 30000));
    ws.on('open', () => ws.send(JSON.stringify({ action, params, echo })));
    ws.on('message', data => {
      let obj;
      try { obj = JSON.parse(data.toString()); } catch { return; }
      if (obj.echo !== echo) return;
      clearTimeout(timer);
      ws.close();
      if (obj.status === 'ok' || obj.retcode === 0) resolve(obj);
      else reject(new Error(`NapCat action failed: ${JSON.stringify(obj)}`));
    });
    ws.on('error', err => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

function displayName(member) {
  return String(member.card || member.nickname || member.user_id || '').trim();
}

function normalizeMembers(groupId, data) {
  return (Array.isArray(data) ? data : []).map(member => ({
    group_id: member.group_id || Number(groupId),
    user_id: member.user_id,
    name: displayName(member),
    card: member.card || '',
    nickname: member.nickname || '',
    role: member.role || '',
    level: member.level || '',
    title: member.title || '',
    is_robot: Boolean(member.is_robot),
    join_time: member.join_time || 0,
    last_sent_time: member.last_sent_time || 0,
    raw: member,
  }));
}

function formatTable(members) {
  return members.map(m => `${m.user_id}\t${m.name}\t${m.role}\t${m.card || m.nickname}`).join('\n');
}

function formatMarkdown(groupId, members) {
  const lines = [
    `# QQ 群成员映射`,
    ``,
    `群号：${groupId}`,
    ``,
    `| QQ号 | 名字 | 角色 | 群名片 | QQ昵称 |`,
    `|---:|---|---|---|---|`,
  ];
  for (const m of members) {
    lines.push(`| ${m.user_id} | ${escapeMd(m.name)} | ${escapeMd(m.role)} | ${escapeMd(m.card)} | ${escapeMd(m.nickname)} |`);
  }
  return lines.join('\n');
}

function escapeMd(value) {
  return String(value || '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help || opts.h) { usage(); return; }
  const groupId = String(opts._[0] || config.defaultGroup || '').trim();
  if (!/^\d+$/.test(groupId)) throw new Error(`Invalid group id: ${groupId || '(empty)'}`);
  const response = await request('get_group_member_list', { group_id: Number(groupId) }, opts);
  let output;
  if (opts.raw) {
    output = JSON.stringify(response, null, 2);
  } else {
    const members = normalizeMembers(groupId, response.data);
    const format = String(opts.format || 'table').toLowerCase();
    if (format === 'json') {
      output = JSON.stringify({ group_id: Number(groupId), count: members.length, members }, null, 2);
    } else if (format === 'md' || format === 'markdown') {
      output = formatMarkdown(groupId, members);
    } else if (format === 'table') {
      output = formatTable(members);
    } else {
      throw new Error(`Unknown format: ${format}`);
    }
  }
  if (opts.out) {
    const outPath = path.resolve(String(opts.out));
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, output, 'utf8');
    console.log(JSON.stringify({ path: outPath, bytes: Buffer.byteLength(output), group_id: Number(groupId) }, null, 2));
  } else {
    console.log(output);
  }
}

main().catch(err => {
  console.error(err.stack || err.message);
  process.exit(1);
});
