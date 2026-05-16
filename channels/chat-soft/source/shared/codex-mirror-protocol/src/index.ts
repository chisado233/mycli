export type MirrorConnectionState = "connected" | "disconnected" | "connecting" | "degraded";

export type MirrorSendState =
  | "pending"
  | "submitting"
  | "confirmed"
  | "failed";

export type MirrorMessageRole = "user" | "assistant" | "system" | "tool";

export interface MirrorSessionSummary {
  sessionId: string;
  sourceSessionId: string;
  source: "vscode-codex";
  title: string;
  mirrorTitle?: string;
  effectiveTitle: string;
  modelId?: string;
  updatedAt: string;
  lastActiveAt: string;
  deletedInMirror: boolean;
}

export interface MirrorMessageView {
  messageId: string;
  sessionId: string;
  sourceMessageId?: string;
  role: MirrorMessageRole;
  text: string;
  createdAt: string;
  updatedAt: string;
  finalizedAt?: string;
  isStreaming: boolean;
  sendState: MirrorSendState;
}

export interface MirrorRawEvent {
  eventId: string;
  sessionId: string;
  messageId?: string;
  eventType: string;
  eventIndex: number;
  eventTs: string;
  rawPayload: unknown;
  normalizedPayload?: unknown;
}

export interface MirrorMessageRecord {
  view: MirrorMessageView;
  rawEvents?: MirrorRawEvent[];
}

export interface MirrorStatus {
  connectionState: MirrorConnectionState;
  currentSessionId?: string;
  defaultModelId?: string;
  lastSyncedAt?: string;
  reason?: string;
}

export interface ListSessionsResponse {
  status: MirrorStatus;
  sessions: MirrorSessionSummary[];
}

export interface GetSessionResponse {
  status: MirrorStatus;
  session: MirrorSessionSummary;
}

export interface ListMessagesResponse {
  status: MirrorStatus;
  session: MirrorSessionSummary;
  messages: MirrorMessageView[];
  rawEventsIncluded: boolean;
}

export interface CreateSessionRequest {
  modelId?: string;
}

export interface RenameSessionRequest {
  mirrorTitle: string;
}

export interface SwitchSessionRequest {
  waitForSwitch?: boolean;
}

export interface SetSessionModelRequest {
  modelId: string;
  waitForSync?: boolean;
}

export interface SetDefaultModelRequest {
  modelId: string;
}

export interface SendMessageRequest {
  text: string;
  waitForConfirmation?: boolean;
}

export interface SendMessageResponse {
  accepted: boolean;
  message: MirrorMessageView;
}

export interface RetryMessageResponse {
  accepted: boolean;
  message: MirrorMessageView;
}

export interface CodexMirrorEventEnvelope {
  type:
    | "connection.changed"
    | "session.created"
    | "session.updated"
    | "session.deleted"
    | "session.switched"
    | "message.created"
    | "message.delta"
    | "message.completed"
    | "message.failed"
    | "message.retrying"
    | "raw.codex.event";
  ts: string;
  payload: unknown;
}

export interface ExportManifest {
  session: MirrorSessionSummary;
  formats: Array<"json" | "markdown" | "raw">;
}
