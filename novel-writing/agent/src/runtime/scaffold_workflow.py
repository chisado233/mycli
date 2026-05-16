from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from pathlib import PureWindowsPath
from typing import Any, Dict, List, Tuple


CURRENT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = CURRENT_DIR.parent.parent
DEFAULT_WORKFLOW_PATH = PROJECT_ROOT / "workspace" / "agent_workflow" / "agent_workflow.json"

DEFAULT_LLM_CONFIG_PATH = PROJECT_ROOT / "config" / "llm.json"
DEFAULT_WORKSPACE_ROOT = PROJECT_ROOT / "workspace"


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_text(path: Path, content: str, overwrite: bool) -> None:
    if path.exists() and not overwrite:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _write_json(path: Path, payload: Dict[str, Any], overwrite: bool) -> None:
    _write_text(path, json.dumps(payload, ensure_ascii=False, indent=2), overwrite=overwrite)


def _normalize_node_dir_name(node_id: str) -> str:
    if node_id.startswith("node_"):
        suffix = node_id.split("_", 1)[1]
        return f"node{suffix}"
    return node_id.replace("_", "")


def _resolve_target_relative_path(raw_path: str, workflow_names: List[str]) -> Path:
    normalized = raw_path.replace("/", "\\").strip("\\")
    parts = list(PureWindowsPath(normalized).parts)
    valid_prefixes = {item.lower() for item in workflow_names if item}
    if parts and parts[0].lower() in valid_prefixes:
        parts = parts[1:]
    return Path(*parts) if parts else Path(PureWindowsPath(normalized).name)


def _resolve_relationship(
    relationships: Dict[str, Dict[str, List[str]]],
    agent_id: str,
) -> Dict[str, Any]:
    relation = relationships.get(agent_id, {}) if isinstance(relationships, dict) else {}
    return {
        "Superior": relation.get("Superior", []),
        "Peer": relation.get("Peer", []),
        "Subordinate": [{"id": item, "connect": "true"} for item in relation.get("Subordinate", [])],
    }


def _default_agent_config(
    *,
    workflow_name: str,
    node_id: str,
    agent_id: str,
    description: str,
    relationships: Dict[str, Dict[str, List[str]]],
    workspace_dir: Path,
) -> Dict[str, Any]:
    return {
        "id": agent_id,
        "context_id": "",
        "agent_capability": {
            "can_delegate": bool(relationships.get(agent_id, {}).get("Subordinate", [])),
            "allowed_targets": [*relationships.get(agent_id, {}).get("Subordinate", [])] or [],
            "can_reply_user": False,
            "can_request_temporary_permission_change": bool(relationships.get(agent_id, {}).get("Subordinate", [])),
            "can_request_persistent_permission_change": False,
            "can_approve_persistent_permission_change": False,
        },
        "llm": {
            "config_path": str(DEFAULT_LLM_CONFIG_PATH),
            "provider": "mytokenland",
            "model": "claude-sonnet-4-6",
            "temperature": 0.0,
            "max_tokens": 8192,
            "max_steps": 64,
        },
        "system_prompt_component": [
            {
                "id": "agent_identity",
                "config": {
                    "enable": "true",
                    "role": f"{node_id} agent",
                    "description": description or f"负责 {workflow_name} 中 {node_id} 的工作。",
                    "goals": [
                        f"正确理解 {node_id} 当前阶段任务",
                        "在当前 workspace 内完成自身职责",
                        "输出可交付的结果，而不只停留在对话中",
                    ],
                },
            },
            {"id": "Tooling", "config": {"enable": "true"}},
            {"id": "Tool_Call_Style", "config": {"enable": "true"}},
            {"id": "Workspace", "config": {"enable": "true", "notes": ["优先在当前 workspace 内完成任务。"]}},
            {"id": "Project_Context", "config": {"enable": "true", "context_files": []}},
            {"id": "Silent_Replies", "config": {"enable": "true"}},
            {"id": "Heartbeats", "config": {"enable": "true"}},
            {"id": "Runtime", "config": {"enable": "true", "shell": "powershell", "channel": "terminal"}},
            {"id": "Agent_Message_Context", "config": {"enable": "true"}},
        ],
        "tool": [
            {"id": "echo", "enable": "true"},
            {"id": "read", "enable": "true"},
            {"id": "write", "enable": "true"},
            {"id": "edit", "enable": "true"},
            {"id": "apply_patch", "enable": "true"},
            {"id": "ls", "enable": "true"},
            {"id": "find", "enable": "true"},
            {"id": "grep", "enable": "true"},
            {"id": "exec", "enable": "true"},
            {"id": "process", "enable": "true"},
            {"id": "agent_config_update", "enable": "true"},
            {"id": "agent_send_task", "enable": "true"},
            {"id": "agent_reply_task", "enable": "true"},
            {"id": "agent_handoff_reply", "enable": "true"},
            {"id": "agent_request_permission_change", "enable": "true"},
            {"id": "agent_request_finish_node", "enable": "true"},
        ],
        "channel": {
            "terminal": {
                "enable": "true",
                "direction": {"inbound": "true", "outbound": "true"},
            }
        },
        "heartbeat": {"enable": "true"},
        "cron": {"enable": "false"},
        "workspace": str(workspace_dir),
        "Relationship with other agents": _resolve_relationship(relationships, agent_id),
    }


