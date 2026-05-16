from __future__ import annotations

import os
import sys
import types
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List


@dataclass
class CbtSessionSnapshot:
    initialized: bool = False
    is_end: bool = False
    current_stage: float = 0.0
    current_stage_name: str = ""
    personal_info: Dict[str, Any] = field(default_factory=dict)
    report: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "initialized": self.initialized,
            "is_end": self.is_end,
            "current_stage": self.current_stage,
            "current_stage_name": self.current_stage_name,
            "personal_info": self.personal_info,
            "report": self.report,
        }


class CbtLegacySessionRuntime:
    def __init__(
        self,
        *,
        experiment_dir: str,
        openclaw_config_path: str,
        provider: str = "custom-aiapi-meccy-top",
        model: str = "gpt-5.4",
        temperature: float = 0.7,
    ) -> None:
        self.experiment_dir = Path(experiment_dir).resolve()
        self.openclaw_config_path = str(Path(openclaw_config_path).resolve())
        self.provider = provider
        self.model = model
        self.temperature = temperature

        self._configure_env()
        self._load_modules()

        self.chatbot = None
        self.gen = None
        self.report = ""
        self.snapshot = CbtSessionSnapshot()

    def _configure_env(self) -> None:
        os.environ["OPENCLAW_CONFIG_PATH"] = self.openclaw_config_path
        os.environ["OPENCLAW_PROVIDER"] = self.provider
        os.environ["OPENCLAW_MODEL"] = self.model
        os.environ["OPENCLAW_TEMPERATURE"] = str(self.temperature)

    def _load_modules(self) -> None:
        if "dashscope" not in sys.modules:
            dashscope_stub = types.ModuleType("dashscope")

            class _GenerationStub:
                @staticmethod
                def call(*args: Any, **kwargs: Any) -> Any:
                    raise RuntimeError("dashscope backend is unavailable in this environment")

            dashscope_stub.Generation = _GenerationStub
            dashscope_stub.base_http_api_url = ""
            sys.modules["dashscope"] = dashscope_stub
        if str(self.experiment_dir) not in sys.path:
            sys.path.insert(0, str(self.experiment_dir))
        from chatbot import CbtChatbot, stage_info  # type: ignore

        self.CbtChatbot = CbtChatbot
        self.stage_info = stage_info

    def _stage_name(self, stage_value: float) -> str:
        try:
            major = int(str(stage_value).split(".", 1)[0])
        except Exception:
            return ""
        for item in self.stage_info:
            if int(item.get("id", -1)) == major:
                return str(item.get("name", ""))
        return ""

    def _refresh_snapshot(self) -> None:
        if self.chatbot is None:
            self.snapshot = CbtSessionSnapshot()
            return
        current_stage = float(self.chatbot.get_current_stage())
        self.snapshot = CbtSessionSnapshot(
            initialized=self.gen is not None,
            is_end=bool(getattr(self.chatbot, "is_end", lambda: 0)()),
            current_stage=current_stage,
            current_stage_name=self._stage_name(current_stage),
            personal_info=self.chatbot.get_personal_info(),
            report=self.report,
        )

    def reset(self) -> Dict[str, Any]:
        self.chatbot = self.CbtChatbot()
        self.gen = self.chatbot.chat()
        self.report = ""
        messages = self._drain_counselor_turns(start=True)
        self._refresh_snapshot()
        return {
            "ok": True,
            "assistant_messages": messages,
            "snapshot": self.snapshot.to_dict(),
        }

    def ensure_started(self) -> Dict[str, Any]:
        if self.gen is None or self.chatbot is None:
            return self.reset()
        self._refresh_snapshot()
        return {
            "ok": True,
            "assistant_messages": [],
            "snapshot": self.snapshot.to_dict(),
        }

    def _drain_counselor_turns(self, *, start: bool = False, seed_value: str = "") -> List[str]:
        if self.gen is None:
            return []
        messages: List[str] = []
        response = None
        if start:
            try:
                response = next(self.gen)
            except StopIteration:
                return messages
        else:
            try:
                response = self.gen.send(seed_value)
            except StopIteration:
                return messages

        while isinstance(response, (list, tuple)) and len(response) >= 2 and response[0] == "counselor":
            text = str(response[1])
            messages.append(text)
            if "心理咨询结束" in text:
                break
            try:
                response = self.gen.send(text)
            except StopIteration:
                break
        return messages

    def respond(self, message: str) -> Dict[str, Any]:
        if self.gen is None or self.chatbot is None:
            self.reset()
        messages = self._drain_counselor_turns(start=False, seed_value=message)
        self._refresh_snapshot()
        return {
            "ok": True,
            "assistant_messages": messages,
            "snapshot": self.snapshot.to_dict(),
        }

    def generate_report(self) -> Dict[str, Any]:
        if self.chatbot is None:
            self.ensure_started()
        self.report = self.chatbot.generate_report() if self.chatbot is not None else ""
        self._refresh_snapshot()
        return {
            "ok": True,
            "report": self.report,
            "snapshot": self.snapshot.to_dict(),
        }
