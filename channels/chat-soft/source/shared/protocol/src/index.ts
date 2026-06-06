export type MessageKind = "text" | "voice" | "audio" | "image" | "video" | "file";
export type MessageStatus = "sending" | "sent" | "delivered" | "read" | "failed";
export type ConversationType = "direct" | "agent";
export type AgentStatus = "online" | "offline";

export interface BaseMessage {
  id: string;
  conversationId: string;
  senderDeviceId: string;
  kind: MessageKind;
  createdAt: string;
  status: MessageStatus;
}

export interface TextMessage extends BaseMessage {
  kind: "text";
  text: string;
}

export interface VoiceMessage extends BaseMessage {
  kind: "voice";
  mediaUrl: string;
  durationMs: number;
  mimeType: string;
}

export interface AttachmentPayload {
  mediaUrl: string;
  mimeType: string;
  fileName: string;
  fileSize: number;
  durationMs?: number;
  thumbnailUrl?: string;
}

export interface AudioMessage extends BaseMessage, AttachmentPayload {
  kind: "audio";
}

export interface ImageMessage extends BaseMessage, AttachmentPayload {
  kind: "image";
}

export interface VideoMessage extends BaseMessage, AttachmentPayload {
  kind: "video";
}

export interface FileMessage extends BaseMessage, AttachmentPayload {
  kind: "file";
}

export type ChatMessage = TextMessage | VoiceMessage | AudioMessage | ImageMessage | VideoMessage | FileMessage;

export interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  platform: "android" | "windows" | "unknown";
}

export interface AgentInfo {
  agentId: string;
  name: string;
  description: string;
  avatarUrl?: string;
  conversationId: string;
  registeredAt: string;
  status: AgentStatus;
  transport: "desktop-local" | "server";
  agentDeviceId: string;
}

export interface AgentConversationState {
  provider: "codex";
  selectedThreadId?: string | null;
  selectedModelId?: string;
  threadTitle?: string;
  lastSyncedAt: string;
}

export interface ConversationSummary {
  conversationId: string;
  title: string;
  type: ConversationType;
  updatedAt: string;
  agentId?: string;
  agentState?: AgentConversationState;
  lastMessage?: ChatMessage;
}

// ─── Phone WS events (existing + new stream) ─────────────────────

export interface HelloEvent {
  type: "auth.hello";
  device: DeviceInfo;
}

export interface ReadyEvent {
  type: "auth.ready";
  deviceId: string;
  conversationId: string;
}

export interface SendTextEvent {
  type: "message.send_text";
  conversationId: string;
  tempId: string;
  text: string;
}

export interface SendVoiceEvent {
  type: "message.send_voice";
  conversationId: string;
  tempId: string;
  mediaUrl: string;
  durationMs: number;
  mimeType: string;
}

export interface SendAttachmentEvent extends AttachmentPayload {
  type: "message.send_attachment";
  conversationId: string;
  tempId: string;
  kind: "audio" | "image" | "video" | "file";
}

export interface MessageCreatedEvent {
  type: "message.created";
  message: ChatMessage;
}

export interface MessageStatusEvent {
  type: "message.status";
  messageId: string;
  status: MessageStatus;
}

export interface SyncPullEvent {
  type: "sync.pull";
}

export interface SyncBatchEvent {
  type: "sync.batch";
  messages: ChatMessage[];
}

export interface MarkReadEvent {
  type: "message.read";
  messageId: string;
}

export interface ErrorEvent {
  type: "error";
  message: string;
}

export interface AgentTypingEvent {
  type: "agent.typing";
  conversationId: string;
  typing: boolean;
}

export interface ClientTypingEvent {
  type: "agent.typing";
  conversationId: string;
  typing: boolean;
}

// ─── New: Phone streaming events ──────────────────────────────────

export interface StreamTextEvent {
  type: "stream.text";
  conversationId: string;
  messageId: string;
  text: string;
  sequence: number;
}

export interface StreamTextDeltaEvent {
  type: "stream.text_delta";
  conversationId: string;
  messageId: string;
  delta: string;
  sequence: number;
}

export interface StreamDoneEvent {
  type: "stream.done";
  conversationId: string;
  messageId: string;
  finalText: string;
}

export interface StreamErrorEvent {
  type: "stream.error";
  conversationId: string;
  messageId?: string;
  error: string;
}

export interface StreamStepStartEvent {
  type: "stream.step_start";
  conversationId: string;
  stepId: string;
}

export interface StreamStepDoneEvent {
  type: "stream.step_done";
  conversationId: string;
  stepId: string;
  durationMs: number;
  tokens?: { total: number; input: number; output: number; reasoning: number };
}

export interface StreamToolCallEvent {
  type: "stream.tool_call";
  conversationId: string;
  stepId: string;
  tool: string;
  summary: string;
}

export interface StreamToolDetailEvent {
  type: "stream.tool_detail";
  conversationId: string;
  stepId: string;
  tool: string;
  input: Record<string, unknown>;
  output: string;
  title: string;
  summary?: string;
}