def _build_workflow_info(workflow_name: str, workflow: Dict[str, Any]) -> str:
    nodes = workflow.get("nodes", [])
    lines = [
        f"# {workflow_name}",
        "",
        "## Workflow Overview",
        "",
        f"该工作流包含 {len(nodes)} 个节点。",
        "",
        "## Nodes",
        "",
    ]
    for node in nodes:
        lines.append(f"- `{node.get('id', '')}`: {node.get('description', '')}")
    lines.extend(["", "## Notes", "", "- 此文件由 scaffold_workflow.py 自动生成。"])
    return "\n".join(lines) + "\n"


def _build_demo_task(workflow_name: str) -> str:
    return "\n".join(
        [
            f"# {workflow_name} Demo Task",
            "",
            "请基于当前 workflow 结构完成一次最小闭环测试：",
            "",
            "1. 入口 agent 接收任务。",
            "2. 必要时将结构化子任务派发给其他 agent。",
            "3. 节点交付物写入各自 output 目录。",
            "4. 下游节点消费上游交付物并形成最终结果。",
            "",
        ]
    )


def _build_node_info(node_id: str, node_description: str, agents: List[Dict[str, Any]], downstream_nodes: List[str]) -> str:
    lines = [
        f"# {node_id} Task Sheet",
        "",
        "## Node Description",
        "",
        node_description or f"{node_id} 的阶段说明暂未填写。",
        "",
        "## Agents",
        "",
    ]
    for agent in agents:
        lines.append(f"- `{agent.get('id', '')}`")
    lines.extend(
        [
            "",
            "## Downstream Nodes",
            "",
            ", ".join(downstream_nodes) if downstream_nodes else "None",
            "",
            "## Output Rule",
            "",
            f"请将本节点产物写入 `nodes\\{_normalize_node_dir_name(node_id)}\\output`。",
            "",
        ]
    )
    return "\n".join(lines)


def _build_agent_info(node_id: str, agent_id: str, relationships: Dict[str, Dict[str, List[str]]]) -> str:
    relation = relationships.get(agent_id, {}) if isinstance(relationships, dict) else {}
    lines = [
        f"# {agent_id}",
        "",
        f"你是 `{node_id}` 下的 `{agent_id}`。",
        "",
        "## Current Role",
        "",
        f"- Superior: {', '.join(relation.get('Superior', [])) or 'None'}",
        f"- Peer: {', '.join(relation.get('Peer', [])) or 'None'}",
        f"- Subordinate: {', '.join(relation.get('Subordinate', [])) or 'None'}",
        "",
        "## Operating Rule",
        "",
        "1. 读取当前节点输入与必要上下文。",
        "2. 在职责范围内完成工作。",
        "3. 输出尽量结构化，并确保能被后续节点或 agent 消费。",
        "",
    ]
    return "\n".join(lines)


