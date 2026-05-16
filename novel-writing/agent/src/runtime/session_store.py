from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


def _now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


class SessionContextStore:
    """Persist high-level session context beside a workflow workspace."""

    def __init__(self, workspace_dir: str, session_id: str = "default") -> None:
        self.workspace_dir = Path(workspace_dir)
        self.session_id = session_id.strip() or "default"
        self.root = self.workspace_dir / "session_store" / self.session_id
        self.turns_path = self.root / "turns.jsonl"
        self.snapshot_path = self.root / "snapshot.json"
        self.root.mkdir(parents=True, exist_ok=True)

    def _read_json(self, path: Path, default: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if not path.exists():
            return dict(default or {})
        return json.loads(path.read_text(encoding="utf-8"))

    def _write_json(self, path: Path, payload: Dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def _read_jsonl(self, path: Path) -> List[Dict[str, Any]]:
        if not path.exists():
            return []
        items: List[Dict[str, Any]] = []
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                items.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return items

    def reset(self) -> None:
        if self.root.exists():
            for path in sorted(self.root.rglob("*"), reverse=True):
                if path.is_file():
                    path.unlink()
                elif path.is_dir():
                    path.rmdir()
        self.root.mkdir(parents=True, exist_ok=True)

    def load_snapshot(self) -> Dict[str, Any]:
        snapshot = self._read_json(
            self.snapshot_path,
            default={
                "session_id": self.session_id,
                "created_at": _now_iso(),
                "updated_at": _now_iso(),
                "run_count": 0,
                "turn_count": 0,
                "latest_user_message": "",
                "latest_assistant_message": "",
                "latest_runtime_result": {},
                "context_summaries": {},
            },
        )
        snapshot.setdefault("session_id", self.session_id)
        snapshot.setdefault("context_summaries", {})
        return snapshot

    def record_turn(
        self,
        *,
        user_message: str,
        assistant_message: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        snapshot = self.load_snapshot()
        timestamp = _now_iso()
        turn_index = int(snapshot.get("turn_count", 0) or 0) + 1
        payload = {
            "turn_index": turn_index,
            "user_message": user_message,
            "assistant_message": assistant_message,
            "metadata": metadata or {},
            "created_at": timestamp,
        }
        with self.turns_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")

        snapshot["turn_count"] = turn_index
        snapshot["latest_user_message"] = user_message
        snapshot["latest_assistant_message"] = assistant_message
        snapshot["updated_at"] = timestamp
        self._write_json(self.snapshot_path, snapshot)
        return payload

    def sync_runtime_result(
        self,
        *,
        workflow_path: str,
        state: Dict[str, Any],
        execution_order: List[str],
        final_response: str,
        result_path: str,
        log_path: str,
        trace_md_path: str,
        dialogue_log_path: str,
    ) -> Dict[str, Any]:
        snapshot = self.load_snapshot()
        snapshot["run_count"] = int(snapshot.get("run_count", 0) or 0) + 1
        snapshot["latest_runtime_result"] = {
            "workflow_path": workflow_path,
            "state": state,
            "execution_order": execution_order,
            "final_response": final_response,
            "result_path": result_path,
            "log_path": log_path,
            "trace_md_path": trace_md_path,
            "dialogue_log_path": dialogue_log_path,
            "updated_at": _now_iso(),
        }
        snapshot["updated_at"] = _now_iso()
        self._write_json(self.snapshot_path, snapshot)
        return snapshot

    def sync_context_summaries(self, contexts_dir: Path) -> Dict[str, Any]:
        snapshot = self.load_snapshot()
        summaries: Dict[str, Any] = {}
        if contexts_dir.exists():
            for path in sorted(contexts_dir.glob("*/summary.json")):
                summaries[path.parent.name] = self._read_json(path)
        snapshot["context_summaries"] = summaries
        snapshot["updated_at"] = _now_iso()
        self._write_json(self.snapshot_path, snapshot)
        return summaries

    def list_turns(self) -> List[Dict[str, Any]]:
        return self._read_jsonl(self.turns_path)
