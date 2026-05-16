import Fastify from "fastify";
import { spawn } from "node:child_process";
import { basename, extname, resolve } from "node:path";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { LOCAL_AGENT_PORT } from "@chat-soft/protocol";

interface LocalAgentConfig {
  serverBaseUrl: string;
  deviceId: string;
  deviceName: string;
  agentId: string;
  agentName: string;
  agentDescription: string;
  agentCliPath: string;
  agentCliMappedAgent: string;
  agentCliCwd: string;
}

interface RegisteredAgent {
  agentId: string;
  name: string;
  description: string;
  agentDeviceId: string;
  conversationId: string;
  registeredAt?: string;
  status?: string;
}

interface AgentAttachmentBody {
  filePath: string;
  fileName?: string;
  mimeType?: string;
  durationMs?: number;
  thumbnailUrl?: string;
}

interface LlmCatalogEntry {
  provider: string;
  model: string;
}

interface LlmAgentState {
  agent: RegisteredAgent;
  provider: string;
  model: string;
  systemPrompt: string;
  temperature: number;
  maxTokens: number;
  history: Array<{ role: "user" | "assistant"; content: string }>;
  processedMessageIds: Set<string>;
  running: boolean;
  lastError?: string;
}

interface AgentCliAgentState {
  agent: RegisteredAgent;
  systemPrompt: string;
  sessionIdsByConversationId: Map<string, string>;
  model?: string;
  processedMessageIds: Set<string>;
  running: boolean;
  lastError?: string;
}

interface AgentCliResult {
  ok: boolean;
  stdout: string;
  stderr: string;
  exitCode: number | null;
  command: string;
  sessionId?: string;
}

interface OpenCodeSessionSummary {
  sessionId: string;
  title: string;
  updatedAt: string;
}

interface WorkerListModelsResult {
  ok: boolean;
  models?: LlmCatalogEntry[];
  error?: string;
}

interface WorkerChatResult {
  ok: boolean;
  provider?: string;
  model?: string;
  content?: string;
  error?: string;
}

type ServerMessage = {
  id: string;
  kind: "text" | "voice" | "audio" | "image" | "video" | "file";
  conversationId: string;
  senderDeviceId: string;
  createdAt: string;
  text?: string;
};

const DEFAULT_LLM_SYSTEM_PROMPT =
  "你是 Chat Soft 内的一个独立 LLM 对话 agent。回答要直接、自然、中文优先，并保持有帮助。";
const LLM_POLL_INTERVAL_MS = 1500;
const MAX_HISTORY_MESSAGES = 24;

const DEFAULT_AGENT_CLI_SYSTEM_PROMPT =
  "你是运行在用户本地电脑的 private-assistant 开发助手，通过 mycli agent-cli 调用。你负责帮助用户完成代码开发、项目维护、命令执行、问题排查、能力调用等工作。回答要简洁、直接，返回操作结果即可。";
const AGENT_CLI_POLL_INTERVAL_MS = 1000;

const desktopRoot = process.cwd();
const projectsRoot = resolve(desktopRoot, "..", "..", "..");
const llmConfigPath = resolve(projectsRoot, "mult_agent", "config", "llm.json");
const llmSourceDir = resolve(projectsRoot, "mult_agent", "src", "llm");
const llmWorkerPath = resolve(desktopRoot, "electron", "llm-worker.py");
const runtimeStateDir = resolve(desktopRoot, "runtime", "state");
const agentCliSessionStatePath = resolve(runtimeStateDir, "agent-cli-sessions.json");

type AgentCliSessionStore = Record<string, Record<string, string>>;

function loadAgentCliSessionStore(): AgentCliSessionStore {
  if (!existsSync(agentCliSessionStatePath)) return {};
  try {
    return JSON.parse(readFileSync(agentCliSessionStatePath, "utf8")) as AgentCliSessionStore;
  } catch {
    return {};
  }
}

function saveAgentCliSessionStore(store: AgentCliSessionStore) {
  if (!existsSync(runtimeStateDir)) mkdirSync(runtimeStateDir, { recursive: true });
  writeFileSync(agentCliSessionStatePath, JSON.stringify(store, null, 2));
}

function clampHistory(history: Array<{ role: "user" | "assistant"; content: string }>) {
  return history.slice(-MAX_HISTORY_MESSAGES);
}

  function normalizeModelCommand(input: string) {
  const trimmed = input.trim();
  const bySlash = trimmed.match(/^\/model\s+([^\s/]+)\/(.+)$/i);
  if (bySlash) {
    return {
      provider: bySlash[1].trim(),
      model: bySlash[2].trim()
    };
  }

  const bySpace = trimmed.match(/^\/model\s+([^\s]+)\s+(.+)$/i);
  if (bySpace) {
    return {
      provider: bySpace[1].trim(),
      model: bySpace[2].trim()
    };
  }

  return null;
}

function normalizeAgentCliModelCommand(input: string) {
  const trimmed = input.trim();
  const match = trimmed.match(/^\/model\s+(.+)$/i);
  if (!match) return null;
  return match[1].trim();
}

function normalizeAgentCliSessionCommand(input: string) {
  const trimmed = input.trim();
  const listMatch = trimmed.match(/^\/sessions?$/i);
  if (listMatch) {
    return { action: "list" as const };
  }

  const newMatch = trimmed.match(/^\/sessions?\s+(?:new|create)$/i);
  if (newMatch) {
    return { action: "new" as const };
  }

  const useMatch = trimmed.match(/^\/sessions?\s+(?:use|switch)\s+(.+)$/i);
  if (useMatch) {
    return { action: "use" as const, sessionId: useMatch[1].trim() };
  }

  const currentMatch = trimmed.match(/^\/sessions?\s+current$/i);
  if (currentMatch) {
    return { action: "current" as const };
  }

  const resetMatch = trimmed.match(/^\/sessions?\s+reset$/i);
  if (resetMatch) {
    return { action: "reset" as const };
  }

  return null;
}

