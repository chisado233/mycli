from typing import Any, Dict

from system_prompt_component_type import system_prompt_component_type


class Silent_Replies(system_prompt_component_type):
    """生成静默回复协议。"""

    def on_init(self) -> None:
        self.silent_data: Dict[str, Any] = {"token": "SILENT_REPLY"}
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        if "token" in kwargs and kwargs["token"]:
            self.silent_data["token"] = str(kwargs["token"]).strip()

    def build_system_prompt(self) -> str:
        token = self.silent_data["token"]
        return "\n".join(
            [
                "## Silent Replies",
                f"When you have nothing useful to say, reply with ONLY: {token}",
                "Do not append the token to normal answers and do not wrap it in markdown.",
            ]
        )
