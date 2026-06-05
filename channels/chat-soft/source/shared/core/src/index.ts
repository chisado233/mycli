import type {
  AgentInfo,
  AgentConversationState,
  AttachmentPayload,
  ChatMessage,
  ClientToServerEvent,
  ConversationSummary,
  DeviceInfo,
  SendAttachmentEvent,
  SendTextEvent,
  SendVoiceEvent,
  ServerToClientEvent,
  TodoItem,
  SessionInfo
} from "@chat-soft/protocol";
import { DEFAULT_CONVERSATION_ID } from "@chat-soft/protocol";
import { createId } from "./id.js";

export { createId } from "./id.js";

type Listener = (messages: ChatMessage[]) => void;
type EventListener = (event: ServerToClientEvent) => void;
type TypingListener = (conversationId: string, typing: boolean) => void;
type StreamTextListener = (conversationId: string, messageId: string, text: string) => void;
type TextDeltaListener = (conversationId: string, messageId: string, delta: string, sequence: number) => void;
type StreamDoneListener = (conversationId: string, messageId: string, finalText: string) => void;
type StepListener = (conversationId: string, event: { type: "step_start" | "step_done"; stepId: string; durationMs?: number; tokens?: { total: number } }) => void;
type ToolCallListener = (conversationId: string, stepId: string, tool: string, summary: string) => void;
type ToolDetailListener = (conversationId: string, stepId: string, tool: string, input: Record<string, unknown>, output: string, title: string) => void;
type ToolStatusListener = (conversationId: string, stepId: string, tool: string, status: "pending" | "running" | "completed" | "error", title?: string) => void;
type ThinkingListener = (conversationId: string, stepId: string, text: string) => void;
type StatusListener = (status: { agentName?: string; modelName?: string; tokenUsed?: number; tokenTotal?: number; sessionId?: string }) => void;
type TodoListener = (todos: TodoItem[]) => void;
type CommandResponseListener = (command: string, data: unknown) => void;

export interface ChatClientOptions {
  serverBaseUrl: string;
  wsUrl: string;
  device: DeviceInfo;
}

export interface UploadedAttachment extends AttachmentPayload {}

