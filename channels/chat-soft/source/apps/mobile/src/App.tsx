import { Fragment, useEffect, useMemo, useReducer, useRef, useState } from "react";
import { ChatClient, createId } from "@chat-soft/core";
import type { TodoItem } from "@chat-soft/protocol";
import { marked } from "marked";

const Markdown = ({ text }: { text: string }) => {
  const html = useMemo(() => {
    try { return marked.parse(text, { async: false }) as string; }
    catch { return text; }
  }, [text]);
  return <div className="markdown-body" dangerouslySetInnerHTML={{ __html: html }} />;
};

/* ── Types ─────────────────────────────── */

interface ToolInfo {
  tool: string;
  summary: string;
  output?: string;
  title?: string;
  status: "pending" | "running" | "completed" | "error";
}
interface ActiveStep {
  id: string;
  status: "running" | "done";
  startedAt: number;
  completedAt?: number;
  thinking?: string;
  tools: ToolInfo[];
  tokens?: { total: number };
}
interface Message {
  id: string;
  role: "user" | "assistant";
  text: string;
  steps?: ActiveStep[];
}
type PickerItem = { label: string; value: string; current: boolean };
type Picker = { type: "agent" | "model" | "session"; items: PickerItem[] };

interface AppState {
  messages: Message[];
  streamingText: string;
  streamingId: string | null;
  activeSteps: ActiveStep[];
  completedSteps: ActiveStep[];
  todos: TodoItem[];
  todoCollapsed: boolean;
  agentName: string;
  modelName: string;
  tokenUsed: number;
  tokenTotal: number;
  sessionId: string | null;
  showCommand: boolean;
  picker: Picker | null;
  inputText: string;
  authenticated: boolean;
}

/* ── Constants ──────────────────────────── */

const WEB_AUTH_USERNAME = "chisado";
const WEB_AUTH_PASSWORD = "chisado233";
const AUTH_KEY = "chatsoft.mobile.webAuth";

const TOOL_ICONS: Record<string, string> = {
  apply_patch: "\u270E", edit: "\u270E", write: "\u270E",
  read: "\uD83D\uDCC4", glob: "\uD83D\uDCC4", grep: "\uD83D\uDCC4",
  bash: "\u2699", websearch_web_search_exa: "\uD83C\uDF10",
  webfetch: "\uD83C\uDF10", task: "\uD83E\uDD16", todowrite: "\u2610"
};
const STATUS_ICONS: Record<ToolInfo["status"], string> = {
  pending: "\u25CB", running: "\u25CC", completed: "\u2713", error: "\u2717"
};

function fmtDur(step: ActiveStep, now: number) {
  return ((Math.max(0, (step.completedAt ?? now) - step.startedAt)) / 1000).toFixed(1) + "s";
}
function fmtTok(n: number) {
  return n >= 1000 ? (n / 1000).toFixed(1) + "K" : String(n);
}
function fmtPct(used: number, total: number) {
  return total > 0 ? Math.round((used / total) * 100) + "%" : "0%";
}

/* ── Reducer helpers ────────────────────── */

function updStep(steps: ActiveStep[], id: string, fn: (s: ActiveStep) => ActiveStep): ActiveStep[] {
  return steps.map(s => (s.id === id ? fn(s) : s));
}
function updTool(step: ActiveStep, nm: string, fn: (t: ToolInfo | undefined) => ToolInfo): ActiveStep {
  const idx = step.tools.findIndex(t => t.tool === nm);
  return {
    ...step,
    tools: idx === -1 ? [...step.tools, fn(undefined)] : step.tools.map((t, i) => (i === idx ? fn(t) : t))
  };
}
function markDone(step: ActiveStep): ActiveStep {
  return {
    ...step,
    tools: step.tools.map(t => ({ ...t, status: t.status === "error" ? "error" : "completed" as const }))
  };
}

/* ── Reducer ────────────────────────────── */

type Action =
  | { type: "STREAM_TEXT"; id: string; text: string }
  | { type: "STREAM_DONE"; id: string; finalText: string }
  | { type: "STEP_START"; stepId: string }
  | { type: "STEP_DONE"; stepId: string; tokens?: { total: number } }
  | { type: "STEP_TOOL"; stepId: string; tool: string; summary: string }
  | { type: "TOOL_STATUS"; stepId: string; tool: string; status: ToolInfo["status"]; title?: string }
  | { type: "TOOL_DETAIL"; stepId: string; tool: string; output: string; title: string }
  | { type: "THINKING"; stepId: string; text: string }
  | { type: "STATUS"; agent?: string; model?: string; tokenUsed?: number; tokenTotal?: number; sessionId?: string }
  | { type: "TODO"; todos: TodoItem[] }
  | { type: "COMMAND_RESPONSE"; command: string; data: unknown }
  | { type: "INPUT"; text: string }
  | { type: "SEND" }
  | { type: "TOGGLE_TODO" }
  | { type: "OPEN_PICKER"; picker: Picker }
  | { type: "CLOSE_PICKER" }
  | { type: "AUTH_OK" }
  | { type: "SSE_EVENT"; eventType: string; data: any };

