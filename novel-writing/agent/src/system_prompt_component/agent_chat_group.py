from __future__ import annotations

from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class agent_chat_group(system_prompt_component_type):
    """输出当前 agent 与其他 agent 的关系拓扑。"""

    def on_init(self) -> None:
        self.group_data: Dict[str, Any] = {
            "agent_id": self.agent_id or self.agent_config.get("id", ""),
            "relationships": self._normalize_relationships(
                self.agent_config.get("Relationship with other agents", {})
            ),
            "allowed_targets": self._normalize_string_list(
                self.agent_config.get("agent_capability", {}).get("allowed_targets", [])
            ),
            "can_delegate": bool(self.agent_config.get("agent_capability", {}).get("can_delegate", False)),
            "can_reply_user": bool(self.agent_config.get("agent_capability", {}).get("can_reply_user", False)),
        }
        self.apply_change(**self.component_config)

    def _normalize_string_list(self, raw_value: Any) -> List[str]:
        if isinstance(raw_value, list):
            return [str(item).strip() for item in raw_value if str(item).strip()]
        if raw_value in (None, ""):
            return []
        value = str(raw_value).strip()
        return [value] if value else []

    def _normalize_relationship_entries(self, raw_value: Any) -> List[Dict[str, str]]:
        entries: List[Dict[str, str]] = []
        if not isinstance(raw_value, list):
            return entries

        for item in raw_value:
            if isinstance(item, dict):
                agent_id = str(item.get("id", "")).strip()
                if not agent_id:
                    continue
                entries.append(
                    {
                        "id": agent_id,
                        "connect": str(item.get("connect", "true")).strip() or "true",
                    }
                )
                continue

            agent_id = str(item).strip()
            if agent_id:
                entries.append({"id": agent_id, "connect": "true"})

        return entries

    def _normalize_relationships(self, raw_value: Any) -> Dict[str, List[Dict[str, str]]]:
        raw_map = raw_value if isinstance(raw_value, dict) else {}
        return {
            "Superior": self._normalize_relationship_entries(raw_map.get("Superior", [])),
            "Peer": self._normalize_relationship_entries(raw_map.get("Peer", [])),
            "Subordinate": self._normalize_relationship_entries(raw_map.get("Subordinate", [])),
        }

    def apply_change(self, **kwargs: Any) -> None:
        relationships = kwargs.get("relationships")
        if relationships is None:
            relationships = kwargs.get("Relationship with other agents")
        if relationships is not None:
            self.group_data["relationships"] = self._normalize_relationships(relationships)

        agent_capability = kwargs.get("agent_capability")
        if isinstance(agent_capability, dict):
            self.group_data["allowed_targets"] = self._normalize_string_list(
                agent_capability.get("allowed_targets", self.group_data.get("allowed_targets", []))
            )
            if "can_delegate" in agent_capability:
                self.group_data["can_delegate"] = bool(agent_capability.get("can_delegate"))
            if "can_reply_user" in agent_capability:
                self.group_data["can_reply_user"] = bool(agent_capability.get("can_reply_user"))

        if "allowed_targets" in kwargs:
            self.group_data["allowed_targets"] = self._normalize_string_list(kwargs.get("allowed_targets"))
        if "can_delegate" in kwargs:
            self.group_data["can_delegate"] = bool(kwargs.get("can_delegate"))
        if "can_reply_user" in kwargs:
            self.group_data["can_reply_user"] = bool(kwargs.get("can_reply_user"))

    def _build_relation_line(self, title: str, items: List[Dict[str, str]]) -> str:
        if not items:
            return f"- {title}: None"
        rendered = [
            f"{item['id']} ({'connected' if str(item.get('connect', 'true')).lower() != 'false' else 'disconnected'})"
            for item in items
        ]
        return f"- {title}: {', '.join(rendered)}"

    def build_system_prompt(self) -> str:
        relationships = self.group_data.get("relationships", {})
        lines = [
            "## Agent Chat Group",
            f"Current agent: `{self.group_data.get('agent_id', '') or 'unknown-agent'}`",
            self._build_relation_line("Superior", relationships.get("Superior", [])),
            self._build_relation_line("Peer", relationships.get("Peer", [])),
            self._build_relation_line("Subordinate", relationships.get("Subordinate", [])),
        ]

        allowed_targets = self.group_data.get("allowed_targets", [])
        if allowed_targets:
            lines.append(f"- Allowed delegate targets: {', '.join(allowed_targets)}")
        else:
            lines.append("- Allowed delegate targets: None configured")

        lines.append(f"- Can delegate tasks: {'yes' if self.group_data.get('can_delegate') else 'no'}")
        lines.append(f"- Can reply to user: {'yes' if self.group_data.get('can_reply_user') else 'no'}")
        return "\n".join(lines)
