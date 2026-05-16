import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import * as http from "node:http";
import * as https from "node:https";
import path from "node:path";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import Fastify from "fastify";
import type { FastifyRequest } from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import type {
  CodexMirrorEventEnvelope,
  CreateSessionRequest,
  ExportManifest,
  ListMessagesResponse,
  ListSessionsResponse,
  MirrorConnectionState,
  MirrorMessageRecord,
  MirrorMessageView,
  MirrorRawEvent,
  MirrorSessionSummary,
  MirrorStatus,
  RenameSessionRequest,
  RetryMessageResponse,
  SendMessageRequest,
  SendMessageResponse,
  SetDefaultModelRequest,
  SetSessionModelRequest,
  SwitchSessionRequest
} from "@chat-soft/codex-mirror-protocol";

type JsonRpcResponse = {
  id: number;
  result?: unknown;
  error?: unknown;
};

type JsonRpcNotification = {
  method: string;
  params?: any;
};

type CodexModel = {
  id: string;
};

type CodexThread = {
  id: string;
  preview: string;
  updatedAt: number;
  cwd: string;
  name?: string | null;
  turns?: CodexTurn[];
};

type CodexThreadItem =
  | {
      type: "userMessage";
      content?: Array<{ type?: string; text?: string }>;
    }
  | {
      type: "agentMessage";
      text?: string;
    }
  | {
      type: "reasoning";
      summary?: string[];
      content?: string[];
    }
  | {
      type: string;
      [key: string]: unknown;
    };

type CodexTurn = {
  id: string;
  items: CodexThreadItem[];
};

type PersistedStore = {
  aliases: Record<string, string>;
  hiddenSessionIds: string[];
  defaultModelId: string;
  currentSessionId?: string;
  lastSyncedAt?: string;
};

type PendingStream = {
  turnId: string;
  sessionId: string;
  userMessage: MirrorMessageView;
  assistantMessage: MirrorMessageView;
  rawEvents: MirrorRawEvent[];
  chunks: string[];
  timeout: NodeJS.Timeout;
};

type PendingSendResult = {
  assistantText: string;
};

const workspaceRoot = path.resolve(process.cwd(), "../..");
const dataDir = path.resolve(process.cwd(), "data");
const storeFile = path.join(dataDir, "mirror-store.json");

function nowIso() {
  return new Date().toISOString();
}

function clampText(value: string, max = 80) {
  const clean = value.replace(/\s+/g, " ").trim();
  if (clean.length <= max) {
    return clean;
  }
  return `${clean.slice(0, max)}...`;
}

