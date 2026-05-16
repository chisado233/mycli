import { Fragment, useEffect, useMemo, useRef, useState, type ChangeEvent } from "react";
import { ChatClient, createId } from "@chat-soft/core";
import type { AgentInfo, ChatMessage, ConversationSummary, DeviceInfo } from "@chat-soft/protocol";

const attachmentPickerMap = {
  audio: "audio/*",
  image: "image/*",
  video: "video/*",
  file: "*/*"
} as const;

type AttachmentKind = keyof typeof attachmentPickerMap;

const commandSuggestions = [
  { command: "/help", label: "查看指令", description: "列出 private-assistant 可用指令" },
  { command: "/agents", label: "查看 agents", description: "列出 agent-cli 当前可用 agent" },
  { command: "/models", label: "查看模型", description: "列出当前可用模型" },
  { command: "/model MoreCode/gpt-5.5", label: "切换到 gpt-5.5", description: "把当前 private-assistant 模型切到 gpt-5.5" },
  { command: "/session", label: "查看会话", description: "列出最近 OpenCode 会话" },
  { command: "/session current", label: "当前会话", description: "查看当前绑定的 private-assistant session" },
  { command: "/session new", label: "新会话", description: "为当前 Chat Soft 对话开启一个新的 agent session" },
  { command: "/session events", label: "查看事件", description: "查看当前 session 最近 agent-cli 事件" },
  { command: "/session reset", label: "重置会话", description: "清空当前 session 绑定" }
] as const;

const WEB_AUTH_USERNAME = "chisado";
const WEB_AUTH_PASSWORD = "chisado233";
const WEB_AUTH_STORAGE_KEY = "chatsoft.mobile.webAuth";

type PreviewState =
  | {
      kind: "image" | "video" | "audio" | "file";
      url: string;
      title: string;
      mimeType?: string;
    }
  | null;

type TextBlock =
  | {
      type: "text";
      content: string;
    }
  | {
      type: "code";
      content: string;
      language: string;
    };

const LONG_TEXT_COLLAPSE_LENGTH = 220;
const LONG_TEXT_COLLAPSE_LINES = 8;

function formatClock(value?: string) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit"
  });
}

function avatarText(title: string) {
  const cleaned = title.trim();
  if (!cleaned) return "?";
  return cleaned.slice(0, 1).toUpperCase();
}

function Avatar({ title, avatarUrl, className }: { title: string; avatarUrl?: string; className: string }) {
  if (avatarUrl) {
    return (
      <div className={className}>
        <img className="avatar-image" src={avatarUrl} alt={title} />
      </div>
    );
  }
  return <div className={className}>{avatarText(title)}</div>;
}

function messagePreview(message?: ChatMessage) {
  if (!message) return "暂无消息";
  if (message.kind === "text") return message.text;
  if (message.kind === "voice") return "[语音消息]";
  if (message.kind === "audio") return `[音频] ${message.fileName}`;
  if (message.kind === "image") return "[图片]";
  if (message.kind === "video") return "[视频]";
  return `[文件] ${message.fileName}`;
}

function formatAgentStateSummary(conversation: ConversationSummary, agent?: AgentInfo) {
  if (conversation.agentState?.provider === "codex") {
    const pieces = ["Codex 已同步"];
    if (conversation.agentState.selectedModelId) {
      pieces.push(conversation.agentState.selectedModelId);
    }
    if (conversation.agentState.threadTitle) {
      pieces.push(conversation.agentState.threadTitle);
    }
    return pieces.join(" · ");
  }
  return agent ? agent.description || "Agent 好友" : "本机设备";
}