function normalizeRestartCommand(input: string) {
  const trimmed = input.trim();
  const match = trimmed.match(/^\/restart(?:\s+(.+))?$/i);
  if (!match) return null;

  return {
    target: match[1]?.trim().toLowerCase() || "session"
  };
}

export async function startLocalAgent(initial?: Partial<LocalAgentConfig>) {
  const envServerBaseUrl = process.env.CHAT_SOFT_SERVER_BASE_URL?.trim();
  const envAgentCliPath = process.env.CHAT_SOFT_AGENT_CLI_PATH?.trim();
  const envAgentCliMappedAgent = process.env.CHAT_SOFT_AGENT_CLI_AGENT?.trim();
  const envAgentCliCwd = process.env.CHAT_SOFT_AGENT_CLI_CWD?.trim();
  let config: LocalAgentConfig = {
    serverBaseUrl: envServerBaseUrl || "http://39.106.125.149:3000",
    deviceId: "desktop-local-agent",
    deviceName: "Windows-PC",
    agentId: "desktop-helper",
    agentName: "桌面助手",
    agentDescription: "运行在 Windows 电脑侧的本地 agent 网关",
    agentCliPath: envAgentCliPath || "D:\\agent_workspace\\capability-library\\mycli\\mycli.ps1",
    agentCliMappedAgent: envAgentCliMappedAgent || "opencode/private-assistant",
    agentCliCwd: envAgentCliCwd || "D:\\agent_workspace",
    ...initial
  };
  const registeredAgents = new Map<string, RegisteredAgent>();
  const llmAgents = new Map<string, LlmAgentState>();
  let llmTimer: NodeJS.Timeout | null = null;
  const agentCliAgents = new Map<string, AgentCliAgentState>();
  const agentCliSessionStore = loadAgentCliSessionStore();
  let agentCliTimer: NodeJS.Timeout | null = null;

  function agentCliCommandCandidates() {
    const configured = config.agentCliPath.trim();
    const candidates = [configured];

    if (process.platform === "win32") {
      candidates.push("mycli");
      candidates.push("mycli.cmd");
    }

    return [...new Set(candidates.map((item) => item.trim()).filter(Boolean))];
  }

  function baseUrl() {
    return config.serverBaseUrl.replace(/\/$/, "");
  }

  function guessMimeType(filePath: string, fallbackKind: "audio" | "image" | "video" | "file") {
    const ext = extname(filePath).toLowerCase();
    const known: Record<string, string> = {
      ".png": "image/png",
      ".jpg": "image/jpeg",
      ".jpeg": "image/jpeg",
      ".gif": "image/gif",
      ".webp": "image/webp",
      ".bmp": "image/bmp",
      ".mp4": "video/mp4",
      ".mov": "video/quicktime",
      ".webm": "video/webm",
      ".mkv": "video/x-matroska",
      ".mp3": "audio/mpeg",
      ".wav": "audio/wav",
      ".ogg": "audio/ogg",
      ".m4a": "audio/mp4",
      ".aac": "audio/aac",
      ".pdf": "application/pdf",
      ".txt": "text/plain",
      ".json": "application/json",
      ".zip": "application/zip"
    };
    if (known[ext]) return known[ext];
    if (fallbackKind === "image") return "image/*";
    if (fallbackKind === "video") return "video/*";
    if (fallbackKind === "audio") return "audio/*";
    return "application/octet-stream";
  }

  async function uploadAttachment(body: AgentAttachmentBody, kind: "audio" | "image" | "video" | "file") {
    const fileName = body.fileName ?? basename(body.filePath);
    const mimeType = body.mimeType ?? guessMimeType(body.filePath, kind);
    const fileBuffer = await readFile(body.filePath);
    const file = new File([fileBuffer], fileName, { type: mimeType });
    const form = new FormData();
    form.append("file", file, fileName);
    form.append("kind", kind);
    const response = await fetch(`${baseUrl()}/api/upload/attachment`, {
      method: "POST",
      body: form
    });
    const payload = (await response.json()) as {
      mediaUrl: string;
      mimeType: string;
      fileName: string;
      fileSize: number;
    };
    return {
      ...payload,
      durationMs: body.durationMs,
      thumbnailUrl: body.thumbnailUrl
    };
  }

  function defaultAgentFromConfig(): RegisteredAgent {
    return {
      agentId: config.agentId,
      name: config.agentName,
      description: config.agentDescription,
      agentDeviceId: config.deviceId,
      conversationId: `agent:${config.agentId}`
    };
  }

  function ensureRegisteredAgent(agentId: string) {
    const existing = registeredAgents.get(agentId);
    if (existing) return existing;
    if (agentId === config.agentId) {
      const fallback = defaultAgentFromConfig();
      registeredAgents.set(agentId, fallback);
      return fallback;
    }
    return null;
  }

  async function fetchConversationMessages(conversationId: string) {
    const response = await fetch(`${baseUrl()}/api/conversations/${encodeURIComponent(conversationId)}/messages`);
    const payload = (await response.json()) as { messages: ServerMessage[] };
    return payload.messages;
  }

  async function sendAgentText(agent: RegisteredAgent, text: string) {
    const response = await fetch(`${baseUrl()}/api/messages/text`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        deviceId: agent.agentDeviceId,
        conversationId: agent.conversationId,
        text
      })
    });
    return response.json();
  }

  async function registerRemoteAgent(input: {
    agentId: string;
    name: string;
    description: string;
    agentDeviceId: string;
  }) {
    const localAgentInfo: RegisteredAgent = {
      agentId: input.agentId,
      name: input.name,
      description: input.description,
      agentDeviceId: input.agentDeviceId,
      conversationId: `agent:${input.agentId}`
    };

    const response = await fetch(`${baseUrl()}/api/agents/register`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        agentId: localAgentInfo.agentId,
        name: localAgentInfo.name,
        description: localAgentInfo.description,
        transport: "desktop-local",
        agentDeviceId: localAgentInfo.agentDeviceId
      })
    });
    const payload = (await response.json()) as {
      ok: boolean;
      agent: {
        agentId: string;
        name: string;
        description: string;
        conversationId: string;
        registeredAt: string;
        status: string;
      };
    };
    const registered: RegisteredAgent = {
      ...localAgentInfo,
      conversationId: payload.agent.conversationId,
      registeredAt: payload.agent.registeredAt,
      status: payload.agent.status
    };
    registeredAgents.set(localAgentInfo.agentId, registered);
    return { payload, registered };
  }

  function extractAgentCliSessionId(stdout: string) {
    const lines = stdout
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    for (const line of lines) {
      const textMatch = line.match(/^sessionID:\s*(.+)$/i);
      if (textMatch?.[1]?.trim()) {
        return textMatch[1].trim();
      }
      try {
        const parsed = JSON.parse(line) as { sessionID?: string };
        if (typeof parsed.sessionID === "string" && parsed.sessionID.trim()) {
          return parsed.sessionID.trim();
        }
      } catch {
        // ignore non-json lines
      }
    }
    return undefined;
  }

  function parseAgentCliText(stdout: string) {
    const lines = stdout
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    const texts: string[] = [];
    for (const line of lines) {
      try {
        const parsed = JSON.parse(line) as { type?: string; part?: { type?: string; text?: string } };
        if (parsed.type === "text" && parsed.part?.type === "text" && parsed.part.text?.trim()) {
          texts.push(parsed.part.text.trim());
        }
      } catch {
        // ignore non-json lines
      }
    }
    if (texts.length > 0) return texts.join("\n\n").trim();
    return lines.filter((line) => !/^sessionID:\s+/i.test(line) && !/^round:\s+/i.test(line)).join("\n").trim();
  }

  function runAgentCli(command: string, args: string[]) {
    return new Promise<AgentCliResult>((resolve, reject) => {
      const isPowerShellScript = process.platform === "win32" && /\.ps1$/i.test(command);
      const executable = isPowerShellScript ? "powershell.exe" : command;
      const executableArgs = isPowerShellScript ? ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", command, ...args] : args;
      const child = spawn(executable, executableArgs, {
        timeout: 10 * 60 * 1000,
        env: { ...process.env, PYTHONUTF8: "1" },
        stdio: ["ignore", "pipe", "pipe"],
        shell: process.platform === "win32" && !isPowerShellScript
      });
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (chunk) => {
        stdout += String(chunk);
      });
      child.stderr.on("data", (chunk) => {
        stderr += String(chunk);
      });
      child.on("error", reject);
      child.on("close", (code) => {
        resolve({
          ok: code === 0,
          stdout: stdout.trim(),
          stderr: stderr.trim(),
          exitCode: code,
          command,
          sessionId: extractAgentCliSessionId(stdout)
        });
      });
    });
  }

  async function invokeAgentCli(args: string[]) {
    let lastFailure: AgentCliResult | null = null;
    let lastError: unknown = null;
    for (const command of agentCliCommandCandidates()) {
      try {
        const result = await runAgentCli(command, args);
        if (result.ok) {
          return {
            text: parseAgentCliText(result.stdout) || result.stdout || "执行完成，无返回结果。",
            sessionId: result.sessionId
          };
        }
        lastFailure = result;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastFailure) {
      throw new Error(lastFailure.stderr || `${lastFailure.command} exited with code ${lastFailure.exitCode}`);
    }
    throw new Error(String(lastError ?? "agent-cli not available"));
  }

  async function listAgentCliSessionEvents(sessionId: string) {
    const result = await invokeAgentCli(["agent-cli", "session", "events", "--session", sessionId, "--last", "3"]);
    return result.text;
  }

  async function listAgentCliAgents() {
    const result = await invokeAgentCli(["agent-cli", "agents"]);
    return result.text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  }

  function getSessionIdForConversation(state: AgentCliAgentState) {
    return state.sessionIdsByConversationId.get(state.agent.conversationId);
  }

  function setSessionIdForConversation(state: AgentCliAgentState, sessionId: string | undefined) {
    if (!agentCliSessionStore[state.agent.agentId]) {
      agentCliSessionStore[state.agent.agentId] = {};
    }
    if (sessionId?.trim()) {
      state.sessionIdsByConversationId.set(state.agent.conversationId, sessionId.trim());
      agentCliSessionStore[state.agent.agentId][state.agent.conversationId] = sessionId.trim();
    } else {
      state.sessionIdsByConversationId.delete(state.agent.conversationId);
      delete agentCliSessionStore[state.agent.agentId][state.agent.conversationId];
    }
    saveAgentCliSessionStore(agentCliSessionStore);
  }

  async function listOpenCodeSessions() {
    const result = await invokeAgentCli(["opencode", "native", "session", "list"]);
    const lines = result.text
      .split(/\r?\n/)
      .map((line) => line.trimEnd())
      .filter(Boolean)
      .filter((line) => !/^Session ID\s+/i.test(line))
      .filter((line) => !/^─+$/u.test(line));
    const sessions: OpenCodeSessionSummary[] = [];
    for (const line of lines) {
      const match = line.match(/^(ses_[^\s]+)\s{2,}(.+?)\s{2,}([^\s]+)$/);
      if (!match) continue;
      sessions.push({
        sessionId: match[1],
        title: match[2].trim(),
        updatedAt: match[3].trim()
      });
    }
    return sessions;
  }

  async function listOpenCodeModels() {
    const result = await invokeAgentCli(["opencode", "native", "models"]);
    return result.text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
  }

  async function listOpenCodeProviders() {
    const result = await invokeAgentCli(["opencode", "native", "providers", "list"]);
    return result.text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .filter((line) => line.startsWith("•") || line.startsWith("-") || line.startsWith("*") || /api$/i.test(line));
  }

  async function handleAgentCliTextCommand(state: AgentCliAgentState, text: string) {
    const trimmed = text.trim();

    if (/^\/help$/i.test(trimmed)) {
      await sendAgentText(
        state.agent,
        [
          "可用指令：",
          "/help",
          "/agents",
          "/providers",
          "/models",
          "/model provider/model",
          "/session",
          "/session current",
          "/session use <SESSION_ID>",
          "/session new",
          "/session reset",
          "/session events",
          "/restart"
        ].join("\n")
      );
      return true;
    }

    const restartCommand = normalizeRestartCommand(trimmed);
    if (restartCommand) {
      if (!["session", "context", "opencode", "private-assistant"].includes(restartCommand.target)) {
        await sendAgentText(state.agent, "用法：/restart\n等价于 /session reset：清空当前 Chat Soft 会话绑定的 opencode session，下一条普通消息会启动新 session。");
        return true;
      }

      setSessionIdForConversation(state, undefined);
      state.lastError = undefined;
      await sendAgentText(
        state.agent,
        "已重启 private-assistant 会话：当前 Chat Soft 会话的 opencode session 绑定已清空。下一条普通消息会创建新 session，并继续通过 mycli agent-cli 调用 opencode/private-assistant。"
      );
      return true;
    }

    if (/^\/agents$/i.test(trimmed)) {
      const agents = await listAgentCliAgents();
      await sendAgentText(state.agent, `agent-cli 可用 agents：\n${agents.join("\n") || "未找到 agent"}`);
      return true;
    }

    if (/^\/providers$/i.test(trimmed)) {
      const providers = await listOpenCodeProviders();
      await sendAgentText(state.agent, `可用 providers：\n${providers.join("\n") || "未找到 provider"}`);
      return true;
    }

    if (/^\/models$/i.test(trimmed)) {
      const models = await listOpenCodeModels();
      const lines = models.map((model) => `${model}${state.model === model ? "  *当前" : ""}`);
      await sendAgentText(state.agent, `可用模型：\n${lines.join("\n") || "未找到模型"}`);
      return true;
    }

    const modelCommand = normalizeAgentCliModelCommand(trimmed);
    if (modelCommand) {
      state.model = modelCommand;
      const currentSessionId = getSessionIdForConversation(state);
      await sendAgentText(state.agent, `已切换模型：${state.model}\n后续消息将继续使用当前 Chat Soft 会话绑定的 session${currentSessionId ? ` (${currentSessionId})` : ""}。`);
      return true;
    }

    const sessionCommand = normalizeAgentCliSessionCommand(trimmed);
    if (sessionCommand?.action === "list") {
      const currentSessionId = getSessionIdForConversation(state);
      const sessions = await listOpenCodeSessions();
      const lines = sessions.map((session) => {
        const current = session.sessionId === currentSessionId ? "  *当前" : "";
        return `- ${session.sessionId} | ${session.title} | ${session.updatedAt}${current}`;
      });
      await sendAgentText(state.agent, `可用会话：\n${lines.join("\n") || "暂无会话"}`);
      return true;
    }

    if (sessionCommand?.action === "current") {
      const currentSessionId = getSessionIdForConversation(state);
      await sendAgentText(
        state.agent,
        currentSessionId
          ? `当前 Chat Soft 会话：${state.agent.conversationId}\n当前 session：${currentSessionId}\n当前模型：${state.model ?? "默认"}`
          : `当前 Chat Soft 会话：${state.agent.conversationId}\n当前还没有绑定 session。下一条普通消息会自动创建并沿用。`
      );
      return true;
    }

    if (sessionCommand?.action === "use") {
      setSessionIdForConversation(state, sessionCommand.sessionId);
      await sendAgentText(state.agent, `已将当前 Chat Soft 会话绑定到 session：${sessionCommand.sessionId}`);
      return true;
    }

    if (sessionCommand?.action === "new") {
      setSessionIdForConversation(state, undefined);
      await sendAgentText(state.agent, "已为当前 Chat Soft 会话开启新 session：下一条普通消息会创建新 session，并在之后自动沿用。也可以直接发送任务内容开始新 session。");
      return true;
    }

    if (sessionCommand?.action === "reset") {
      setSessionIdForConversation(state, undefined);
      await sendAgentText(state.agent, "已清空当前 Chat Soft 会话的 session 绑定。下一条普通消息会创建新 session。其他 Chat Soft 会话不受影响。");
      return true;
    }

    if (/^\/sessions?\s+events$/i.test(trimmed)) {
      const currentSessionId = getSessionIdForConversation(state);
      if (!currentSessionId) {
        await sendAgentText(state.agent, "当前还没有绑定 session。");
      } else {
        await sendAgentText(state.agent, await listAgentCliSessionEvents(currentSessionId));
      }
      return true;
    }

    return false;
  }

  function listLlmModels() {
    if (!existsSync(llmConfigPath)) {
      throw new Error(`LLM config not found: ${llmConfigPath}`);
    }
    const raw = JSON.parse(readFileSync(llmConfigPath, "utf8")) as {
      models?: {
        providers?: Record<
          string,
          {
            models?: Array<string | { id?: string; name?: string }>;
          }
        >;
      };
    };
    const providers = raw.models?.providers ?? {};
    const entries: LlmCatalogEntry[] = [];
    for (const [provider, providerConfig] of Object.entries(providers)) {
      const models = Array.isArray(providerConfig?.models) ? providerConfig.models : [];
      for (const model of models) {
        const modelId =
          typeof model === "string" ? model.trim() : typeof model?.id === "string" ? model.id.trim() : "";
        if (modelId) {
          entries.push({
            provider,
            model: modelId
          });
        }
      }
    }
    return entries;
  }

  function ensureLlmModel(provider: string, model: string) {
    const models = listLlmModels();
    const hit = models.find((item) => item.provider === provider && item.model === model);
    if (!hit) {
      throw new Error(`Unknown model selection: ${provider}/${model}`);
    }
    return hit;
  }

  function defaultLlmModel() {
    const models = listLlmModels();
    const first = models[0];
    if (!first) {
      throw new Error("No models found in mult_agent/config/llm.json");
    }
    return first;
  }

  function callPythonWorker<T>(payload: object) {
    return new Promise<T>((resolvePromise, reject) => {
      const child = spawn("python", [llmWorkerPath], {
        cwd: desktopRoot,
        stdio: ["pipe", "pipe", "pipe"],
        env: {
          ...process.env,
          PYTHONUTF8: "1"
        }
      });

      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (chunk) => {
        stdout += String(chunk);
      });
      child.stderr.on("data", (chunk) => {
        stderr += String(chunk);
      });
      child.on("error", (error) => {
        reject(error);
      });
      child.on("close", (code) => {
        if (code !== 0) {
          reject(new Error(stderr.trim() || `python worker exited with code ${code}`));
          return;
        }
        try {
          resolvePromise(JSON.parse(stdout) as T);
        } catch (error) {
          reject(new Error(`Failed to parse python worker output: ${String(error)}\n${stdout}`));
        }
      });

      child.stdin.write(JSON.stringify(payload));
      child.stdin.end();
    });
  }

  async function invokeLlmChat(state: LlmAgentState, userText: string) {
    const response = await callPythonWorker<WorkerChatResult>({
      action: "chat",
      configPath: llmConfigPath,
      llmSourceDir,
      provider: state.provider,
      model: state.model,
      temperature: state.temperature,
      maxTokens: state.maxTokens,
      messages: [
        { role: "system", content: state.systemPrompt },
        ...state.history,
        { role: "user", content: userText }
      ]
    });
    if (!response.ok || !response.content?.trim()) {
      throw new Error(response.error || "LLM returned empty response");
    }
    return response.content.trim();
  }

  async function bootstrapProcessedMessages(agent: RegisteredAgent) {
    const messages = await fetchConversationMessages(agent.conversationId);
    return new Set(messages.map((message) => message.id));
  }

  async function registerLlmAgent(input?: {
    agentId?: string;
    name?: string;
    description?: string;
    provider?: string;
    model?: string;
    systemPrompt?: string;
    temperature?: number;
    maxTokens?: number;
  }) {
    const defaultSelection = defaultLlmModel();
    const provider = input?.provider ?? defaultSelection.provider;
    const model = input?.model ?? defaultSelection.model;
    ensureLlmModel(provider, model);

    const agentId = input?.agentId?.trim() || "llm-chat";
    const name = input?.name?.trim() || "LLM Chat";
    const description =
      input?.description?.trim() || `基于 ${provider}/${model} 的纯 LLM 对话 agent，可在会话中切换模型`;
    const { payload, registered } = await registerRemoteAgent({
      agentId,
      name,
      description,
      agentDeviceId: `${config.deviceId}:llm:${agentId}`
    });

    const state: LlmAgentState = {
      agent: registered,
      provider,
      model,
      systemPrompt: input?.systemPrompt?.trim() || DEFAULT_LLM_SYSTEM_PROMPT,
      temperature: input?.temperature ?? 1,
      maxTokens: input?.maxTokens ?? 1024,
      history: [],
      processedMessageIds: await bootstrapProcessedMessages(registered),
      running: false
    };
    llmAgents.set(agentId, state);
    return {
      ok: true,
      agent: payload.agent,
      llm: {
        provider,
        model,
        systemPrompt: state.systemPrompt,
        temperature: state.temperature,
        maxTokens: state.maxTokens
      }
    };
  }

  async function registerAgentCliAgent(input?: {
    agentId?: string;
    name?: string;
    description?: string;
    systemPrompt?: string;
  }) {
    const agentId = input?.agentId?.trim() || "private-assistant";
    const name = input?.name?.trim() || "Private Assistant";
    const description =
      input?.description?.trim() || "运行在本地电脑的 private-assistant，通过 agent-cli 接入，支持代码编辑、命令执行、项目构建等能力";
    const { payload, registered } = await registerRemoteAgent({
      agentId,
      name,
      description,
      agentDeviceId: `${config.deviceId}:agent-cli:${agentId}`
    });

    const state: AgentCliAgentState = {
      agent: registered,
      systemPrompt: input?.systemPrompt?.trim() || DEFAULT_AGENT_CLI_SYSTEM_PROMPT,
      sessionIdsByConversationId: new Map(Object.entries(agentCliSessionStore[agentId] ?? {})),
      model: undefined,
      processedMessageIds: await bootstrapProcessedMessages(registered),
      running: false
    };
    agentCliAgents.set(agentId, state);
    return {
      ok: true,
      agent: payload.agent,
      systemPrompt: state.systemPrompt
    };
  }

  async function processAgentCliAgent(state: AgentCliAgentState) {
    const messages = await fetchConversationMessages(state.agent.conversationId);
    for (const message of messages) {
      if (state.processedMessageIds.has(message.id)) continue;
      if (message.senderDeviceId === state.agent.agentDeviceId) {
        state.processedMessageIds.add(message.id);
        continue;
      }

      state.processedMessageIds.add(message.id);
      if (message.kind !== "text") {
        await sendAgentText(state.agent, "当前 private-assistant agent 先只处理文本指令。");
        continue;
      }

      const text = message.text?.trim() || "";
      if (!text) continue;

      try {
        if (await handleAgentCliTextCommand(state, text)) {
          state.lastError = undefined;
          continue;
        }

        const args = ["agent-cli", "run", "--agent", config.agentCliMappedAgent, "--prompt", text, "--cwd", config.agentCliCwd, "--return_mode", "silent"];
        const currentSessionId = getSessionIdForConversation(state);
        if (currentSessionId) {
          args.push("--session", currentSessionId);
        }
        if (state.model) {
          args.push("--model", state.model);
        }

        const answer = await invokeAgentCli(args);
        if (answer.sessionId) {
          setSessionIdForConversation(state, answer.sessionId);
        }
        const nextSessionId = getSessionIdForConversation(state);
        state.lastError = undefined;
        await sendAgentText(
          state.agent,
          `${answer.text}${nextSessionId ? `\n\n[session: ${nextSessionId}]` : ""}${state.model ? `\n[model: ${state.model}]` : ""}`
        );
      } catch (error) {
        state.lastError = String(error);
        await sendAgentText(
          state.agent,
          `private-assistant 执行失败：${state.lastError}\n请确认 mycli agent-cli 可用，并且 ${config.agentCliMappedAgent} 已同步注册。`
        );
      }
    }
  }

  async function tickAgentCliAgents() {
    for (const state of agentCliAgents.values()) {
      if (state.running) continue;
      state.running = true;
      try {
        await processAgentCliAgent(state);
      } finally {
        state.running = false;
      }
    }
  }

  function startAgentCliLoop() {
    if (agentCliTimer) clearInterval(agentCliTimer);
    agentCliTimer = setInterval(() => {
      void tickAgentCliAgents().catch((error) => {
        console.error("[local-agent] agent-cli loop failed", error);
      });
    }, AGENT_CLI_POLL_INTERVAL_MS);
  }

  async function handleLlmTextCommand(state: LlmAgentState, text: string) {
    const trimmed = text.trim();
    if (/^\/models$/i.test(trimmed)) {
      const models = listLlmModels();
      const lines = models.map((item) => {
        const current = item.provider === state.provider && item.model === state.model ? " *当前" : "";
        return `- ${item.provider}/${item.model}${current}`;
      });
      await sendAgentText(state.agent, `可用模型：\n${lines.join("\n")}`);
      return true;
    }

    if (/^\/reset$/i.test(trimmed)) {
      state.history = [];
      state.lastError = undefined;
      await sendAgentText(state.agent, "上下文已清空，我们可以重新开始。");
      return true;
    }

    const modelCommand = normalizeModelCommand(trimmed);
    if (modelCommand) {
      ensureLlmModel(modelCommand.provider, modelCommand.model);
      state.provider = modelCommand.provider;
      state.model = modelCommand.model;
      state.history = [];
      state.lastError = undefined;
      await sendAgentText(state.agent, `已切换到模型：${state.provider}/${state.model}\n上下文已重置。`);
      return true;
    }

    return false;
  }

  async function processLlmAgent(state: LlmAgentState) {
    const messages = await fetchConversationMessages(state.agent.conversationId);
    for (const message of messages) {
      if (state.processedMessageIds.has(message.id)) continue;
      if (message.senderDeviceId === state.agent.agentDeviceId) {
        state.processedMessageIds.add(message.id);
        continue;
      }

      state.processedMessageIds.add(message.id);
      if (message.kind !== "text") {
        await sendAgentText(state.agent, "当前这个 LLM agent 先只处理文本消息。");
        continue;
      }

      const text = message.text?.trim() || "";
      if (!text) continue;
      if (await handleLlmTextCommand(state, text)) {
        continue;
      }

      try {
        const answer = await invokeLlmChat(state, text);
        state.history = clampHistory([...state.history, { role: "user", content: text }, { role: "assistant", content: answer }]);
        state.lastError = undefined;
        await sendAgentText(state.agent, answer);
      } catch (error) {
        state.lastError = String(error);
        await sendAgentText(state.agent, `LLM 调用失败：${state.lastError}`);
      }
    }
  }

  async function tickLlmAgents() {
    for (const state of llmAgents.values()) {
      if (state.running) continue;
      state.running = true;
      try {
        await processLlmAgent(state);
      } finally {
        state.running = false;
      }
    }
  }

  function startLlmLoop() {
    if (llmTimer) clearInterval(llmTimer);
    llmTimer = setInterval(() => {
      void tickLlmAgents().catch((error) => {
        console.error("[local-agent] llm loop failed", error);
      });
    }, LLM_POLL_INTERVAL_MS);
  }

  const localAgent = Fastify({ logger: false });
  localAgent.get("/health", async () => ({ ok: true }));
  localAgent.get("/api/v1/config", async () => config);
  localAgent.post<{ Body: Partial<LocalAgentConfig> }>("/api/v1/config", async (request) => {
    config = { ...config, ...request.body };
    return { ok: true, config };
  });
  localAgent.get("/api/v1/local-agents", async () => {
    return {
      agents: [...registeredAgents.values()]
    };
  });
  localAgent.get("/api/v1/agents", async () => {
    const response = await fetch(`${baseUrl()}/api/agents`);
    return response.json();
  });
  localAgent.post<{
    Body: {
      agentId?: string;
      name?: string;
      description?: string;
      agentDeviceId?: string;
    };
  }>("/api/v1/agents/register", async (request) => {
    return registerRemoteAgent({
      agentId: request.body?.agentId ?? config.agentId,
      name: request.body?.name ?? config.agentName,
      description: request.body?.description ?? config.agentDescription,
      agentDeviceId: request.body?.agentDeviceId ?? `${config.deviceId}:${request.body?.agentId ?? config.agentId}`
    }).then(({ payload }) => payload);
  });
  localAgent.get("/api/v1/llm/models", async () => {
    const models = await callPythonWorker<WorkerListModelsResult>({
      action: "list_models",
      configPath: llmConfigPath,
      llmSourceDir
    });
    if (!models.ok) {
      throw new Error(models.error || "Failed to list LLM models");
    }
    return {
      models: models.models ?? []
    };
  });
  localAgent.get("/api/v1/llm-agents", async () => {
    return {
      agents: [...llmAgents.values()].map((state) => ({
        agentId: state.agent.agentId,
        name: state.agent.name,
        conversationId: state.agent.conversationId,
        provider: state.provider,
        model: state.model,
        systemPrompt: state.systemPrompt,
        temperature: state.temperature,
        maxTokens: state.maxTokens,
        lastError: state.lastError ?? null
      }))
    };
  });
  localAgent.post<{
    Body: {
      agentId?: string;
      name?: string;
      description?: string;
      provider?: string;
      model?: string;
      systemPrompt?: string;
      temperature?: number;
      maxTokens?: number;
    };
  }>("/api/v1/llm-agents/register", async (request) => {
    return registerLlmAgent(request.body);
  });
  localAgent.get<{ Params: { agentId: string } }>("/api/v1/llm-agents/:agentId", async (request, reply) => {
    const state = llmAgents.get(request.params.agentId);
    if (!state) {
      return reply.code(404).send({ message: "llm agent not registered locally" });
    }
    return {
      agentId: state.agent.agentId,
      name: state.agent.name,
      conversationId: state.agent.conversationId,
      provider: state.provider,
      model: state.model,
      systemPrompt: state.systemPrompt,
      temperature: state.temperature,
      maxTokens: state.maxTokens,
      lastError: state.lastError ?? null
    };
  });
  localAgent.post<{
    Params: { agentId: string };
    Body: { provider: string; model: string; resetHistory?: boolean };
  }>("/api/v1/llm-agents/:agentId/model", async (request, reply) => {
    const state = llmAgents.get(request.params.agentId);
    if (!state) {
      return reply.code(404).send({ message: "llm agent not registered locally" });
    }
    ensureLlmModel(request.body.provider, request.body.model);
    state.provider = request.body.provider;
    state.model = request.body.model;
    if (request.body.resetHistory ?? true) {
      state.history = [];
    }
    state.lastError = undefined;
    return {
      ok: true,
      agentId: state.agent.agentId,
      provider: state.provider,
      model: state.model,
      historyReset: request.body.resetHistory ?? true
    };
  });
  localAgent.post<{ Params: { agentId: string } }>("/api/v1/llm-agents/:agentId/reset", async (request, reply) => {
    const state = llmAgents.get(request.params.agentId);
    if (!state) {
      return reply.code(404).send({ message: "llm agent not registered locally" });
    }
    state.history = [];
    state.lastError = undefined;
    return { ok: true };
  });

  // Agent CLI / private-assistant 接口
  localAgent.get("/api/v1/opencode-agents", async () => {
    return {
      agents: [...agentCliAgents.values()].map((state) => ({
        agentId: state.agent.agentId,
        name: state.agent.name,
        conversationId: state.agent.conversationId,
        systemPrompt: state.systemPrompt,
        sessionId: getSessionIdForConversation(state) ?? null,
        sessionIdsByConversationId: Object.fromEntries(state.sessionIdsByConversationId),
        model: state.model ?? null,
        lastError: state.lastError ?? null
      }))
    };
  });

  localAgent.post<{
    Body: {
      agentId?: string;
      name?: string;
      description?: string;
      systemPrompt?: string;
    };
  }>("/api/v1/opencode-agents/register", async (request) => {
    return registerAgentCliAgent(request.body);
  });

  localAgent.get<{ Params: { agentId: string } }>("/api/v1/opencode-agents/:agentId", async (request, reply) => {
    const state = agentCliAgents.get(request.params.agentId);
    if (!state) {
      return reply.code(404).send({ message: "agent-cli agent not registered locally" });
    }
    return {
      agentId: state.agent.agentId,
      name: state.agent.name,
      conversationId: state.agent.conversationId,
      systemPrompt: state.systemPrompt,
      sessionId: getSessionIdForConversation(state) ?? null,
      sessionIdsByConversationId: Object.fromEntries(state.sessionIdsByConversationId),
      model: state.model ?? null,
      lastError: state.lastError ?? null
    };
  });
  localAgent.get<{ Params: { agentId: string } }>("/api/v1/agents/:agentId", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    return { agent };
  });
  localAgent.get<{ Params: { agentId: string } }>("/api/v1/agents/:agentId/messages", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const response = await fetch(`${baseUrl()}/api/conversations/${encodeURIComponent(agent.conversationId)}/messages`);
    return response.json();
  });
  localAgent.get<{
    Params: { agentId: string };
    Querystring: { since?: string; limit?: string };
  }>("/api/v1/agents/:agentId/inbox", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const response = await fetch(`${baseUrl()}/api/conversations/${encodeURIComponent(agent.conversationId)}/messages`);
    const payload = (await response.json()) as { messages: ServerMessage[] };
    const since = request.query.since ? new Date(request.query.since).toISOString() : "";
    const limit = Number(request.query.limit ?? "50");
    const messages = payload.messages
      .filter((message) => message.senderDeviceId !== agent.agentDeviceId)
      .filter((message) => (since ? message.createdAt > since : true))
      .slice(-limit);
    return {
      agent,
      messages
    };
  });
  localAgent.post<{
    Params: { agentId: string };
    Body: { text: string };
  }>("/api/v1/agents/:agentId/messages/text", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const response = await fetch(`${baseUrl()}/api/messages/text`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        deviceId: agent.agentDeviceId,
        conversationId: agent.conversationId,
        text: request.body.text
      })
    });
    return response.json();
  });
  localAgent.post<{
    Params: { agentId: string };
    Body: AgentAttachmentBody;
  }>("/api/v1/agents/:agentId/messages/audio", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const uploaded = await uploadAttachment(request.body, "audio");
    const response = await fetch(`${baseUrl()}/api/messages/attachment`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceId: agent.agentDeviceId,
        conversationId: agent.conversationId,
        kind: "audio",
        ...uploaded
      })
    });
    return response.json();
  });
  localAgent.post<{
    Params: { agentId: string };
    Body: AgentAttachmentBody;
  }>("/api/v1/agents/:agentId/messages/image", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const uploaded = await uploadAttachment(request.body, "image");
    const response = await fetch(`${baseUrl()}/api/messages/attachment`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceId: agent.agentDeviceId,
        conversationId: agent.conversationId,
        kind: "image",
        ...uploaded
      })
    });
    return response.json();
  });
  localAgent.post<{
    Params: { agentId: string };
    Body: AgentAttachmentBody;
  }>("/api/v1/agents/:agentId/messages/video", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const uploaded = await uploadAttachment(request.body, "video");
    const response = await fetch(`${baseUrl()}/api/messages/attachment`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceId: agent.agentDeviceId,
        conversationId: agent.conversationId,
        kind: "video",
        ...uploaded
      })
    });
    return response.json();
  });
  localAgent.post<{
    Params: { agentId: string };
    Body: AgentAttachmentBody;
  }>("/api/v1/agents/:agentId/messages/file", async (request, reply) => {
    const agent = ensureRegisteredAgent(request.params.agentId);
    if (!agent) {
      return reply.code(404).send({ message: "agent not registered locally" });
    }
    const uploaded = await uploadAttachment(request.body, "file");
    const response = await fetch(`${baseUrl()}/api/messages/attachment`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceId: agent.agentDeviceId,
        conversationId: agent.conversationId,
        kind: "file",
        ...uploaded
      })
    });
    return response.json();
  });
  localAgent.get("/api/v1/conversations", async () => {
    const response = await fetch(`${baseUrl()}/api/conversations`);
    return response.json();
  });
  localAgent.get<{ Params: { conversationId: string } }>("/api/v1/conversations/:conversationId/messages", async (request) => {
    const response = await fetch(
      `${baseUrl()}/api/conversations/${encodeURIComponent(request.params.conversationId)}/messages`
    );
    return response.json();
  });
  localAgent.get("/api/v1/messages/recent", async () => {
    const response = await fetch(`${baseUrl()}/api/messages/recent`);
    return response.json();
  });
  localAgent.post<{ Body: { conversationId?: string; text: string } }>("/api/v1/messages/text", async (request) => {
    const response = await fetch(`${baseUrl()}/api/messages/text`, {
      method: "POST",
      headers: {
        "content-type": "application/json"
      },
      body: JSON.stringify({
        deviceId: config.deviceId,
        conversationId: request.body.conversationId,
        text: request.body.text
      })
    });
    return response.json();
  });

  await localAgent.listen({ host: "127.0.0.1", port: LOCAL_AGENT_PORT });
  startLlmLoop();
  // 自动注册 private-assistant agent
  await registerAgentCliAgent().catch(console.error);
  await registerAgentCliAgent({
    agentId: "private-assistant-2",
    name: "Private Assistant 2",
    description: "备用 private-assistant，通过 agent-cli 接入；当主助手异常时可用于修复或接管任务。"
  }).catch(console.error);
  startAgentCliLoop();
  return localAgent;
}