function safeJson(value: unknown) {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function toIsoFromCodexTimestamp(value: number | string | undefined) {
  if (typeof value === "string") {
    const parsed = Number(value);
    if (!Number.isNaN(parsed)) {
      return toIsoFromCodexTimestamp(parsed);
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? nowIso() : date.toISOString();
  }

  if (typeof value !== "number" || Number.isNaN(value)) {
    return nowIso();
  }

  const normalized = value < 100_000_000_000 ? value * 1000 : value;
  return new Date(normalized).toISOString();
}

class CodexAppServerClient {
  private child: ChildProcessWithoutNullStreams | null = null;
  private buffer = "";
  private nextRequestId = 1;
  private readonly pending = new Map<number, { resolve: (value: unknown) => void; reject: (error: Error) => void }>();
  private readonly notificationListeners = new Set<(notification: JsonRpcNotification) => void>();

  constructor(
    private readonly executable: string,
    private readonly workspaceRootPath: string,
    private readonly proxyUrl: string,
    private readonly noProxy: string[],
    private readonly log: (message: string) => void
  ) {}

  async start() {
    if (this.child) {
      return;
    }

    const env: NodeJS.ProcessEnv = {
      ...process.env,
      NO_PROXY: this.noProxy.join(","),
      no_proxy: this.noProxy.join(",")
    };

    if (this.proxyUrl) {
      env.HTTP_PROXY = this.proxyUrl;
      env.HTTPS_PROXY = this.proxyUrl;
      env.ALL_PROXY = this.proxyUrl;
      env.http_proxy = this.proxyUrl;
      env.https_proxy = this.proxyUrl;
      env.all_proxy = this.proxyUrl;
    }

    this.child = spawn(this.executable, ["app-server", "--listen", "stdio://"], {
      cwd: this.workspaceRootPath,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
      env
    });

    this.child.stdout.setEncoding("utf8");
    this.child.stdout.on("data", (chunk: string) => this.handleStdout(chunk));

    this.child.stderr.setEncoding("utf8");
    this.child.stderr.on("data", (chunk: string) => {
      const line = chunk.trim();
      if (line) {
        this.log(line);
      }
    });

    this.child.on("close", (code) => {
      this.log(`Codex app-server closed with code ${String(code)}`);
      this.child = null;
      for (const pending of this.pending.values()) {
        pending.reject(new Error("Codex app-server closed."));
      }
      this.pending.clear();
    });

    await this.request("initialize", {
      clientInfo: {
        name: "chat-soft-codex-mirror",
        title: "Chat Soft Codex Mirror",
        version: "0.1.0"
      },
      capabilities: {
        experimentalApi: true
      }
    });
  }

  stop() {
    this.child?.kill();
    this.child = null;
  }

  async request<T = unknown>(method: string, params: unknown): Promise<T> {
    await this.start();
    if (!this.child) {
      throw new Error("Codex app-server is not available.");
    }

    const id = this.nextRequestId++;
    const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params });
    const promise = new Promise<T>((resolve, reject) => {
      this.pending.set(id, {
        resolve: (value) => resolve(value as T),
        reject
      });
    });

    this.child.stdin.write(`${payload}\n`);
    return promise;
  }

  onNotification(listener: (notification: JsonRpcNotification) => void) {
    this.notificationListeners.add(listener);
    return () => {
      this.notificationListeners.delete(listener);
    };
  }

  private handleStdout(chunk: string) {
    this.buffer += chunk;
    while (true) {
      const newlineIndex = this.buffer.indexOf("\n");
      if (newlineIndex < 0) {
        break;
      }

      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);
      if (!line) {
        continue;
      }

      try {
        const message = JSON.parse(line) as JsonRpcResponse | JsonRpcNotification;
        if ("method" in message) {
          for (const listener of this.notificationListeners) {
            listener(message);
          }
          continue;
        }

        const pending = this.pending.get(message.id);
        if (!pending) {
          continue;
        }
        this.pending.delete(message.id);
        if (message.error) {
          pending.reject(new Error(typeof message.error === "string" ? message.error : JSON.stringify(message.error)));
        } else {
          pending.resolve(message.result);
        }
      } catch (error) {
        this.log(`Failed to parse app-server message: ${String(error)}`);
      }
    }
  }
}

class LocalStore {
  private state: PersistedStore = {
    aliases: {},
    hiddenSessionIds: [],
    defaultModelId: "gpt-5.4"
  };

  async init() {
    await mkdir(dataDir, { recursive: true });
    try {
      const raw = await readFile(storeFile, "utf8");
      this.state = {
        aliases: {},
        hiddenSessionIds: [],
        defaultModelId: "gpt-5.4",
        ...(JSON.parse(raw) as Partial<PersistedStore>)
      };
    } catch {
      await this.persist();
    }
  }

  getState() {
    return this.state;
  }

  async renameSession(sessionId: string, title: string) {
    if (title.trim()) {
      this.state.aliases[sessionId] = title.trim();
    } else {
      delete this.state.aliases[sessionId];
    }
    await this.persist();
  }

  async hideSession(sessionId: string) {
    if (!this.state.hiddenSessionIds.includes(sessionId)) {
      this.state.hiddenSessionIds.push(sessionId);
      await this.persist();
    }
  }

  async setCurrentSession(sessionId?: string) {
    this.state.currentSessionId = sessionId;
    this.state.lastSyncedAt = nowIso();
    await this.persist();
  }

  async setDefaultModel(modelId: string) {
    this.state.defaultModelId = modelId;
    this.state.lastSyncedAt = nowIso();
    await this.persist();
  }

  private async persist() {
    await writeFile(storeFile, JSON.stringify(this.state, null, 2), "utf8");
  }
}

class CodexMirrorService {
  private client: CodexAppServerClient | null = null;
  private connectionState: MirrorConnectionState = "connecting";
  private connectionReason = "Initializing Codex connection...";
  private readonly pendingTurns = new Map<string, PendingStream>();