function resolveMediaUrl(serverBaseUrl: string, mediaUrl: string) {
  if (!mediaUrl) return mediaUrl;
  if (/^https?:\/\//i.test(mediaUrl)) return mediaUrl;
  return `${serverBaseUrl.replace(/\/$/, "")}${mediaUrl.startsWith("/") ? "" : "/"}${mediaUrl}`;
}

function normalizeMessage(serverBaseUrl: string, message: ChatMessage): ChatMessage {
  if ("mediaUrl" in message && typeof message.mediaUrl === "string") {
    const thumbnailUrl =
      "thumbnailUrl" in message && typeof message.thumbnailUrl === "string"
        ? resolveMediaUrl(serverBaseUrl, message.thumbnailUrl)
        : undefined;
    return {
      ...message,
      mediaUrl: resolveMediaUrl(serverBaseUrl, message.mediaUrl),
      ...(thumbnailUrl ? { thumbnailUrl } : {})
    } as ChatMessage;
  }
  return message;
}

function normalizeAgent(serverBaseUrl: string, agent: AgentInfo): AgentInfo {
  if (!agent.avatarUrl) {
    return agent;
  }
  return {
    ...agent,
    avatarUrl: resolveMediaUrl(serverBaseUrl, agent.avatarUrl)
  };
}

export class ChatClient {
  private socket: WebSocket | null = null;
  private messages: ChatMessage[] = [];
  private messageListeners = new Set<Listener>();
  private eventListeners = new Set<EventListener>();
  private typingListeners = new Set<TypingListener>();
  private streamTextListeners = new Set<StreamTextListener>();
  private textDeltaListeners = new Set<TextDeltaListener>();
  private streamDoneListeners = new Set<StreamDoneListener>();
  private stepListeners = new Set<StepListener>();
  private toolCallListeners = new Set<ToolCallListener>();
  private toolDetailListeners = new Set<ToolDetailListener>();
  private toolStatusListeners = new Set<ToolStatusListener>();
  private thinkingListeners = new Set<ThinkingListener>();
  private statusListeners = new Set<StatusListener>();
  private todoListeners = new Set<TodoListener>();
  private commandResponseListeners = new Set<CommandResponseListener>();
  private typingMap = new Map<string, boolean>();
  private pollStreamTextById = new Map<string, string>();
  private pollCompletedStreams = new Set<string>();
  private pollSeenTools = new Set<string>();
  private pollTimer: number | null = null;

  constructor(private readonly options: ChatClientOptions) {}

  connect() {
    if (this.socket && this.socket.readyState <= 1) return;
    // Always start polling for message sync (reliable)
    this.startPolling();
    // Also try WebSocket for real-time stream events
    if (typeof window !== "undefined" && window.location.protocol === "https:" && this.options.wsUrl.startsWith("ws://")) {
      return;
    }
    try {
      this.socket = new WebSocket(this.options.wsUrl);
      this.socket.addEventListener("open", () => {
        this.send({
          type: "auth.hello",
          device: this.options.device
        });
        this.send({ type: "sync.pull" });
      });
      this.socket.addEventListener("message", (raw) => {
        const event = JSON.parse(String(raw.data)) as ServerToClientEvent;
        this.handleServerEvent(event);
      });
      this.socket.addEventListener("close", () => {
        this.socket = null;
      });
      this.socket.addEventListener("error", () => {
        this.socket?.close();
        this.socket = null;
      });
    } catch {
      this.socket = null;
      this.startPolling();
    }
  }

  disconnect() {
    this.socket?.close();
    this.socket = null;
    if (this.pollTimer !== null) {
      window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  onMessages(listener: Listener) {
    this.messageListeners.add(listener);
    listener(this.messages);
    return () => this.messageListeners.delete(listener);
  }

  onEvent(listener: EventListener) {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  onTypingChange(listener: TypingListener) {
    this.typingListeners.add(listener);
    return () => this.typingListeners.delete(listener);
  }

  isTyping(conversationId: string) {
    return this.typingMap.get(conversationId) ?? false;
  }

  onStreamText(listener: StreamTextListener) { return this.subscribe(this.streamTextListeners, listener); }
  onTextDelta(listener: TextDeltaListener) { return this.subscribe(this.textDeltaListeners, listener); }
  onStreamDone(listener: StreamDoneListener) { return this.subscribe(this.streamDoneListeners, listener); }
  onStep(listener: StepListener) { return this.subscribe(this.stepListeners, listener); }
  onToolCall(listener: ToolCallListener) { return this.subscribe(this.toolCallListeners, listener); }
  onToolDetail(listener: ToolDetailListener) { return this.subscribe(this.toolDetailListeners, listener); }
  onToolStatus(listener: ToolStatusListener) { return this.subscribe(this.toolStatusListeners, listener); }
  onThinking(listener: ThinkingListener) { return this.subscribe(this.thinkingListeners, listener); }
  onStatus(listener: StatusListener) { return this.subscribe(this.statusListeners, listener); }
  onTodo(listener: TodoListener) { return this.subscribe(this.todoListeners, listener); }
  onCommandResponse(listener: CommandResponseListener) { return this.subscribe(this.commandResponseListeners, listener); }

  // SSE events (not yet wired through bridge protocol — placeholder to prevent crash)
  onSse(_listener: (_conversationId: string, _sessionId: string, _eventType: string, _data: unknown) => void) {
    return () => {};
  }

  private subscribe<T extends (...args: never[]) => void>(set: Set<T>, listener: T) {
    set.add(listener);
    return () => { set.delete(listener); };
  }

  getMessages() {
    return this.messages;
  }

  async uploadVoice(file: Blob, durationMs: number) {
    const form = new FormData();
    form.append("file", file, "voice.webm");
    form.append("durationMs", String(durationMs));
    const response = await fetch(`${this.options.serverBaseUrl}/api/upload/voice`, {
      method: "POST",
      body: form
    });
    if (!response.ok) {
      throw new Error("上传语音失败");
    }
    const payload = (await response.json()) as {
      mediaUrl: string;
      durationMs: number;
      mimeType: string;
    };
    return {
      ...payload,
      mediaUrl: resolveMediaUrl(this.options.serverBaseUrl, payload.mediaUrl)
    };
  }

  async uploadAttachment(file: File | Blob, kind: "audio" | "image" | "video" | "file", fileName?: string) {
    const form = new FormData();
    const inferredName = fileName ?? ("name" in file && typeof file.name === "string" ? file.name : `${kind}-${createId()}`);
    form.append("file", file, inferredName);
    form.append("kind", kind);
    const response = await fetch(`${this.options.serverBaseUrl}/api/upload/attachment`, {
      method: "POST",
      body: form
    });
    if (!response.ok) {
      throw new Error("上传附件失败");
    }
    const payload = (await response.json()) as UploadedAttachment;
    return {
      ...payload,
      mediaUrl: resolveMediaUrl(this.options.serverBaseUrl, payload.mediaUrl),
      thumbnailUrl: payload.thumbnailUrl
        ? resolveMediaUrl(this.options.serverBaseUrl, payload.thumbnailUrl)
        : payload.thumbnailUrl
    };
  }

  async listAgents() {
    const response = await fetch(`${this.options.serverBaseUrl}/api/agents`);
    if (!response.ok) {
      throw new Error("获取 agent 列表失败");
    }
    const payload = (await response.json()) as { agents: AgentInfo[] };
    return {
      agents: payload.agents.map((agent) => normalizeAgent(this.options.serverBaseUrl, agent))
    };
  }

  async listConversations() {
    const response = await fetch(`${this.options.serverBaseUrl}/api/conversations`);
    if (!response.ok) {
      throw new Error("获取会话列表失败");
    }
    const payload = (await response.json()) as { conversations: ConversationSummary[] };
    return {
      conversations: payload.conversations.map((conversation) => ({
        ...conversation,
        lastMessage: conversation.lastMessage
          ? normalizeMessage(this.options.serverBaseUrl, conversation.lastMessage)
          : conversation.lastMessage
      }))
    };
  }

  async updateConversationAgentState(conversationId: string, agentState: AgentConversationState) {
    const response = await fetch(`${this.options.serverBaseUrl}/api/conversations/${encodeURIComponent(conversationId)}/agent-state`, {
      method: "PATCH",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify(agentState)
    });
    if (!response.ok) {
      throw new Error("更新会话同步状态失败");
    }
    return (await response.json()) as { ok: boolean; conversation: ConversationSummary };
  }

  async fetchConversationMessages(conversationId: string) {
    const response = await fetch(`${this.options.serverBaseUrl}/api/conversations/${encodeURIComponent(conversationId)}/messages`);
    if (!response.ok) {
      throw new Error("获取会话消息失败");
    }
    const payload = (await response.json()) as { messages: ChatMessage[] };
    return payload.messages
      .map((message) => normalizeMessage(this.options.serverBaseUrl, message))
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }

  async sendText(text: string, conversationId = DEFAULT_CONVERSATION_ID) {
    const clientMessageId = createId();
    const event: SendTextEvent = {
      type: "message.send_text",
      conversationId,
      tempId: clientMessageId,
      text
    };
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.send(event);
      return;
    }
    await fetch(`${this.options.serverBaseUrl}/api/messages/text`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        clientMessageId,
        deviceId: this.options.device.deviceId,
        conversationId,
        text
      })
    });
    await this.fetchRecent(conversationId);
  }

  async sendVoice(mediaUrl: string, durationMs: number, mimeType: string, conversationId = DEFAULT_CONVERSATION_ID) {
    const clientMessageId = createId();
    const event: SendVoiceEvent = {
      type: "message.send_voice",
      conversationId,
      tempId: clientMessageId,
      mediaUrl,
      durationMs,
      mimeType
    };
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.send(event);
      return;
    }
    await fetch(`${this.options.serverBaseUrl}/api/messages/voice`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        clientMessageId,
        deviceId: this.options.device.deviceId,
        conversationId,
        mediaUrl,
        durationMs,
        mimeType
      })
    });
    await this.fetchRecent(conversationId);
  }

  async sendAttachment(
    kind: "audio" | "image" | "video" | "file",
    attachment: UploadedAttachment,
    conversationId = DEFAULT_CONVERSATION_ID
  ) {
    const clientMessageId = createId();
    const event: SendAttachmentEvent = {
      type: "message.send_attachment",
      conversationId,
      tempId: clientMessageId,
      kind,
      ...attachment
    };
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.send(event);
      return;
    }
    await fetch(`${this.options.serverBaseUrl}/api/messages/attachment`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        clientMessageId,
        deviceId: this.options.device.deviceId,
        conversationId,
        kind,
        ...attachment
      })
    });
    await this.fetchRecent(conversationId);
  }

  private send(event: ClientToServerEvent) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("连接未建立");
    }
    this.socket.send(JSON.stringify(event));
  }

  private handleServerEvent(event: ServerToClientEvent) {
    if (event.type === "sync.batch") {
      this.messages = event.messages
        .map((message) => normalizeMessage(this.options.serverBaseUrl, message))
        .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
      this.emitMessages();
    }
    if (event.type === "message.created") {
      const has = this.messages.some((message) => message.id === event.message.id);
      if (!has) {
        this.messages = [...this.messages, normalizeMessage(this.options.serverBaseUrl, event.message)].sort((a, b) =>
          a.createdAt.localeCompare(b.createdAt)
        );
        this.emitMessages();
      }
    }
    if (event.type === "message.status") {
      this.messages = this.messages.map((message) =>
        message.id === event.messageId ? { ...message, status: event.status } : message
      );
      this.emitMessages();
    }
    if (event.type === "agent.typing") {
      this.typingMap.set(event.conversationId, event.typing);
      this.typingListeners.forEach((listener) => listener(event.conversationId, event.typing));
    }
    if (event.type === "stream.text") {
      const streamKey = `${event.conversationId}:${event.messageId}`;
      const previous = this.pollStreamTextById.get(streamKey) ?? "";
      this.pollStreamTextById.set(streamKey, previous + event.text);
      this.streamTextListeners.forEach((listener) => listener(event.conversationId, event.messageId, event.text));
      this.textDeltaListeners.forEach((listener) => listener(event.conversationId, event.messageId, event.text, event.sequence));
    }
    if (event.type === "stream.text_delta") {
      const streamKey = `${event.conversationId}:${event.messageId}`;
      const previous = this.pollStreamTextById.get(streamKey) ?? "";
      this.pollStreamTextById.set(streamKey, previous + event.delta);
      this.streamTextListeners.forEach((listener) => listener(event.conversationId, event.messageId, event.delta));
      this.textDeltaListeners.forEach((listener) => listener(event.conversationId, event.messageId, event.delta, event.sequence));
    }
    if (event.type === "stream.done") {
      const streamKey = `${event.conversationId}:${event.messageId}`;
      this.pollCompletedStreams.add(streamKey);
      this.pollStreamTextById.delete(streamKey);
      this.streamDoneListeners.forEach((listener) => listener(event.conversationId, event.messageId, event.finalText));
    }
    if (event.type === "stream.step_start" || event.type === "stream.step_done") {
      this.stepListeners.forEach((listener) => listener(event.conversationId, {
        type: event.type === "stream.step_start" ? "step_start" : "step_done",
        stepId: event.stepId,
        durationMs: (event as { durationMs?: number }).durationMs,
        tokens: (event as { tokens?: { total: number } }).tokens
      }));
    }
    if (event.type === "stream.tool_call") {
      this.toolCallListeners.forEach((listener) => listener(event.conversationId, event.stepId, event.tool, event.summary));
    }
    if (event.type === "stream.tool_detail") {
      const summary = "summary" in event ? event.summary ?? "" : "";
      const toolKey = `${event.conversationId}:${event.stepId}:${event.tool}:${summary}:${event.title ?? ""}:${event.output ?? ""}`;
      this.pollSeenTools.add(toolKey);
      this.toolDetailListeners.forEach((listener) => listener(event.conversationId, event.stepId, event.tool, event.input, event.output, event.title));
    }
    if (event.type === "stream.tool_status") {
      this.toolStatusListeners.forEach((listener) =>
        listener(event.conversationId, event.stepId, event.tool, event.status, event.title)
      );
    }
    if (event.type === "stream.thinking") {
      this.thinkingListeners.forEach((listener) => listener(event.conversationId, event.stepId, event.text));
    }
    if (event.type === "status") {
      this.statusListeners.forEach((listener) => listener({
        agentName: event.agentName, modelName: event.modelName,
        tokenUsed: event.tokenUsed, tokenTotal: event.tokenTotal, sessionId: event.sessionId
      }));
    }
    if (event.type === "todo") {
      this.todoListeners.forEach((listener) => listener(event.todos));
    }
    if (event.type === "command.response") {
      this.commandResponseListeners.forEach((listener) => listener(event.command, event.data));
    }
    this.eventListeners.forEach((listener) => listener(event));
  }

  private emitMessages() {
    this.messageListeners.forEach((listener) => listener(this.messages));
  }

  private startPolling() {
    if (this.pollTimer !== null) return;
    void this.fetchRecent();
    this.pollTimer = window.setInterval(() => {
      void this.fetchRecent();
    }, 3000);
  }

  private async fetchRecent(conversationId?: string) {
    const query = conversationId ? `?conversationId=${encodeURIComponent(conversationId)}` : "";
    const response = await fetch(`${this.options.serverBaseUrl}/api/messages/recent${query}`);
    if (!response.ok) return;
    const payload = (await response.json()) as {
      messages: ChatMessage[];
      typingConversations?: string[];
      activeStreams?: Array<{ conversationId: string; messageId: string; text?: string; finalText?: string; status?: string }>;
      recentToolCalls?: Record<string, Array<{ stepId: string; tool: string; summary: string; output?: string; title?: string }>>;
    };
    const normalizedMessages = payload.messages.map((message) => normalizeMessage(this.options.serverBaseUrl, message));
    if (conversationId) {
      const otherMessages = this.messages.filter((message) => message.conversationId !== conversationId);
      this.messages = [...otherMessages, ...normalizedMessages].sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    } else {
      this.messages = normalizedMessages.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    }
    this.emitMessages();
    if (payload.typingConversations) {
      const activeSet = new Set(payload.typingConversations);
      for (const [convId, wasTyping] of this.typingMap) {
        if (wasTyping && !activeSet.has(convId)) {
          this.typingMap.set(convId, false);
          this.typingListeners.forEach((listener) => listener(convId, false));
        }
      }
      for (const convId of activeSet) {
        if (!this.typingMap.get(convId)) {
          this.typingMap.set(convId, true);
          this.typingListeners.forEach((listener) => listener(convId, true));
        }
      }
    }
    if (payload.activeStreams) {
      for (const stream of payload.activeStreams) {
        const streamKey = `${stream.conversationId}:${stream.messageId}`;
        if (stream.status === "completed" && stream.finalText) {
          if (!this.pollCompletedStreams.has(streamKey)) {
            this.pollCompletedStreams.add(streamKey);
            this.pollStreamTextById.delete(streamKey);
            this.streamDoneListeners.forEach((listener) => listener(stream.conversationId, stream.messageId, stream.finalText!));
          }
        } else {
          const text = stream.text ?? "";
          const previous = this.pollStreamTextById.get(streamKey) ?? "";
          const delta = text.startsWith(previous) ? text.slice(previous.length) : text;
          if (delta) {
            this.pollStreamTextById.set(streamKey, text);
            this.streamTextListeners.forEach((listener) => listener(stream.conversationId, stream.messageId, delta));
            this.textDeltaListeners.forEach((listener) => listener(stream.conversationId, stream.messageId, delta, text.length));
          }
        }
      }
    }
    if (payload.recentToolCalls) {
      for (const [convId, tools] of Object.entries(payload.recentToolCalls)) {
        for (const tool of tools) {
          const toolKey = `${convId}:${tool.stepId}:${tool.tool}:${tool.summary}:${tool.title ?? ""}:${tool.output ?? ""}`;
          if (this.pollSeenTools.has(toolKey)) continue;
          this.pollSeenTools.add(toolKey);
          this.toolCallListeners.forEach((listener) => listener(convId, tool.stepId, tool.tool, tool.summary));
          this.toolDetailListeners.forEach((listener) => listener(convId, tool.stepId, tool.tool, {}, tool.output ?? "", tool.title ?? ""));
        }
      }
    }
  }
}
