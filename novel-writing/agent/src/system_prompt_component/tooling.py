from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class Tooling(system_prompt_component_type):
    """生成工具能力说明。"""

    DEFAULT_TOOL_SUMMARIES: Dict[str, str] = {
        "read": "Read file contents",
        "write": "Create or overwrite files",
        "edit": "Make precise edits to files",
        "apply_patch": "Apply multi-file patches",
        "grep": "Search file contents for patterns",
        "find": "Find files by glob pattern",
        "ls": "List directory contents",
        "exec": "Run shell commands",
        "process": "Manage background exec sessions",
        "agent_config_update": "Update agent configuration fields when runtime policy allows it",
        "agent_send_task": "Send a task message to another agent through the runtime bus",
        "agent_reply_task": "Reply to a parent or upstream task on the runtime bus",
        "agent_handoff_reply": "Transfer reply ownership to another agent and attach handoff context",
        "agent_request_permission_change": "Request temporary or persistent agent permission changes",
        "agent_request_finish_node": "You can request finishing the current node when the stage work is complete and output artifacts are ready",
        "memory_search": "Search memory snippets before answering questions about prior work or decisions",
        "memory_get": "Read specific memory lines after search",
        "cron": "Manage reminders and scheduled wake events",
        "heartbeat": "Trigger or inspect heartbeat-related flows",
        "subagent": "Spawn or coordinate sub-agents for longer tasks",
    }

    def on_init(self) -> None:
        self.tool_data: Dict[str, Any] = {
            "tools": [],
            "tool_summaries": dict(self.DEFAULT_TOOL_SUMMARIES),
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        if "tool_summaries" in kwargs and isinstance(kwargs["tool_summaries"], dict):
            self.tool_data["tool_summaries"].update(kwargs["tool_summaries"])

        tools = kwargs.get("tools")
        if tools is None:
            tools = self.agent_config.get("tool", [])
        self.tool_data["tools"] = self._normalize_tools(tools)

    def _normalize_tools(self, tools: Any) -> List[str]:
        normalized: List[str] = []
        if not isinstance(tools, list):
            return normalized

        for item in tools:
            if isinstance(item, str):
                normalized.extend(self._split_tool_string(item))
                continue
            if not isinstance(item, dict):
                continue

            enabled_value = item.get("enable", item.get("enbale", True))
            enabled = str(enabled_value).lower() != "false"
            if not enabled:
                continue

            normalized.extend(self._split_tool_string(str(item.get("id", ""))))

        deduped: List[str] = []
        seen = set()
        for tool_name in normalized:
            if tool_name not in seen:
                seen.add(tool_name)
                deduped.append(tool_name)
        return deduped

    def _split_tool_string(self, raw: str) -> List[str]:
        return [part.strip() for part in raw.split("/") if part.strip()]

    def build_system_prompt(self) -> str:
        lines = [
            "## Tooling",
            "Tool availability (filtered by policy):",
            "Tool names are case-sensitive. Call tools exactly as listed.",
        ]
        tools = self.tool_data.get("tools", [])
        if not tools:
            lines.append("No tools are currently enabled.")
            return "\n".join(lines)

        summaries = self.tool_data.get("tool_summaries", {})
        for tool_name in tools:
            summary = summaries.get(tool_name, "")
            lines.append(f"- {tool_name}: {summary}" if summary else f"- {tool_name}")

        lines.extend(
            [
                "Use first-class tools directly when they exist instead of asking the user to do equivalent shell work.",
                "For long-running work, prefer sub-agent orchestration over blocking the current agent.",
            ]
        )
        return "\n".join(lines)
