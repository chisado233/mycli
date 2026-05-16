from __future__ import annotations

import json
import shutil
import uuid
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


PRIORITY_ORDER = {"high": 0, "normal": 1, "low": 2}


def _now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def _json_dump(payload: Dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2)


@dataclass
class RuntimeBusPaths:
    root: Path
    messages: Path
    tasks: Path
    agents: Path
    contexts: Path


class RuntimeBus:
    """文件化的最小 runtime bus。"""

    def __init__(self, workflow_dir: str, policy: Optional[Dict[str, Any]] = None) -> None:
        self.workflow_dir = Path(workflow_dir)
        self.policy = policy or {}
        root = self.workflow_dir / "runtime_bus"
        self.paths = RuntimeBusPaths(
            root=root,
            messages=root / "messages",
            tasks=root / "tasks",
            agents=root / "agents",
            contexts=root / "contexts",
        )
        for path in (
            self.paths.root,
            self.paths.messages,
            self.paths.tasks,
            self.paths.agents,
            self.paths.contexts,
        ):
            path.mkdir(parents=True, exist_ok=True)

    def reset(self) -> None:
        if self.paths.root.exists():
            shutil.rmtree(self.paths.root)
        for path in (
            self.paths.root,
            self.paths.messages,
            self.paths.tasks,
            self.paths.agents,
            self.paths.contexts,
        ):
            path.mkdir(parents=True, exist_ok=True)

    def _write_json(self, path: Path, payload: Dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(_json_dump(payload), encoding="utf-8")

    def _read_json(self, path: Path) -> Dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    def _message_path(self, message_id: str) -> Path:
        return self.paths.messages / f"{message_id}.json"

    def _task_path(self, task_id: str) -> Path:
        return self.paths.tasks / f"{task_id}.json"

    def _agent_dir(self, agent_id: str) -> Path:
        path = self.paths.agents / agent_id
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _agent_inbox_path(self, agent_id: str) -> Path:
        return self._agent_dir(agent_id) / "inbox.json"

    def _agent_history_path(self, agent_id: str) -> Path:
        return self._agent_dir(agent_id) / "history.jsonl"

    def _context_dir(self, context_id: str) -> Path:
        path = self.paths.contexts / context_id
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _context_summary_path(self, context_id: str) -> Path:
        return self._context_dir(context_id) / "summary.json"

    def _context_events_path(self, context_id: str) -> Path:
        return self._context_dir(context_id) / "events.jsonl"

    def _load_inbox(self, agent_id: str) -> List[str]:
        path = self._agent_inbox_path(agent_id)
        if not path.exists():
            return []
        return json.loads(path.read_text(encoding="utf-8"))

    def _save_inbox(self, agent_id: str, inbox: List[str]) -> None:
        self._write_json(self._agent_inbox_path(agent_id), {"message_ids": inbox})

    def _load_inbox_ids(self, agent_id: str) -> List[str]:
        path = self._agent_inbox_path(agent_id)
        if not path.exists():
            return []
        payload = self._read_json(path)
        ids = payload.get("message_ids", [])
        return [str(item) for item in ids if str(item).strip()]

    def _append_inbox(self, agent_id: str, message_id: str) -> None:
        inbox = self._load_inbox_ids(agent_id)
        if message_id not in inbox:
            inbox.append(message_id)
        self._write_json(self._agent_inbox_path(agent_id), {"message_ids": inbox})

    def _remove_from_inbox(self, agent_id: str, message_id: str) -> None:
        inbox = [item for item in self._load_inbox_ids(agent_id) if item != message_id]
        self._write_json(self._agent_inbox_path(agent_id), {"message_ids": inbox})

    def _append_history(self, agent_id: str, event: Dict[str, Any]) -> None:
        path = self._agent_history_path(agent_id)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")

    def _append_context_event(self, context_id: str, event: Dict[str, Any]) -> None:
        path = self._context_events_path(context_id)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")

    def _load_context_summary(self, context_id: str) -> Dict[str, Any]:
        path = self._context_summary_path(context_id)
        if not path.exists():
            summary = {
                "context_id": context_id,
                "summary": "",
                "key_facts": [],
                "open_tasks": [],
                "tool_state": [],
                "handoff_notes": [],
                "recent_raw_events": [],
                "updated_at": _now_iso(),
            }
            self._write_json(path, summary)
            return summary
        return self._read_json(path)

    def load_message(self, message_id: str) -> Dict[str, Any]:
        return self._read_json(self._message_path(message_id))

    def save_message(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        self._write_json(self._message_path(str(payload["message_id"])), payload)
        return payload

    def load_task(self, task_id: str) -> Dict[str, Any]:
        return self._read_json(self._task_path(task_id))

    def save_task(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        self._write_json(self._task_path(str(payload["task_id"])), payload)
        return payload

    def list_messages(self, node_id: Optional[str] = None) -> List[Dict[str, Any]]:
        items: List[Dict[str, Any]] = []
        for path in sorted(self.paths.messages.glob("*.json")):
            payload = self._read_json(path)
            if node_id and payload.get("node_id") != node_id:
                continue
            items.append(payload)
        return items

    def list_tasks(self, node_id: Optional[str] = None) -> List[Dict[str, Any]]:
        items: List[Dict[str, Any]] = []
        for path in sorted(self.paths.tasks.glob("*.json")):
            payload = self._read_json(path)
            if node_id and payload.get("node_id") != node_id:
                continue
            items.append(payload)
        return items

    def create_channel_message(
        self,
        *,
        channel: str,
        node_id: str,
        to_agent: str,
        text: str,
        context_id: str = "",
        priority: str = "normal",
        payload: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        task_id = _new_id("task")
        message_id = _new_id("msg")
        context_key = context_id or f"{node_id}_{to_agent}"
        now = _now_iso()
        task = {
            "task_id": task_id,
            "context_id": context_key,
            "root_message_id": message_id,
            "node_id": node_id,
            "channel": channel,
            "origin_agent": "",
            "current_owner_agent": to_agent,
            "status": "running",
            "priority": priority,
            "message_ids": [message_id],
            "participants": [to_agent],
            "pending_replies": [],
            "final_response_message_id": None,
            "created_at": now,
            "updated_at": now,
        }
        message = {
            "message_id": message_id,
            "task_id": task_id,
            "context_id": context_key,
            "channel": channel,
            "node_id": node_id,
            "from_agent": "",
            "to_agent": to_agent,
            "message_type": "channel_message",
            "priority": priority,
            "status": "queued",
            "reply_to": None,
            "owner_agent": to_agent,
            "handoff_from": None,
            "handoff_note": {},
            "content": {"text": text, "payload": payload or {}},
            "created_at": now,
            "updated_at": now,
        }
        self.save_task(task)
        self.save_message(message)
        self._append_inbox(to_agent, message_id)
        self.record_event(
            agent_id=to_agent,
            context_id=context_key,
            task_id=task_id,
            message_id=message_id,
            node_id=node_id,
            event_type="channel_message",
            content={"channel": channel, "text": text},
        )
        return message

    def send_task(
        self,
        *,
        from_agent: str,
        to_agent: str,
        node_id: str,
        task_id: str,
        context_id: str,
        text: str,
        priority: str = "normal",
        payload: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        message_id = _new_id("msg")
        now = _now_iso()
        message = {
            "message_id": message_id,
            "task_id": task_id,
            "context_id": context_id,
            "channel": "",
            "node_id": node_id,
            "from_agent": from_agent,
            "to_agent": to_agent,
            "message_type": "task_request",
            "priority": priority,
            "status": "queued",
            "reply_to": None,
            "owner_agent": self.load_task(task_id).get("current_owner_agent", from_agent),
            "handoff_from": None,
            "handoff_note": {},
            "content": {"text": text, "payload": payload or {}},
            "created_at": now,
            "updated_at": now,
        }
        task = self.load_task(task_id)
        task["message_ids"].append(message_id)
        task["participants"] = sorted({*task.get("participants", []), from_agent, to_agent})
        task["pending_replies"].append(message_id)
        task["status"] = "waiting_reply"
        task["updated_at"] = now
        self.save_task(task)
        self.save_message(message)
        self._append_inbox(to_agent, message_id)
        self.record_event(
            agent_id=from_agent,
            context_id=context_id,
            task_id=task_id,
            message_id=message_id,
            node_id=node_id,
            event_type="task_dispatched",
            content={"to_agent": to_agent, "text": text, "priority": priority},
        )
        return message

    def reply_task(
        self,
        *,
        from_agent: str,
        reply_to_message_id: str,
        text: str,
        payload: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        parent = self.load_message(reply_to_message_id)
        task = self.load_task(parent["task_id"])
        now = _now_iso()
        message_id = _new_id("msg")
        reply_message = {
            "message_id": message_id,
            "task_id": parent["task_id"],
            "context_id": parent["context_id"],
            "channel": "",
            "node_id": parent["node_id"],
            "from_agent": from_agent,
            "to_agent": parent["from_agent"],
            "message_type": "task_reply",
            "priority": parent.get("priority", "normal"),
            "status": "queued" if parent.get("from_agent") else "replied",
            "reply_to": reply_to_message_id,
            "owner_agent": task.get("current_owner_agent", parent.get("owner_agent", "")),
            "handoff_from": None,
            "handoff_note": {},
            "content": {"text": text, "payload": payload or {}},
            "created_at": now,
            "updated_at": now,
        }
        parent["status"] = "replied"
        parent["updated_at"] = now
        self.save_message(parent)

        task["message_ids"].append(message_id)
        task["participants"] = sorted({*task.get("participants", []), from_agent})
        task["pending_replies"] = [item for item in task.get("pending_replies", []) if item != reply_to_message_id]
        task["status"] = "running" if task.get("pending_replies") else "running"
        task["updated_at"] = now
        self.save_task(task)
        self.save_message(reply_message)
        if parent.get("from_agent"):
            self._append_inbox(parent["from_agent"], message_id)
        self.record_event(
            agent_id=from_agent,
            context_id=parent["context_id"],
            task_id=parent["task_id"],
            message_id=message_id,
            node_id=parent["node_id"],
            event_type="task_reply_sent",
            content={"reply_to": reply_to_message_id, "text": text},
        )
        return reply_message

    def handoff_reply(
        self,
        *,
        from_agent: str,
        to_agent: str,
        task_id: str,
        handoff_note: Dict[str, Any],
    ) -> Dict[str, Any]:
        task = self.load_task(task_id)
        now = _now_iso()
        message_id = _new_id("msg")
        message = {
            "message_id": message_id,
            "task_id": task_id,
            "context_id": task["context_id"],
            "channel": task.get("channel", ""),
            "node_id": task["node_id"],
            "from_agent": from_agent,
            "to_agent": to_agent,
            "message_type": "reply_handoff",
            "priority": task.get("priority", "normal"),
            "status": "queued",
            "reply_to": task.get("root_message_id"),
            "owner_agent": to_agent,
            "handoff_from": from_agent,
            "handoff_note": handoff_note,
            "content": {"text": handoff_note.get("summary", ""), "payload": handoff_note},
            "created_at": now,
            "updated_at": now,
        }
        task["message_ids"].append(message_id)
        task["current_owner_agent"] = to_agent
        task["status"] = "handoff_in_progress"
        task["updated_at"] = now
        self.save_task(task)
        self.save_message(message)
        self._append_inbox(to_agent, message_id)
        self.record_event(
            agent_id=from_agent,
            context_id=task["context_id"],
            task_id=task_id,
            message_id=message_id,
            node_id=task["node_id"],
            event_type="reply_handoff_sent",
            content={"to_agent": to_agent, "handoff_note": handoff_note},
        )
        return message

    def claim_next_message(self, agent_id: str, node_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        inbox_ids = self._load_inbox_ids(agent_id)
        messages = []
        for message_id in inbox_ids:
            message = self.load_message(message_id)
            if node_id and message.get("node_id") != node_id:
                continue
            if message.get("status") not in {"queued", "dispatched"}:
                continue
            messages.append(message)
        if not messages:
            return None
        messages.sort(
            key=lambda item: (
                PRIORITY_ORDER.get(item.get("priority", "normal"), 1),
                item.get("created_at", ""),
            )
        )
        selected = messages[0]
        selected["status"] = "processing"
        selected["updated_at"] = _now_iso()
        self.save_message(selected)
        self._remove_from_inbox(agent_id, selected["message_id"])
        return selected

    def has_pending_messages(self, node_id: Optional[str] = None) -> bool:
        for message_file in self.paths.messages.glob("*.json"):
            message = self._read_json(message_file)
            if node_id and message.get("node_id") != node_id:
                continue
            if message.get("status") in {"queued", "dispatched"}:
                return True
        return False

    def mark_message_failed(self, message_id: str, error: str) -> Dict[str, Any]:
        message = self.load_message(message_id)
        message["status"] = "failed"
        message["updated_at"] = _now_iso()
        message.setdefault("content", {}).setdefault("payload", {})["error"] = error
        self.save_message(message)
        return message

    def complete_root_response(self, message_id: str, final_response: str) -> Dict[str, Any]:
        message = self.load_message(message_id)
        task = self.load_task(message["task_id"])
        now = _now_iso()
        message["status"] = "replied"
        message["updated_at"] = now
        self.save_message(message)
        final_message_id = _new_id("msg")
        final_message = {
            "message_id": final_message_id,
            "task_id": task["task_id"],
            "context_id": task["context_id"],
            "channel": task.get("channel", ""),
            "node_id": task["node_id"],
            "from_agent": task.get("current_owner_agent", message.get("to_agent", "")),
            "to_agent": "",
            "message_type": "task_reply",
            "priority": task.get("priority", "normal"),
            "status": "replied",
            "reply_to": message["message_id"],
            "owner_agent": task.get("current_owner_agent", ""),
            "handoff_from": None,
            "handoff_note": {},
            "content": {"text": final_response, "payload": {}},
            "created_at": now,
            "updated_at": now,
        }
        task["message_ids"].append(final_message_id)
        task["final_response_message_id"] = final_message_id
        task["status"] = "completed"
        task["updated_at"] = now
        self.save_task(task)
        self.save_message(final_message)
        self.record_event(
            agent_id=final_message["from_agent"] or message.get("to_agent", ""),
            context_id=task["context_id"],
            task_id=task["task_id"],
            message_id=final_message_id,
            node_id=task["node_id"],
            event_type="assistant_reply",
            content={"text": final_response},
        )
        return final_message

    def record_event(
        self,
        *,
        agent_id: str,
        context_id: str,
        task_id: str,
        message_id: str,
        node_id: str,
        event_type: str,
        content: Dict[str, Any],
    ) -> Dict[str, Any]:
        event = {
            "event_id": _new_id("evt"),
            "agent_id": agent_id,
            "node_id": node_id,
            "context_id": context_id,
            "task_id": task_id,
            "message_id": message_id,
            "event_type": event_type,
            "content": deepcopy(content),
            "created_at": _now_iso(),
        }
        if agent_id:
            self._append_history(agent_id, event)
        if context_id:
            self._append_context_event(context_id, event)
            self._refresh_context_summary(context_id)
        return event

    def _load_jsonl(self, path: Path) -> List[Dict[str, Any]]:
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

    def _refresh_context_summary(self, context_id: str) -> None:
        events = self._load_jsonl(self._context_events_path(context_id))
        recent = events[-20:]
        open_tasks: List[str] = []
        handoff_notes: List[Dict[str, Any]] = []
        tool_state: List[Dict[str, Any]] = []
        key_facts: List[str] = []
        for item in recent:
            event_type = item.get("event_type", "")
            content = item.get("content", {})
            if event_type == "task_dispatched":
                open_tasks.append(str(content.get("text", "")).strip())
            if event_type in {"reply_handoff_sent", "reply_handoff_received"}:
                handoff_notes.append(content)
            if event_type == "tool_result":
                tool_state.append(content)
            if event_type in {"assistant_reply", "task_reply_received"}:
                text = str(content.get("text", "")).strip()
                if text:
                    key_facts.append(text[:200])
        summary = {
            "context_id": context_id,
            "summary": f"context {context_id} has {len(events)} events recorded",
            "key_facts": key_facts[-10:],
            "open_tasks": open_tasks[-10:],
            "tool_state": tool_state[-10:],
            "handoff_notes": handoff_notes[-10:],
            "recent_raw_events": recent[-20:],
            "updated_at": _now_iso(),
        }
        self._write_json(self._context_summary_path(context_id), summary)

    def _estimate_tokens(self, text: str) -> int:
        return max(1, len(text) // 4)

    def maybe_compress_context(
        self,
        *,
        agent_id: str,
        context_id: str,
        max_tokens: int,
        recent_history_events: int,
    ) -> bool:
        history = self._load_jsonl(self._agent_history_path(agent_id))
        serialized = json.dumps(history, ensure_ascii=False)
        if self._estimate_tokens(serialized) <= max_tokens:
            return False
        summary = self._load_context_summary(context_id)
        recent = history[-recent_history_events:]
        summary["recent_raw_events"] = recent
        summary["summary"] = f"compressed history for {agent_id}; preserved {len(recent)} recent events"
        summary["updated_at"] = _now_iso()
        self._write_json(self._context_summary_path(context_id), summary)
        compressed_event = self.record_event(
            agent_id=agent_id,
            context_id=context_id,
            task_id="",
            message_id="",
            node_id="",
            event_type="context_compressed",
            content={"max_tokens": max_tokens, "kept_events": len(recent)},
        )
        kept_lines = [json.dumps(item, ensure_ascii=False) for item in recent]
        self._agent_history_path(agent_id).write_text("\n".join(kept_lines) + ("\n" if kept_lines else ""), encoding="utf-8")
        self._append_history(agent_id, compressed_event)
        summary["recent_raw_events"] = recent
        summary["summary"] = f"compressed history for {agent_id}; preserved {len(recent)} recent events"
        summary["updated_at"] = _now_iso()
        self._write_json(self._context_summary_path(context_id), summary)
        return True

    def build_agent_message_context(
        self,
        *,
        agent_id: str,
        current_message: Dict[str, Any],
        recent_history_events: int = 20,
    ) -> Dict[str, Any]:
        task = self.load_task(current_message["task_id"])
        context_id = current_message["context_id"]
        summary = self._load_context_summary(context_id)
        recent_history = self._load_jsonl(self._agent_history_path(agent_id))[-recent_history_events:]
        pending_children = []
        for message_id in task.get("pending_replies", []):
            child = self.load_message(message_id)
            if child.get("from_agent") == agent_id:
                pending_children.append(
                    {
                        "message_id": child["message_id"],
                        "to_agent": child.get("to_agent", ""),
                        "text": child.get("content", {}).get("text", ""),
                        "priority": child.get("priority", "normal"),
                    }
                )
        return {
            "current_message": current_message,
            "current_task": task,
            "reply_owner": task.get("current_owner_agent", ""),
            "channel_context": {
                "channel": current_message.get("channel", ""),
                "is_external": bool(current_message.get("channel")),
            },
            "handoff_context": current_message.get("handoff_note", {}) or {},
            "context_summary": summary,
            "recent_history": {
                "latest_summary": summary,
                "events": recent_history,
            },
            "pending_children": pending_children,
        }