def _scaffold_node(
    *,
    target_dir: Path,
    workflow_name: str,
    source_workflow_names: List[str],
    node: Dict[str, Any],
    downstream_nodes: List[str],
    overwrite: bool,
) -> Tuple[List[str], List[str]]:
    created_paths: List[str] = []
    warnings: List[str] = []

    node_id = str(node.get("id", "")).strip()
    if not node_id:
        warnings.append("Skipped a node without id.")
        return created_paths, warnings

    node_dir_name = _normalize_node_dir_name(node_id)
    node_dir = target_dir / "nodes" / node_dir_name
    input_dir = node_dir / "input"
    output_dir = node_dir / "output"
    config_dir = target_dir / "config" / node_dir_name
    input_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    config_dir.mkdir(parents=True, exist_ok=True)
    created_paths.extend([str(input_dir), str(output_dir), str(config_dir)])

    relationships = node.get("agent_relationship", {}) if isinstance(node.get("agent_relationship", {}), dict) else {}
    agents = node.get("agent", []) if isinstance(node.get("agent", []), list) else []

    node_info_path = input_dir / "node_info.md"
    _write_text(
        node_info_path,
        _build_node_info(node_id, str(node.get("description", "")).strip(), agents, downstream_nodes),
        overwrite=overwrite,
    )
    created_paths.append(str(node_info_path))

    for agent in agents:
        if not isinstance(agent, dict):
            continue
        agent_id = str(agent.get("id", "")).strip()
        if not agent_id:
            continue

        config_payload = _default_agent_config(
            workflow_name=workflow_name,
            node_id=node_id,
            agent_id=agent_id,
            description=str(node.get("description", "")).strip(),
            relationships=relationships,
            workspace_dir=DEFAULT_WORKSPACE_ROOT,
        )

        raw_config_path = str(agent.get("config_path", "")).strip()
        config_path = (
            _resolve_target_relative_path(raw_config_path, source_workflow_names)
            if raw_config_path
            else config_dir / f"{agent_id}.json"
        )
        if not config_path.is_absolute():
            config_path = target_dir / config_path
        _write_json(config_path, config_payload, overwrite=overwrite)
        created_paths.append(str(config_path))

        node_agent_path = node_dir / f"{agent_id}.json"
        _write_json(node_agent_path, config_payload, overwrite=overwrite)
        created_paths.append(str(node_agent_path))

        agent_info_path = input_dir / f"{agent_id}_info.md"
        _write_text(
            agent_info_path,
            _build_agent_info(node_id, agent_id, relationships),
            overwrite=overwrite,
        )
        created_paths.append(str(agent_info_path))

    return created_paths, warnings


def scaffold_workflow(
    workflow_path: Path,
    target_dir: Path,
    *,
    overwrite: bool = False,
    clean: bool = False,
) -> Dict[str, Any]:
    workflow = _load_json(workflow_path)
    workflow_name = target_dir.name
    source_workflow_name = workflow_path.parent.name
    source_workflow_stem = workflow_path.stem

    if clean and target_dir.exists():
        shutil.rmtree(target_dir)

    target_dir.mkdir(parents=True, exist_ok=True)
    created_paths: List[str] = [str(target_dir)]
    warnings: List[str] = []

    workflow_copy_path = target_dir / "agent_workflow.json"
    _write_json(workflow_copy_path, workflow, overwrite=True)
    created_paths.append(str(workflow_copy_path))

    workflow_info_path = target_dir / "agent_workflow_info.md"
    _write_text(workflow_info_path, _build_workflow_info(workflow_name, workflow), overwrite=overwrite)
    created_paths.append(str(workflow_info_path))

    demo_task_path = target_dir / "demo_task.md"
    _write_text(demo_task_path, _build_demo_task(workflow_name), overwrite=overwrite)
    created_paths.append(str(demo_task_path))

    id_map = workflow.get("id_map", {}) if isinstance(workflow.get("id_map", {}), dict) else {}
    for node in workflow.get("nodes", []):
        if not isinstance(node, dict):
            continue
        node_id = str(node.get("id", "")).strip()
        downstream = [item for item in id_map.get(node_id, []) if isinstance(item, str)]
        node_paths, node_warnings = _scaffold_node(
            target_dir=target_dir,
            workflow_name=workflow_name,
            source_workflow_names=[source_workflow_name, source_workflow_stem],
            node=node,
            downstream_nodes=downstream,
            overwrite=overwrite,
        )
        created_paths.extend(node_paths)
        warnings.extend(node_warnings)

    return {
        "ok": True,
        "workflow_path": str(workflow_path),
        "target_dir": str(target_dir),
        "created_count": len(created_paths),
        "created_paths": created_paths,
        "warnings": warnings,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Scaffold a workflow workspace from agent_workflow.json.")
    parser.add_argument(
        "--workflow",
        default=str(DEFAULT_WORKFLOW_PATH),
        help="Path to the source agent_workflow.json",
    )
    parser.add_argument(
        "--target",
        default=str(DEFAULT_WORKFLOW_PATH.parent),
        help="Target workflow workspace directory to create or update",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing generated files",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove the target directory before scaffolding",
    )
    args = parser.parse_args()

    result = scaffold_workflow(
        workflow_path=Path(args.workflow),
        target_dir=Path(args.target),
        overwrite=args.overwrite,
        clean=args.clean,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
