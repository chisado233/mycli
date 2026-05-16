from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class agent_identity(system_prompt_component_type):
    """负责生成 agent 身份定义相关的 system prompt。"""

    def on_init(self) -> None:
        self.identity_data: Dict[str, Any] = {
            "name": self.agent_id or self.agent_config.get("id", "unknown-agent"),
            "role": "personal assistant",
            "system_name": "SM-agent",
            "description": "",
            "goals": [],
        }
        self.apply_change(
            **self.component_config,
            agent_name=self.agent_config.get("id", ""),
        )

    def apply_change(self, **kwargs: Any) -> None:
        agent_name = kwargs.get("agent_name") or kwargs.get("name")
        if agent_name:
            self.identity_data["name"] = agent_name

        if "role" in kwargs and kwargs["role"]:
            self.identity_data["role"] = kwargs["role"]

        if "system_name" in kwargs and kwargs["system_name"]:
            self.identity_data["system_name"] = kwargs["system_name"]

        if "description" in kwargs:
            self.identity_data["description"] = kwargs["description"] or ""

        goals = kwargs.get("goals")
        if goals is not None:
            if isinstance(goals, list):
                self.identity_data["goals"] = [str(goal).strip() for goal in goals if str(goal).strip()]
            else:
                goal_text = str(goals).strip()
                self.identity_data["goals"] = [goal_text] if goal_text else []

    def build_system_prompt(self) -> str:
        lines: List[str] = [
            "# Agent Identity",
            (
                f"You are `{self.identity_data['name']}`, a "
                f"{self.identity_data['role']} running inside `{self.identity_data['system_name']}`."
            ),
        ]

        description = self.identity_data.get("description", "").strip()
        if description:
            lines.append(description)

        goals = self.identity_data.get("goals", [])
        if goals:
            lines.append("Your primary goals are:")
            lines.extend(f"- {goal}" for goal in goals)

        return "\n".join(lines)
