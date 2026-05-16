from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class LLMToolDefinition:
    name: str
    description: str
    parameters: Dict[str, Any]


@dataclass
class LLMToolCall:
    id: str
    name: str
    arguments: Dict[str, Any] = field(default_factory=dict)


@dataclass
class LLMMessage:
    role: str
    content: str
    name: str = ""
    tool_call_id: str = ""
    tool_calls: List[LLMToolCall] = field(default_factory=list)


@dataclass
class LLMRequest:
    provider: str
    model: str
    messages: List[LLMMessage]
    tools: List[LLMToolDefinition] = field(default_factory=list)
    tool_choice: str = "auto"
    temperature: float = 0.0
    max_tokens: int = 2048
    extra_params: Dict[str, Any] = field(default_factory=dict)


@dataclass
class LLMUsage:
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0


@dataclass
class LLMResponse:
    ok: bool
    provider: str
    model: str
    message: LLMMessage
    finish_reason: str = ""
    usage: LLMUsage = field(default_factory=LLMUsage)
    raw_response: Dict[str, Any] = field(default_factory=dict)
    error: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "provider": self.provider,
            "model": self.model,
            "message": {
                "role": self.message.role,
                "content": self.message.content,
                "name": self.message.name,
                "tool_call_id": self.message.tool_call_id,
                "tool_calls": [asdict(item) for item in self.message.tool_calls],
            },
            "finish_reason": self.finish_reason,
            "usage": asdict(self.usage),
            "raw_response": self.raw_response,
            "error": self.error,
        }


class LLMError(RuntimeError):
    """LLM 调用异常。"""


class BaseLLMProvider:
    provider_name: str = ""

    def call(self, request: LLMRequest) -> LLMResponse:
        raise NotImplementedError


