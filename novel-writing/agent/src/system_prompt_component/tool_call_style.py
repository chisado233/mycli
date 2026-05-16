from typing import Any, Dict

from system_prompt_component_type import system_prompt_component_type


class Tool_Call_Style(system_prompt_component_type):
    """生成工具调用风格约束。"""

    def on_init(self) -> None:
        self.style_data: Dict[str, Any] = {
            "default_narrate": False,
            "brief_narration": True,
            "mention_sensitive_actions": True,
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        for key in ("default_narrate", "brief_narration", "mention_sensitive_actions"):
            if key in kwargs:
                self.style_data[key] = bool(kwargs[key])

    def build_system_prompt(self) -> str:
        lines = ["## Tool Call Style"]
        if self.style_data["default_narrate"]:
            lines.append("Default: narrate tool calls before you execute them.")
        else:
            lines.append("Default: do not narrate routine, low-risk tool calls.")

        if self.style_data["brief_narration"]:
            lines.append("When narration helps, keep it brief and value-dense.")
        if self.style_data["mention_sensitive_actions"]:
            lines.append("Always call out sensitive or destructive actions before doing them.")

        lines.extend(
            [
                "Narrate when it helps the user track multi-step reasoning, risk, or progress.",
                "Avoid repetitive commentary for obvious file reads, searches, or straightforward tool calls.",
            ]
        )
        return "\n".join(lines)