function triggerDownload(url: string, fileName: string) {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  anchor.target = "_blank";
  anchor.rel = "noreferrer";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

function openExternal(url: string) {
  window.open(url, "_blank", "noopener,noreferrer");
}

function parseTextBlocks(text: string) {
  const blocks: TextBlock[] = [];
  const source = text ?? "";
  const fencePattern = /```([^\n`]*)\n([\s\S]*?)```/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = fencePattern.exec(source)) !== null) {
    if (match.index > lastIndex) {
      const textContent = source.slice(lastIndex, match.index);
      if (textContent.trim()) {
        blocks.push({
          type: "text",
          content: textContent.trim()
        });
      }
    }

    blocks.push({
      type: "code",
      language: match[1].trim(),
      content: match[2].replace(/\s+$/, "")
    });
    lastIndex = match.index + match[0].length;
  }

  const trailing = source.slice(lastIndex);
  if (trailing.trim()) {
    blocks.push({
      type: "text",
      content: trailing.trim()
    });
  }

  if (blocks.length === 0) {
    blocks.push({
      type: "text",
      content: source
    });
  }

  return blocks;
}

function shouldCollapseLongText(text: string) {
  const normalized = text.trim();
  if (!normalized) return false;
  const lineCount = normalized.split(/\r?\n/).length;
  return normalized.length > LONG_TEXT_COLLAPSE_LENGTH || lineCount > LONG_TEXT_COLLAPSE_LINES;
}

function CodeBlock({ block }: { block: Extract<TextBlock, { type: "code" }> }) {
  const [expanded, setExpanded] = useState(false);
  const lineCount = block.content.split(/\r?\n/).length;
  const title = block.language || "代码/命令";

  return (
    <div className="code-block-card">
      <button type="button" className="code-block-header" onClick={() => setExpanded((current) => !current)}>
        <div className="code-block-meta">
          <strong>{title}</strong>
          <span>{lineCount} 行</span>
        </div>
        <span className="code-block-toggle">{expanded ? "收起" : "展开"}</span>
      </button>
      {expanded && (
        <pre className="code-block-body">
          <code>{block.content}</code>
        </pre>
      )}
    </div>
  );
}

function CollapsibleText({ text }: { text: string }) {
  const [expanded, setExpanded] = useState(false);
  const collapsible = shouldCollapseLongText(text);

  if (!collapsible) {
    return <p className="message-text">{text}</p>;
  }

  return (
    <div className="long-text-card">
      <p className={`message-text ${expanded ? "" : "message-text-clamped"}`}>{text}</p>
      <button type="button" className="long-text-toggle" onClick={() => setExpanded((current) => !current)}>
        {expanded ? "收起全文" : "展开全文"}
      </button>
    </div>
  );
}

function TextMessageBody({ text, isSelf }: { text?: string; isSelf: boolean }) {
  const blocks = useMemo(() => parseTextBlocks(text ?? ""), [text]);

  return (
    <div className="text-message-stack">
      {blocks.map((block, index) => (
        <Fragment key={`${block.type}-${index}`}>
          {block.type === "text" ? (
            isSelf ? (
              <CollapsibleText text={block.content} />
            ) : (
              <p className="message-text">{block.content}</p>
            )
          ) : (
            <CodeBlock block={block} />
          )}
        </Fragment>
      ))}
    </div>
  );
}

function renderAttachmentActions(message: Extract<ChatMessage, { mediaUrl: string }>, onPreview: (preview: PreviewState) => void) {
  const previewKind = message.kind === "voice" ? "audio" : message.kind;
  return (
    <div className="message-actions">
      <button
        type="button"
        className="ghost-action"
        onClick={() =>
          onPreview({
            kind: previewKind === "voice" ? "audio" : previewKind,
            url: message.mediaUrl,
            title: message.fileName ?? "附件",
            mimeType: message.mimeType
          })
        }
      >
        预览
      </button>
      <button type="button" className="ghost-action" onClick={() => openExternal(message.mediaUrl)}>
        打开
      </button>
      <button
        type="button"
        className="ghost-action"
        onClick={() => triggerDownload(message.mediaUrl, message.fileName ?? "chat-soft-attachment")}
      >
        下载
      </button>
    </div>
  );
}

function renderMessageBody(message: ChatMessage, onPreview: (preview: PreviewState) => void, isSelf: boolean) {
  if (message.kind === "text") {
    return <TextMessageBody text={message.text} isSelf={isSelf} />;
  }

  if (message.kind === "voice" || message.kind === "audio") {
    return (
      <div className="attachment-card audio-card">
        <div className="attachment-title">{message.kind === "voice" ? "语音消息" : message.fileName}</div>
        <audio className="inline-audio" controls preload="metadata" src={message.mediaUrl}></audio>
        {renderAttachmentActions(message, onPreview)}
      </div>
    );
  }

  if (message.kind === "image") {
    return (
      <div className="attachment-card image-card">
        <button
          type="button"
          className="preview-button"
          onClick={() =>
            onPreview({
              kind: "image",
              url: message.mediaUrl,
              title: message.fileName,
              mimeType: message.mimeType
            })
          }
        >
          <img className="message-image" src={message.mediaUrl} alt={message.fileName} />
        </button>
        <div className="attachment-title">{message.fileName}</div>
        {renderAttachmentActions(message, onPreview)}
      </div>
    );
  }

  if (message.kind === "video") {
    return (
      <div className="attachment-card video-card">
        <video
          className="message-video"
          controls
          preload="metadata"
          playsInline
          src={message.mediaUrl}
          onClick={() =>
            onPreview({
              kind: "video",
              url: message.mediaUrl,
              title: message.fileName,
              mimeType: message.mimeType
            })
          }
        ></video>
        <div className="attachment-title">{message.fileName}</div>
        {renderAttachmentActions(message, onPreview)}
      </div>
    );
  }

  return (
    <div className="attachment-card file-card">
      <div className="file-icon">文</div>
      <div className="file-meta">
        <strong>{message.fileName}</strong>
        <span>{message.mimeType || "application/octet-stream"}</span>
      </div>
      {renderAttachmentActions(message, onPreview)}
    </div>
  );
}

function isSelfMessage(
  message: ChatMessage,
  options: {
    currentDeviceId: string;
    activeConversation: ConversationSummary | null;
    activeAgent?: AgentInfo;
  }
) {
  const { currentDeviceId, activeConversation, activeAgent } = options;

  if (activeConversation?.type === "agent" && activeAgent?.agentDeviceId) {
    return message.senderDeviceId !== activeAgent.agentDeviceId;
  }

  return message.senderDeviceId === currentDeviceId;
}

function PreviewModal({ preview, onClose }: { preview: PreviewState; onClose: () => void }) {
  if (!preview) return null;
  return (
    <div className="preview-modal" onClick={onClose}>
      <div className="preview-panel" onClick={(event) => event.stopPropagation()}>
        <div className="preview-header">
          <strong>{preview.title}</strong>
          <button type="button" className="icon-button" onClick={onClose}>
            关闭
          </button>
        </div>
        <div className="preview-body">
          {preview.kind === "image" && <img className="preview-image" src={preview.url} alt={preview.title} />}
          {preview.kind === "video" && <video className="preview-video" controls preload="metadata" src={preview.url}></video>}
          {preview.kind === "audio" && <audio className="preview-audio" controls preload="metadata" src={preview.url}></audio>}
          {preview.kind === "file" && (
            <div className="preview-file">
              <p>{preview.title}</p>
              <p>{preview.mimeType ?? "未知文件类型"}</p>
            </div>
          )}
        </div>
        <div className="preview-actions">
          <button type="button" className="primary-action" onClick={() => openExternal(preview.url)}>
            打开
          </button>
          <button type="button" className="secondary-action" onClick={() => triggerDownload(preview.url, preview.title)}>
            下载
          </button>
        </div>
      </div>
    </div>
  );
}

export function App({ platform }: { platform: DeviceInfo["platform"] }) {
  const [authForm, setAuthForm] = useState({ username: "", password: "" });
  const [authError, setAuthError] = useState("");
  const [authenticated, setAuthenticated] = useState(
    () => localStorage.getItem(WEB_AUTH_STORAGE_KEY) === "ok"
  );
  const [serverBaseUrl, setServerBaseUrl] = useState(
    localStorage.getItem("chatsoft.mobile.serverBaseUrl") ?? "http://39.106.125.149:3000"
  );
  const [deviceName, setDeviceName] = useState(localStorage.getItem("chatsoft.mobile.deviceName") ?? "Huawei-P60");
  const [agents, setAgents] = useState<AgentInfo[]>([]);
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [allMessages, setAllMessages] = useState<ChatMessage[]>([]);
  const [activeConversationId, setActiveConversationId] = useState<string>("");
  const [text, setText] = useState("");
  const [recording, setRecording] = useState(false);
  const [loading, setLoading] = useState(true);
  const [pickerKind, setPickerKind] = useState<AttachmentKind>("file");
  const [chatOpen, setChatOpen] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showAttachmentPanel, setShowAttachmentPanel] = useState(false);
  const [showCommandPanel, setShowCommandPanel] = useState(false);
  const [preview, setPreview] = useState<PreviewState>(null);
  const mediaChunksRef = useRef<Blob[]>([]);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const startedAtRef = useRef<number>(0);
  const filePickerRef = useRef<HTMLInputElement | null>(null);
  const composerTextAreaRef = useRef<HTMLTextAreaElement | null>(null);
  const messageEndRef = useRef<HTMLDivElement | null>(null);
  const chatListRef = useRef<HTMLElement | null>(null);
  const lastAutoScrollMessageIdRef = useRef<string>("");

  const deviceId = useMemo(() => {
    const existing = localStorage.getItem("chatsoft.mobile.deviceId");
    if (existing) return existing;
    const next = createId();
    localStorage.setItem("chatsoft.mobile.deviceId", next);
    return next;
  }, []);

  const client = useMemo(() => {
    const normalized = serverBaseUrl.replace(/\/$/, "");
    const httpUrl = new URL(normalized);
    const wsProtocol = httpUrl.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${wsProtocol}//${httpUrl.host}/ws`;
    return new ChatClient({
      serverBaseUrl: normalized,
      wsUrl,
      device: {
        deviceId,
        deviceName,
        platform
      }
    });
  }, [deviceId, deviceName, platform, serverBaseUrl]);

  const agentMap = useMemo(() => new Map(agents.map((agent) => [agent.conversationId, agent])), [agents]);

  const activeConversation = useMemo(
    () => conversations.find((conversation) => conversation.conversationId === activeConversationId) ?? null,
    [activeConversationId, conversations]
  );

  const visibleMessages = useMemo(
    () =>
      allMessages
        .filter((message) => message.conversationId === activeConversationId)
        .sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
    [activeConversationId, allMessages]
  );

  const effectiveConversationId = activeConversationId || conversations[0]?.conversationId || "primary";

  const slashSuggestions = useMemo(() => {
    const trimmed = text.trimStart();
    if (!trimmed.startsWith("/")) {
      return [];
    }
    const query = trimmed.toLowerCase();
    return commandSuggestions.filter((item) => {
      const haystack = `${item.command} ${item.label} ${item.description}`.toLowerCase();
      return haystack.includes(query);
    });
  }, [text]);

  useEffect(() => {
    localStorage.setItem("chatsoft.mobile.serverBaseUrl", serverBaseUrl);
    localStorage.setItem("chatsoft.mobile.deviceName", deviceName);
  }, [deviceName, serverBaseUrl]);

  useEffect(() => {
    async function loadSidebar() {
      setLoading(true);
      try {
        const [agentPayload, conversationPayload] = await Promise.all([client.listAgents(), client.listConversations()]);
        setAgents(agentPayload.agents);
        setConversations(conversationPayload.conversations);
        setActiveConversationId((current) => current || conversationPayload.conversations[0]?.conversationId || "");
      } finally {
        setLoading(false);
      }
    }

    client.connect();
    void loadSidebar();

    const offMessages = client.onMessages((messages) => {
      setAllMessages(messages);
    });
    const offEvents = client.onEvent((event) => {
      if (event.type === "message.created") {
        void client.listConversations().then((payload) => {
          setConversations(payload.conversations);
          setActiveConversationId((current) => current || payload.conversations[0]?.conversationId || "");
        });
      }
    });

    return () => {
      offMessages();
      offEvents();
      client.disconnect();
    };
  }, [client]);

  useEffect(() => {
    if (!chatOpen) return;
    const container = chatListRef.current;
    const lastMessageId = visibleMessages.at(-1)?.id ?? "";
    if (!container || !lastMessageId || lastAutoScrollMessageIdRef.current === lastMessageId) {
      return;
    }

    const distanceFromBottom = container.scrollHeight - container.scrollTop - container.clientHeight;
    const shouldStickToBottom = distanceFromBottom < 120;
    lastAutoScrollMessageIdRef.current = lastMessageId;

    if (shouldStickToBottom) {
      messageEndRef.current?.scrollIntoView({ behavior: "auto", block: "end" });
    }
  }, [chatOpen, visibleMessages]);

  async function startRecording() {
    if (!activeConversationId) return;
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const recorder = new MediaRecorder(stream);
    mediaChunksRef.current = [];
    recorderRef.current = recorder;
    startedAtRef.current = Date.now();
    recorder.ondataavailable = (event) => {
      mediaChunksRef.current.push(event.data);
    };
    recorder.onstop = async () => {
      const blob = new Blob(mediaChunksRef.current, { type: recorder.mimeType || "audio/webm" });
      const durationMs = Date.now() - startedAtRef.current;
      const uploaded = await client.uploadVoice(blob, durationMs);
      await client.sendVoice(uploaded.mediaUrl, uploaded.durationMs, uploaded.mimeType, activeConversationId);
      stream.getTracks().forEach((track) => track.stop());
    };
    recorder.start();
    setRecording(true);
  }

  function stopRecording() {
    recorderRef.current?.stop();
    setRecording(false);
  }

  async function handleAttachmentSelect(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file || !activeConversationId) return;
    const uploaded = await client.uploadAttachment(file, pickerKind, file.name);
    await client.sendAttachment(pickerKind, uploaded, activeConversationId);
    event.target.value = "";
    setShowAttachmentPanel(false);
  }

  async function sendTextMessage(value: string) {
    if (!effectiveConversationId || !value.trim()) return;
    await client.sendText(value.trim(), effectiveConversationId);
    setActiveConversationId((current) => current || effectiveConversationId);
    setText("");
  }

  async function handleCommandQuickSend(command: string) {
    await sendTextMessage(command);
  }

  const conversationItems = conversations.map((conversation) => {
    const boundAgent = agentMap.get(conversation.conversationId);
    return {
      ...conversation,
      displayTitle: boundAgent?.name ?? conversation.title,
      displaySubtitle: formatAgentStateSummary(conversation, boundAgent),
      avatarUrl: boundAgent?.avatarUrl
    };
  }).filter((conversation) => {
    const boundAgent = agentMap.get(conversation.conversationId);
    if (!boundAgent) return true;
    if (boundAgent.agentId === "codex-agent") return true;
    if (boundAgent.agentId === "llm-chat") return true;
    if (boundAgent.agentId === "desktop-helper") return true;
    if (boundAgent.agentId === "private-assistant") return true;
    if (boundAgent.agentId === "private-assistant-2") return true;
    if (boundAgent.agentId.startsWith("codex-thread-")) return false;
    if (/debug/i.test(boundAgent.name)) return false;
    return true;
  });

  function handleLogin() {
    if (authForm.username === WEB_AUTH_USERNAME && authForm.password === WEB_AUTH_PASSWORD) {
      localStorage.setItem(WEB_AUTH_STORAGE_KEY, "ok");
      setAuthenticated(true);
      setAuthError("");
      return;
    }
    setAuthError("用户名或密码不正确");
  }

  if (!authenticated) {
    return (
      <main className="login-screen">
        <section className="login-card">
          <div>
            <div className="login-kicker">Chat Soft</div>
            <h1>需要登录</h1>
            <p>请输入访问账号和密码后继续使用网页端。</p>
          </div>
          <label>
            用户名
            <input
              value={authForm.username}
              autoComplete="username"
              onChange={(event) => setAuthForm((current) => ({ ...current, username: event.target.value }))}
              onKeyDown={(event) => {
                if (event.key === "Enter") handleLogin();
              }}
            />
          </label>
          <label>
            密码
            <input
              type="password"
              value={authForm.password}
              autoComplete="current-password"
              onChange={(event) => setAuthForm((current) => ({ ...current, password: event.target.value }))}
              onKeyDown={(event) => {
                if (event.key === "Enter") handleLogin();
              }}
            />
          </label>
          {authError && <div className="login-error">{authError}</div>}
          <button type="button" className="login-button" onClick={handleLogin}>
            登录
          </button>
        </section>
      </main>
    );
  }

  return (
    <div className="qq-shell">
      {!chatOpen && (
        <section className="qq-list-page">
          <header className="qq-topbar">
            <div>
              <div className="qq-title">消息</div>
              <div className="qq-subtitle">一个 agent 就像一个 QQ 好友</div>
            </div>
            <button type="button" className="icon-button" onClick={() => setShowSettings((current) => !current)}>
              设置
            </button>
          </header>

          {showSettings && (
            <section className="settings-card">
              <label>
                服务器地址
                <input value={serverBaseUrl} onChange={(event) => setServerBaseUrl(event.target.value)} placeholder="服务器地址" />
              </label>
              <label>
                设备名称
                <input value={deviceName} onChange={(event) => setDeviceName(event.target.value)} placeholder="设备名称" />
              </label>
            </section>
          )}

          <main className="friend-list">
            {loading && <div className="empty-hint">加载中...</div>}
            {!loading &&
              conversationItems.map((conversation) => (
                <button
                  key={conversation.conversationId}
                  type="button"
                  className="friend-row"
                  onClick={() => {
                    setActiveConversationId(conversation.conversationId);
                    setChatOpen(true);
                  }}
                >
                  <Avatar title={conversation.displayTitle} avatarUrl={conversation.avatarUrl} className="friend-avatar" />
                  <div className="friend-main">
                    <div className="friend-line">
                      <strong>{conversation.displayTitle}</strong>
                      <span>{formatClock(conversation.updatedAt)}</span>
                    </div>
                    <div className="friend-line friend-secondary">
                      <span>{conversation.displaySubtitle}</span>
                      <span className="preview-text">{messagePreview(conversation.lastMessage)}</span>
                    </div>
                  </div>
                </button>
              ))}
          </main>
        </section>
      )}

      {chatOpen && (
        <section className="qq-chat-page">
          <header className="chat-topbar">
            <button
              type="button"
              className="icon-button"
              onClick={() => {
                setChatOpen(false);
                setShowAttachmentPanel(false);
              }}
            >
              返回
            </button>
            <div className="chat-title-block">
              <strong>{activeConversation ? agentMap.get(activeConversation.conversationId)?.name ?? activeConversation.title : "聊天"}</strong>
              <span>
                {activeConversation?.agentState?.provider === "codex"
                  ? `${activeConversation.agentState.selectedModelId || "Codex"} · ${
                      activeConversation.agentState.threadTitle || "未绑定线程"
                    }`
                  : agentMap.get(activeConversationId)?.status === "online"
                    ? "在线"
                    : "会话中"}
              </span>
            </div>
          </header>

          <main
            className="chat-message-list"
            ref={(node) => {
              chatListRef.current = node;
            }}
          >
            {visibleMessages.map((message) => {
              const activeAgent = activeConversation ? agentMap.get(activeConversation.conversationId) : undefined;
              const isSelf = isSelfMessage(message, {
                currentDeviceId: deviceId,
                activeConversation,
                activeAgent
              });
              const peerTitle = activeConversation ? activeAgent?.name ?? activeConversation.title : "A";
              return (
                <div key={message.id} className={`chat-row ${isSelf ? "self" : "peer"}`}>
                  {!isSelf && (
                    <Avatar title={peerTitle} avatarUrl={activeAgent?.avatarUrl} className="message-avatar" />
                  )}
                  {isSelf && <div className="message-side-spacer" aria-hidden="true"></div>}
                  <div className={`message-bubble ${isSelf ? "self" : "peer"}`}>
                    {renderMessageBody(message, setPreview, isSelf)}
                  </div>
                  {isSelf && <div className="message-avatar self-avatar">我</div>}
                </div>
              );
            })}
            {activeConversationId && visibleMessages.length === 0 && <div className="empty-hint chat-empty">这个会话里还没有消息</div>}
            <div ref={messageEndRef}></div>
          </main>

          <footer className="qq-composer">
            <div className="composer-main">
              <button type="button" className="composer-tool" onClick={() => setShowAttachmentPanel((current) => !current)}>
                +
              </button>
              <button
                type="button"
                className="composer-tool slash-tool"
                disabled={!activeConversationId}
                onClick={() => {
                  setShowAttachmentPanel(false);
                  setText((current) => (current.trimStart().startsWith("/") ? current : "/"));
                  setShowCommandPanel(true);
                  requestAnimationFrame(() => composerTextAreaRef.current?.focus());
                }}
              >
                /
              </button>
              <textarea
                ref={composerTextAreaRef}
                value={text}
                onChange={(event) => {
                  setText(event.target.value);
                  setShowCommandPanel(event.target.value.trimStart().startsWith("/"));
                }}
                placeholder={activeConversationId ? "输入消息" : "先选择一个会话"}
                disabled={!effectiveConversationId}
              />
              <button
                type="button"
                className="send-button"
                disabled={!effectiveConversationId}
                onClick={() => {
                  void sendTextMessage(text);
                }}
              >
                发送
              </button>
            </div>

            {showCommandPanel && (
              <div className="command-panel">
                <div className="command-panel-title">可用指令</div>
                {slashSuggestions.length > 0 ? (
                  slashSuggestions.map((item) => (
                    <button
                      key={item.command}
                      type="button"
                      className="command-row"
                      disabled={!activeConversationId}
                      onClick={() => {
                        setShowCommandPanel(false);
                        void handleCommandQuickSend(item.command);
                      }}
                    >
                      <div className="command-main">
                        <strong>{item.command}</strong>
                        <span>{item.label}</span>
                      </div>
                      <div className="command-desc">{item.description}</div>
                    </button>
                  ))
                ) : (
                  <div className="command-empty">没有匹配的指令</div>
                )}
              </div>
            )}

            {showAttachmentPanel && (
              <div className="attachment-panel">
                <input
                  ref={filePickerRef}
                  type="file"
                  accept={attachmentPickerMap[pickerKind]}
                  className="hidden-picker"
                  onChange={handleAttachmentSelect}
                />
                <button
                  type="button"
                  className="attachment-tile"
                  disabled={!activeConversationId}
                  onTouchStart={startRecording}
                  onTouchEnd={stopRecording}
                  onTouchCancel={stopRecording}
                >
                  <strong>{recording ? "松开" : "语音"}</strong>
                  <span>{recording ? "发送录音" : "按住录音"}</span>
                </button>
                <button
                  type="button"
                  className="attachment-tile"
                  disabled={!activeConversationId}
                  onClick={() => {
                    setPickerKind("image");
                    filePickerRef.current?.click();
                  }}
                >
                  <strong>图片</strong>
                  <span>发送照片</span>
                </button>
                <button
                  type="button"
                  className="attachment-tile"
                  disabled={!activeConversationId}
                  onClick={() => {
                    setPickerKind("video");
                    filePickerRef.current?.click();
                  }}
                >
                  <strong>视频</strong>
                  <span>发送视频</span>
                </button>
                <button
                  type="button"
                  className="attachment-tile"
                  disabled={!activeConversationId}
                  onClick={() => {
                    setPickerKind("audio");
                    filePickerRef.current?.click();
                  }}
                >
                  <strong>音频</strong>
                  <span>发送音频</span>
                </button>
                <button
                  type="button"
                  className="attachment-tile"
                  disabled={!activeConversationId}
                  onClick={() => {
                    setPickerKind("file");
                    filePickerRef.current?.click();
                  }}
                >
                  <strong>文件</strong>
                  <span>发送文件</span>
                </button>
              </div>
            )}
          </footer>
        </section>
      )}

      <PreviewModal preview={preview} onClose={() => setPreview(null)} />
    </div>
  );
}
