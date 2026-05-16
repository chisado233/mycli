from typing import Any, Dict

from system_prompt_component_type import system_prompt_component_type


class Sandbox(system_prompt_component_type):
    """生成沙箱相关提示。"""

    def on_init(self) -> None:
        self.sandbox_data: Dict[str, Any] = {
            "enabled": False,
            "mode": "",
            "workspace_access": "",
            "network_access": "",
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        if "enabled" in kwargs:
            self.sandbox_data["enabled"] = str(kwargs["enabled"]).lower() == "true" or kwargs["enabled"] is True
        if "mode" in kwargs:
            self.sandbox_data["mode"] = str(kwargs["mode"]).strip()
        if "workspace_access" in kwargs:
            self.sandbox_data["workspace_access"] = str(kwargs["workspace_access"]).strip()
        if "network_access" in kwargs:
            self.sandbox_data["network_access"] = str(kwargs["network_access"]).strip()

    def build_system_prompt(self) -> str:
        if not self.sandbox_data.get("enabled"):
            return ""

        lines = ["## Sandbox", "You are running in a sandboxed environment."]
        if self.sandbox_data.get("mode"):
            lines.append(f"Sandbox mode: {self.sandbox_data['mode']}")
        if self.sandbox_data.get("workspace_access"):
            lines.append(f"Workspace access: {self.sandbox_data['workspace_access']}")
        if self.sandbox_data.get("network_access"):
            lines.append(f"Network access: {self.sandbox_data['network_access']}")
        lines.append("If sandbox limits block progress, ask for a safer alternative instead of guessing.")
        return "\n".join(lines)
