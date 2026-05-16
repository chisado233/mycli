import { useEffect, useState } from "react";
import type {
  CodexMirrorEventEnvelope,
  MirrorMessageView,
  MirrorSessionSummary,
  MirrorStatus
} from "@chat-soft/codex-mirror-protocol";

const baseUrl = "http://127.0.0.1:3090";

async function readJson<T>(url: string, init?: RequestInit) {
  const response = await fetch(url, init);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return (await response.json()) as T;
}

export function App() {
  const [status, setStatus] = useState<MirrorStatus | null>(null);
  const [sessions, setSessions] = useState<MirrorSessionSummary[]>([]);
  const [selectedSessionId, setSelectedSessionId] = useState<string>("");
  const [messages, setMessages] = useState<MirrorMessageView[]>([]);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState("");
  const [logLines, setLogLines] = useState<string[]>([]);

  useEffect(() => {
    void refreshSessions();
    const ws = new WebSocket("ws://127.0.0.1:3090/ws");
    ws.onmessage = (event) => {
      const payload = JSON.parse(String(event.data)) as CodexMirrorEventEnvelope;
      setLogLines((current) => [`${payload.ts} ${payload.type}`, ...current].slice(0, 40));
      if (payload.type === "connection.changed") {
        void refreshSessions();
      }
      if (
        payload.type === "session.created" ||
        payload.type === "session.updated" ||
        payload.type === "session.deleted" ||
        payload.type === "session.switched"
      ) {
        void refreshSessions();
      }
      if (
        payload.type === "message.created" ||
        payload.type === "message.delta" ||
        payload.type === "message.completed" ||
        payload.type === "message.failed" ||
        payload.type === "message.retrying"
      ) {
        void refreshMessages(selectedSessionId || undefined);
      }
    };
    return () => ws.close();
  }, [selectedSessionId]);

  async function refreshSessions() {
    try {
      const payload = await readJson<{ status: MirrorStatus; sessions: MirrorSessionSummary[] }>(`${baseUrl}/api/codex-mirror/sessions`);
      setStatus(payload.status);
      setSessions(payload.sessions);
      const nextSessionId = selectedSessionId || payload.status.currentSessionId || payload.sessions[0]?.sessionId || "";
      setSelectedSessionId(nextSessionId);
      if (nextSessionId) {
        await refreshMessages(nextSessionId);
      } else {
        setMessages([]);
      }
      setError("");
    } catch (nextError) {
      setError(String(nextError));
    }
  }

  async function refreshMessages(sessionId = selectedSessionId) {
    if (!sessionId) {
      setMessages([]);
      return;
    }
    try {
      const payload = await readJson<{ messages: MirrorMessageView[] }>(`${baseUrl}/api/codex-mirror/sessions/${encodeURIComponent(sessionId)}/messages`);
      setMessages(payload.messages);
      setError("");
    } catch (nextError) {
      setError(String(nextError));
    }
  }

  async function createSession() {
    try {
      await readJson(`${baseUrl}/api/codex-mirror/sessions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({})
      });
      await refreshSessions();
    } catch (nextError) {
      setError(String(nextError));
    }
  }

  async function sendMessage() {
    if (!selectedSessionId || !draft.trim()) return;
    try {
      await readJson(`${baseUrl}/api/codex-mirror/sessions/${encodeURIComponent(selectedSessionId)}/messages`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ text: draft, waitForConfirmation: true })
      });
      setDraft("");
      await refreshMessages();
    } catch (nextError) {
      setError(String(nextError));
    }
  }

  async function switchSession(sessionId: string) {
    setSelectedSessionId(sessionId);
    try {
      await readJson(`${baseUrl}/api/codex-mirror/sessions/${encodeURIComponent(sessionId)}/switch`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ waitForSwitch: true })
      });
      await refreshSessions();
      await refreshMessages(sessionId);
    } catch (nextError) {
      setError(String(nextError));
    }
  }

  return (
    <div className="page">
      <aside className="sidebar">
        <div className="panel">
          <h1>Codex Mirror</h1>
          <p className="muted">
            {status?.connectionState === "connected" ? "已连接" : "Codex 未连接"}
          </p>
          <button onClick={() => void createSession()} disabled={status?.connectionState !== "connected"}>
            新建会话
          </button>
        </div>
        <div className="panel list">
          {sessions.map((session) => (
            <button
              key={session.sessionId}
              className={session.sessionId === selectedSessionId ? "session active" : "session"}
              onClick={() => void switchSession(session.sessionId)}
            >
              <strong>{session.effectiveTitle}</strong>
              <span>{session.modelId || "未设置模型"}</span>
            </button>
          ))}
          {sessions.length === 0 ? <div className="empty">还没有镜像会话</div> : null}
        </div>
      </aside>
      <main className="content">
        <section className="panel messages">
          {messages.map((message) => (
            <article key={message.messageId} className="message">
              <header>
                <strong>{message.role}</strong>
                <span>{message.sendState}</span>
              </header>
              <pre>{message.text || "(empty)"}</pre>
            </article>
          ))}
          {messages.length === 0 ? <div className="empty">当前没有消息</div> : null}
        </section>
        <section className="panel composer">
          <textarea
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            placeholder="给当前镜像会话发送消息"
            disabled={status?.connectionState !== "connected"}
          />
          <button onClick={() => void sendMessage()} disabled={status?.connectionState !== "connected"}>
            发送
          </button>
          {error ? <div className="error">{error}</div> : null}
        </section>
        <section className="panel logs">
          <h2>事件流</h2>
          <div className="logList">
            {logLines.map((line) => (
              <div key={line}>{line}</div>
            ))}
          </div>
        </section>
      </main>
    </div>
  );
}
