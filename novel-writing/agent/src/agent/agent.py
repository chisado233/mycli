from __future__ import annotations

import json
import logging
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


CURRENT_DIR = Path(__file__).resolve().parent
SRC_DIR = CURRENT_DIR.parent
LLM_DIR = SRC_DIR / "llm"
TOOL_DIR = SRC_DIR / "tool"
SYSTEM_PROMPT_COMPONENT_DIR = SRC_DIR / "system_prompt_component"

for path in (CURRENT_DIR, LLM_DIR, TOOL_DIR, SYSTEM_PROMPT_COMPONENT_DIR):
    if str(path) not in sys.path:
        sys.path.append(str(path))

from llm import LLM, LLMResponse  # noqa: E402
from system_prompt import AgentSystemPrompt  # noqa: E402
from tool import tool as ToolManager  # noqa: E402


class agent:
    """单个 agent 的最小可运行实现。"""

    def __init__(
        self,
        config_path: Optional[str] = None,
        config: Optional[Dict[str, Any]] = None,
        runtime_context: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.logger = logging.getLogger(f"mult_agent.agent.{id(self)}")
        self.logger.setLevel(logging.INFO)
        if not self.logger.handlers:
            handler = logging.StreamHandler()
            handler.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
            self.logger.addHandler(handler)
        self.logger.propagate = False

        self.config_path = config_path or str(CURRENT_DIR / "config.json")
        self.config = config or self._load_config(self.config_path)
        self.runtime_context = runtime_context or {}
        self.session_messages: List[Dict[str, Any]] = []
        self.debug_log: List[Dict[str, Any]] = []

        llm_config = self.config.get("llm", {})
        self.provider = str(llm_config.get("provider", "custom-aiapi-meccy-top")).strip()
        self.model = str(llm_config.get("model", "gemini-2.5-flash")).strip()
        self.max_steps = int(llm_config.get("max_steps", 6) or 6)

        self.system_prompt_manager = AgentSystemPrompt(self.config)
        self.tool_manager = ToolManager(
            workspace_dir=str(self.config.get("workspace", "")),
            runtime=self.runtime_context,
        )
        self.llm = self._build_llm()
        self._log_event(
            "agent_initialized",
            {
                "config_path": self.config_path,
                "workspace": self.config.get("workspace", ""),
                "provider": self.provider,
                "model": self.model,
                "system_prompt_class": type(self.system_prompt_manager).__name__,
                "tool_manager_class": type(self.tool_manager).__name__,
            },
        )

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        path = Path(config_path)
        return json.loads(path.read_text(encoding="utf-8"))

    def _build_llm(self) -> LLM:
        llm_config = self.config.get("llm", {})
        openclaw_config_path = str(llm_config.get("openclaw_config_path", r"D:\agent_workspace\openclaw.json")).strip()
        client = LLM.from_openclaw_config(openclaw_config_path)
        self._log_event(
            "llm_loaded",
            {
                "openclaw_config_path": openclaw_config_path,
                "providers": client.list_providers(),
            },
        )
        return client

    def _log_event(self, event: str, details: Dict[str, Any]) -> None:
        payload = {"event": event, "details": details}
        self.debug_log.append(payload)
        self.logger.info("%s | %s", event, json.dumps(details, ensure_ascii=False))

    def get_system_prompt(self) -> str:
        if self.runtime_context:
            self.system_prompt_manager.update_all_components(**self.runtime_context)
        prompt = self.system_prompt_manager.get_prompt()
        self._log_event(
            "system_prompt_loaded",
            {
                "length": len(prompt),
                "has_project_context": "# Project Context" in prompt,
            },
        )
        return prompt

    def get_messages(self) -> List[Dict[str, Any]]:
        messages = [{"role": "system", "content": self.get_system_prompt()}]
        messages.extend(self.session_messages)
        return messages

    def append_user_message(self, content: str) -> None:
        self.session_messages.append({"role": "user", "content": content})

    def append_assistant_message(self, content: str) -> None:
        self.session_messages.append({"role": "assistant", "content": content})

    def append_tool_result(self, tool_call_id: str, tool_name: str, content: str) -> None:
        self.session_messages.append(
            {
                "role": "tool",
                "content": content,
                "name": tool_name,
                "tool_call_id": tool_call_id,
            }
        )

    def _resolve_enabled_tool_names(self) -> List[str]:
        tool_names: List[str] = []
        available = set(self.tool_manager.注册())
        for item in self.config.get("tool", []):
            if not isinstance(item, dict):
                continue
            enabled_value = item.get("enable", item.get("enbale", True))
            if str(enabled_value).lower() == "false":
                continue
            for part in str(item.get("id", "")).split("/"):
                name = part.strip()
                if name and name in available and name not in tool_names:
                    tool_names.append(name)
        return tool_names

    def _build_llm_tools(self) -> List[Dict[str, Any]]:
        enabled_tool_names = self._resolve_enabled_tool_names()
        definitions = self.tool_manager.get_tool_definitions(enabled_tool_names)
        self._log_event(
            "tools_bound",
            {
                "enabled_tool_names": enabled_tool_names,
                "tool_count": len(definitions),
            },
        )
        return definitions

    def tool_call(self, tool_name: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        self._log_event("tool_call_started", {"tool_name": tool_name, "params": params or {}})
        result = self.tool_manager.invoke(tool_name, params).to_dict()
        self._log_event(
            "tool_call_finished",
            {
                "tool_name": tool_name,
                "ok": result.get("ok", False),
                "error": result.get("error", ""),
            },
        )
        return result

    def _call_llm_once(self) -> LLMResponse:
        return self.llm.call_chat(
            provider=self.provider,
            model=self.model,
            messages=self.get_messages(),
            tools=self._build_llm_tools(),
            temperature=float(self.config.get("llm", {}).get("temperature", 0.0) or 0.0),
            max_tokens=int(self.config.get("llm", {}).get("max_tokens", 512) or 512),
        )

    def agent_loop(self, trigger_message: str, runtime_context: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if runtime_context:
            self.runtime_context = runtime_context
            self.tool_manager = ToolManager(
                workspace_dir=str(self.config.get("workspace", "")),
                runtime=self.runtime_context,
            )
        self._log_event("agent_loop_started", {"trigger_message": trigger_message})
        self.append_user_message(trigger_message)
        trace: List[Dict[str, Any]] = []

        for step in range(1, self.max_steps + 1):
            response = self._call_llm_once()
            trace.append({"step": step, "llm_response": response.to_dict()})

            if not response.ok:
                self._log_event("agent_loop_failed", {"error": response.error, "step": step})
                return {
                    "ok": False,
                    "error": response.error,
                    "trace": trace,
                    "messages": self.session_messages,
                    "debug_log": self.debug_log,
                }

            if response.message.tool_calls:
                assistant_tool_call_message = {
                    "role": "assistant",
                    "content": response.message.content,
                    "tool_calls": [
                        {"id": item.id, "name": item.name, "arguments": item.arguments}
                        for item in response.message.tool_calls
                    ],
                }
                self.session_messages.append(assistant_tool_call_message)

                for tool_call in response.message.tool_calls:
                    tool_result = self.tool_call(tool_call.name, tool_call.arguments)
                    trace.append(
                        {
                            "step": step,
                            "tool_call": {
                                "id": tool_call.id,
                                "name": tool_call.name,
                                "arguments": tool_call.arguments,
                                "result": tool_result,
                            },
                        }
                    )
                    tool_content = tool_result.get("content") or tool_result.get("error") or json.dumps(
                        tool_result, ensure_ascii=False
                    )
                    self.append_tool_result(tool_call.id, tool_call.name, str(tool_content))
                continue

            assistant_content = response.message.content.strip()
            self.append_assistant_message(assistant_content)
            self._log_event(
                "agent_loop_finished",
                {"step": step, "finish_reason": response.finish_reason, "final_response": assistant_content},
            )
            return {
                "ok": True,
                "final_response": assistant_content,
                "finish_reason": response.finish_reason,
                "trace": trace,
                "messages": self.session_messages,
                "debug_log": self.debug_log,
            }

        self._log_event("agent_loop_failed", {"error": "max steps exceeded"})
        return {
            "ok": False,
            "error": "agent loop reached max steps without final response",
            "trace": trace,
            "messages": self.session_messages,
            "debug_log": self.debug_log,
        }
