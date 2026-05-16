from __future__ import annotations

import glob
import json
import subprocess
from pathlib import Path
from typing import Any, Dict, List

from tool_base import BaseTool, ToolExecutionError, ToolResult
from tool_runtime import ToolRegistry


registry = ToolRegistry()
PROCESS_REGISTRY: Dict[str, subprocess.Popen[str]] = {}


def _require_runtime_bus(context: Any):
    bus = context.runtime.get("bus")
    if bus is None:
        raise ToolExecutionError("runtime bus is not available in tool context")
    return bus


def _require_runtime_value(context: Any, key: str) -> Any:
    value = context.runtime.get(key)
    if value in (None, ""):
        raise ToolExecutionError(f"runtime context missing required field: {key}")
    return value


def _runtime_agent_capability(context: Any) -> Dict[str, Any]:
    capability = context.runtime.get("agent_capability", {})
    return capability if isinstance(capability, dict) else {}


def _resolve_path(raw_path: str, workspace_dir: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return Path(workspace_dir or ".") / path


def _deep_merge_dict(base: Dict[str, Any], updates: Dict[str, Any]) -> Dict[str, Any]:
    merged = dict(base)
    for key, value in updates.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge_dict(merged[key], value)
            continue
        merged[key] = value
    return merged


@registry.register
class EchoTool(BaseTool):
    name = "echo"
    description = "Return the provided text for connectivity and workflow testing."
    input_schema = {
        "type": "object",
        "properties": {
            "text": {"type": "string", "description": "Text to echo back"},
        },
        "required": ["text"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        text = str(params["text"])
        return ToolResult(ok=True, tool_name=self.name, content=text, data={"text": text})


@registry.register
class ReadFileTool(BaseTool):
    name = "read"
    description = "Read UTF-8 text file contents from the current workspace."
    input_schema = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Relative or absolute file path"},
        },
        "required": ["path"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        target = _resolve_path(str(params["path"]), self.context.workspace_dir)
        if not target.exists() or not target.is_file():
            raise ToolExecutionError(f"file not found: {target}")
        try:
            content = target.read_text(encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to read file: {exc}") from exc
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=content,
            data={"path": str(target), "size": len(content)},
        )

@registry.register
class WriteFileTool(BaseTool):
    name = "write"
    description = "Create or overwrite a UTF-8 text file in the current workspace."
    input_schema = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Relative or absolute file path"},
            "content": {"type": "string", "description": "Full file content to write"},
        },
        "required": ["path", "content"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        target = _resolve_path(str(params["path"]), self.context.workspace_dir)
        target.parent.mkdir(parents=True, exist_ok=True)
        content = str(params["content"])
        try:
            target.write_text(content, encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to write file: {exc}") from exc
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"wrote {target}",
            data={"path": str(target), "size": len(content)},
        )


@registry.register
class EditFileTool(BaseTool):
    name = "edit"
    description = "Apply a precise string replacement inside a UTF-8 text file."
    input_schema = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Relative or absolute file path"},
            "old_text": {"type": "string", "description": "Exact text to replace"},
            "new_text": {"type": "string", "description": "Replacement text"},
            "replace_all": {"type": "boolean", "description": "Whether to replace all occurrences"},
        },
        "required": ["path", "old_text", "new_text"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        target = _resolve_path(str(params["path"]), self.context.workspace_dir)
        if not target.exists() or not target.is_file():
            raise ToolExecutionError(f"file not found: {target}")

        old_text = str(params["old_text"])
        new_text = str(params["new_text"])
        replace_all = bool(params.get("replace_all", False))

        try:
            content = target.read_text(encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to read file for edit: {exc}") from exc

        if old_text not in content:
            raise ToolExecutionError("old_text not found in target file")

        updated = content.replace(old_text, new_text) if replace_all else content.replace(old_text, new_text, 1)
        try:
            target.write_text(updated, encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to write edited file: {exc}") from exc

        replacement_count = content.count(old_text) if replace_all else 1
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"edited {target}",
            data={"path": str(target), "replacements": replacement_count},
        )


@registry.register
class ApplyPatchTool(BaseTool):
    name = "apply_patch"
    description = "Apply a simple file patch by replacing full content or one exact segment."
    input_schema = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Relative or absolute file path"},
            "content": {"type": "string", "description": "Optional full replacement content"},
            "old_text": {"type": "string", "description": "Optional exact text to replace"},
            "new_text": {"type": "string", "description": "Replacement for old_text"},
        },
        "required": ["path"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        target = _resolve_path(str(params["path"]), self.context.workspace_dir)
        target.parent.mkdir(parents=True, exist_ok=True)

        full_content = params.get("content")
        old_text = params.get("old_text")
        new_text = params.get("new_text", "")

        if full_content is not None:
            try:
                target.write_text(str(full_content), encoding="utf-8")
            except OSError as exc:
                raise ToolExecutionError(f"failed to apply full patch: {exc}") from exc
            return ToolResult(
                ok=True,
                tool_name=self.name,
                content=f"patched {target}",
                data={"path": str(target), "mode": "replace_file"},
            )

        if old_text is None:
            raise ToolExecutionError("apply_patch requires either `content` or `old_text` + `new_text`")

        if not target.exists() or not target.is_file():
            raise ToolExecutionError(f"file not found: {target}")

        try:
            content = target.read_text(encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to read file for patch: {exc}") from exc

        if str(old_text) not in content:
            raise ToolExecutionError("patch old_text not found in target file")

        updated = content.replace(str(old_text), str(new_text), 1)
        try:
            target.write_text(updated, encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to write patched file: {exc}") from exc

        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"patched {target}",
            data={"path": str(target), "mode": "replace_segment"},
        )


@registry.register
class ListDirectoryTool(BaseTool):
    name = "ls"
    description = "List files and directories under a target path."
    input_schema = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Directory path", "default": "."},
        },
        "required": [],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        raw_path = str(params.get("path", "."))
        target = _resolve_path(raw_path, self.context.workspace_dir)
        if not target.exists() or not target.is_dir():
            raise ToolExecutionError(f"directory not found: {target}")

        items: List[Dict[str, Any]] = []
        for child in sorted(target.iterdir(), key=lambda item: (not item.is_dir(), item.name.lower())):
            items.append(
                {
                    "name": child.name,
                    "type": "dir" if child.is_dir() else "file",
                }
            )

        content = "\n".join(f"{item['type']}: {item['name']}" for item in items)
        return ToolResult(ok=True, tool_name=self.name, content=content, data={"path": str(target), "items": items})

@registry.register
class FindFilesTool(BaseTool):
    name = "find"
    description = "Find files with a glob pattern under the current workspace."
    input_schema = {
        "type": "object",
        "properties": {
            "pattern": {"type": "string", "description": "Glob pattern such as **/*.py"},
        },
        "required": ["pattern"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        workspace_dir = self.context.workspace_dir or "."
        pattern = str(params["pattern"])
        matches = sorted(glob.glob(str(Path(workspace_dir) / pattern), recursive=True))
        content = "\n".join(matches)
        return ToolResult(ok=True, tool_name=self.name, content=content, data={"matches": matches, "count": len(matches)})


@registry.register
class GrepTool(BaseTool):
    name = "grep"
    description = "Search text files under the current workspace for a plain-text pattern."
    input_schema = {
        "type": "object",
        "properties": {
            "pattern": {"type": "string", "description": "Plain-text pattern to search"},
            "glob": {"type": "string", "description": "Optional glob filter such as **/*.py", "default": "**/*"},
        },
        "required": ["pattern"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        workspace_dir = self.context.workspace_dir or "."
        pattern = str(params["pattern"])
        file_glob = str(params.get("glob", "**/*"))
        matches: List[Dict[str, Any]] = []

        for candidate in glob.glob(str(Path(workspace_dir) / file_glob), recursive=True):
            path = Path(candidate)
            if not path.is_file():
                continue
            try:
                content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue

            for lineno, line in enumerate(content.splitlines(), start=1):
                if pattern in line:
                    matches.append({"path": str(path), "line": lineno, "text": line})

        output = "\n".join(f"{item['path']}:{item['line']}: {item['text']}" for item in matches)
        return ToolResult(ok=True, tool_name=self.name, content=output, data={"matches": matches, "count": len(matches)})


@registry.register
class ExecTool(BaseTool):
    name = "exec"
    description = "Run a shell command in the current workspace."
    input_schema = {
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "Command string to execute"},
            "timeout_ms": {"type": "integer", "description": "Optional timeout in milliseconds"},
        },
        "required": ["command"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        command = str(params["command"])
        timeout_ms = params.get("timeout_ms", 10000)
        cwd = self.context.workspace_dir or None

        try:
            completed = subprocess.run(
                command,
                cwd=cwd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                shell=True,
                timeout=float(timeout_ms) / 1000.0,
            )
        except subprocess.TimeoutExpired as exc:
            raise ToolExecutionError(f"command timed out after {timeout_ms} ms") from exc
        except OSError as exc:
            raise ToolExecutionError(f"failed to execute command: {exc}") from exc

        stdout_text = (completed.stdout or "").strip()
        stderr_text = (completed.stderr or "").strip()
        content = stdout_text
        if stderr_text:
            content = f"{content}\n{stderr_text}".strip()

        return ToolResult(
            ok=completed.returncode == 0,
            tool_name=self.name,
            content=content,
            data={"returncode": completed.returncode, "cwd": cwd or ""},
            error="" if completed.returncode == 0 else f"command exited with code {completed.returncode}",
        )


@registry.register
class ProcessTool(BaseTool):
    name = "process"
    description = "Manage background commands started by this tool runtime."
    input_schema = {
        "type": "object",
        "properties": {
            "action": {"type": "string", "description": "One of: start, poll, kill, list"},
            "command": {"type": "string", "description": "Command to start when action=start"},
            "process_id": {"type": "string", "description": "Background process id for poll/kill"},
        },
        "required": ["action"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        action = str(params["action"]).strip().lower()
        if action == "start":
            return self._start_process(str(params.get("command", "")))
        if action == "poll":
            return self._poll_process(str(params.get("process_id", "")))
        if action == "kill":
            return self._kill_process(str(params.get("process_id", "")))
        if action == "list":
            return self._list_processes()
        raise ToolExecutionError(f"unsupported process action: {action}")

    def _start_process(self, command: str) -> ToolResult:
        if not command:
            raise ToolExecutionError("process start requires `command`")
        cwd = self.context.workspace_dir or None
        try:
            proc = subprocess.Popen(
                command,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                text=True,
                encoding="utf-8",
                errors="replace",
                shell=True,
            )
        except OSError as exc:
            raise ToolExecutionError(f"failed to start background process: {exc}") from exc

        process_id = str(proc.pid)
        PROCESS_REGISTRY[process_id] = proc
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"started process {process_id}",
            data={"process_id": process_id, "command": command},
        )

    def _poll_process(self, process_id: str) -> ToolResult:
        proc = PROCESS_REGISTRY.get(process_id)
        if proc is None:
            raise ToolExecutionError(f"unknown process id: {process_id}")

        returncode = proc.poll()
        status = "running" if returncode is None else "finished"
        stdout = ""
        stderr = ""
        if returncode is not None:
            out, err = proc.communicate()
            stdout = out.strip()
            stderr = err.strip()
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=status,
            data={
                "process_id": process_id,
                "status": status,
                "returncode": returncode,
                "stdout": stdout,
                "stderr": stderr,
            },
        )

    def _kill_process(self, process_id: str) -> ToolResult:
        proc = PROCESS_REGISTRY.get(process_id)
        if proc is None:
            raise ToolExecutionError(f"unknown process id: {process_id}")
        proc.kill()
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"killed process {process_id}",
            data={"process_id": process_id},
        )

    def _list_processes(self) -> ToolResult:
        items = []
        for process_id, proc in PROCESS_REGISTRY.items():
            items.append(
                {
                    "process_id": process_id,
                    "status": "running" if proc.poll() is None else "finished",
                }
            )
        content = "\n".join(f"{item['process_id']}: {item['status']}" for item in items)
        return ToolResult(ok=True, tool_name=self.name, content=content, data={"processes": items})


@registry.register
class AgentConfigUpdateTool(BaseTool):
    name = "agent_config_update"
    description = "Update another agent's JSON runtime config by deep-merging the provided fields."
    input_schema = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Relative or absolute JSON config file path"},
            "updates": {"type": "object", "description": "Nested fields to merge into the target config"},
        },
        "required": ["path", "updates"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        target = _resolve_path(str(params["path"]), self.context.workspace_dir)
        updates = params["updates"]
        if not isinstance(updates, dict):
            raise ToolExecutionError("agent_config_update requires `updates` to be an object")
        if target.suffix.lower() != ".json":
            raise ToolExecutionError("agent_config_update only supports .json files")
        if not target.exists() or not target.is_file():
            raise ToolExecutionError(f"config file not found: {target}")

        try:
            current = json.loads(target.read_text(encoding="utf-8"))
        except OSError as exc:
            raise ToolExecutionError(f"failed to read config file: {exc}") from exc
        except json.JSONDecodeError as exc:
            raise ToolExecutionError(f"invalid json config: {exc}") from exc

        if not isinstance(current, dict):
            raise ToolExecutionError("agent_config_update only supports top-level JSON objects")

        updated = _deep_merge_dict(current, updates)

        try:
            target.write_text(json.dumps(updated, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as exc:
            raise ToolExecutionError(f"failed to write config file: {exc}") from exc

        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"updated agent config {target}",
            data={"path": str(target), "updated_keys": sorted(updates.keys())},
        )


@registry.register
class AgentSendTaskTool(BaseTool):
    name = "agent_send_task"
    description = "Send a task_request message to another agent through the runtime bus."
    input_schema = {
        "type": "object",
        "properties": {
            "to_agent": {"type": "string", "description": "Target agent id"},
            "text": {"type": "string", "description": "Task text"},
            "priority": {"type": "string", "description": "high / normal / low", "default": "normal"},
            "payload": {"type": "object", "description": "Optional structured payload"},
        },
        "required": ["to_agent", "text"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        bus = _require_runtime_bus(self.context)
        from_agent = _require_runtime_value(self.context, "agent_id")
        node_id = _require_runtime_value(self.context, "node_id")
        task_id = _require_runtime_value(self.context, "task_id")
        context_id = _require_runtime_value(self.context, "context_id")
        capability = _runtime_agent_capability(self.context)
        if not bool(capability.get("can_delegate", False)):
            raise ToolExecutionError(f"agent `{from_agent}` is not allowed to delegate tasks")
        allowed_targets = capability.get("allowed_targets", [])
        if not isinstance(allowed_targets, list):
            allowed_targets = []
        target_agent = str(params["to_agent"])
        normalized_targets = [str(item).strip() for item in allowed_targets if str(item).strip()]
        if "all" not in normalized_targets and target_agent not in normalized_targets:
            raise ToolExecutionError(f"agent `{from_agent}` is not allowed to delegate to `{target_agent}`")

        message = bus.send_task(
            from_agent=str(from_agent),
            to_agent=target_agent,
            node_id=str(node_id),
            task_id=str(task_id),
            context_id=str(context_id),
            text=str(params["text"]),
            priority=str(params.get("priority", "normal") or "normal"),
            payload=params.get("payload", {}) if isinstance(params.get("payload", {}), dict) else {},
        )
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"sent task to {message['to_agent']}",
            data={"message_id": message["message_id"], "to_agent": message["to_agent"]},
        )


@registry.register
class AgentReplyTaskTool(BaseTool):
    name = "agent_reply_task"
    description = (
        "Send a task_reply message for the current task_request. "
        "If this reply will be shown to the end user, write it as direct user-facing dialogue only. "
        "Focus on responding to the user's current need, and do not add workflow reports, process explanations, or other irrelevant content."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "text": {"type": "string", "description": "Reply text"},
            "payload": {"type": "object", "description": "Optional structured payload"},
        },
        "required": ["text"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        bus = _require_runtime_bus(self.context)
        from_agent = _require_runtime_value(self.context, "agent_id")
        current_message_id = _require_runtime_value(self.context, "current_message_id")
        message = bus.reply_task(
            from_agent=str(from_agent),
            reply_to_message_id=str(current_message_id),
            text=str(params["text"]),
            payload=params.get("payload", {}) if isinstance(params.get("payload", {}), dict) else {},
        )
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"replied to {current_message_id}",
            data={"message_id": message["message_id"], "reply_to": current_message_id},
        )


@registry.register
class AgentHandoffReplyTool(BaseTool):
    name = "agent_handoff_reply"
    description = (
        "Transfer the current reply ownership to another agent. "
        "This is an internal workflow action, not a user-facing reply. "
        "Do not use it to talk to the user. User-facing content should stay focused on helping the user, not on reporting internal process details."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "to_agent": {"type": "string", "description": "Target agent that should take over the reply"},
            "reason": {"type": "string", "description": "Why the handoff happens"},
            "summary": {"type": "string", "description": "What has been done so far"},
            "suggested_reply_style": {"type": "string", "description": "Suggested reply style"},
            "risks": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Known risks or caveats",
            },
        },
        "required": ["to_agent", "reason", "summary", "suggested_reply_style"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        bus = _require_runtime_bus(self.context)
        from_agent = _require_runtime_value(self.context, "agent_id")
        task_id = _require_runtime_value(self.context, "task_id")
        handoff_note = {
            "reason": str(params["reason"]),
            "summary": str(params["summary"]),
            "suggested_reply_style": str(params["suggested_reply_style"]),
            "risks": [str(item) for item in params.get("risks", []) if str(item).strip()],
        }
        message = bus.handoff_reply(
            from_agent=str(from_agent),
            to_agent=str(params["to_agent"]),
            task_id=str(task_id),
            handoff_note=handoff_note,
        )
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"reply ownership handed to {message['to_agent']}",
            data={"message_id": message["message_id"], "to_agent": message["to_agent"]},
        )


@registry.register
class AgentRequestPermissionChangeTool(BaseTool):
    name = "agent_request_permission_change"
    description = "Request a temporary or persistent permission change for another agent."
    input_schema = {
        "type": "object",
        "properties": {
            "target_agent": {"type": "string", "description": "Target agent id"},
            "scope": {"type": "string", "description": "temporary or persistent"},
            "changes": {"type": "object", "description": "Permission changes to apply"},
            "reason": {"type": "string", "description": "Reason for the change"},
        },
        "required": ["target_agent", "scope", "changes", "reason"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        bus = _require_runtime_bus(self.context)
        requester = str(_require_runtime_value(self.context, "agent_id"))
        task_id = str(_require_runtime_value(self.context, "task_id"))
        context_id = str(_require_runtime_value(self.context, "context_id"))
        node_id = str(_require_runtime_value(self.context, "node_id"))
        capability = _runtime_agent_capability(self.context)
        scope = str(params["scope"]).strip().lower()
        changes = params.get("changes", {})
        if scope not in {"temporary", "persistent"}:
            raise ToolExecutionError("scope must be `temporary` or `persistent`")
        if not isinstance(changes, dict):
            raise ToolExecutionError("changes must be an object")

        if scope == "temporary" and not bool(capability.get("can_request_temporary_permission_change", False)):
            raise ToolExecutionError(f"agent `{requester}` is not allowed to request temporary permission changes")
        if scope == "persistent" and not bool(capability.get("can_request_persistent_permission_change", False)):
            raise ToolExecutionError(f"agent `{requester}` is not allowed to request persistent permission changes")

        target_agent = str(params["target_agent"]).strip()
        reason = str(params["reason"]).strip()
        session_permissions = self.context.runtime.get("session_permissions", {})
        config_path_map = self.context.runtime.get("agent_config_path_map", {})
        bus.record_event(
            agent_id=requester,
            context_id=context_id,
            task_id=task_id,
            message_id="",
            node_id=node_id,
            event_type="permission_change_requested",
            content={
                "target_agent": target_agent,
                "scope": scope,
                "changes": changes,
                "reason": reason,
            },
        )

        if scope == "temporary":
            task_permissions = session_permissions.setdefault(task_id, {})
            current = task_permissions.setdefault(target_agent, {})
            current.update(changes)
        else:
            config_path = config_path_map.get(target_agent)
            if not config_path:
                raise ToolExecutionError(f"config path not found for target agent `{target_agent}`")
            target = Path(str(config_path))
            if not target.exists():
                raise ToolExecutionError(f"target config file not found: {target}")
            try:
                current_payload = json.loads(target.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                raise ToolExecutionError(f"failed to load target agent config: {exc}") from exc
            target_capability = current_payload.get("agent_capability", {})
            if not isinstance(target_capability, dict):
                target_capability = {}
            target_capability.update(changes)
            current_payload["agent_capability"] = target_capability
            try:
                target.write_text(json.dumps(current_payload, ensure_ascii=False, indent=2), encoding="utf-8")
            except OSError as exc:
                raise ToolExecutionError(f"failed to write target agent config: {exc}") from exc

        bus.record_event(
            agent_id=requester,
            context_id=context_id,
            task_id=task_id,
            message_id="",
            node_id=node_id,
            event_type="permission_change_applied",
            content={
                "target_agent": target_agent,
                "scope": scope,
                "changes": changes,
                "reason": reason,
            },
        )
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content=f"{scope} permission change applied for {target_agent}",
            data={"target_agent": target_agent, "scope": scope, "changes": changes},
        )


@registry.register
class AgentRequestFinishNodeTool(BaseTool):
    name = "agent_request_finish_node"
    description = (
        "You have the ability to request finishing the current node. "
        "Call this only when you judge the current stage work is complete and the node outputs are already written "
        "to the output directory. Provide a single `message` describing why the node can finish, what was completed, "
        "any remaining risks, and what the next node should know. Runtime will validate the request before the node "
        "is actually marked done."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "message": {
                "type": "string",
                "description": (
                    "A completion request note explaining why the current node can finish, what was completed, "
                    "any remaining risks, and what the next node should know."
                ),
            },
        },
        "required": ["message"],
    }

    def execute(self, params: Dict[str, Any]) -> ToolResult:
        bus = _require_runtime_bus(self.context)
        agent_id = str(_require_runtime_value(self.context, "agent_id"))
        node_id = str(_require_runtime_value(self.context, "node_id"))
        task_id = str(_require_runtime_value(self.context, "task_id"))
        context_id = str(_require_runtime_value(self.context, "context_id"))
        current_message_id = str(_require_runtime_value(self.context, "current_message_id"))
        message = str(params["message"]).strip()
        if not message:
            raise ToolExecutionError("message must not be empty")

        request_payload = {
            "agent_id": agent_id,
            "node_id": node_id,
            "task_id": task_id,
            "context_id": context_id,
            "current_message_id": current_message_id,
            "message": message,
        }
        self.context.runtime["node_finish_request"] = request_payload
        bus.record_event(
            agent_id=agent_id,
            context_id=context_id,
            task_id=task_id,
            message_id=current_message_id,
            node_id=node_id,
            event_type="node_finish_requested",
            content={"message": message},
        )
        return ToolResult(
            ok=True,
            tool_name=self.name,
            content="node finish request submitted",
            data={"node_id": node_id, "message": message},
        )
