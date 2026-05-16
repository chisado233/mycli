from __future__ import annotations

import json
import sys
from collections import deque
from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


CURRENT_DIR = Path(__file__).resolve().parent
SRC_DIR = CURRENT_DIR.parent
AGENT_DIR = SRC_DIR / "agent"

for path in (CURRENT_DIR, SRC_DIR, AGENT_DIR):
    if str(path) not in sys.path:
        sys.path.append(str(path))

from agent import agent as AgentRunner  # noqa: E402
from runtime_bus import RuntimeBus  # noqa: E402
from session_store import SessionContextStore  # noqa: E402


@dataclass
class AgentRunRecord:
    agent_id: str
    role: str
    prompt: str
    result: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "role": self.role,
            "prompt": self.prompt,
            "result": self.result,
        }


@dataclass
class NodeRunRecord:
    node_id: str
    node_dir: str
    state: str
    leader_id: str
    worker_ids: List[str] = field(default_factory=list)
    inputs: List[str] = field(default_factory=list)
    upstream_artifacts: List[str] = field(default_factory=list)
    agent_runs: List[AgentRunRecord] = field(default_factory=list)
    generated_files: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "node_id": self.node_id,
            "node_dir": self.node_dir,
            "state": self.state,
            "leader_id": self.leader_id,
            "worker_ids": self.worker_ids,
            "inputs": self.inputs,
            "upstream_artifacts": self.upstream_artifacts,
            "agent_runs": [item.to_dict() for item in self.agent_runs],
            "generated_files": self.generated_files,
        }


