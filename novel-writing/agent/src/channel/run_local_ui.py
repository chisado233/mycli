from __future__ import annotations

import argparse
import json
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict

from channel import ChannelManager


CURRENT_DIR = Path(__file__).resolve().parent
SRC_DIR = CURRENT_DIR.parent
RUNTIME_DIR = SRC_DIR / "runtime"
PROJECTS_ROOT = CURRENT_DIR.parents[3]
if str(RUNTIME_DIR) not in sys.path:
    sys.path.append(str(RUNTIME_DIR))

from runtime import runtime  # noqa: E402
from cbt_session_runtime import CbtLegacySessionRuntime  # noqa: E402


def discover_workflows() -> list[Dict[str, str]]:
    items: list[Dict[str, str]] = []
    seen: set[str] = set()
    for path in PROJECTS_ROOT.rglob("agent_workflow.json"):
        if "workspace" not in {part.lower() for part in path.parts}:
            continue
        resolved = str(path.resolve())
        if resolved in seen:
            continue
        seen.add(resolved)
        project_name = path.parents[2].name if len(path.parents) >= 3 else path.parent.name
        workflow_name = path.parent.name
        label = f"{project_name} / {workflow_name}"
        items.append(
            {
                "label": label,
                "path": resolved,
                "project": project_name,
                "workflow": workflow_name,
            }
        )
    items.sort(key=lambda item: (item["project"], item["workflow"], item["path"]))
    return items


