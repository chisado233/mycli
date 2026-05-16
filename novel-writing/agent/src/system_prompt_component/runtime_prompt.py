from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class Runtime(system_prompt_component_type):
    """生成运行时信息。"""

    def on_init(self) -> None:
        self.runtime_data: Dict[str, Any] = {
            "agent_id": self.agent_id or self.agent_config.get("id", ""),
            "host": "",
            "os": "",
            "arch": "",
            "node": "",
            "model": "",
            "default_model": "",
            "shell": "",
            "channel": "",
            "capabilities": [],
            "thinking": "off",
            "reasoning": "off",
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        for key in (
            "agent_id",
            "host",
            "os",
            "arch",
            "node",
            "model",
            "default_model",
            "shell",
            "channel",
            "thinking",
            "reasoning",
        ):
            if key in kwargs and kwargs[key] is not None:
                self.runtime_data[key] = str(kwargs[key]).strip()

        if "capabilities" in kwargs:
            capabilities = kwargs["capabilities"]
            if isinstance(capabilities, list):
                self.runtime_data["capabilities"] = [str(item).strip() for item in capabilities if str(item).strip()]

    def build_system_prompt(self) -> str:
        parts: List[str] = []
        for key in (
            "agent_id",
            "host",
            "os",
            "arch",
            "node",
            "model",
            "default_model",
            "shell",
            "channel",
        ):
            value = self.runtime_data.get(key, "")
            if value:
                parts.append(f"{key}={value}")

        capabilities = self.runtime_data.get("capabilities", [])
        if capabilities:
            parts.append(f"capabilities={','.join(capabilities)}")

        if self.runtime_data.get("thinking"):
            parts.append(f"thinking={self.runtime_data['thinking']}")
        if self.runtime_data.get("reasoning"):
            parts.append(f"reasoning={self.runtime_data['reasoning']}")

        return "\n".join(
            [
                "## Runtime",
                f"Runtime: {' | '.join(parts) if parts else 'runtime details unavailable'}",
            ]
        )