export interface StreamToolStatusEvent {
  type: "stream.tool_status";
  conversationId: string;
  stepId: string;
  tool: string;
  status: "pending" | "running" | "completed" | "error";
  title?: string;
}

export interface StreamThinkingEvent {
  type: "stream.thinking";
  conversationId: string;
  stepId: string;
  text: string;
}

export interface StatusEvent {
  type: "status";
  conversationId: string;
  agentName?: string;
  modelName?: string;
  tokenUsed?: number;
  tokenTotal?: number;
  sessionId?: string;
}

// ─── Todo model ───────────────────────────────────────────────────

export interface TodoItem {
  content: string;
  status: "pending" | "in_progress" | "completed" | "cancelled";
  priority: "high" | "medium" | "low";
}

export interface TodoEvent {
  type: "todo";
  conversationId: string;
  todos: TodoItem[];
}

// ─── Command response (phone UI picks) ────────────────────────────

export interface SessionInfo {
  sessionId: string;
  title: string;
  updatedAt: string;
}

export interface CommandResponseEvent {
  type: "command.response";
  conversationId: string;
  command: string;
  data:
    | { kind: "agents"; items: Array<{ name: string; current: boolean }> }
    | { kind: "models"; items: Array<{ name: string; current: boolean }> }
    | { kind: "sessions"; items: SessionInfo[]; current: string | null };
}

// ─── Bridge ↔ Server events ──────────────────────────────────────

export interface BridgeHelloEvent {
  type: "bridge.hello";
  deviceId: string;
  agents: Array<{
    agentId: string;
    name: string;
    conversationId: string;
    agentDeviceId: string;
  }>;
}

export interface BridgeNewMessageEvent {
  type: "bridge.message.new";
  conversationId: string;
  message: {
    id: string;
    text: string;
    senderDeviceId: string;
  };
}

export interface SseEvent {
  type: "sse";
  conversationId: string;
  eventType: string;
  data: Record<string, unknown>;
}

// ─── Event unions ─────────────────────────────────────────────────

export type ClientToServerEvent =
  | HelloEvent
  | SendTextEvent
  | SendVoiceEvent
  | SendAttachmentEvent
  | SyncPullEvent
  | MarkReadEvent
  | ClientTypingEvent;

export type PhoneServerEvent =
  | ReadyEvent
  | MessageCreatedEvent
  | MessageStatusEvent
  | SyncBatchEvent
  | AgentTypingEvent
  | StreamTextEvent
  | StreamTextDeltaEvent
  | StreamDoneEvent
  | StreamErrorEvent
  | StreamStepStartEvent
  | StreamStepDoneEvent
  | StreamToolCallEvent
  | StreamToolDetailEvent
  | StreamToolStatusEvent
  | StreamThinkingEvent
  | StatusEvent
  | TodoEvent
  | CommandResponseEvent
  | ErrorEvent
  | SseEvent;

// Legacy alias
export type ServerToClientEvent = PhoneServerEvent;

export type BridgeServerEvent =
  | BridgeHelloEvent
  | BridgeNewMessageEvent;

// Bridge → Server (via WS, forwarded to phone)
export type BridgeClientEvent =
  | BridgeHelloEvent
  | { type: "bridge.stream.text"; conversationId: string; messageId: string; text: string; sequence: number }
  | { type: "bridge.stream.text_delta"; conversationId: string; messageId: string; delta: string; sequence: number }
  | { type: "bridge.stream.tool_call"; conversationId: string; stepId: string; tool: string; summary: string }
  | { type: "bridge.stream.tool_detail"; conversationId: string; stepId: string; tool: string; input: Record<string, unknown>; output: string; title: string; summary?: string }
  | { type: "bridge.stream.tool_status"; conversationId: string; stepId: string; tool: string; status: StreamToolStatusEvent["status"]; title?: string }
  | { type: "bridge.stream.thinking"; conversationId: string; stepId: string; text: string }
  | { type: "bridge.stream.step_start"; conversationId: string; stepId: string }
  | { type: "bridge.stream.step_done"; conversationId: string; stepId: string; durationMs: number; tokens?: StreamStepDoneEvent["tokens"] }
  | { type: "bridge.stream.done"; conversationId: string; messageId: string; finalText: string }
  | { type: "bridge.stream.error"; conversationId: string; messageId?: string; error: string }
  | { type: "bridge.status"; conversationId: string; agentName?: string; modelName?: string; tokenUsed?: number; tokenTotal?: number; sessionId?: string }
  | { type: "bridge.todo"; conversationId: string; todos: TodoItem[] }
  | { type: "bridge.command.response"; conversationId: string; command: string; data: CommandResponseEvent["data"] }
  | { type: "bridge.sse"; conversationId: string; eventType: string; data: Record<string, unknown> };

export const DEFAULT_CONVERSATION_ID = "primary";
export const DEFAULT_CONVERSATION_TITLE = "我的设备";

export const LOCAL_AGENT_PORT = 45888;
