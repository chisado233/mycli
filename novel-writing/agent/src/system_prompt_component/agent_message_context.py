from __future__ import annotations

import json
from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class Agent_Message_Context(system_prompt_component_type):
    """注入 runtime 整理好的当前消息与上下文。"""

    def on_init(self) -> None:
        self.message_context: Dict[str, Any] = {
            "current_message": {},
            "current_task": {},
            "reply_owner": "",
            "channel_context": {},
            "handoff_context": {},
            "context_summary": {},
            "recent_history": {"latest_summary": {}, "events": []},
            "pending_children": [],
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        if "message_context" in kwargs and isinstance(kwargs["message_context"], dict):
            self.message_context.update(kwargs["message_context"])
        for key in (
            "current_message",
            "current_task",
            "reply_owner",
            "channel_context",
            "handoff_context",
            "context_summary",
            "recent_history",
            "pending_children",
        ):
            if key in kwargs and kwargs[key] is not None:
                self.message_context[key] = kwargs[key]

    def _format_json_block(self, title: str, payload: Any) -> List[str]:
        if not payload:
            return []
        return [f"### {title}", "```json", json.dumps(payload, ensure_ascii=False, indent=2), "```", ""]

    def build_system_prompt(self) -> str:
        if not any(self.message_context.values()):
            return ""

        lines: List[str] = ["## Agent Message Context", ""]
        lines.extend(self._format_json_block("Current Message", self.message_context.get("current_message", {})))
        lines.extend(self._format_json_block("Current Task", self.message_context.get("current_task", {})))

        reply_owner = str(self.message_context.get("reply_owner", "")).strip()
        if reply_owner:
            lines.extend(["### Reply Ownership", f"Current reply owner: `{reply_owner}`", ""])

        lines.extend(self._format_json_block("Channel Context", self.message_context.get("channel_context", {})))
        lines.extend(self._format_json_block("Handoff Context", self.message_context.get("handoff_context", {})))
        lines.extend(self._format_json_block("Shared Context Summary", self.message_context.get("context_summary", {})))
        lines.extend(self._format_json_block("Recent History", self.message_context.get("recent_history", {})))
        lines.extend(self._format_json_block("Pending Child Tasks", self.message_context.get("pending_children", [])))
        return "\n".join(lines).rstrip()