class MockLLMProvider(BaseLLMProvider):
    provider_name = "mock"

    def call(self, request: LLMRequest) -> LLMResponse:
        last_user_message = self._find_last_message(request.messages, role="user")
        content = last_user_message.content if last_user_message else ""
        system_message = self._find_last_message(request.messages, role="system")
        system_content = system_message.content if system_message else ""
        last_tool_message = self._find_last_message(request.messages, role="tool")

        if last_tool_message is not None:
            tool_follow_up = self._maybe_finish_after_tool(request, last_tool_message)
            if tool_follow_up is not None:
                return tool_follow_up

        bus_tool_response = self._maybe_handle_bus_tools(request, system_content, content)
        if bus_tool_response is not None:
            return bus_tool_response

        if request.tools and "[call_tool:" in content:
            tool_name = content.split("[call_tool:", 1)[1].split("]", 1)[0].strip()
            tool_call = LLMToolCall(
                id="mock-tool-call-1",
                name=tool_name,
                arguments={"mock": True, "source": "mock-provider"},
            )
            message = LLMMessage(role="assistant", content="", tool_calls=[tool_call])
            return LLMResponse(
                ok=True,
                provider=request.provider,
                model=request.model,
                message=message,
                finish_reason="tool_calls",
                usage=self._mock_usage(request),
                raw_response={"mock": True, "mode": "tool_call"},
            )

        assistant_text = f"[mock:{request.model}] {content}".strip()
        message = LLMMessage(role="assistant", content=assistant_text)
        return LLMResponse(
            ok=True,
            provider=request.provider,
            model=request.model,
            message=message,
            finish_reason="stop",
            usage=self._mock_usage(request, completion_text=assistant_text),
            raw_response={"mock": True, "mode": "text"},
        )

    def _maybe_handle_bus_tools(
        self,
        request: LLMRequest,
        system_content: str,
        user_content: str,
    ) -> Optional[LLMResponse]:
        tool_names = {tool.name for tool in request.tools}
        current_message_type = self._extract_json_string(system_content, '"message_type": "')
        current_message_id = self._extract_json_string(system_content, '"message_id": "')
        target_agent = self._extract_agent_target(system_content)

        if "agent_send_task" in tool_names and current_message_type == "channel_message" and target_agent:
            tool_call = LLMToolCall(
                id="mock-tool-call-send-task",
                name="agent_send_task",
                arguments={
                    "to_agent": target_agent,
                    "text": "请分析当前 workflow 输入，并返回结构化摘要。",
                    "priority": "normal",
                    "payload": {"source": "mock-provider"},
                },
            )
            message = LLMMessage(role="assistant", content="", tool_calls=[tool_call])
            return LLMResponse(
                ok=True,
                provider=request.provider,
                model=request.model,
                message=message,
                finish_reason="tool_calls",
                usage=self._mock_usage(request),
                raw_response={"mock": True, "mode": "bus_send_task"},
            )

        if "agent_reply_task" in tool_names and current_message_type == "task_request" and current_message_id:
            tool_call = LLMToolCall(
                id="mock-tool-call-reply-task",
                name="agent_reply_task",
                arguments={
                    "text": "结构化分析已完成：workflow 输入、节点职责和交付边界已经梳理。",
                    "payload": {"source": "mock-provider", "reply_to": current_message_id},
                },
            )
            message = LLMMessage(role="assistant", content="", tool_calls=[tool_call])
            return LLMResponse(
                ok=True,
                provider=request.provider,
                model=request.model,
                message=message,
                finish_reason="tool_calls",
                usage=self._mock_usage(request),
                raw_response={"mock": True, "mode": "bus_reply_task"},
            )

        return None

    def _maybe_finish_after_tool(
        self,
        request: LLMRequest,
        last_tool_message: LLMMessage,
    ) -> Optional[LLMResponse]:
        follow_up_map = {
            "agent_send_task": "Delegation recorded. Waiting for the delegated agent to reply.",
            "agent_reply_task": "Reply sent successfully.",
            "agent_handoff_reply": "Reply ownership has been transferred.",
        }
        follow_up = follow_up_map.get(last_tool_message.name)
        if not follow_up:
            return None
        message = LLMMessage(role="assistant", content=f"[mock:{request.model}] {follow_up}")
        return LLMResponse(
            ok=True,
            provider=request.provider,
            model=request.model,
            message=message,
            finish_reason="stop",
            usage=self._mock_usage(request, completion_text=message.content),
            raw_response={"mock": True, "mode": "tool_follow_up"},
        )

    def _extract_json_string(self, text: str, marker: str) -> str:
        if marker not in text:
            return ""
        return text.split(marker, 1)[1].split('"', 1)[0].strip()

    def _extract_agent_target(self, text: str) -> str:
        for agent_id in ("agent_2", "agent_3", "agent_4"):
            if agent_id in text:
                return agent_id
        return ""

    def _find_last_message(self, messages: List[LLMMessage], role: str) -> Optional[LLMMessage]:
        for message in reversed(messages):
            if message.role == role:
                return message
        return None

    def _mock_usage(self, request: LLMRequest, completion_text: str = "") -> LLMUsage:
        prompt_chars = sum(len(message.content) for message in request.messages)
        completion_chars = len(completion_text)
        return LLMUsage(
            prompt_tokens=max(1, prompt_chars // 4),
            completion_tokens=max(1, completion_chars // 4) if completion_text else 0,
            total_tokens=max(1, prompt_chars // 4) + (max(1, completion_chars // 4) if completion_text else 0),
        )


class OpenAICompatibleProvider(BaseLLMProvider):
    provider_name = "openai_compatible"

    def __init__(
        self,
        api_base: str,
        api_key: str = "",
        api_key_env: str = "",
        default_headers: Optional[Dict[str, str]] = None,
    ) -> None:
        self.api_base = api_base.rstrip("/")
        self.api_key = api_key
        self.api_key_env = api_key_env
        self.default_headers = default_headers or {}

    def call(self, request: LLMRequest) -> LLMResponse:
        api_key = self.api_key or os.getenv(self.api_key_env, "")
        if not api_key:
            raise LLMError(
                f"provider `{request.provider}` missing API key; set config api_key or env `{self.api_key_env}`"
            )

        payload = self._build_payload(request)
        body = json.dumps(payload).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "OpenClaw/1.0 Python-urllib",
            "Authorization": f"Bearer {api_key}",
            **self.default_headers,
        }
        url = f"{self.api_base}/chat/completions"
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")

        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="ignore")
            raise LLMError(f"http {exc.code}: {error_body}") from exc
        except urllib.error.URLError as exc:
            raise LLMError(f"network error: {exc}") from exc

        try:
            payload_data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise LLMError(f"provider returned non-json payload: {raw[:200]}") from exc

        return self._normalize_response(request, payload_data)

    def _build_payload(self, request: LLMRequest) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "model": request.model,
            "messages": [self._message_to_payload(message) for message in request.messages],
            "temperature": request.temperature,
            "max_tokens": request.max_tokens,
        }
        if request.tools:
            payload["tools"] = [
                {
                    "type": "function",
                    "function": {
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters,
                    },
                }
                for tool in request.tools
            ]
            payload["tool_choice"] = request.tool_choice
        payload.update(request.extra_params)
        return payload

    def _message_to_payload(self, message: LLMMessage) -> Dict[str, Any]:
        content: Any = message.content
        if message.role == "user" and isinstance(content, str):
            content = [{"type": "text", "text": content}]

        payload: Dict[str, Any] = {"role": message.role, "content": content}
        if message.name:
            payload["name"] = message.name
        if message.tool_call_id:
            payload["tool_call_id"] = message.tool_call_id
        if message.tool_calls:
            payload["tool_calls"] = [
                {
                    "id": tool_call.id,
                    "type": "function",
                    "function": {
                        "name": tool_call.name,
                        "arguments": json.dumps(tool_call.arguments, ensure_ascii=False),
                    },
                }
                for tool_call in message.tool_calls
            ]
        return payload

    def _normalize_response(self, request: LLMRequest, payload: Dict[str, Any]) -> LLMResponse:
        choices = payload.get("choices") or []
        if not choices:
            raise LLMError("provider returned no choices")

        choice = choices[0]
        message_payload = choice.get("message") or {}
        tool_calls = []
        for item in message_payload.get("tool_calls") or []:
            function = item.get("function") or {}
            raw_arguments = function.get("arguments", "{}")
            try:
                arguments = json.loads(raw_arguments) if isinstance(raw_arguments, str) else raw_arguments
            except json.JSONDecodeError:
                arguments = {"raw": raw_arguments}
            tool_calls.append(
                LLMToolCall(
                    id=str(item.get("id", "")),
                    name=str(function.get("name", "")),
                    arguments=arguments if isinstance(arguments, dict) else {"value": arguments},
                )
            )

        message = LLMMessage(
            role=str(message_payload.get("role", "assistant")),
            content=str(message_payload.get("content") or ""),
            tool_calls=tool_calls,
        )
        usage_payload = payload.get("usage") or {}
        usage = LLMUsage(
            prompt_tokens=int(usage_payload.get("prompt_tokens", 0) or 0),
            completion_tokens=int(usage_payload.get("completion_tokens", 0) or 0),
            total_tokens=int(usage_payload.get("total_tokens", 0) or 0),
        )
        return LLMResponse(
            ok=True,
            provider=request.provider,
            model=request.model,
            message=message,
            finish_reason=str(choice.get("finish_reason") or ""),
            usage=usage,
            raw_response=payload,
        )


