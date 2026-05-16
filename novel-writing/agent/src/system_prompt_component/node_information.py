from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from system_prompt_component_type import system_prompt_component_type


class node_infomation(system_prompt_component_type):
    """兼容旧配置中的 node_infomation 组件，负责加载节点说明文件。"""

    DEFAULT_CANDIDATE_FILES = [
        "node_info.md",
        "node_infomation.md",
        "input/node_info.md",
        "input/node_infomation.md",
    ]

    def on_init(self) -> None:
        self.node_data: Dict[str, Any] = {
            "workspace_dir": self.agent_config.get("workspace", ""),
            "file": "",
            "title": "Node Information",
            "loaded_path": "",
            "content": "",
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        workspace_dir = kwargs.get("workspace_dir") or kwargs.get("workspace")
        if workspace_dir:
            self.node_data["workspace_dir"] = str(workspace_dir).strip()

        file_path = (
            kwargs.get("node_infomation")
            or kwargs.get("node_information")
            or kwargs.get("path")
            or kwargs.get("file")
        )
        if file_path is not None:
            self.node_data["file"] = str(file_path).strip()

        title = kwargs.get("title")
        if title:
            self.node_data["title"] = str(title).strip()

        loaded_path, content = self._load_content()
        self.node_data["loaded_path"] = loaded_path
        self.node_data["content"] = content

    def _candidate_paths(self) -> List[Path]:
        workspace_dir = str(self.node_data.get("workspace_dir", "")).strip()
        workspace_path = Path(workspace_dir) if workspace_dir else None
        raw_file = str(self.node_data.get("file", "")).strip()

        candidates: List[Path] = []
        if raw_file:
            file_path = Path(raw_file)
            candidates.append(file_path)
            if workspace_path and not file_path.is_absolute():
                candidates.append(workspace_path / file_path)

        if workspace_path:
            candidates.extend(workspace_path / relative for relative in self.DEFAULT_CANDIDATE_FILES)

        deduped: List[Path] = []
        seen = set()
        for candidate in candidates:
            candidate_key = str(candidate)
            if candidate_key in seen:
                continue
            seen.add(candidate_key)
            deduped.append(candidate)
        return deduped

    def _load_content(self) -> tuple[str, str]:
        for path in self._candidate_paths():
            if not path.exists() or not path.is_file():
                continue
            try:
                content = path.read_text(encoding="utf-8").strip()
            except OSError:
                continue
            if content:
                return str(path), content
        return "", ""

    def build_system_prompt(self) -> str:
        content = self.node_data.get("content", "").strip()
        if not content:
            return ""

        lines = [f"## {self.node_data.get('title', 'Node Information')}"]
        loaded_path = str(self.node_data.get("loaded_path", "")).strip()
        if loaded_path:
            lines.append(f"Source: {loaded_path}")
        lines.extend(["", content])
        return "\n".join(lines)