  constructor(
    private readonly store: LocalStore,
    private readonly emit: (event: CodexMirrorEventEnvelope) => void,
    private readonly log: (message: string) => void
  ) {}

  async init() {
    await this.store.init();
    await this.ensureClient();
  }

  getStatus(): MirrorStatus {
    const state = this.store.getState();
    return {
      connectionState: this.connectionState,
      currentSessionId: state.currentSessionId,
      defaultModelId: state.defaultModelId,
      lastSyncedAt: state.lastSyncedAt,
      reason: this.connectionReason
    };
  }

  async listModels() {
    const client = await this.requireClient();
    const response = await client.request<{ data?: Array<{ id?: string }> }>("model/list", {});
    return (response.data || [])
      .map((item) => ({ id: item.id || "" }))
      .filter((item) => Boolean(item.id))
      .map((item) => ({
        id: item.id,
        label: item.id
      }));
  }

  async listSessions(): Promise<ListSessionsResponse> {
    const threads = await this.listRecentThreads();
    const sessions = threads.map((thread) => this.mapThreadToSession(thread));
    return {
      status: this.getStatus(),
      sessions
    };
  }

  async getSession(sessionId: string) {
    const thread = await this.readThreadMeta(sessionId);
    return {
      status: this.getStatus(),
      session: this.mapThreadToSession(thread)
    };
  }

  async createSession(body: CreateSessionRequest) {
    const modelId = body.modelId || this.store.getState().defaultModelId;
    const client = await this.requireClient();
    const response = await client.request<{ thread: CodexThread }>("thread/start", {
      model: modelId,
      cwd: workspaceRoot,
      approvalPolicy: "never",
      sandbox: "danger-full-access",
      experimentalRawEvents: true,
      persistExtendedHistory: true
    });
    await this.store.setCurrentSession(response.thread.id);
    const session = this.mapThreadToSession(response.thread);
    this.emit(this.wrapEvent("session.created", session));
    return {
      status: this.getStatus(),
      session
    };
  }

  async renameSession(sessionId: string, body: RenameSessionRequest) {
    await this.readThreadMeta(sessionId);
    await this.store.renameSession(sessionId, body.mirrorTitle);
    const session = this.mapThreadToSession(await this.readThreadMeta(sessionId));
    this.emit(this.wrapEvent("session.updated", session));
    return {
      status: this.getStatus(),
      session
    };
  }

  async deleteSession(sessionId: string) {
    await this.readThreadMeta(sessionId);
    await this.store.hideSession(sessionId);
    const session = this.mapThreadToSession(await this.readThreadMeta(sessionId));
    this.emit(this.wrapEvent("session.deleted", session));
    return {
      status: this.getStatus(),
      session
    };
  }

  async switchSession(sessionId: string, _body: SwitchSessionRequest) {
    await this.readThreadMeta(sessionId);
    await this.store.setCurrentSession(sessionId);
    const session = this.mapThreadToSession(await this.readThreadMeta(sessionId));
    this.connectionReason = "Codex connected. Session switch is tracked in mirror; VS Code visible-tab switching is not wired yet.";
    this.emit(this.wrapEvent("session.switched", session));
    return {
      status: this.getStatus(),
      session
    };
  }

  async listMessages(sessionId: string): Promise<ListMessagesResponse> {
    const thread = await this.readThreadWithTurns(sessionId);
    const session = this.mapThreadToSession(thread);
    const records = this.normalizeThreadMessages(thread);
    const pending = this.pendingMessagesForSession(sessionId);
    return {
      status: this.getStatus(),
      session,
      messages: [...records.map((record) => record.view), ...pending].sort((left, right) =>
        left.createdAt.localeCompare(right.createdAt)
      ),
      rawEventsIncluded: false
    };
  }

