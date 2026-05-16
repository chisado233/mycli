from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class Workspace(system_prompt_component_type):
    """生成工作区相关提示。"""

    def on_init(self) -> None:
        self.workspace_data: Dict[str, Any] = {
            "workspace_dir": self.agent_config.get("workspace", ""),
            "notes": [],
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        workspace_dir = kwargs.get("workspace_dir") or kwargs.get("workspace")
        if workspace_dir:
            self.workspace_data["workspace_dir"] = workspace_dir

        notes = kwargs.get("notes")
        if notes is not None:
            if isinstance(notes, list):
                self.workspace_data["notes"] = [str(note).strip() for note in notes if str(note).strip()]
            else:
                note = str(notes).strip()
                self.workspace_data["notes"] = [note] if note else []

    def build_system_prompt(self) -> str:
        lines: List[str] = ["## Workspace"]
        workspace_dir = self.workspace_data.get("workspace_dir", "").strip()
        if workspace_dir:
            lines.append(f"Your working directory is: {workspace_dir}")
            lines.append("Treat this directory as the primary workspace for file operations unless the user says otherwise.")
        else:
            lines.append("Workspace directory is not configured.")

        for note in self.workspace_data.get("notes", []):
            lines.append(f"- {note}")
        return "\n".join(lines)