class LLM:
    """
    统一 LLM 调用入口。

    参考 OpenClaw 的思路，拆成：
    - provider 注册 / 解析
    - 统一 request / response 结构
    - 单次对话调用
    """

    def __init__(self, provider_configs: Optional[Dict[str, Dict[str, Any]]] = None) -> None:
        self.provider_configs = provider_configs or {}
        self.providers: Dict[str, BaseLLMProvider] = {}
        self.register_provider("mock", MockLLMProvider())
        self._register_configured_providers()

    @classmethod
    def from_openclaw_config(cls, config_path: str) -> "LLM":
        provider_configs = cls.load_provider_configs_from_openclaw(config_path)
        return cls(provider_configs=provider_configs)

    @staticmethod
    def load_provider_configs_from_openclaw(config_path: str) -> Dict[str, Dict[str, Any]]:
        path = Path(config_path)
        if not path.exists() or not path.is_file():
            raise LLMError(f"openclaw config not found: {config_path}")

        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise LLMError(f"failed to read openclaw config: {exc}") from exc
        except json.JSONDecodeError as exc:
            raise LLMError(f"invalid openclaw json: {exc}") from exc

        providers = payload.get("models", {}).get("providers", {})
        normalized: Dict[str, Dict[str, Any]] = {}
        for provider_name, config in providers.items():
            if not isinstance(config, dict):
                continue
            api_type = str(config.get("api", "")).strip().lower()
            base_url = str(config.get("baseUrl", "")).strip()
            api_key = str(config.get("apiKey", "")).strip()
            if api_type not in {"openai-completions", "anthropic-messages"} or not base_url:
                continue

            normalized[provider_name] = {
                "type": "openai_compatible",
                "api_base": base_url,
                "api_key": api_key,
                "models": config.get("models", []),
                "source": "openclaw.json",
            }
        return normalized

    def _register_configured_providers(self) -> None:
        for provider_name, config in self.provider_configs.items():
            provider_type = str(config.get("type", "")).strip().lower()
            if provider_type != "openai_compatible":
                continue
            self.register_provider(
                provider_name,
                OpenAICompatibleProvider(
                    api_base=str(config.get("api_base", "")).strip(),
                    api_key=str(config.get("api_key", "")).strip(),
                    api_key_env=str(config.get("api_key_env", "")).strip(),
                    default_headers=config.get("headers", {}) if isinstance(config.get("headers"), dict) else {},
                ),
            )

    def register_provider(self, provider_name: str, provider: BaseLLMProvider) -> None:
        self.providers[provider_name] = provider

    def list_providers(self) -> List[str]:
        return sorted(self.providers.keys())

    def build_request(
        self,
        provider: str,
        model: str,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        tool_choice: str = "auto",
        temperature: float = 0.0,
        max_tokens: int = 2048,
        extra_params: Optional[Dict[str, Any]] = None,
    ) -> LLMRequest:
        llm_messages = [self._normalize_message(item) for item in messages]
        llm_tools = [self._normalize_tool(item) for item in (tools or [])]
        return LLMRequest(
            provider=provider,
            model=model,
            messages=llm_messages,
            tools=llm_tools,
            tool_choice=tool_choice,
            temperature=temperature,
            max_tokens=max_tokens,
            extra_params=extra_params or {},
        )

    def call(self, request: LLMRequest) -> LLMResponse:
        provider = self.providers.get(request.provider)
        if provider is None:
            return LLMResponse(
                ok=False,
                provider=request.provider,
                model=request.model,
                message=LLMMessage(role="assistant", content=""),
                error=f"provider not registered: {request.provider}",
            )
        try:
            return provider.call(request)
        except Exception as exc:  # noqa: BLE001
            return LLMResponse(
                ok=False,
                provider=request.provider,
                model=request.model,
                message=LLMMessage(role="assistant", content=""),
                error=str(exc),
            )

    def call_chat(
        self,
        provider: str,
        model: str,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        tool_choice: str = "auto",
        temperature: float = 0.0,
        max_tokens: int = 2048,
        extra_params: Optional[Dict[str, Any]] = None,
    ) -> LLMResponse:
        request = self.build_request(
            provider=provider,
            model=model,
            messages=messages,
            tools=tools,
            tool_choice=tool_choice,
            temperature=temperature,
            max_tokens=max_tokens,
            extra_params=extra_params,
        )
        return self.call(request)

    def _normalize_message(self, payload: Dict[str, Any]) -> LLMMessage:
        tool_calls = []
        for item in payload.get("tool_calls", []) or []:
            tool_calls.append(
                LLMToolCall(
                    id=str(item.get("id", "")),
                    name=str(item.get("name", "")),
                    arguments=item.get("arguments", {}) if isinstance(item.get("arguments", {}), dict) else {},
                )
            )
        return LLMMessage(
            role=str(payload.get("role", "user")),
            content=str(payload.get("content", "")),
            name=str(payload.get("name", "")),
            tool_call_id=str(payload.get("tool_call_id", "")),
            tool_calls=tool_calls,
        )

    def _normalize_tool(self, payload: Dict[str, Any]) -> LLMToolDefinition:
        return LLMToolDefinition(
            name=str(payload.get("name", "")),
            description=str(payload.get("description", "")),
            parameters=payload.get("parameters", {}) if isinstance(payload.get("parameters", {}), dict) else {},
        )