  async sendMessage(sessionId: string, body: SendMessageRequest): Promise<SendMessageResponse> {
    const text = body.text?.trim();
    if (!text) {
      throw new Error("Message text is required");
    }

    const session = this.mapThreadToSession(await this.readThreadMeta(sessionId));
    await this.store.setCurrentSession(sessionId);
    const client = await this.requireClient();

    const userMessage: MirrorMessageView = {
      messageId: randomUUID(),
      sessionId,
      role: "user",
      text,
      createdAt: nowIso(),
      updatedAt: nowIso(),
      isStreaming: false,
      sendState: "submitting"
    };

    const assistantMessage: MirrorMessageView = {
      messageId: randomUUID(),
      sessionId,
      role: "assistant",
      text: "",
      createdAt: nowIso(),
      updatedAt: nowIso(),
      isStreaming: true,
      sendState: "pending"
    };

    this.emit(this.wrapEvent("message.created", userMessage));
    this.emit(this.wrapEvent("message.created", assistantMessage));

    const started = await client.request<{ turn: { id: string } }>("turn/start", {
      threadId: sessionId,
      input: [
        {
          type: "text",
          text,
          text_elements: []
        }
      ],
      model: session.modelId || this.store.getState().defaultModelId
    });

    const pending: PendingStream = {
      turnId: started.turn.id,
      sessionId,
      userMessage,
      assistantMessage,
      rawEvents: [
        {
          eventId: randomUUID(),
          sessionId,
          messageId: userMessage.messageId,
          eventType: "mirror.message.submitted",
          eventIndex: 0,
          eventTs: nowIso(),
          rawPayload: { text }
        }
      ],
      chunks: [],
      timeout: setTimeout(() => {
        const failed = this.pendingTurns.get(started.turn.id);
        if (!failed) {
          return;
        }
        failed.assistantMessage.isStreaming = false;
        failed.assistantMessage.sendState = "failed";
        failed.assistantMessage.updatedAt = nowIso();
        this.pendingTurns.delete(started.turn.id);
        this.emit(this.wrapEvent("message.failed", failed.assistantMessage));
      }, 120000)
    };

    pending.userMessage.sendState = "confirmed";
    pending.userMessage.updatedAt = nowIso();
    this.pendingTurns.set(started.turn.id, pending);
    this.emit(this.wrapEvent("message.completed", pending.userMessage));

    return {
      accepted: true,
      message: pending.userMessage
    };
  }

  async retryMessage(messageId: string): Promise<RetryMessageResponse> {
    for (const pending of this.pendingTurns.values()) {
      if (pending.userMessage.messageId === messageId || pending.assistantMessage.messageId === messageId) {
        this.emit(this.wrapEvent("message.retrying", pending.userMessage));
        return {
          accepted: false,
          message: pending.userMessage
        };
      }
    }

    throw new Error("Only in-flight messages can be retried in the current build");
  }

  async setSessionModel(sessionId: string, body: SetSessionModelRequest) {
    const session = this.mapThreadToSession(await this.readThreadMeta(sessionId), body.modelId);
    this.emit(this.wrapEvent("session.updated", session));
    return {
      status: {
        ...this.getStatus(),
        currentSessionId: sessionId
      },
      session
    };
  }

  async setDefaultModel(body: SetDefaultModelRequest) {
    await this.store.setDefaultModel(body.modelId);
    const status = this.getStatus();
    this.emit(this.wrapEvent("connection.changed", status));
    return { status };
  }

  async exportSession(sessionId: string, format: "json" | "markdown" | "raw") {
    const thread = await this.readThreadWithTurns(sessionId);
    const session = this.mapThreadToSession(thread);
    const records = this.normalizeThreadMessages(thread);
    const manifest: ExportManifest = {
      session,
      formats: ["json", "markdown", "raw"]
    };

    if (format === "markdown") {
      const lines = [`# ${session.effectiveTitle}`, ""];
      for (const record of records) {
        lines.push(`## ${record.view.role}`);
        lines.push("");
        lines.push(record.view.text || "");
        lines.push("");
      }
      return { manifest, content: lines.join("\n") };
    }

    if (format === "raw") {
      return {
        manifest,
        content: {
          session,
          rawTurns: thread.turns || [],
          rawEvents: records.flatMap((record) => record.rawEvents || [])
        }
      };
    }

    return {
      manifest,
      content: {
        status: this.getStatus(),
        session,
        messages: records
      }
    };
  }

  private wrapEvent(type: CodexMirrorEventEnvelope["type"], payload: unknown): CodexMirrorEventEnvelope {
    return {
      type,
      ts: nowIso(),
      payload
    };
  }