class runtime:
    """
    最小可运行的 workflow runtime。

    当前版本聚焦两件事：
    1. 节点串行调度
    2. 节点内主从协作

    它不会尝试实现完整的事件系统或通用 DAG 执行器，而是先让
    `workspace/agent_workflow` 模板能够从 node_1 跑到 node_2。
    """

    def __init__(
        self,
        workflow_path: str,
        llm_overrides: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.workflow_path = Path(workflow_path)
        self.workflow_dir = self.workflow_path.parent
        self.workspace_root = self.workflow_dir.parent
        self.llm_overrides = llm_overrides or {}

        self.workflow = self._load_json(self.workflow_path)
        self.nodes = self.workflow.get("nodes", [])
        self.node_map = {
            str(node.get("id", "")).strip(): node
            for node in self.nodes
            if isinstance(node, dict) and str(node.get("id", "")).strip()
        }
        self.id_map: Dict[str, List[str]] = {}
        for node_id, next_nodes in (self.workflow.get("id_map", {}) or {}).items():
            if node_id not in self.node_map:
                continue
            self.id_map[node_id] = [item for item in next_nodes if item in self.node_map]

        self.reverse_edges = self._build_reverse_edges()
        self.execution_order = self._resolve_execution_order()
        self.state: Dict[str, str] = {node_id: "pending" for node_id in self.node_map}
        self.execution_log: List[Dict[str, Any]] = []
        self.log_path = self.workflow_dir / "runtime_execution.log"
        self.trace_md_path = self.workflow_dir / "runtime_llm_trace.md"
        self.dialogue_log_path = self.workflow_dir / "dialogue_log.md"
        self.bus_policy = self._load_bus_policy()
        self.context_policy = self._load_context_policy()
        self.channel_routing = self.workflow.get("channel_routing", {}) if isinstance(self.workflow.get("channel_routing"), dict) else {}
        self.bus = RuntimeBus(str(self.workflow_dir), policy=self.bus_policy) if self.bus_policy.get("enabled", True) else None
        self.session_permissions: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self.node_finish_requests: Dict[str, Dict[str, Any]] = {}
        self.session_store = SessionContextStore(str(self.workflow_dir))

    def _load_json(self, path: Path) -> Dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))

    def _build_reverse_edges(self) -> Dict[str, List[str]]:
        reverse_edges: Dict[str, List[str]] = {node_id: [] for node_id in self.node_map}
        for source_node, target_nodes in self.id_map.items():
            for target_node in target_nodes:
                reverse_edges.setdefault(target_node, []).append(source_node)
        return reverse_edges

    def _load_bus_policy(self) -> Dict[str, Any]:
        policy = self.workflow.get("bus_policy", {}) if isinstance(self.workflow.get("bus_policy"), dict) else {}
        defaults = {
            "enabled": True,
            "message_types": ["task_request", "task_reply", "reply_handoff"],
            "priority_levels": ["high", "normal", "low"],
        }
        defaults.update(policy)
        return defaults

    def _load_context_policy(self) -> Dict[str, Any]:
        policy = self.workflow.get("context_policy", {}) if isinstance(self.workflow.get("context_policy"), dict) else {}
        compression = policy.get("compression", {}) if isinstance(policy.get("compression", {}), dict) else {}
        return {
            "compression": {
                "enabled": bool(compression.get("enabled", True)),
                "max_tokens": int(compression.get("max_tokens", 80000) or 80000),
            },
            "recent_history_events": int(policy.get("recent_history_events", 20) or 20),
        }

    def _resolve_execution_order(self) -> List[str]:
        indegree = {node_id: len(self.reverse_edges.get(node_id, [])) for node_id in self.node_map}
        queue = deque(sorted(node_id for node_id, count in indegree.items() if count == 0))
        order: List[str] = []

        while queue:
            node_id = queue.popleft()
            order.append(node_id)
            for target_node in self.id_map.get(node_id, []):
                indegree[target_node] -= 1
                if indegree[target_node] == 0:
                    queue.append(target_node)

        if len(order) == len(self.node_map):
            return order

        missing = [node_id for node_id in self.node_map if node_id not in order]
        return order + missing

    def _resolve_node_dir(self, node_id: str) -> Path:
        candidates = [self.workflow_dir / "nodes" / node_id]
        if node_id.startswith("node_"):
            candidates.append(self.workflow_dir / "nodes" / f"node{node_id.split('_', 1)[1]}")
        if node_id.startswith("node") and "_" not in node_id and len(node_id) > 4:
            suffix = node_id[4:]
            candidates.append(self.workflow_dir / "nodes" / f"node_{suffix}")

        for candidate in candidates:
            if candidate.exists():
                return candidate
        return candidates[0]

    def _resolve_agent_config_path(self, raw_path: str) -> Path:
        raw = Path(raw_path)
        candidates = []
        if raw.is_absolute():
            candidates.append(raw)
        else:
            candidates.extend(
                [
                    self.workspace_root / raw_path,
                    self.workflow_dir / raw_path,
                    self.workflow_path.parent / raw_path,
                ]
            )
        for candidate in candidates:
            if candidate.exists():
                return candidate
        return candidates[0]

    def _load_agent_config(self, config_path: Path) -> Dict[str, Any]:
        payload = self._load_json(config_path)
        llm_config = payload.get("llm", {})
        if isinstance(llm_config, dict):
            if "openclaw_config_path" not in llm_config and "config_path" in llm_config:
                llm_config["openclaw_config_path"] = llm_config["config_path"]
            llm_config.update(self.llm_overrides)
            payload["llm"] = llm_config
        payload["workspace"] = str(self.workspace_root)
        return payload

    def _agent_capability(self, config: Dict[str, Any]) -> Dict[str, Any]:
        payload = config.get("agent_capability", {})
        return payload if isinstance(payload, dict) else {}

    def _effective_agent_capability(self, config: Dict[str, Any], agent_id: str, task_id: str) -> Dict[str, Any]:
        capability = deepcopy(self._agent_capability(config))
        task_permissions = self.session_permissions.get(task_id, {})
        if isinstance(task_permissions.get(agent_id), dict):
            capability.update(task_permissions[agent_id])
        return capability

    def _read_text_file(self, path: Path) -> str:
        try:
            return path.read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    def _log(self, event: str, **details: Any) -> None:
        payload = {
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "event": event,
            "details": details,
        }
        self.execution_log.append(payload)

    def _collect_node_input_files(self, node_dir: Path) -> List[Path]:
        shared_files = [self.workflow_path, self.workflow_dir / "agent_workflow_info.md"]
        input_dir = node_dir / "input"
        input_files: List[Path] = []
        for path in shared_files:
            if path.exists() and path.is_file():
                input_files.append(path)
        if input_dir.exists():
            input_files.extend(sorted(path for path in input_dir.iterdir() if path.is_file()))
        return input_files

    def _collect_upstream_files(self, node_id: str) -> List[Path]:
        files: List[Path] = []
        for upstream_node in self.reverse_edges.get(node_id, []):
            output_dir = self._resolve_node_dir(upstream_node) / "output"
            if not output_dir.exists():
                continue
            files.extend(sorted(path for path in output_dir.iterdir() if path.is_file()))
        return files

    def _node_relationships(self, node_payload: Dict[str, Any]) -> Dict[str, Dict[str, List[str]]]:
        relationships = node_payload.get("agent_relationship", {})
        return relationships if isinstance(relationships, dict) else {}

    def _resolve_leader_id(self, node_payload: Dict[str, Any]) -> str:
        agent_ids = [str(item.get("id", "")).strip() for item in node_payload.get("agent", []) if isinstance(item, dict)]
        relationships = self._node_relationships(node_payload)

        for agent_id in agent_ids:
            superior = relationships.get(agent_id, {}).get("Superior", [])
            if not superior:
                return agent_id
        return agent_ids[0] if agent_ids else ""

    def _build_worker_prompt(
        self,
        global_task: str,
        node_payload: Dict[str, Any],
        worker_id: str,
        node_inputs: Dict[str, str],
    ) -> str:
        input_sections = "\n\n".join(
            f"[{path}]\n{content}" for path, content in node_inputs.items()
        ) or "No input files were loaded."
        return (
            f"Global task:\n{global_task}\n\n"
            f"Current node: {node_payload.get('id', '')}\n"
            f"Node description: {node_payload.get('description', '')}\n"
            f"You are worker `{worker_id}` inside a leader-worker collaboration.\n\n"
            "Please produce a concise structured analysis with these sections:\n"
            "1. Key facts\n2. Suggested deliverables\n3. Risks or gaps\n\n"
            f"Node input materials:\n{input_sections}"
        )

    def _build_leader_prompt(
        self,
        global_task: str,
        node_payload: Dict[str, Any],
        leader_id: str,
        node_inputs: Dict[str, str],
        upstream_inputs: Dict[str, str],
        worker_outputs: Dict[str, str],
        next_nodes: List[str],
    ) -> str:
        node_input_text = "\n\n".join(
            f"[{path}]\n{content}" for path, content in node_inputs.items()
        ) or "No node-local inputs were loaded."
        upstream_text = "\n\n".join(
            f"[{path}]\n{content}" for path, content in upstream_inputs.items()
        ) or "No upstream artifacts were loaded."
        worker_text = "\n\n".join(
            f"[{worker_id}]\n{content}" for worker_id, content in worker_outputs.items()
        ) or "No worker output was collected."
        next_nodes_text = ", ".join(next_nodes) if next_nodes else "no downstream nodes"

        return (
            f"Global task:\n{global_task}\n\n"
            f"Current node: {node_payload.get('id', '')}\n"
            f"Node description: {node_payload.get('description', '')}\n"
            f"You are leader `{leader_id}`.\n"
            f"Downstream nodes: {next_nodes_text}\n\n"
            "Please return a concise node summary with these sections:\n"
            "1. Node objective\n2. What this node produced\n3. Handoff notes\n\n"
            f"Node input materials:\n{node_input_text}\n\n"
            f"Upstream artifacts:\n{upstream_text}\n\n"
            f"Worker outputs:\n{worker_text}"
        )

    def _run_agent(self, agent_id: str, config_path: Path, prompt: str, role: str) -> AgentRunRecord:
        config = self._load_agent_config(config_path)
        llm_config = config.get("llm", {})
        self._log(
            "agent_started",
            agent_id=agent_id,
            role=role,
            config_path=str(config_path),
            workspace=config.get("workspace", ""),
            provider=llm_config.get("provider", ""),
            model=llm_config.get("model", ""),
            prompt_length=len(prompt),
        )
        runner = AgentRunner(config_path=str(config_path), config=config)
        result = runner.agent_loop(prompt)
        final_response = result.get("final_response") or result.get("error", "")
        self._log(
            "agent_finished",
            agent_id=agent_id,
            role=role,
            ok=result.get("ok", False),
            finish_reason=result.get("finish_reason", ""),
            response_preview=final_response[:200],
        )
        return AgentRunRecord(agent_id=agent_id, role=role, prompt=prompt, result=result)

    def _run_agent_with_runtime_context(
        self,
        *,
        agent_id: str,
        config_path: Path,
        prompt: str,
        role: str,
        runtime_context: Dict[str, Any],
    ) -> AgentRunRecord:
        config = self._load_agent_config(config_path)
        llm_config = config.get("llm", {})
        self._log(
            "agent_started",
            agent_id=agent_id,
            role=role,
            config_path=str(config_path),
            workspace=config.get("workspace", ""),
            provider=llm_config.get("provider", ""),
            model=llm_config.get("model", ""),
            prompt_length=len(prompt),
            current_message_id=runtime_context.get("current_message_id", ""),
        )
        runner = AgentRunner(config_path=str(config_path), config=config, runtime_context=runtime_context)
        result = runner.agent_loop(prompt, runtime_context=runtime_context)
        final_response = result.get("final_response") or result.get("error", "")
        self._log(
            "agent_finished",
            agent_id=agent_id,
            role=role,
            ok=result.get("ok", False),
            finish_reason=result.get("finish_reason", ""),
            response_preview=final_response[:200],
        )
        return AgentRunRecord(agent_id=agent_id, role=role, prompt=prompt, result=result)

    def _write_text(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _write_json(self, path: Path, payload: Dict[str, Any]) -> None:
        self._write_text(path, json.dumps(payload, ensure_ascii=False, indent=2))

    def _collect_dialogue_turns(self) -> List[Dict[str, str]]:
        if self.bus is None:
            return []
        contexts_dir = self.workflow_dir / "runtime_bus" / "contexts"
        if not contexts_dir.exists():
            return []

        events: List[Dict[str, Any]] = []
        for path in sorted(contexts_dir.glob("*/events.jsonl")):
            events.extend(self.bus._load_jsonl(path))
        if not events:
            return []

        events.sort(key=lambda item: (str(item.get("created_at", "")), str(item.get("event_id", ""))))
        turn_order: List[str] = []
        turn_map: Dict[str, Dict[str, str]] = {}

        for item in events:
            event_type = str(item.get("event_type", "")).strip()
            if event_type not in {"channel_message", "assistant_reply"}:
                continue
            task_id = str(item.get("task_id", "")).strip() or str(item.get("message_id", "")).strip()
            if not task_id:
                continue
            if task_id not in turn_map:
                turn_map[task_id] = {
                    "user": "",
                    "assistant": "",
                    "created_at": str(item.get("created_at", "")),
                }
                turn_order.append(task_id)

            content = item.get("content", {}) if isinstance(item.get("content", {}), dict) else {}
            if event_type == "channel_message" and not turn_map[task_id]["user"]:
                turn_map[task_id]["user"] = str(content.get("text", "")).strip()
            if event_type == "assistant_reply":
                turn_map[task_id]["assistant"] = str(content.get("text", "")).strip()

        turns: List[Dict[str, str]] = []
        for task_id in turn_order:
            turn = turn_map[task_id]
            if not turn.get("user") and not turn.get("assistant"):
                continue
            turns.append(
                {
                    "task_id": task_id,
                    "created_at": turn.get("created_at", ""),
                    "user": turn.get("user", ""),
                    "assistant": turn.get("assistant", ""),
                }
            )
        return turns

    def _build_dialogue_log_markdown(self) -> str:
        turns = self._collect_dialogue_turns()
        lines: List[str] = ["# Dialogue Log", ""]
        if not turns:
            lines.extend(["（本次运行尚未形成可记录的用户 / AI 对话。）", ""])
            return "\n".join(lines)

        for index, turn in enumerate(turns, start=1):
            lines.extend(
                [
                    f"## Turn {index}",
                    "",
                    "用户：",
                    turn.get("user", "") or "（空）",
                    "",
                    "AI：",
                    turn.get("assistant", "") or "（空）",
                    "",
                ]
            )
        return "\n".join(lines).rstrip() + "\n"

    def _build_trace_markdown(self, node_records: List[NodeRunRecord], global_task: str) -> str:
        lines: List[str] = [
            "# Runtime LLM Trace",
            "",
            "## Global Task",
            global_task,
            "",
        ]

        for node_record in node_records:
            lines.extend(
                [
                    f"## {node_record.node_id}",
                    f"- State: {node_record.state}",
                    f"- Leader: {node_record.leader_id}",
                    f"- Workers: {', '.join(node_record.worker_ids) if node_record.worker_ids else 'None'}",
                    "",
                ]
            )

            for agent_run in node_record.agent_runs:
                result = agent_run.result
                trace = result.get("trace", [])
                debug_log = result.get("debug_log", [])
                lines.extend(
                    [
                        f"### Agent `{agent_run.agent_id}` ({agent_run.role})",
                        "",
                        "#### Prompt",
                        "```text",
                        agent_run.prompt,
                        "```",
                        "",
                        "#### Final Response",
                        "```text",
                        str(result.get("final_response") or result.get("error") or ""),
                        "```",
                        "",
                        "#### Result Summary",
                        f"- ok: {result.get('ok', False)}",
                        f"- finish_reason: {result.get('finish_reason', '')}",
                        f"- trace_steps: {len(trace)}",
                        f"- debug_events: {len(debug_log)}",
                        "",
                    ]
                )

                if trace:
                    lines.append("#### Trace")
                    lines.append("")
                    for index, item in enumerate(trace, start=1):
                        lines.append(f"##### Trace Item {index}")
                        lines.append("```json")
                        lines.append(json.dumps(item, ensure_ascii=False, indent=2))
                        lines.append("```")
                        lines.append("")

                if debug_log:
                    lines.append("#### Debug Log")
                    lines.append("")
                    for index, item in enumerate(debug_log, start=1):
                        lines.append(f"##### Debug Event {index}")
                        lines.append("```json")
                        lines.append(json.dumps(item, ensure_ascii=False, indent=2))
                        lines.append("```")
                        lines.append("")

        return "\n".join(lines).rstrip() + "\n"

    def _persist_node_outputs(
        self,
        node_id: str,
        node_dir: Path,
        global_task: str,
        leader_summary: str,
        worker_outputs: Dict[str, str],
        next_nodes: List[str],
        agent_runs: List[AgentRunRecord],
    ) -> List[str]:
        output_dir = node_dir / "output"
        output_dir.mkdir(parents=True, exist_ok=True)

        generated_files: List[str] = []
        normalized_node_id = node_id.replace("_", "")

        if normalized_node_id == "node1":
            analysis_path = output_dir / "node1_workflow_analysis.md"
            handoff_path = output_dir / "node1_handoff_summary.md"
            analysis_content = "\n".join(
                [
                    "# Node 1 Workflow Analysis",
                    "",
                    "## Global Task",
                    global_task,
                    "",
                    "## Leader Summary",
                    leader_summary,
                    "",
                    "## Worker Results",
                ]
            )
            for worker_id, worker_output in worker_outputs.items():
                analysis_content += f"\n\n### {worker_id}\n{worker_output}"

            handoff_content = "\n".join(
                [
                    "# Node 1 Handoff Summary",
                    "",
                    "## Downstream Nodes",
                    ", ".join(next_nodes) if next_nodes else "None",
                    "",
                    "## Produced Files",
                    "- node1_workflow_analysis.md",
                    "- node1_handoff_summary.md",
                    "",
                    "## Handoff Notes",
                    leader_summary,
                ]
            )
            self._write_text(analysis_path, analysis_content)
            self._write_text(handoff_path, handoff_content)
            generated_files.extend([str(analysis_path), str(handoff_path)])

        elif normalized_node_id == "node2":
            delivery_path = output_dir / "workflow_final_delivery.md"
            manifest_path = output_dir / "workflow_delivery_manifest.json"
            delivery_content = "\n".join(
                [
                    "# Workflow Final Delivery",
                    "",
                    "## Global Task",
                    global_task,
                    "",
                    "## Final Summary",
                    leader_summary,
                    "",
                    "## Included Sources",
                    "- node1_workflow_analysis.md",
                    "- node1_handoff_summary.md",
                ]
            )
            manifest_payload = {
                "workflow": self.workflow.get("id", self.workflow_path.stem),
                "node_id": node_id,
                "files": [
                    {
                        "path": "workflow_final_delivery.md",
                        "purpose": "Final workflow delivery document",
                    },
                    {
                        "path": "workflow_delivery_manifest.json",
                        "purpose": "Machine-readable manifest of final deliverables",
                    },
                ],
            }
            self._write_text(delivery_path, delivery_content)
            self._write_json(manifest_path, manifest_payload)
            generated_files.extend([str(delivery_path), str(manifest_path)])

        generic_summary_path = output_dir / "runtime_node_summary.md"
        runtime_state_path = output_dir / "runtime_node_result.json"
        self._write_text(
            generic_summary_path,
            "\n".join(
                [
                    f"# Runtime Summary for {node_id}",
                    "",
                    "## Leader Summary",
                    leader_summary,
                ]
            ),
        )
        self._write_json(
            runtime_state_path,
            {
                "node_id": node_id,
                "leader_summary": leader_summary,
                "worker_outputs": worker_outputs,
                "agent_runs": [item.to_dict() for item in agent_runs],
            },
        )
        generated_files.extend([str(generic_summary_path), str(runtime_state_path)])
        return generated_files

    def _extract_tool_names(self, run_record: AgentRunRecord) -> List[str]:
        tool_names: List[str] = []
        for item in run_record.result.get("trace", []):
            tool_call = item.get("tool_call", {})
            name = str(tool_call.get("name", "")).strip()
            if name:
                tool_names.append(name)
        return tool_names

    def _should_retry_empty_reply(
        self,
        *,
        current_message: Dict[str, Any],
        agent_id: str,
        run_record: AgentRunRecord,
    ) -> bool:
        if self.bus is None:
            return False
        if not run_record.result.get("ok", False):
            return False
        final_response = str(run_record.result.get("final_response") or "").strip()
        if final_response:
            return False
        tool_names = set(self._extract_tool_names(run_record))
        if "agent_handoff_reply" in tool_names:
            return False
        task = self.bus.load_task(current_message["task_id"])
        return (
            agent_id == task.get("current_owner_agent")
            and current_message.get("message_type") in {"channel_message", "task_reply", "reply_handoff"}
        )

    def _record_trace_events(
        self,
        *,
        agent_id: str,
        node_id: str,
        context_id: str,
        task_id: str,
        trace: List[Dict[str, Any]],
    ) -> None:
        if self.bus is None:
            return
        for item in trace:
            tool_call = item.get("tool_call")
            if tool_call:
                self.bus.record_event(
                    agent_id=agent_id,
                    context_id=context_id,
                    task_id=task_id,
                    message_id=str(tool_call.get("id", "")),
                    node_id=node_id,
                    event_type="tool_call",
                    content={"tool_name": tool_call.get("name", ""), "arguments": tool_call.get("arguments", {})},
                )
                self.bus.record_event(
                    agent_id=agent_id,
                    context_id=context_id,
                    task_id=task_id,
                    message_id=str(tool_call.get("id", "")),
                    node_id=node_id,
                    event_type="tool_result",
                    content=tool_call.get("result", {}),
                )

    def _resolve_channel_target_agent(self, node_id: str, fallback_agent_id: str) -> str:
        default_map = self.channel_routing.get("default", {}) if isinstance(self.channel_routing.get("default", {}), dict) else {}
        node_map = self.channel_routing.get(node_id, {}) if isinstance(self.channel_routing.get(node_id, {}), dict) else {}
        return str(node_map.get("terminal") or default_map.get("terminal") or fallback_agent_id).strip()

    def _prepare_node_channel_payload(self, node_id: str, global_task: str) -> Dict[str, Any]:
        node_dir = self._resolve_node_dir(node_id)
        node_inputs = {
            str(path.relative_to(self.workspace_root)): self._read_text_file(path)
            for path in self._collect_node_input_files(node_dir)
        }
        upstream_inputs = {
            str(path.relative_to(self.workspace_root)): self._read_text_file(path)
            for path in self._collect_upstream_files(node_id)
        }
        return {
            "global_task": global_task,
            "node_inputs": node_inputs,
            "upstream_artifacts": upstream_inputs,
        }

    def _agent_config_path_map(self, node_payload: Dict[str, Any]) -> Dict[str, str]:
        result: Dict[str, str] = {}
        for item in node_payload.get("agent", []):
            if not isinstance(item, dict):
                continue
            agent_id = str(item.get("id", "")).strip()
            config_path = str(item.get("config_path", "")).strip()
            if not agent_id or not config_path:
                continue
            result[agent_id] = str(self._resolve_agent_config_path(config_path))
        return result

    def _auto_complete_message(
        self,
        *,
        current_message: Dict[str, Any],
        agent_id: str,
        run_record: AgentRunRecord,
    ) -> None:
        if self.bus is None:
            return
        final_response = run_record.result.get("final_response") or ""
        if not final_response:
            return
        tool_names = set(self._extract_tool_names(run_record))
        if current_message.get("message_type") == "task_request" and "agent_reply_task" not in tool_names:
            self.bus.reply_task(
                from_agent=agent_id,
                reply_to_message_id=current_message["message_id"],
                text=final_response,
                payload={"auto_reply": True},
            )
            return

        task = self.bus.load_task(current_message["task_id"])
        if (
            agent_id == task.get("current_owner_agent")
            and current_message.get("message_type") in {"channel_message", "task_reply", "reply_handoff"}
            and "agent_handoff_reply" not in tool_names
            and not task.get("pending_replies")
        ):
            self.bus.complete_root_response(current_message["message_id"], final_response)

    def _consume_finish_request(self, runtime_context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        request = runtime_context.pop("node_finish_request", None)
        if isinstance(request, dict):
            return request
        return None

    def _validate_finish_request(
        self,
        *,
        node_id: str,
        request: Dict[str, Any],
        current_message_id: str = "",
    ) -> Optional[str]:
        if self.bus is None:
            return "runtime bus is not initialized"
        if node_id in self.node_finish_requests:
            return f"node `{node_id}` already has an accepted finish request"
        if not str(request.get("message", "")).strip():
            return "finish request message must not be empty"

        pending_messages = [
            item
            for item in self.bus.list_messages(node_id=node_id)
            if item.get("status") in {"queued", "dispatched"} and item.get("message_id") != current_message_id
        ]
        if pending_messages:
            return f"node `{node_id}` still has pending messages"

        waiting_tasks = [
            item
            for item in self.bus.list_tasks(node_id=node_id)
            if item.get("pending_replies")
        ]
        if waiting_tasks:
            return f"node `{node_id}` still has pending task replies"
        return None

    def _accept_finish_request(
        self,
        *,
        node_id: str,
        current_message: Dict[str, Any],
        request: Dict[str, Any],
    ) -> Dict[str, Any]:
        if self.bus is None:
            raise RuntimeError("runtime bus is not initialized")

        validation_error = self._validate_finish_request(
            node_id=node_id,
            request=request,
            current_message_id=str(current_message.get("message_id", "")),
        )
        if validation_error:
            self.bus.record_event(
                agent_id=str(request.get("agent_id", "")),
                context_id=str(request.get("context_id", "")),
                task_id=str(request.get("task_id", "")),
                message_id=str(request.get("current_message_id", "")),
                node_id=node_id,
                event_type="node_finish_rejected",
                content={"reason": validation_error, "message": request.get("message", "")},
            )
            return {"ok": False, "error": validation_error}

        task = self.bus.load_task(current_message["task_id"])
        if not task.get("final_response_message_id"):
            self.bus.complete_root_response(current_message["message_id"], str(request["message"]))
        self.bus.record_event(
            agent_id=str(request.get("agent_id", "")),
            context_id=str(request.get("context_id", "")),
            task_id=str(request.get("task_id", "")),
            message_id=str(request.get("current_message_id", "")),
            node_id=node_id,
            event_type="node_finish_accepted",
            content={"message": request.get("message", "")},
        )
        self.node_finish_requests[node_id] = request
        return {"ok": True, "message": str(request["message"])}

    def _build_bus_prompt(self, current_message: Dict[str, Any]) -> str:
        message_type = current_message.get("message_type", "")
        if message_type == "task_request":
            return (
                "Process the current task request from the runtime message context. "
                "Use `agent_reply_task` to send a formal reply when you finish, unless you explicitly need to hand work onward."
            )
        if message_type == "reply_handoff":
            return (
                "You have received reply ownership for the current external task. "
                "Review the injected handoff context and respond or delegate as needed."
            )
        if message_type == "task_reply":
            return (
                "You have received a task reply from another agent. "
                "Decide whether to continue work, delegate more tasks, hand off ownership, or provide the final answer."
            )
        return (
            "Process the current runtime message context. "
            "If you need another agent, send a task. If you are done, provide the final answer."
        )

    def _execute_node_with_bus(self, node_id: str, global_task: str) -> NodeRunRecord:
        if self.bus is None:
            raise RuntimeError("runtime bus is not initialized")

        node_payload = self.node_map[node_id]
        node_dir = self._resolve_node_dir(node_id)
        relationships = self._node_relationships(node_payload)
        leader_id = self._resolve_leader_id(node_payload)
        worker_ids = list(relationships.get(leader_id, {}).get("Subordinate", []))
        node_inputs = {
            str(path.relative_to(self.workspace_root)): self._read_text_file(path)
            for path in self._collect_node_input_files(node_dir)
        }
        upstream_inputs = {
            str(path.relative_to(self.workspace_root)): self._read_text_file(path)
            for path in self._collect_upstream_files(node_id)
        }
        self._log(
            "node_started",
            node_id=node_id,
            node_dir=str(node_dir),
            leader_id=leader_id,
            worker_ids=worker_ids,
            input_files=list(node_inputs.keys()),
            upstream_files=list(upstream_inputs.keys()),
            mode="bus",
        )

        agent_entries = {
            str(item.get("id", "")).strip(): item
            for item in node_payload.get("agent", [])
            if isinstance(item, dict)
        }
        entry_agent_id = self._resolve_channel_target_agent(node_id, leader_id)
        entry_agent_entry = agent_entries.get(entry_agent_id)
        if entry_agent_entry is None:
            raise KeyError(f"entry agent not found for node {node_id}: {entry_agent_id}")

        agent_config = self._load_agent_config(self._resolve_agent_config_path(str(entry_agent_entry.get("config_path", ""))))
        context_id = str(agent_config.get("context_id") or agent_config.get("contextWindow_id") or f"{node_id}_{entry_agent_id}").strip()
        entry_message = self.bus.create_channel_message(
            channel="terminal",
            node_id=node_id,
            to_agent=entry_agent_id,
            text=global_task,
            context_id=context_id,
            payload=self._prepare_node_channel_payload(node_id, global_task),
        )

        agent_runs: List[AgentRunRecord] = []
        accepted_finish_request: Optional[Dict[str, Any]] = None
        safety_counter = 0
        while self.bus.has_pending_messages(node_id=node_id):
            safety_counter += 1
            if safety_counter > 50:
                self._log("node_bus_safety_break", node_id=node_id, reason="too_many_iterations")
                break

            progressed = False
            for agent_id, entry in agent_entries.items():
                current_message = self.bus.claim_next_message(agent_id, node_id=node_id)
                if current_message is None:
                    continue
                progressed = True
                config_path = self._resolve_agent_config_path(str(entry.get("config_path", "")))
                config = self._load_agent_config(config_path)
                context_id = str(config.get("context_id") or config.get("contextWindow_id") or current_message.get("context_id", "")).strip()
                effective_capability = self._effective_agent_capability(config, agent_id, current_message["task_id"])
                if self.context_policy["compression"]["enabled"]:
                    self.bus.maybe_compress_context(
                        agent_id=agent_id,
                        context_id=context_id or current_message.get("context_id", ""),
                        max_tokens=self.context_policy["compression"]["max_tokens"],
                        recent_history_events=self.context_policy["recent_history_events"],
                    )
                if current_message.get("message_type") == "task_request":
                    self.bus.record_event(
                        agent_id=agent_id,
                        context_id=current_message["context_id"],
                        task_id=current_message["task_id"],
                        message_id=current_message["message_id"],
                        node_id=node_id,
                        event_type="task_received",
                        content=current_message.get("content", {}),
                    )
                if current_message.get("message_type") == "task_reply":
                    self.bus.record_event(
                        agent_id=agent_id,
                        context_id=current_message["context_id"],
                        task_id=current_message["task_id"],
                        message_id=current_message["message_id"],
                        node_id=node_id,
                        event_type="task_reply_received",
                        content=current_message.get("content", {}),
                    )
                if current_message.get("message_type") == "reply_handoff":
                    self.bus.record_event(
                        agent_id=agent_id,
                        context_id=current_message["context_id"],
                        task_id=current_message["task_id"],
                        message_id=current_message["message_id"],
                        node_id=node_id,
                        event_type="reply_handoff_received",
                        content=current_message.get("handoff_note", {}),
                    )

                message_context = self.bus.build_agent_message_context(
                    agent_id=agent_id,
                    current_message=current_message,
                    recent_history_events=self.context_policy["recent_history_events"],
                )
                runtime_context = {
                    "bus": self.bus,
                    "agent_id": agent_id,
                    "node_id": node_id,
                    "task_id": current_message["task_id"],
                    "context_id": current_message["context_id"],
                    "current_message_id": current_message["message_id"],
                    "message_context": message_context,
                    "current_message": current_message,
                    "agent_capability": effective_capability,
                    "session_permissions": self.session_permissions,
                    "agent_config_path_map": self._agent_config_path_map(node_payload),
                }
                prompt = self._build_bus_prompt(current_message)
                role = "leader" if agent_id == leader_id else "worker"
                run_record = self._run_agent_with_runtime_context(
                    agent_id=agent_id,
                    config_path=config_path,
                    prompt=prompt,
                    role=role,
                    runtime_context=runtime_context,
                )
                agent_runs.append(run_record)
                self._record_trace_events(
                    agent_id=agent_id,
                    node_id=node_id,
                    context_id=current_message["context_id"],
                    task_id=current_message["task_id"],
                    trace=run_record.result.get("trace", []),
                )
                if self._should_retry_empty_reply(
                    current_message=current_message,
                    agent_id=agent_id,
                    run_record=run_record,
                ):
                    self._log(
                        "agent_empty_reply_retry",
                        agent_id=agent_id,
                        role=role,
                        current_message_id=current_message["message_id"],
                    )
                    run_record = self._run_agent_with_runtime_context(
                        agent_id=agent_id,
                        config_path=config_path,
                        prompt=prompt,
                        role=role,
                        runtime_context=runtime_context,
                    )
                    agent_runs.append(run_record)
                    self._record_trace_events(
                        agent_id=agent_id,
                        node_id=node_id,
                        context_id=current_message["context_id"],
                        task_id=current_message["task_id"],
                        trace=run_record.result.get("trace", []),
                    )
                self._auto_complete_message(
                    current_message=current_message,
                    agent_id=agent_id,
                    run_record=run_record,
                )
                finish_request = self._consume_finish_request(runtime_context)
                if finish_request is not None:
                    finish_result = self._accept_finish_request(
                        node_id=node_id,
                        current_message=current_message,
                        request=finish_request,
                    )
                    if finish_result.get("ok", False):
                        accepted_finish_request = finish_request
                        break
                if not run_record.result.get("ok", False):
                    self.bus.mark_message_failed(current_message["message_id"], run_record.result.get("error", ""))
            if accepted_finish_request is not None:
                break
            if not progressed:
                break

        root_task = self.bus.load_task(entry_message["task_id"])
        final_message_id = root_task.get("final_response_message_id")
        leader_summary = ""
        if final_message_id:
            leader_summary = self.bus.load_message(final_message_id).get("content", {}).get("text", "")
        elif accepted_finish_request is not None:
            leader_summary = str(accepted_finish_request.get("message", ""))
        elif agent_runs:
            leader_summary = agent_runs[-1].result.get("final_response") or ""

        generated_files = self._persist_node_outputs(
            node_id=node_id,
            node_dir=node_dir,
            global_task=global_task,
            leader_summary=leader_summary,
            worker_outputs={},
            next_nodes=self.id_map.get(node_id, []),
            agent_runs=agent_runs,
        )
        self._log(
            "node_finished",
            node_id=node_id,
            state="done",
            generated_files=generated_files,
            next_nodes=self.id_map.get(node_id, []),
            mode="bus",
        )
        return NodeRunRecord(
            node_id=node_id,
            node_dir=str(node_dir),
            state="done",
            leader_id=leader_id,
            worker_ids=worker_ids,
            inputs=list(node_inputs.keys()),
            upstream_artifacts=list(upstream_inputs.keys()),
            agent_runs=agent_runs,
            generated_files=generated_files,
        )

    def _execute_node(self, node_id: str, global_task: str) -> NodeRunRecord:
        node_payload = self.node_map[node_id]
        node_dir = self._resolve_node_dir(node_id)
        node_inputs = {
            str(path.relative_to(self.workspace_root)): self._read_text_file(path)
            for path in self._collect_node_input_files(node_dir)
        }
        upstream_inputs = {
            str(path.relative_to(self.workspace_root)): self._read_text_file(path)
            for path in self._collect_upstream_files(node_id)
        }

        relationships = self._node_relationships(node_payload)
        leader_id = self._resolve_leader_id(node_payload)
        worker_ids = list(relationships.get(leader_id, {}).get("Subordinate", []))
        self._log(
            "node_started",
            node_id=node_id,
            node_dir=str(node_dir),
            leader_id=leader_id,
            worker_ids=worker_ids,
            input_files=list(node_inputs.keys()),
            upstream_files=list(upstream_inputs.keys()),
        )

        agent_entries = {
            str(item.get("id", "")).strip(): item
            for item in node_payload.get("agent", [])
            if isinstance(item, dict)
        }
        next_nodes = self.id_map.get(node_id, [])

        agent_runs: List[AgentRunRecord] = []
        worker_outputs: Dict[str, str] = {}

        for worker_id in worker_ids:
            worker_entry = agent_entries.get(worker_id)
            if worker_entry is None:
                continue
            config_path = self._resolve_agent_config_path(str(worker_entry.get("config_path", "")))
            prompt = self._build_worker_prompt(global_task, node_payload, worker_id, node_inputs)
            run_record = self._run_agent(worker_id, config_path, prompt, role="worker")
            agent_runs.append(run_record)
            worker_outputs[worker_id] = run_record.result.get("final_response") or run_record.result.get("error", "")

        leader_entry = agent_entries.get(leader_id)
        if leader_entry is None:
            raise KeyError(f"leader agent not found for node {node_id}: {leader_id}")
        leader_config_path = self._resolve_agent_config_path(str(leader_entry.get("config_path", "")))
        leader_prompt = self._build_leader_prompt(
            global_task=global_task,
            node_payload=node_payload,
            leader_id=leader_id,
            node_inputs=node_inputs,
            upstream_inputs=upstream_inputs,
            worker_outputs=worker_outputs,
            next_nodes=next_nodes,
        )
        leader_run = self._run_agent(leader_id, leader_config_path, leader_prompt, role="leader")
        agent_runs.append(leader_run)
        leader_summary = leader_run.result.get("final_response") or leader_run.result.get("error", "")

        generated_files = self._persist_node_outputs(
            node_id=node_id,
            node_dir=node_dir,
            global_task=global_task,
            leader_summary=leader_summary,
            worker_outputs=worker_outputs,
            next_nodes=next_nodes,
            agent_runs=agent_runs,
        )
        self._log(
            "node_finished",
            node_id=node_id,
            state="done",
            generated_files=generated_files,
            next_nodes=next_nodes,
        )

        return NodeRunRecord(
            node_id=node_id,
            node_dir=str(node_dir),
            state="done",
            leader_id=leader_id,
            worker_ids=worker_ids,
            inputs=list(node_inputs.keys()),
            upstream_artifacts=list(upstream_inputs.keys()),
            agent_runs=agent_runs,
            generated_files=generated_files,
        )

    def run(self, global_task: str) -> Dict[str, Any]:
        self.execution_log = []
        self.node_finish_requests = {}
        if self.bus is not None:
            self.bus.reset()
        self._log(
            "runtime_started",
            workflow_path=str(self.workflow_path),
            execution_order=self.execution_order,
            global_task=global_task,
        )
        node_records: List[NodeRunRecord] = []
        for node_id in self.execution_order:
            self.state[node_id] = "running"
            if self.bus_policy.get("enabled", True):
                node_record = self._execute_node_with_bus(node_id=node_id, global_task=global_task)
            else:
                node_record = self._execute_node(node_id=node_id, global_task=global_task)
            self.state[node_id] = node_record.state
            node_records.append(node_record)

        runtime_output_path = self.workflow_dir / "runtime_execution_result.json"
        self._log(
            "runtime_finished",
            state=deepcopy(self.state),
            result_path=str(runtime_output_path),
        )
        runtime_result = {
            "ok": True,
            "workflow_path": str(self.workflow_path),
            "global_task": global_task,
            "execution_order": self.execution_order,
            "state": deepcopy(self.state),
            "nodes": [record.to_dict() for record in node_records],
            "execution_log": deepcopy(self.execution_log),
            "final_response": self._extract_final_response(node_records),
        }
        self._write_json(runtime_output_path, runtime_result)
        self._write_text(
            self.log_path,
            "\n".join(
                f"[{item['timestamp']}] {item['event']} | {json.dumps(item['details'], ensure_ascii=False)}"
                for item in self.execution_log
            ),
        )
        self._write_text(
            self.trace_md_path,
            self._build_trace_markdown(node_records=node_records, global_task=global_task),
        )
        self._write_text(
            self.dialogue_log_path,
            self._build_dialogue_log_markdown(),
        )
        self.session_store.record_turn(
            user_message=global_task,
            assistant_message=runtime_result["final_response"],
            metadata={
                "workflow_path": str(self.workflow_path),
                "state": deepcopy(self.state),
                "execution_order": list(self.execution_order),
            },
        )
        self.session_store.sync_runtime_result(
            workflow_path=str(self.workflow_path),
            state=deepcopy(self.state),
            execution_order=list(self.execution_order),
            final_response=runtime_result["final_response"],
            result_path=str(runtime_output_path),
            log_path=str(self.log_path),
            trace_md_path=str(self.trace_md_path),
            dialogue_log_path=str(self.dialogue_log_path),
        )
        if self.bus is not None:
            self.session_store.sync_context_summaries(self.workflow_dir / "runtime_bus" / "contexts")
        runtime_result["result_path"] = str(runtime_output_path)
        runtime_result["log_path"] = str(self.log_path)
        runtime_result["trace_md_path"] = str(self.trace_md_path)
        runtime_result["dialogue_log_path"] = str(self.dialogue_log_path)
        runtime_result["session_snapshot_path"] = str(self.session_store.snapshot_path)
        runtime_result["session_turns_path"] = str(self.session_store.turns_path)
        return runtime_result

    def _extract_final_response(self, node_records: List[NodeRunRecord]) -> str:
        for node_record in reversed(node_records):
            for run_record in reversed(node_record.agent_runs):
                content = run_record.result.get("final_response") or ""
                if content:
                    return str(content)
        return ""