const initialState: AppState = {
  messages: [], streamingText: "", streamingId: null, activeSteps: [], completedSteps: [],
  todos: [], todoCollapsed: true,
  agentName: "private-assistant", modelName: "", tokenUsed: 0, tokenTotal: 1048576, sessionId: null,
  showCommand: false, picker: null, inputText: "",
  authenticated: localStorage.getItem(AUTH_KEY) === "ok"
};

function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    case "STREAM_TEXT":
      return state.streamingId === action.id
        ? { ...state, streamingText: state.streamingText + action.text }
        : { ...state, streamingId: action.id, streamingText: action.text };

    case "STREAM_DONE": {
      const ft = state.streamingText || action.finalText;
      const msg: Message = {
        id: action.id, role: "assistant", text: ft,
        steps: [...state.completedSteps, ...state.activeSteps.map(s => ({ ...markDone(s), status: "done" as const, completedAt: Date.now() }))]
      };
      return { ...state, streamingText: "", streamingId: null, messages: [...state.messages, msg], activeSteps: [], completedSteps: [] };
    }

    case "STEP_START":
      return { ...state, activeSteps: [...state.activeSteps, { id: action.stepId, status: "running", startedAt: Date.now(), tools: [] }] };

    case "STEP_TOOL":
      return { ...state, activeSteps: updStep(state.activeSteps, action.stepId, s => updTool(s, action.tool, t => ({
        tool: action.tool, summary: action.summary, output: t?.output, title: t?.title, status: t?.status ?? "running"
      }))) };

    case "TOOL_STATUS":
      return { ...state, activeSteps: updStep(state.activeSteps, action.stepId, s => updTool(s, action.tool, t => ({
        tool: action.tool, summary: t?.summary ?? "", output: t?.output, title: action.title ?? t?.title, status: action.status
      }))) };

    case "TOOL_DETAIL":
      return { ...state, activeSteps: updStep(state.activeSteps, action.stepId, s => updTool(s, action.tool, t => ({
        tool: action.tool, summary: t?.summary ?? "", output: action.output, title: action.title || t?.title,
        status: t?.status === "error" ? "error" : "completed"
      }))) };

    case "THINKING":
      return { ...state, activeSteps: updStep(state.activeSteps, action.stepId, s => ({
        ...s, thinking: s.thinking ? s.thinking + "\n" + action.text : action.text
      })) };

    case "STEP_DONE": {
      const st = state.activeSteps.find(s => s.id === action.stepId);
      if (!st) return state;
      return {
        ...state,
        activeSteps: state.activeSteps.filter(s => s.id !== action.stepId),
        completedSteps: [...state.completedSteps, { ...markDone(st), status: "done", completedAt: Date.now(), tokens: action.tokens }]
      };
    }

    case "STATUS":
      return { ...state, agentName: action.agent ?? state.agentName, modelName: action.model ?? state.modelName, tokenUsed: action.tokenUsed ?? state.tokenUsed, tokenTotal: action.tokenTotal ?? state.tokenTotal, sessionId: action.sessionId ?? state.sessionId };

    case "TODO": return { ...state, todos: action.todos, todoCollapsed: false };
    case "COMMAND_RESPONSE": {
      const d = action.data as { kind: string; items: { name?: string; sessionId?: string; title?: string; current?: boolean }[]; current?: string | null };
      const items: PickerItem[] = d.items.map(i => ({
        label: i.name || i.title || i.sessionId || "",
        value: i.name || i.sessionId || "",
        current: i.current ?? false
      }));
      return { ...state, picker: { type: action.command.replace("/", "") as Picker["type"], items } };
    }
    case "INPUT": return { ...state, inputText: action.text, showCommand: action.text === "/" };
    case "SEND":
      return { ...state, inputText: "", showCommand: false, messages: [...state.messages, { id: createId(), role: "user", text: state.inputText }], activeSteps: [], completedSteps: [] };
    case "TOGGLE_TODO": return { ...state, todoCollapsed: !state.todoCollapsed };
    case "OPEN_PICKER": return { ...state, picker: action.picker, showCommand: false };
    case "CLOSE_PICKER": return { ...state, picker: null };
    case "AUTH_OK": return { ...state, authenticated: true };
    case "SSE_EVENT": {
      const d = action.data;
      const p = d?.properties || {};
      switch (action.eventType) {
        case "message.part.delta":
          if (p.delta) return { ...state, streamingText: state.streamingText + (p.delta||""), streamingId: p.messageID || state.streamingId || p.partID };
          return state;
        case "message.part.updated": {
          const pt = p.part || {};
          if (pt.type === "tool") {
            const st = pt.state?.status || pt.status || "";
            const sid = p.sessionID || pt.id || pt.sessionID || "";
            const tn = pt.tool || "";
            if (st) return { ...state, activeSteps: updStep(state.activeSteps, sid, s => 
              updTool(s, tn, t => ({ tool: tn, summary: t?.summary || pt.state?.title || pt.title || "", output: t?.output || (typeof pt.state?.output === "string" ? pt.state.output : "") || "", title: t?.title || pt.state?.title || pt.title || "", status: st as ToolInfo["status"] }))
            )};
          }
          if (pt.type === "step-start") {
            return { ...state, activeSteps: [...state.activeSteps, { id: p.sessionID || pt.id || pt.sessionID || "", status: "running" as const, startedAt: Date.now(), tools: [] }] };
          }
          if (pt.type === "step-finish") {
            const sid = p.sessionID || pt.id || pt.sessionID || "";
            const stp = state.activeSteps.find(s => s.id === sid);
            if (!stp) return state;
            const tok = pt.tokens;
            return { ...state, activeSteps: state.activeSteps.filter(s => s.id !== sid), completedSteps: [...state.completedSteps, { ...markDone(stp), status: "done" as const, completedAt: Date.now(), tokens: tok }] };
          }
          if (pt.type === "text" && pt.text) {
            return { ...state, streamingText: pt.text, streamingId: p.sessionID || pt.sessionID || state.streamingId };
          }
          if (pt.type === "reasoning" || pt.type === "thinking") {
            const sid = p.sessionID || pt.sessionID || "";
            const txt = pt.text || "";
            if (txt) return { ...state, activeSteps: updStep(state.activeSteps, sid, s => ({ ...s, thinking: s.thinking ? s.thinking + "\n" + txt : txt })) };
          }
          return state;
        }
        case "session.idle": {
          const final = state.streamingText;
          const msg: Message = {
            id: p.sessionID || "",
            role: "assistant",
            text: final,
            steps: [...state.completedSteps, ...state.activeSteps.map(s => ({ ...markDone(s), status: "done" as const, completedAt: Date.now() }))]
          };
          return { ...state, streamingText: "", streamingId: null, messages: [...state.messages, msg], activeSteps: [], completedSteps: [] };
        }
        case "todo.updated":
          if (Array.isArray(p.todos)) return { ...state, todos: p.todos, todoCollapsed: false };
          return state;
        case "message.updated":
          if (p.info?.tokens?.total) return { ...state, tokenUsed: p.info.tokens.total };
          return state;
        case "session.status":
          return state;
        case "session.diff":
        case "file.edited":
          return state;
        default: return state;
      }
    }
    default: return state;
  }
}