HTML = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Multi-Agent Runtime Console</title>
  <style>
    :root {
      --bg: #f4fbf6;
      --panel: rgba(255, 255, 255, 0.9);
      --panel-soft: rgba(247, 252, 248, 0.88);
      --line: rgba(53, 94, 63, 0.1);
      --line-strong: rgba(53, 94, 63, 0.18);
      --text: #203126;
      --text-muted: #6c8372;
      --accent: #5fa777;
      --accent-strong: #3f7f58;
      --user: rgba(157, 214, 174, 0.32);
      --agent: rgba(214, 241, 222, 0.88);
      --shadow: 0 24px 60px rgba(91, 133, 103, 0.12);
      --danger: #b44d4d;
      --warn: #c08a33;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--text);
      font-family: "Segoe UI", "PingFang SC", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(95,167,119,.16), transparent 24%),
        radial-gradient(circle at top right, rgba(183,227,196,.42), transparent 24%),
        linear-gradient(180deg, #f7fcf8 0%, #edf7ef 100%);
    }
    .app {
      display: grid;
      grid-template-columns: 280px 1fr;
      min-height: 100vh;
    }
    .sidebar {
      border-right: 1px solid var(--line);
      background: linear-gradient(180deg, rgba(247,252,248,.98), rgba(237,247,239,.94));
      padding: 20px 18px;
      display: flex;
      flex-direction: column;
      gap: 18px;
    }
    .brand {
      padding-bottom: 18px;
      border-bottom: 1px solid var(--line);
    }
    .eyebrow {
      font-size: 11px;
      letter-spacing: .14em;
      color: var(--accent);
      text-transform: uppercase;
    }
    .brand h1 {
      margin: 8px 0 0;
      font-size: 24px;
      line-height: 1.1;
    }
    .brand p {
      margin: 10px 0 0;
      color: var(--text-muted);
      line-height: 1.5;
      font-size: 14px;
    }
    .stat-card, .nav-card {
      background: var(--panel-soft);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      box-shadow: inset 0 1px 0 rgba(255,255,255,.66);
    }
    .nav-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      padding: 12px 10px;
      border-radius: 14px;
      background: rgba(255,255,255,.58);
      border: 1px solid transparent;
      margin-top: 10px;
    }
    .nav-item.active {
      background: rgba(95,167,119,.12);
      border-color: rgba(95,167,119,.22);
    }
    .badge {
      display: inline-flex;
      align-items: center;
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 12px;
      color: var(--text);
      background: rgba(255,255,255,.78);
      border: 1px solid rgba(95,167,119,.15);
    }
    .badge.online { color: #2f6d46; background: rgba(145, 211, 164, 0.22); border-color: rgba(95,167,119,.24); }
    .badge.warn { color: var(--warn); border-color: rgba(192,138,51,.24); background: rgba(255,240,213,.7); }
    .badge.danger { color: var(--danger); border-color: rgba(180,77,77,.24); background: rgba(255,231,231,.72); }
    .content {
      padding: 22px;
      display: flex;
      flex-direction: column;
      gap: 18px;
    }
    .topbar {
      padding: 18px 22px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 24px;
      background: linear-gradient(180deg, rgba(255,255,255,.72), rgba(255,255,255,.18));
      box-shadow: var(--shadow);
    }
    .topbar h2 { margin: 0; font-size: 20px; }
    .topbar p { margin: 6px 0 0; color: var(--text-muted); font-size: 13px; }
    .toolbar { display: flex; gap: 10px; align-items: center; }
    .ghost-btn, .send-btn {
      border: 1px solid var(--line-strong);
      background: rgba(255,255,255,.82);
      color: var(--text);
      border-radius: 999px;
      cursor: pointer;
      transition: .18s ease;
      padding: 10px 14px;
    }
    .ghost-btn:hover, .send-btn:hover {
      transform: translateY(-1px);
      border-color: rgba(95,167,119,.28);
      background: rgba(255,255,255,.96);
    }
    .send-btn {
      width: 100%;
      margin-top: 10px;
      background: linear-gradient(180deg, rgba(95,167,119,.96), rgba(63,127,88,.96));
      color: #f8fff9;
    }
    .dashboard {
      display: grid;
      grid-template-columns: 1.2fr .8fr;
      gap: 18px;
    }
    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 24px;
      overflow: hidden;
      box-shadow: var(--shadow);
      min-height: 180px;
    }
    .panel-header {
      padding: 16px 18px;
      border-bottom: 1px solid var(--line);
      background: linear-gradient(180deg, rgba(255,255,255,.72), rgba(255,255,255,.18));
    }
    .panel-header h3 {
      margin: 0;
      font-size: 15px;
    }
    .panel-header p {
      margin: 6px 0 0;
      font-size: 12px;
      color: var(--text-muted);
    }
    .panel-body {
      padding: 16px 18px;
    }
    .chat-shell {
      display: grid;
      grid-template-rows: 1fr auto;
      min-height: 620px;
    }
    .messages {
      overflow: auto;
      padding: 18px;
      display: flex;
      flex-direction: column;
      gap: 14px;
      background:
        linear-gradient(180deg, rgba(255,255,255,.44), transparent 12%),
        radial-gradient(circle at 50% 0%, rgba(95,167,119,.08), transparent 22%);
    }
    .msg {
      max-width: min(880px, 92%);
      border-radius: 18px;
      border: 1px solid var(--line);
      padding: 14px 16px;
      line-height: 1.55;
      white-space: pre-wrap;
      backdrop-filter: blur(6px);
    }
    .msg.user {
      align-self: flex-end;
      background: linear-gradient(180deg, rgba(157,214,174,.44), rgba(157,214,174,.24));
      border-color: rgba(95,167,119,.18);
    }
    .msg.agent {
      align-self: flex-start;
      background: linear-gradient(180deg, rgba(255,255,255,.96), rgba(241,249,243,.88));
      border-color: rgba(95,167,119,.14);
    }
    .msg-meta {
      display: flex;
      gap: 10px;
      align-items: center;
      margin-bottom: 8px;
      color: var(--text-muted);
      font-size: 12px;
    }
    .msg-head {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 12px;
      margin-bottom: 8px;
    }
    .msg-actions {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-shrink: 0;
    }
    .copy-btn {
      border: 1px solid var(--line-strong);
      background: rgba(255,255,255,.82);
      color: var(--text);
      border-radius: 999px;
      cursor: pointer;
      transition: .18s ease;
      padding: 6px 10px;
      font-size: 12px;
      line-height: 1;
    }
    .copy-btn:hover {
      border-color: rgba(95,167,119,.28);
      background: rgba(255,255,255,.96);
    }
    .copy-btn.copied {
      color: #2f6d46;
      background: rgba(145, 211, 164, 0.22);
      border-color: rgba(95,167,119,.24);
    }
    .composer {
      border-top: 1px solid var(--line);
      padding: 16px 18px 18px;
      background: rgba(244,251,246,.86);
    }
    .composer-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 14px;
    }
    .composer-card {
      padding: 14px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: rgba(255,255,255,.6);
    }
    .composer-card h3 { margin: 0 0 10px; font-size: 14px; }
    textarea {
      width: 100%;
      min-height: 110px;
      resize: vertical;
      border-radius: 16px;
      padding: 12px 14px;
      border: 1px solid var(--line-strong);
      background: rgba(255,255,255,.94);
      color: var(--text);
      font: inherit;
      outline: none;
    }
    textarea:focus {
      border-color: rgba(95,167,119,.42);
      box-shadow: 0 0 0 3px rgba(95,167,119,.12);
    }
    .hint { margin-top: 8px; color: var(--text-muted); font-size: 12px; line-height: 1.45; }
    .empty {
      padding: 20px;
      border-radius: 18px;
      border: 1px dashed var(--line-strong);
      color: var(--text-muted);
      background: rgba(255,255,255,.7);
    }
    .stat-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
    }
    .mini-stat {
      padding: 14px;
      border-radius: 18px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,.72);
    }
    .mini-stat .label {
      color: var(--text-muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .08em;
    }
    .mini-stat .value {
      margin-top: 8px;
      font-size: 24px;
      font-weight: 700;
    }
    .cards {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
    }
    .list-card {
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      background: rgba(255,255,255,.72);
    }
    .list-card h4 {
      margin: 0 0 10px;
      font-size: 14px;
    }
    .item-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
      max-height: 280px;
      overflow: auto;
    }
    .item {
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 12px;
      background: rgba(247,252,248,.86);
    }
    .item-title {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      align-items: center;
      font-size: 13px;
      font-weight: 600;
    }
    .item-meta {
      margin-top: 8px;
      color: var(--text-muted);
      font-size: 12px;
      line-height: 1.5;
      white-space: pre-wrap;
      word-break: break-word;
    }
    code.inline {
      padding: 2px 6px;
      border-radius: 8px;
      background: rgba(63,127,88,.08);
      border: 1px solid rgba(63,127,88,.1);
      font-size: 12px;
    }
    @media (max-width: 1180px) {
      .dashboard { grid-template-columns: 1fr; }
      .cards { grid-template-columns: 1fr; }
    }
    @media (max-width: 980px) {
      .app { grid-template-columns: 1fr; }
      .sidebar { display: none; }
      .content { padding: 14px; }
      .composer-grid { grid-template-columns: 1fr; }
      .msg { max-width: 100%; }
    }
  </style>
