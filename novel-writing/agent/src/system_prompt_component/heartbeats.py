from typing import Any, Dict

from system_prompt_component_type import system_prompt_component_type


class Heartbeats(system_prompt_component_type):
    """生成 heartbeat 协议提示。"""

    def on_init(self) -> None:
        enabled = self.agent_config.get("heartbeat", {}).get("enable", "false")
        self.heartbeat_data: Dict[str, Any] = {
            "enabled": str(enabled).lower() == "true",
            "prompt": "Read HEARTBEAT.md if it exists. If nothing needs attention, reply HEARTBEAT_OK.",
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        if "enabled" in kwargs:
            self.heartbeat_data["enabled"] = str(kwargs["enabled"]).lower() == "true" or kwargs["enabled"] is True
        if "prompt" in kwargs and kwargs["prompt"]:
            self.heartbeat_data["prompt"] = str(kwargs["prompt"]).strip()

    def build_system_prompt(self) -> str:
        if not self.heartbeat_data.get("enabled"):
            return ""

        return "\n".join(
            [
                "## Heartbeats",
                f"Heartbeat prompt: {self.heartbeat_data['prompt']}",
                "If you receive a heartbeat poll and nothing needs attention, reply exactly:",
                "HEARTBEAT_OK",
                'If something needs attention, do not include "HEARTBEAT_OK"; reply with the alert text instead.',
            ]
        )
