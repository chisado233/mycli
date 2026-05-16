from pathlib import Path
from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class Project_Context(system_prompt_component_type):
    """加载并输出项目上下文文件。"""

    def on_init(self) -> None:
        self.context_data: Dict[str, Any] = {
            "workspace_dir": self.agent_config.get("workspace", ""),
            "files": [],
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        workspace_dir = kwargs.get("workspace_dir") or kwargs.get("workspace")
        if workspace_dir:
            self.context_data["workspace_dir"] = workspace_dir

        files = kwargs.get("files")
        if files is None:
            has_explicit_file_update = any(key in kwargs for key in ("memory", "project_context", "context_files"))
            if not has_explicit_file_update:
                return
            files = []
            for key in ("memory", "project_context", "context_files"):
                value = kwargs.get(key)
                if not value:
                    continue
                if isinstance(value, list):
                    files.extend(value)
                else:
                    files.append(value)
        self.context_data["files"] = [str(file).strip() for file in files if str(file).strip()]

    def _load_files(self) -> List[Dict[str, str]]:
        workspace_dir = self.context_data.get("workspace_dir", "")
        loaded: List[Dict[str, str]] = []
        for relative_path in self.context_data.get("files", []):
            path = Path(relative_path)
            if not path.is_absolute() and workspace_dir:
                path = Path(workspace_dir) / relative_path
            if not path.exists() or not path.is_file():
                continue
            try:
                content = path.read_text(encoding="utf-8").strip()
            except OSError:
                continue
            loaded.append({"path": str(path), "content": content})
        return loaded

    def get_system_prompt(self) -> str:
        # Project context is expected to reflect the latest shared workspace notes.
        # Rebuild it on every access so edited context files appear immediately.
        return self.refresh()

    def build_system_prompt(self) -> str:
        loaded_files = self._load_files()
        if not loaded_files:
            return ""

        lines = ["# Project Context", "The following project context files have been loaded:", ""]
        for item in loaded_files:
            lines.extend([f"## {item['path']}", "", item["content"], ""])
        return "\n".join(lines).rstrip()