/* ── Components ─────────────────────────── */

function TodoPanel({ todos, collapsed, onToggle }: { todos: TodoItem[]; collapsed: boolean; onToggle: () => void }) {
  if (!todos.length) return null;
  const done = todos.filter(t => t.status === "completed").length;
  return (
    <div className={`todo-panel${collapsed ? " collapsed" : ""}`}>
      <div className="todo-header">
        <span>Tasks {done}/{todos.length} done</span>
        <button onClick={onToggle}>{collapsed ? "Show" : "Hide"}</button>
      </div>
      {todos.map((t, i) => (
        <div key={i} className={`todo-item ${t.status}`}>
          <span className="status">{t.status === "completed" ? "\u2713" : t.status === "in_progress" ? "\u25CF" : "\u25CB"}</span>
          <span className="content">{t.content}</span>
        </div>
      ))}
    </div>
  );
}

function StepRow({ step, now }: { step: ActiveStep; now: number }) {
  const [thinkOpen, setThinkOpen] = useState(step.status === "running");
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  return (
    <div className={`step-group ${step.status}`}>
      <div className={`step-header ${step.status}`}>
        <span>{step.status === "running" ? "\u2699 Working..." : "\u2713 Done"}</span>
        {step.tokens && <span className="step-tokens">{fmtTok(step.tokens.total)} tok</span>}
        <span className="step-duration">{fmtDur(step, now)}</span>
      </div>
      {step.thinking && (
        <div className="thinking-shell">
          <button className="thinking-header" onClick={() => setThinkOpen(o => !o)}>
            {thinkOpen ? "\u25BE" : "\u25B8"} Thinking...
          </button>
          {thinkOpen && <div className="thinking-block">{step.thinking}</div>}
        </div>
      )}
      {step.tools.map((t, i) => {
        const key = `${step.id}:${t.tool}:${i}`;
        return (
          <div key={i} className="step-tool">
            <div className="step-tool-line">
              <span className={`tool-status ${t.status}`}>{STATUS_ICONS[t.status]}</span>
              <span className="step-tool-name">{TOOL_ICONS[t.tool] || "\u2699"} {t.tool}</span>
              <span className="step-tool-title">{t.title || t.summary || "..."}</span>
            </div>
            {t.output && (
              <div className="tool-output-shell">
                <button className="tool-output-toggle" onClick={() => setExpanded(e => ({ ...e, [key]: !e[key] }))}>
                  {expanded[key] ? "\u25BE" : "\u25B8"} Output
                </button>
                {expanded[key] && <div className="tool-output-area">{t.output}</div>}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function StatusBar({ agentName, modelName, tokenUsed, tokenTotal, sessionId }: {
  agentName: string; modelName: string; tokenUsed: number; tokenTotal: number; sessionId: string | null;
}) {
  return (
    <div className="status-bar">
      <span>{agentName}</span>
      <span className="sep">\u00B7</span>
      {modelName && <><span>{modelName}</span><span className="sep">\u00B7</span></>}
      <span>{fmtTok(tokenUsed)}/{fmtTok(tokenTotal)} ({fmtPct(tokenUsed, tokenTotal)})</span>
      {sessionId && <><span className="sep">\u00B7</span><span>{sessionId.slice(0, 12)}...</span></>}
    </div>
  );
}

function PickerSheet({ picker, onSelect, onClose }: { picker: Picker; onSelect: (v: string) => void; onClose: () => void }) {
  return (
    <div className="picker-backdrop" onClick={onClose}>
      <div className="picker-sheet" onClick={e => e.stopPropagation()}>
        <div className="picker-title">
          <span>Select {picker.type}</span>
          <button onClick={onClose}>Cancel</button>
        </div>
        {picker.items.map((item, i) => (
          <div key={i} className={`picker-item${item.current ? " current" : ""}`} onClick={() => onSelect(item.value)}>
            <span>{item.label}</span>
            {item.current && <span className="check">\u2713</span>}
          </div>
        ))}
      </div>
    </div>
  );
}

function LoginScreen({ onLogin }: { onLogin: () => void }) {
  const [u, setU] = useState("");
  const [p, setP] = useState("");
  const [err, setErr] = useState("");
  const doLogin = () => {
    if (u === WEB_AUTH_USERNAME && p === WEB_AUTH_PASSWORD) { localStorage.setItem(AUTH_KEY, "ok"); onLogin(); }
    else setErr("Invalid credentials");
  };
  return (
    <div className="login-screen">
      <div className="login-card">
        <h1>Chat Soft</h1>
        <p>OpenCode terminal for mobile</p>
        <label>Username<input value={u} autoComplete="username" onChange={e => setU(e.target.value)} onKeyDown={e => e.key === "Enter" && doLogin()} /></label>
        <label>Password<input type="password" value={p} autoComplete="current-password" onChange={e => setP(e.target.value)} onKeyDown={e => e.key === "Enter" && doLogin()} /></label>
        {err && <div className="login-error">{err}</div>}
        <button className="login-button" onClick={doLogin}>Login</button>
      </div>
    </div>
  );
}

/* ── App ────────────────────────────────── */

export function App({ platform }: { platform: "android" | "windows" | "unknown" }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  const [now, setNow] = useState(() => Date.now());
  const listRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<ChatClient | null>(null);
  const autoScroll = useRef(true);

  const deviceId = useMemo(() => {
    const e = localStorage.getItem("chatsoft.mobile.deviceId");
    if (e) return e;
    const n = createId(); localStorage.setItem("chatsoft.mobile.deviceId", n); return n;
  }, []);
  const deviceName = useMemo(() => localStorage.getItem("chatsoft.mobile.deviceName") || "P60-Pro", []);
  const serverUrl = useMemo(() => "http://49.232.183.40:3000", []);

  /* clock */
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 500); return () => clearInterval(t); }, []);

  /* ws connect */
  useEffect(() => {
    const c = new ChatClient({ serverBaseUrl: serverUrl, wsUrl: serverUrl.replace(/^http/, "ws") + "/ws", device: { deviceId, deviceName, platform } });
    wsRef.current = c; c.connect();
    const u1 = c.onStreamText((_c, id, t) => dispatch({ type: "STREAM_TEXT", id, text: t }));
    const u2 = c.onStreamDone((_c, id, t) => dispatch({ type: "STREAM_DONE", id, finalText: t }));
    const u3 = c.onStep((_c, e) => { if (e.type === "step_start") dispatch({ type: "STEP_START", stepId: e.stepId }); else dispatch({ type: "STEP_DONE", stepId: e.stepId, tokens: e.tokens }); });
    const u4 = c.onToolCall((_c, sid, tool, sum) => dispatch({ type: "STEP_TOOL", stepId: sid, tool, summary: sum }));
    const u5 = c.onToolDetail((_c, sid, tool, _i, out, title) => dispatch({ type: "TOOL_DETAIL", stepId: sid, tool, output: out, title }));
    const u6 = c.onStatus(s => dispatch({ type: "STATUS", ...s }));
    const u7 = c.onTodo(todos => dispatch({ type: "TODO", todos }));
    const u8 = c.onCommandResponse((cmd, data) => dispatch({ type: "COMMAND_RESPONSE", command: cmd, data }));
    const u9 = c.onToolStatus((_c, sid, tool, status, title) => dispatch({ type: "TOOL_STATUS", stepId: sid, tool, status, title }));
    const u10 = c.onThinking((_c, sid, text) => dispatch({ type: "THINKING", stepId: sid, text }));
    const u11 = c.onSse((_c, _sid, evType, data) => dispatch({ type: "SSE_EVENT", eventType: evType, data: data as any }));
    return () => { u1(); u2(); u3(); u4(); u5(); u6(); u7(); u8(); u9(); u10(); u11(); c.disconnect(); };
  }, [serverUrl, deviceId, deviceName, platform]);

  /* auto scroll */
  useEffect(() => { if (autoScroll.current) listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" }); }, [state.messages, state.streamingText, state.activeSteps]);

  const onScroll = () => { if (listRef.current) autoScroll.current = listRef.current.scrollHeight - listRef.current.scrollTop - listRef.current.clientHeight < 40; };
  const send = () => { const t = state.inputText.trim(); if (!t) return; dispatch({ type: "SEND" }); wsRef.current?.sendText(t, `agent:${state.agentName}`); };
  const sendCmd = (cmd: string) => { wsRef.current?.sendText(cmd, `agent:${state.agentName}`); };
  const pick = (v: string) => { if (!state.picker) return; dispatch({ type: "CLOSE_PICKER" }); setTimeout(() => wsRef.current?.sendText(`/${state.picker!.type} ${v}`, `agent:${state.agentName}`), 50); };

  if (!state.authenticated) return <LoginScreen onLogin={() => dispatch({ type: "AUTH_OK" })} />;

  return (
    <div className="app-shell">
      <TodoPanel todos={state.todos} collapsed={state.todoCollapsed} onToggle={() => dispatch({ type: "TOGGLE_TODO" })} />

      <div className="message-list" ref={listRef} onScroll={onScroll}>
        {state.messages.map(msg => (
          <Fragment key={msg.id}>
            {msg.role === "user" ? <div className="user-msg"><span className="content">{msg.text}</span></div> : <Markdown text={msg.text} />}
            {msg.steps?.map(s => <StepRow key={s.id} step={s} now={now} />)}
          </Fragment>
        ))}
        {state.completedSteps.map(s => <StepRow key={s.id} step={s} now={now} />)}
        {state.activeSteps.map(s => <StepRow key={s.id} step={s} now={now} />)}
        {state.streamingText && <Markdown text={state.streamingText + "\u258E"} />}
      </div>

      <div className="input-bar">
        {state.showCommand && (
          <div className="command-overlay">
            <button className="command-btn" onClick={() => sendCmd("/agent")}>/agent</button>
            <button className="command-btn" onClick={() => sendCmd("/model")}>/model</button>
            <button className="command-btn" onClick={() => sendCmd("/session")}>/session</button>
          </div>
        )}
        <textarea value={state.inputText} placeholder="Message OpenCode..." onChange={e => dispatch({ type: "INPUT", text: e.target.value })} onKeyDown={e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} rows={1} />
      </div>

      <StatusBar agentName={state.agentName} modelName={state.modelName} tokenUsed={state.tokenUsed} tokenTotal={state.tokenTotal} sessionId={state.sessionId} />

      {state.picker && <PickerSheet picker={state.picker} onSelect={pick} onClose={() => dispatch({ type: "CLOSE_PICKER" })} />}
    </div>
  );
}