</head>
<body>
  <div class="app">
    <aside class="sidebar">
      <div class="brand">
        <div class="eyebrow">Multi-Agent Runtime Console</div>
        <h1>Local Workflow Surface</h1>
        <p>这是通用 agent-workflow 控制台。任意项目只要有 `agent_workflow.json`，都可以在这里切换、运行和观察。</p>
      </div>
      <div class="nav-card">
        <div style="color:var(--text-muted);font-size:12px;text-transform:uppercase;letter-spacing:.1em;">Channels</div>
        <div class="nav-item active">
          <div>
            <div style="font-weight:600;">terminal</div>
            <div style="color:var(--text-muted);font-size:12px;margin-top:4px;">default interactive surface</div>
          </div>
          <span class="badge online">online</span>
        </div>
      </div>
      <div class="stat-card">
        <div style="color:var(--text-muted);font-size:12px;text-transform:uppercase;letter-spacing:.1em;">Quick Stats</div>
        <div style="margin-top:10px;font-size:28px;font-weight:700;" id="messageCount">0</div>
        <div style="margin-top:6px;color:var(--text-muted);font-size:13px;">surface messages</div>
        <div style="margin-top:14px;font-size:28px;font-weight:700;" id="busMessageCount">0</div>
        <div style="margin-top:6px;color:var(--text-muted);font-size:13px;">bus messages</div>
      </div>
    </aside>
    <main class="content">
      <section class="topbar">
        <div>
          <h2>Workflow Debug Dashboard</h2>
          <p id="workflowMeta">用户消息会直接触发当前 workflow 运行。右侧所有观测区都会跟着刷新。</p>
        </div>
        <div class="toolbar">
          <select id="workflowSelect" class="ghost-btn" style="max-width:360px;" onchange="selectWorkflow()"></select>
          <button class="ghost-btn" id="sessionResetBtn" onclick="resetSession()" style="display:none;">New Session</button>
          <button class="ghost-btn" id="sessionReportBtn" onclick="generateSessionReport()" style="display:none;">Generate Report</button>
          <span class="badge online">live</span>
          <button class="ghost-btn" onclick="refreshAll()">Refresh</button>
        </div>
      </section>

      <section class="dashboard">
        <section class="panel chat-shell">
          <div id="messages" class="messages"></div>
          <div class="composer">
            <div class="composer-grid">
              <div class="composer-card">
                <h3>Send as User</h3>
                <textarea id="userInput" placeholder="输入一条用户消息，触发 workflow runtime"></textarea>
                <button class="send-btn" onclick="sendUser()">Run workflow from terminal message</button>
                <div class="hint">用户消息会进入 terminal channel，然后直接触发当前 workflow 运行。</div>
              </div>
              <div class="composer-card">
                <h3>Reply as Agent</h3>
                <textarea id="agentInput" placeholder="手动插入一条 agent 消息"></textarea>
                <button class="send-btn" onclick="sendAgent()">Send outbound message</button>
                <div class="hint">这个入口主要用来手动补消息，不会触发 workflow。</div>
              </div>
            </div>
          </div>
        </section>

        <section class="panel">
          <div class="panel-header">
            <h3>Runtime Overview</h3>
            <p>当前 workflow 的节点状态、最终回复与 bus 统计。</p>
          </div>
          <div class="panel-body">
            <div class="stat-grid">
              <div class="mini-stat">
                <div class="label">Final Response</div>
                <div class="value" id="finalResponsePreview" style="font-size:15px;font-weight:600;line-height:1.5;">-</div>
              </div>
              <div class="mini-stat">
                <div class="label">Current Owner</div>
                <div class="value" id="replyOwner">-</div>
              </div>
              <div class="mini-stat">
                <div class="label">Tasks</div>
                <div class="value" id="taskCount">0</div>
              </div>
              <div class="mini-stat">
                <div class="label">Contexts</div>
                <div class="value" id="contextCount">0</div>
              </div>
            </div>
            <div class="cards" style="margin-top:14px;">
              <div class="list-card">
                <h4>Node State</h4>
                <div id="nodeStateList" class="item-list"></div>
              </div>
              <div class="list-card">
                <h4>Agents</h4>
                <div id="agentStateList" class="item-list"></div>
              </div>
            </div>
          </div>
        </section>
      </section>

      <section class="dashboard">
        <section class="panel">
          <div class="panel-header">
            <h3>Bus Messages</h3>
            <p>单条消息生命周期：谁发给谁、类型、状态、reply_to、owner。</p>
          </div>
          <div class="panel-body">
            <div id="busMessageList" class="item-list"></div>
          </div>
        </section>
        <section class="panel">
          <div class="panel-header">
            <h3>Tasks</h3>
            <p>任务聚合状态：participants、pending replies、final response、current owner。</p>
          </div>
          <div class="panel-body">
            <div id="taskList" class="item-list"></div>
          </div>
        </section>
      </section>

      <section class="dashboard">
        <section class="panel">
          <div class="panel-header">
            <h3>Context Summary</h3>
            <p>context_id 维度的摘要、open tasks、handoff notes 与 recent raw events。</p>
          </div>
          <div class="panel-body">
            <div id="contextList" class="item-list"></div>
          </div>
        </section>
        <section class="panel">
          <div class="panel-header">
            <h3>Latest Runtime Log</h3>
            <p>最近一段 runtime_execution.log，方便你对照 UI 与真实执行顺序。</p>
          </div>
          <div class="panel-body">
            <div id="runtimeLogList" class="item-list"></div>
          </div>
        </section>
      </section>
    </main>
  </div>
  <script>
    async function loadWorkflowOptions() {
      const data = await api("/api/workflows");
      const select = document.getElementById("workflowSelect");
      if (!select) return;
      const current = data.current_workflow_path || "";
      select.innerHTML = "";
      for (const item of (data.workflows || [])) {
        const option = document.createElement("option");
        option.value = item.path;
        option.textContent = item.label;
        option.selected = item.path === current;
        select.appendChild(option);
      }
    }

    async function selectWorkflow() {
      const select = document.getElementById("workflowSelect");
      const workflowPath = (select?.value || "").trim();
      if (!workflowPath) return;
      await api("/api/select-workflow", {
        method: "POST",
        body: JSON.stringify({ workflow_path: workflowPath })
      });
      await refreshAll();
    }

    async function resetSession() {
      await api("/api/session/reset", { method: "POST", body: JSON.stringify({}) });
      await refreshAll();
    }

    async function generateSessionReport() {
      const data = await api("/api/session/report", { method: "POST", body: JSON.stringify({}) });
      if (data?.report) {
        alert(data.report);
      }
      await refreshAll();
    }

    async function api(path, options = {}) {
      const response = await fetch(path, {
        headers: { "Content-Type": "application/json" },
        ...options
      });
      return response.json();
    }

    function escapeHtml(text) {
      const div = document.createElement("div");
      div.textContent = text || "";
      return div.innerHTML;
    }

    function badgeClass(status) {
      if (["failed", "timeout", "rejected"].includes(status)) return "badge danger";
      if (["processing", "running", "waiting_reply", "handoff_in_progress"].includes(status)) return "badge warn";
      if (["completed", "replied", "done"].includes(status)) return "badge online";
      return "badge";
    }

    function truncate(text, max = 220) {
      const value = text || "";
      return value.length > max ? value.slice(0, max) + "..." : value;
    }

    async function copyMessage(button) {
      const text = button?.dataset?.copyText || "";
      if (!text) return;
      const original = button.textContent;
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          const textarea = document.createElement("textarea");
          textarea.value = text;
          textarea.setAttribute("readonly", "readonly");
          textarea.style.position = "absolute";
          textarea.style.left = "-9999px";
          document.body.appendChild(textarea);
          textarea.select();
          document.execCommand("copy");
          document.body.removeChild(textarea);
        }
        button.textContent = "已复制";
        button.classList.add("copied");
        setTimeout(() => {
          button.textContent = original;
          button.classList.remove("copied");
        }, 1400);
      } catch (error) {
        button.textContent = "复制失败";
        setTimeout(() => {
          button.textContent = original;
        }, 1400);
      }
    }

    function renderMessages(items) {
      const root = document.getElementById("messages");
      const count = document.getElementById("messageCount");
      count.textContent = String(items.length);
      root.innerHTML = "";
      if (!items.length) {
        root.innerHTML = '<div class="empty">暂无消息。先从左下角输入一条用户消息，workflow 就会开始运行。</div>';
        return;
      }
      for (const item of items) {
        const div = document.createElement("div");
        div.className = "msg " + (item.direction === "inbound" ? "user" : "agent");
        const date = new Date(item.created_at * 1000);
        const role = item.direction === "inbound" ? "user" : "agent";
        const showCopy = item.direction !== "inbound";
        const safeContent = escapeHtml(item.content);
        div.innerHTML = `
          <div class="msg-head">
            <div class="msg-meta">
              <span class="badge">${role}</span>
              <span>${escapeHtml(item.sender || "-")} -> ${escapeHtml(item.receiver || "-")}</span>
              <span>${date.toLocaleString()}</span>
            </div>
            <div class="msg-actions">
              ${showCopy ? `<button class="copy-btn" data-copy-text="${safeContent}" onclick="copyMessage(this)">复制</button>` : ""}
            </div>
          </div>
          <div>${safeContent}</div>
        `;
        if (showCopy) {
          const button = div.querySelector(".copy-btn");
          if (button) {
            button.dataset.copyText = item.content || "";
          }
        }
        root.appendChild(div);
      }
      root.scrollTop = root.scrollHeight;
    }

    function renderSimpleItems(rootId, items, renderer, emptyText) {
      const root = document.getElementById(rootId);
      root.innerHTML = "";
      if (!items || !items.length) {
        root.innerHTML = `<div class="empty">${escapeHtml(emptyText)}</div>`;
        return;
      }
      for (const item of items) {
        const div = document.createElement("div");
        div.className = "item";
        div.innerHTML = renderer(item);
        root.appendChild(div);
      }
    }

    function renderDashboard(snapshot) {
      const runtime = snapshot.runtime_result || {};
      const session = snapshot.session || {};
      const mode = snapshot.mode || "workflow";
      const bus = snapshot.bus || {};
      const currentWorkflow = snapshot.current_workflow || {};
      const messages = bus.messages || [];
      const tasks = bus.tasks || [];
      const contexts = bus.contexts || [];
      const agents = bus.agents || [];
      const sessionResetBtn = document.getElementById("sessionResetBtn");
      const sessionReportBtn = document.getElementById("sessionReportBtn");
      if (sessionResetBtn) sessionResetBtn.style.display = mode === "session" ? "inline-flex" : "none";
      if (sessionReportBtn) sessionReportBtn.style.display = mode === "session" ? "inline-flex" : "none";
      const meta = document.getElementById("workflowMeta");
      if (meta) {
        meta.textContent = mode === "session"
          ? `当前 workflow：${currentWorkflow.label || "-"}。这套工作流正在使用 session 式 CBT 访谈 runtime。`
          : `当前 workflow：${currentWorkflow.label || "-"}。用户消息会直接触发这一套 agent-workflow 运行。`;
      }
      document.getElementById("busMessageCount").textContent = String(messages.length);
      document.getElementById("taskCount").textContent = String(tasks.length);
      document.getElementById("contextCount").textContent = String(contexts.length);
      document.getElementById("finalResponsePreview").textContent = mode === "session"
        ? truncate(session.report || `${session.current_stage_name || "-"} (${session.current_stage || 0})`, 180)
        : truncate(runtime.final_response || "-", 180);

      const owner = mode === "session"
        ? (session.current_stage_name || "-")
        : (tasks.length ? (tasks[0].current_owner_agent || "-") : "-");
      document.getElementById("replyOwner").textContent = owner;

      const nodeEntries = Object.entries(runtime.state || {});
      renderSimpleItems(
        "nodeStateList",
        mode === "session"
          ? [
              {
                node_id: "session",
                state: session.is_end ? "completed" : (session.initialized ? "running" : "pending"),
              },
              {
                node_id: "stage",
                state: `${session.current_stage || 0} / ${session.current_stage_name || "-"}`,
              }
            ]
          : nodeEntries.map(([node_id, state]) => ({ node_id, state })),
        (item) => `
          <div class="item-title">
            <span><code class="inline">${escapeHtml(item.node_id)}</code></span>
            <span class="${badgeClass(item.state)}">${escapeHtml(item.state)}</span>
          </div>
        `,
        "暂无节点状态。"
      );

      renderSimpleItems(
        "agentStateList",
        mode === "session"
          ? [
              {
                agent_id: "cbt-session",
                inbox_count: (session.personal_info?.emo_list || []).length,
                history_count: (session.personal_info?.event_list || []).length,
                latest_context_id: `ideas=${(session.personal_info?.idea_list || []).length}`,
              }
            ]
          : agents,
        (item) => `
          <div class="item-title">
            <span><code class="inline">${escapeHtml(item.agent_id)}</code></span>
            <span class="badge">${item.inbox_count} inbox / ${item.history_count} history</span>
          </div>
          <div class="item-meta">latest_context: ${escapeHtml(item.latest_context_id || "-")}</div>
        `,
        "暂无 agent 状态。"
      );

      renderSimpleItems(
        "busMessageList",
        messages,
        (item) => `
          <div class="item-title">
            <span><code class="inline">${escapeHtml(item.message_id)}</code></span>
            <span class="${badgeClass(item.status)}">${escapeHtml(item.status)}</span>
          </div>
          <div class="item-meta">
type: ${escapeHtml(item.message_type)}\n
from: ${escapeHtml(item.from_agent || "-")} -> ${escapeHtml(item.to_agent || "-")}\n
owner: ${escapeHtml(item.owner_agent || "-")}\n
reply_to: ${escapeHtml(item.reply_to || "-")}\n
text: ${escapeHtml(truncate(item.content?.text || "", 200))}
          </div>
        `,
        "暂无总线消息。"
      );

      renderSimpleItems(
        "taskList",
        tasks,
        (item) => `
          <div class="item-title">
            <span><code class="inline">${escapeHtml(item.task_id)}</code></span>
            <span class="${badgeClass(item.status)}">${escapeHtml(item.status)}</span>
          </div>
          <div class="item-meta">
node: ${escapeHtml(item.node_id)}\n
owner: ${escapeHtml(item.current_owner_agent || "-")}\n
participants: ${escapeHtml((item.participants || []).join(", ") || "-")}\n
pending_replies: ${escapeHtml((item.pending_replies || []).join(", ") || "-")}\n
final_response_message_id: ${escapeHtml(item.final_response_message_id || "-")}
          </div>
        `,
        "暂无任务状态。"
      );

      renderSimpleItems(
        "contextList",
        contexts,
        (item) => `
          <div class="item-title">
            <span><code class="inline">${escapeHtml(item.context_id)}</code></span>
            <span class="badge">${item.event_count} events</span>
          </div>
          <div class="item-meta">
summary: ${escapeHtml(truncate(item.summary || "-", 200))}\n
open_tasks: ${escapeHtml((item.open_tasks || []).join(" | ") || "-")}\n
handoff_notes: ${escapeHtml(String((item.handoff_notes || []).length))}
          </div>
        `,
        "暂无上下文摘要。"
      );

      renderSimpleItems(
        "runtimeLogList",
        snapshot.runtime_log || [],
        (item) => `
          <div class="item-title">
            <span>${escapeHtml(item.timestamp || "-")}</span>
            <span class="badge">${escapeHtml(item.event || "-")}</span>
          </div>
          <div class="item-meta">${escapeHtml(JSON.stringify(item.details || {}, null, 2))}</div>
        `,
        "暂无 runtime 日志。"
      );
    }

    async function refreshMessages() {
      const data = await api("/api/messages");
      renderMessages(data.messages || []);
    }

    async function refreshDashboard() {
      const data = await api("/api/dashboard");
      if (data.ok) {
        renderDashboard(data);
      }
    }

    async function refreshAll() {
      await loadWorkflowOptions();
      await refreshMessages();
      await refreshDashboard();
    }

    async function sendUser() {
      const textarea = document.getElementById("userInput");
      const content = textarea.value.trim();
      if (!content) return;
      await api("/api/user-message", { method: "POST", body: JSON.stringify({ content }) });
      textarea.value = "";
      await refreshAll();
    }

    async function sendAgent() {
      const textarea = document.getElementById("agentInput");
      const content = textarea.value.trim();
      if (!content) return;
      await api("/api/agent-message", { method: "POST", body: JSON.stringify({ content }) });
      textarea.value = "";
      await refreshAll();
    }

    refreshAll();
    setInterval(refreshAll, 2500);
  </script>