  private async ensureClient() {
    if (this.client) {
      return this.client;
    }

    const executable = await this.resolveCodexExecutable();
    const proxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || "";
    const client = new CodexAppServerClient(executable, workspaceRoot, proxyUrl, ["127.0.0.1", "localhost", "::1"], (msg) =>
      this.log(msg)
    );
    client.onNotification((notification) => this.handleNotification(notification));

    try {
      await client.start();
      this.client = client;
      this.connectionState = "connected";
      this.connectionReason = "Codex connected.";
      this.emit(this.wrapEvent("connection.changed", this.getStatus()));
      return client;
    } catch (error) {
      this.connectionState = "disconnected";
      this.connectionReason = `Codex connection failed: ${String(error)}`;
      this.emit(this.wrapEvent("connection.changed", this.getStatus()));
      throw error;
    }
  }

  private async requireClient() {
    try {
      return await this.ensureClient();
    } catch (error) {
      this.connectionState = "disconnected";
      this.connectionReason = `Codex unavailable: ${String(error)}`;
      throw new Error("Codex 未连接");
    }
  }

  private handleNotification(notification: JsonRpcNotification) {
    if (notification.method === "item/agentMessage/delta") {
      const params = notification.params as { turnId: string; delta: string };
      const pending = this.pendingTurns.get(params.turnId);
      if (!pending) {
        return;
      }
      pending.chunks.push(params.delta || "");
      pending.assistantMessage.text = pending.chunks.join("");
      pending.assistantMessage.updatedAt = nowIso();
      pending.rawEvents.push({
        eventId: randomUUID(),
        sessionId: pending.sessionId,
        messageId: pending.assistantMessage.messageId,
        eventType: "codex.agent.delta",
        eventIndex: pending.rawEvents.length,
        eventTs: nowIso(),
        rawPayload: notification.params,
        normalizedPayload: { delta: params.delta || "" }
      });
      this.emit(this.wrapEvent("message.delta", pending.assistantMessage));
      this.emit(this.wrapEvent("raw.codex.event", notification));
      return;
    }

    if (notification.method === "turn/completed") {
      const params = notification.params as { turn: { id: string; status: string; error?: { message?: string } | null } };
      const pending = this.pendingTurns.get(params.turn.id);
      if (!pending) {
        return;
      }

      clearTimeout(pending.timeout);
      this.pendingTurns.delete(params.turn.id);
      pending.assistantMessage.isStreaming = false;
      pending.assistantMessage.updatedAt = nowIso();
      pending.assistantMessage.finalizedAt = nowIso();

      if (params.turn.status === "failed" || params.turn.error) {
        pending.assistantMessage.sendState = "failed";
        this.emit(this.wrapEvent("message.failed", pending.assistantMessage));
      } else {
        pending.assistantMessage.text = pending.chunks.join("").trim();
        pending.assistantMessage.sendState = "confirmed";
        this.emit(this.wrapEvent("message.completed", pending.assistantMessage));
      }

      this.emit(this.wrapEvent("raw.codex.event", notification));
      return;
    }

    if (notification.method === "error") {
      this.connectionState = "degraded";
      this.connectionReason = safeJson(notification.params ?? {});
      this.emit(this.wrapEvent("connection.changed", this.getStatus()));
      this.emit(this.wrapEvent("raw.codex.event", notification));
    }
  }

  private async resolveCodexExecutable() {
    if (process.env.CODEX_EXECUTABLE?.trim()) {
      return process.env.CODEX_EXECUTABLE.trim();
    }

    return "codex";
  }

  private async listRecentThreads() {
    const client = await this.requireClient();
    const merged = new Map<string, CodexThread>();

    try {
      const loaded = await client.request<{ data?: string[] }>("thread/loaded/list", { limit: 100 });
      for (const id of loaded.data || []) {
        try {
          const response = await client.request<{ thread: CodexThread }>("thread/read", {
            threadId: id,
            includeTurns: false
          });
          merged.set(response.thread.id, response.thread);
        } catch (error) {
          this.log(`Failed to read loaded thread ${id}: ${String(error)}`);
        }
      }
    } catch (error) {
      this.log(`thread/loaded/list failed: ${String(error)}`);
    }

    const listed = await client.request<{ data?: CodexThread[] }>("thread/list", {
      limit: 200,
      archived: false
    });
    for (const thread of listed.data || []) {
      merged.set(thread.id, thread);
    }

    const hidden = new Set(this.store.getState().hiddenSessionIds);
    return [...merged.values()]
      .filter((thread) => !hidden.has(thread.id))
      .sort((left, right) => right.updatedAt - left.updatedAt);
  }

  private async readThreadMeta(threadId: string) {
    const client = await this.requireClient();
    const response = await client.request<{ thread: CodexThread }>("thread/read", {
      threadId,
      includeTurns: false
    });
    return response.thread;
  }

  private async readThreadWithTurns(threadId: string) {
    const client = await this.requireClient();
    const response = await client.request<{ thread: CodexThread }>("thread/read", {
      threadId,
      includeTurns: true
    });
    return response.thread;
  }

  private mapThreadToSession(thread: CodexThread, modelIdOverride?: string): MirrorSessionSummary {
    const alias = this.store.getState().aliases[thread.id];
    const title =
      thread.name?.trim() ||
      thread.preview?.trim() ||
      path.basename(thread.cwd || workspaceRoot) ||
      "Untitled Codex Session";
    return {
      sessionId: thread.id,
      sourceSessionId: thread.id,
      source: "vscode-codex",
      title,
      mirrorTitle: alias,
      effectiveTitle: alias || title,
      modelId: modelIdOverride || this.store.getState().defaultModelId,
      updatedAt: toIsoFromCodexTimestamp(thread.updatedAt),
      lastActiveAt: toIsoFromCodexTimestamp(thread.updatedAt),
      deletedInMirror: false
    };
  }

  private normalizeThreadMessages(thread: CodexThread): MirrorMessageRecord[] {
    const records: MirrorMessageRecord[] = [];
    const sessionId = thread.id;
    const turns = thread.turns || [];

    for (const turn of turns) {
      for (const item of turn.items || []) {
        if (item.type === "userMessage") {
          const contentItems = Array.isArray(item.content) ? item.content : [];
          const text = contentItems
            .filter((content: { type?: string; text?: string }) => content.type === "text" && content.text)
            .map((content: { type?: string; text?: string }) => content.text?.trim() || "")
            .filter(Boolean)
            .join("\n");
          if (!text) {
            continue;
          }
          records.push(this.createRecord(sessionId, "user", text, turn.id, item));
          continue;
        }

        if (item.type === "agentMessage") {
          const text = typeof item.text === "string" ? item.text.trim() : "";
          if (!text) {
            continue;
          }
          records.push(this.createRecord(sessionId, "assistant", text, turn.id, item));
          continue;
        }

        if (item.type === "reasoning") {
          const summaryItems = Array.isArray(item.summary) ? item.summary : [];
          const contentItems = Array.isArray(item.content) ? item.content : [];
          const text = [...summaryItems, ...contentItems].filter(Boolean).join("\n");
          if (!text) {
            continue;
          }
          records.push(this.createRecord(sessionId, "tool", text, turn.id, item));
          continue;
        }

        const fallbackText = safeJson(item);
        records.push(this.createRecord(sessionId, "tool", fallbackText, turn.id, item));
      }
    }

    return records;
  }

  private createRecord(
    sessionId: string,
    role: MirrorMessageView["role"],
    text: string,
    sourceMessageId: string,
    rawPayload: unknown
  ): MirrorMessageRecord {
    const createdAt = nowIso();
    return {
      view: {
        messageId: `${sourceMessageId}:${role}:${Math.abs(this.hashText(text))}`,
        sessionId,
        sourceMessageId,
        role,
        text,
        createdAt,
        updatedAt: createdAt,
        finalizedAt: createdAt,
        isStreaming: false,
        sendState: "confirmed"
      },
      rawEvents: [
        {
          eventId: randomUUID(),
          sessionId,
          messageId: `${sourceMessageId}:${role}:${Math.abs(this.hashText(text))}`,
          eventType: "codex.thread.item",
          eventIndex: 0,
          eventTs: createdAt,
          rawPayload
        }
      ]
    };
  }

  private pendingMessagesForSession(sessionId: string) {
    const views: MirrorMessageView[] = [];
    for (const pending of this.pendingTurns.values()) {
      if (pending.sessionId !== sessionId) {
        continue;
      }
      views.push(pending.userMessage, pending.assistantMessage);
    }
    return views;
  }