</body>
</html>
"""


class LocalUIHandler(BaseHTTPRequestHandler):
    manager = ChannelManager(config={"channels": [{"id": "terminal", "enable": "true", "echo_to_stdout": "false"}]})
    available_workflows = discover_workflows()
    session_backends: dict[str, Any] = {}
    workflow_path = (
        str(SRC_DIR.parent / "workspace" / "agent_workflow" / "agent_workflow.json")
        if (SRC_DIR.parent / "workspace" / "agent_workflow" / "agent_workflow.json").exists()
        else (available_workflows[0]["path"] if available_workflows else "")
    )

    def do_GET(self) -> None:
        if self.path == "/":
            self._write_html(HTML)
            return
        if self.path.startswith("/api/messages"):
            messages = [item.to_dict() for item in self.manager.list_messages("terminal", limit=200)]
            self._write_json({"ok": True, "messages": messages})
            return
        if self.path.startswith("/api/runtime-result"):
            result_path = Path(self.workflow_path).parent / "runtime_execution_result.json"
            if not result_path.exists():
                self._write_json({"ok": True, "result": {}})
                return
            self._write_json({"ok": True, "result": json.loads(result_path.read_text(encoding="utf-8"))})
            return
        if self.path.startswith("/api/workflows"):
            self._write_json(
                {
                    "ok": True,
                    "current_workflow_path": self.workflow_path,
                    "workflows": self.available_workflows,
                }
            )
            return
        if self.path.startswith("/api/dashboard"):
            self._write_json(self._build_dashboard_payload())
            return
        self._write_json({"ok": False, "error": "not found"}, status=HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        payload = self._read_json()
        if self.path == "/api/user-message":
            content = str(payload.get("content", ""))
            if self._is_session_mode():
                try:
                    backend = self._get_session_backend()
                    startup = backend.ensure_started()
                    self._sync_assistant_messages(startup.get("assistant_messages", []), sender="cbt-session")
                    inbound = self.manager.push_inbound_message("terminal", content)
                    result = backend.respond(content)
                    outbound_messages = self._sync_assistant_messages(result.get("assistant_messages", []), sender="cbt-session")
                    self._write_json(
                        {
                            "ok": True,
                            "mode": "session",
                            "inbound": inbound.to_dict(),
                            "outbound_messages": outbound_messages,
                            "session": result.get("snapshot", {}),
                        }
                    )
                except Exception as exc:  # noqa: BLE001
                    self._write_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
                return
            inbound = self.manager.push_inbound_message("terminal", content)
            try:
                runner = runtime(workflow_path=self.workflow_path)
                runtime_result = runner.run(content)
                final_response = runtime_result.get("final_response") or "workflow finished without a final response"
                outbound = self.manager.send_message("terminal", final_response)
                self._write_json(
                    {
                        "ok": True,
                        "mode": "workflow",
                        "inbound": inbound.to_dict(),
                        "outbound": outbound.to_dict(),
                        "runtime_result": {
                            "result_path": runtime_result.get("result_path", ""),
                            "final_response": final_response,
                            "state": runtime_result.get("state", {}),
                        },
                    }
                )
            except Exception as exc:  # noqa: BLE001
                self._write_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if self.path == "/api/agent-message":
            result = self.manager.send_message("terminal", str(payload.get("content", "")))
            self._write_json(result.to_dict())
            return
        if self.path == "/api/select-workflow":
            raw_path = str(payload.get("workflow_path", "")).strip()
            if not raw_path:
                self._write_json({"ok": False, "error": "workflow_path is required"}, status=HTTPStatus.BAD_REQUEST)
                return
            selected = Path(raw_path)
            if not selected.exists() or selected.name != "agent_workflow.json":
                self._write_json({"ok": False, "error": f"workflow not found: {raw_path}"}, status=HTTPStatus.BAD_REQUEST)
                return
            resolved_workflow = str(selected.resolve())
            self.__class__.session_backends.pop(resolved_workflow, None)
            self.__class__.workflow_path = resolved_workflow
            self.__class__.available_workflows = discover_workflows()
            self.manager.clear_messages("terminal")
            self._write_json(
                {
                    "ok": True,
                    "workflow_path": self.workflow_path,
                    "workflow_dir": str(selected.parent),
                }
            )
            return
        if self.path == "/api/session/reset":
            if not self._is_session_mode():
                self._write_json({"ok": False, "error": "current workflow is not session-based"}, status=HTTPStatus.BAD_REQUEST)
                return
            try:
                self.manager.clear_messages("terminal")
                backend = self._get_session_backend(reset=True)
                result = backend.reset()
                outbound_messages = self._sync_assistant_messages(result.get("assistant_messages", []), sender="cbt-session")
                self._write_json({"ok": True, "outbound_messages": outbound_messages, "session": result.get("snapshot", {})})
            except Exception as exc:  # noqa: BLE001
                self._write_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        if self.path == "/api/session/report":
            if not self._is_session_mode():
                self._write_json({"ok": False, "error": "current workflow is not session-based"}, status=HTTPStatus.BAD_REQUEST)
                return
            try:
                backend = self._get_session_backend()
                result = backend.generate_report()
                self._write_json({"ok": True, "report": result.get("report", ""), "session": result.get("snapshot", {})})
            except Exception as exc:  # noqa: BLE001
                self._write_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        self._write_json({"ok": False, "error": "not found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _workflow_dir(self) -> Path:
        return Path(self.workflow_path).parent

    def _load_workflow_config(self) -> Dict[str, Any]:
        path = Path(self.workflow_path)
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

    def _session_runtime_config(self) -> Dict[str, Any]:
        workflow = self._load_workflow_config()
        payload = workflow.get("session_runtime", {})
        return payload if isinstance(payload, dict) else {}

    def _is_session_mode(self) -> bool:
        config = self._session_runtime_config()
        return bool(config.get("enabled")) and str(config.get("type", "")).strip().lower() == "cbt_legacy"

    def _get_session_backend(self, *, reset: bool = False) -> CbtLegacySessionRuntime:
        workflow_path = str(Path(self.workflow_path).resolve())
        if reset:
            self.__class__.session_backends.pop(workflow_path, None)
        backend = self.__class__.session_backends.get(workflow_path)
        if backend is not None:
            return backend
        config = self._session_runtime_config()
        backend = CbtLegacySessionRuntime(
            experiment_dir=str(config.get("experiment_dir", "")).strip(),
            openclaw_config_path=str(config.get("openclaw_config_path", "")).strip(),
            provider=str(config.get("provider", "custom-aiapi-meccy-top")).strip(),
            model=str(config.get("model", "gpt-5.4")).strip(),
            temperature=float(config.get("temperature", 0.7) or 0.7),
        )
        self.__class__.session_backends[workflow_path] = backend
        return backend

    def _sync_assistant_messages(self, messages: list[str], sender: str = "agent") -> list[Dict[str, Any]]:
        synced: list[Dict[str, Any]] = []
        for text in messages:
            result = self.manager.send_message("terminal", str(text), sender=sender, receiver="user")
            synced.append(result.to_dict())
        return synced

    def _current_workflow_info(self) -> Dict[str, str]:
        path = Path(self.workflow_path)
        project = path.parents[2].name if len(path.parents) >= 3 else path.parent.name
        workflow = path.parent.name
        return {
            "path": str(path),
            "project": project,
            "workflow": workflow,
            "label": f"{project} / {workflow}",
        }

    def _runtime_bus_dir(self) -> Path:
        return self._workflow_dir() / "runtime_bus"

    def _read_json_file(self, path: Path, default: Dict[str, Any] | None = None) -> Dict[str, Any]:
        if not path.exists():
            return default or {}
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return default or {}

    def _read_jsonl_file(self, path: Path) -> list[Dict[str, Any]]:
        if not path.exists():
            return []
        items: list[Dict[str, Any]] = []
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    items.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        except OSError:
            return []
        return items

    def _load_runtime_result(self) -> Dict[str, Any]:
        return self._read_json_file(self._workflow_dir() / "runtime_execution_result.json", default={})

    def _load_runtime_log(self) -> list[Dict[str, Any]]:
        result = self._load_runtime_result()
        log = result.get("execution_log", [])
        if isinstance(log, list):
            return [item for item in log if isinstance(item, dict)][-20:]
        return []

    def _load_bus_messages(self) -> list[Dict[str, Any]]:
        message_dir = self._runtime_bus_dir() / "messages"
        items = [self._read_json_file(path, default={}) for path in sorted(message_dir.glob("*.json"))]
        items = [item for item in items if item]
        items.sort(key=lambda item: item.get("created_at", ""))
        return items

    def _load_bus_tasks(self) -> list[Dict[str, Any]]:
        task_dir = self._runtime_bus_dir() / "tasks"
        items = [self._read_json_file(path, default={}) for path in sorted(task_dir.glob("*.json"))]
        items = [item for item in items if item]
        items.sort(key=lambda item: item.get("created_at", ""))
        return items

    def _load_bus_agents(self) -> list[Dict[str, Any]]:
        agent_dir = self._runtime_bus_dir() / "agents"
        agents: list[Dict[str, Any]] = []
        for path in sorted(agent_dir.iterdir()) if agent_dir.exists() else []:
            if not path.is_dir():
                continue
            inbox = self._read_json_file(path / "inbox.json", default={"message_ids": []})
            history = self._read_jsonl_file(path / "history.jsonl")
            latest_context_id = history[-1].get("context_id", "") if history else ""
            agents.append(
                {
                    "agent_id": path.name,
                    "inbox_count": len(inbox.get("message_ids", [])) if isinstance(inbox.get("message_ids", []), list) else 0,
                    "history_count": len(history),
                    "latest_context_id": latest_context_id,
                }
            )
        return agents

    def _load_bus_contexts(self) -> list[Dict[str, Any]]:
        context_dir = self._runtime_bus_dir() / "contexts"
        contexts: list[Dict[str, Any]] = []
        for path in sorted(context_dir.iterdir()) if context_dir.exists() else []:
            if not path.is_dir():
                continue
            summary = self._read_json_file(path / "summary.json", default={})
            events = self._read_jsonl_file(path / "events.jsonl")
            contexts.append(
                {
                    "context_id": path.name,
                    "summary": summary.get("summary", ""),
                    "open_tasks": summary.get("open_tasks", []),
                    "handoff_notes": summary.get("handoff_notes", []),
                    "event_count": len(events),
                }
            )
        return contexts

    def _build_dashboard_payload(self) -> Dict[str, Any]:
        session_payload: Dict[str, Any] = {}
        mode = "session" if self._is_session_mode() else "workflow"
        if mode == "session":
            backend = self._get_session_backend()
            startup = backend.ensure_started()
            self._sync_assistant_messages(startup.get("assistant_messages", []), sender="cbt-session")
            session_payload = startup.get("snapshot", {})
        return {
            "ok": True,
            "mode": mode,
            "current_workflow": self._current_workflow_info(),
            "available_workflows": self.available_workflows,
            "session": session_payload,
            "messages": [item.to_dict() for item in self.manager.list_messages("terminal", limit=200)],
            "runtime_result": self._load_runtime_result(),
            "runtime_log": self._load_runtime_log(),
            "bus": {
                "messages": self._load_bus_messages(),
                "tasks": self._load_bus_tasks(),
                "agents": self._load_bus_agents(),
                "contexts": self._load_bus_contexts(),
            },
        }

    def _read_json(self) -> Dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {}

    def _write_html(self, content: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = content.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_json(self, payload: Dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the generic agent-workflow local UI.")
    parser.add_argument("--workflow", default="", help="Optional default agent_workflow.json path")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind")
    parser.add_argument("--port", type=int, default=8765, help="Port to bind")
    args = parser.parse_args()

    if args.workflow:
        workflow_path = Path(args.workflow).resolve()
        if not workflow_path.exists() or workflow_path.name != "agent_workflow.json":
            raise FileNotFoundError(f"workflow not found: {workflow_path}")
        LocalUIHandler.workflow_path = str(workflow_path)
    LocalUIHandler.available_workflows = discover_workflows()
    if LocalUIHandler.available_workflows and not Path(LocalUIHandler.workflow_path).exists():
        LocalUIHandler.workflow_path = LocalUIHandler.available_workflows[0]["path"]

    host = args.host
    port = args.port
    server = ThreadingHTTPServer((host, port), LocalUIHandler)
    print(f"Generic agent-workflow UI running at http://{host}:{port}")
    print(f"Current workflow: {LocalUIHandler.workflow_path}")
    server.serve_forever()


if __name__ == "__main__":
    main()