  private hashText(text: string) {
    let value = 0;
    for (let index = 0; index < text.length; index += 1) {
      value = (value << 5) - value + text.charCodeAt(index);
      value |= 0;
    }
    return value;
  }
}

const app = Fastify({ logger: true });
const websocketClients = new Set<{ send: (payload: string) => void }>();

function emit(event: CodexMirrorEventEnvelope) {
  const payload = JSON.stringify(event);
  for (const client of websocketClients) {
    client.send(payload);
  }
}

const store = new LocalStore();
const service = new CodexMirrorService(store, emit, (message) => app.log.info(message));

await app.register(cors, { origin: true });
await app.register(websocket);
await service.init();

app.get("/health", async () => ({ ok: true }));

app.get("/api/codex-mirror/status", async () => service.getStatus());

app.get("/api/codex-mirror/sessions", async (): Promise<ListSessionsResponse> => service.listSessions());

app.post("/api/codex-mirror/sessions", async (request: FastifyRequest) => {
  const body = (request.body || {}) as CreateSessionRequest;
  return service.createSession(body);
});

app.get("/api/codex-mirror/sessions/:sessionId", async (request: FastifyRequest) => {
  const { sessionId } = request.params as { sessionId: string };
  return service.getSession(sessionId);
});

app.patch("/api/codex-mirror/sessions/:sessionId", async (request: FastifyRequest) => {
  const { sessionId } = request.params as { sessionId: string };
  const body = request.body as RenameSessionRequest;
  return service.renameSession(sessionId, body);
});

app.delete("/api/codex-mirror/sessions/:sessionId", async (request: FastifyRequest) => {
  const { sessionId } = request.params as { sessionId: string };
  return service.deleteSession(sessionId);
});

app.post("/api/codex-mirror/sessions/:sessionId/switch", async (request: FastifyRequest) => {
  const { sessionId } = request.params as { sessionId: string };
  const body = (request.body || {}) as SwitchSessionRequest;
  return service.switchSession(sessionId, body);
});

app.get("/api/codex-mirror/sessions/:sessionId/messages", async (request: FastifyRequest): Promise<ListMessagesResponse> => {
  const { sessionId } = request.params as { sessionId: string };
  return service.listMessages(sessionId);
});

app.post("/api/codex-mirror/sessions/:sessionId/messages", async (request: FastifyRequest): Promise<SendMessageResponse> => {
  const { sessionId } = request.params as { sessionId: string };
  const body = request.body as SendMessageRequest;
  return service.sendMessage(sessionId, body);
});

app.post("/api/codex-mirror/messages/:messageId/retry", async (request: FastifyRequest): Promise<RetryMessageResponse> => {
  const { messageId } = request.params as { messageId: string };
  return service.retryMessage(messageId);
});

app.get("/api/codex-mirror/models", async () => {
  return {
    status: service.getStatus(),
    models: await service.listModels()
  };
});

app.post("/api/codex-mirror/sessions/:sessionId/model", async (request: FastifyRequest) => {
  const { sessionId } = request.params as { sessionId: string };
  const body = request.body as SetSessionModelRequest;
  return service.setSessionModel(sessionId, body);
});

app.post("/api/codex-mirror/default-model", async (request: FastifyRequest) => {
  const body = request.body as SetDefaultModelRequest;
  return service.setDefaultModel(body);
});

app.get("/api/codex-mirror/sessions/:sessionId/export", async (request: FastifyRequest) => {
  const { sessionId } = request.params as { sessionId: string };
  const { format = "json" } = request.query as { format?: "json" | "markdown" | "raw" };
  return service.exportSession(sessionId, format);
});

app.get("/ws", { websocket: true }, (socket: { send: (payload: string) => void; on: (event: string, cb: () => void) => void }) => {
  const client = {
    send(payload: string) {
      socket.send(payload);
    }
  };
  websocketClients.add(client);
  socket.send(
    JSON.stringify({
      type: "connection.changed",
      ts: nowIso(),
      payload: service.getStatus()
    } satisfies CodexMirrorEventEnvelope)
  );
  socket.on("close", () => {
    websocketClients.delete(client);
  });
});

const host = process.env.HOST || "127.0.0.1";
const port = Number(process.env.PORT || 3090);

app.listen({ host, port }).catch((error: unknown) => {
  app.log.error(error);
  process.exit(1);
});
