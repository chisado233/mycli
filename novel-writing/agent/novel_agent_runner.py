from __future__ import annotations

import argparse
import json
import locale
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


AGENT_ROOT = Path(__file__).resolve().parent
WORKSPACE_ROOT = Path(r"D:\agent_workspace")
MYCLI = WORKSPACE_ROOT / "capability-library" / "mycli" / "mycli.ps1"


@dataclass
class ContextFile:
    path: Path
    label: str = ""
    required: bool = True
    relate: bool = False
    source: str = "direct"


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_json_relaxed(path: Path) -> Dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            return json.loads(text[start : end + 1])
        raise


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


FILE_BLOCK_RE = re.compile(
    r"^<<<FILE:\s*(?P<path>.+?)\s*>>>\s*$\n?(?P<content>.*?)(?=^<<<FILE:\s*.+?\s*>>>\s*$|\Z)",
    re.MULTILINE | re.DOTALL,
)

PLAIN_FILE_BLOCK_RE = re.compile(
    r"^FILE:\s*(?P<path>.+?)\s*$\n?(?P<content>.*?)(?=^FILE:\s*.+?\s*$|\Z)",
    re.MULTILINE | re.DOTALL,
)


def resolve_path(raw: str, base_dir: Path) -> Path:
    text = str(raw).strip()
    path = Path(text)
    if path.is_absolute():
        return path
    return (base_dir / path).resolve()


def normalize_context_files(payload: Dict[str, Any], base_dir: Path) -> List[ContextFile]:
    files: List[ContextFile] = []
    for item in payload.get("context_files", []) or payload.get("上下文文件", []) or []:
        if isinstance(item, str):
            files.append(ContextFile(path=resolve_path(item, base_dir)))
            continue
        if isinstance(item, dict):
            raw_path = item.get("path") or item.get("路径") or item.get("file") or item.get("文件")
            if not raw_path:
                continue
            required = item.get("required", item.get("必需", True))
            relate = item.get("relate", item.get("关联", item.get("自动关联", False)))
            files.append(
                ContextFile(
                    path=resolve_path(str(raw_path), base_dir),
                    label=str(item.get("label") or item.get("名称") or item.get("name") or ""),
                    required=bool(required),
                    relate=bool(relate),
                )
            )
    return files


def parse_simple_yaml_frontmatter(path: Path) -> Dict[str, Any]:
    if not path.exists() or not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    yaml_lines: List[str] = []
    for line in lines[1:]:
        if line.strip() == "---":
            break
        yaml_lines.append(line)
    return parse_yaml_subset(yaml_lines)


def parse_yaml_subset(lines: List[str]) -> Dict[str, Any]:
    data: Dict[str, Any] = {}
    current_key: Optional[str] = None
    for raw in lines:
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith(" ") and current_key and line.strip().startswith("-"):
            value = line.strip()[1:].strip()
            data.setdefault(current_key, [])
            if isinstance(data[current_key], list):
                data[current_key].append(strip_yaml_scalar(value))
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        current_key = key
        if value == "":
            data[key] = []
        else:
            data[key] = parse_yaml_value(value)
    return data


def parse_yaml_value(value: str) -> Any:
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [strip_yaml_scalar(part.strip()) for part in inner.split(",")]
    return strip_yaml_scalar(value)


def strip_yaml_scalar(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def as_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        if not value.strip():
            return []
        return [value.strip()]
    return [str(value).strip()]


def find_named_file(project_root: Path, category: str, name: str) -> Optional[Path]:
    safe_name = name.strip()
    if not safe_name:
        return None
    candidates: List[Path] = []
    if category == "人物":
        candidates.extend(
            [
                project_root / "04-角色" / "主角" / f"{safe_name}.md",
                project_root / "04-角色" / "配角" / f"{safe_name}.md",
            ]
        )
    elif category == "势力":
        candidates.append(project_root / "02-世界观" / "势力分布" / f"{safe_name}.md")
    elif category == "伏笔":
        candidates.append(project_root / "06-明线暗线伏笔" / f"{safe_name}.md")
    elif category == "素材":
        # 素材可能在项目素材引用中，也可能在全局素材库中；第一版只尝试项目内直接路径。
        candidates.append(project_root / "09-素材引用" / f"{safe_name}.md")
    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def add_unique_context(files: List[ContextFile], seen: set[str], path: Optional[Path], label: str, source: str) -> None:
    if path is None:
        return
    key = str(path.resolve()).lower()
    if key in seen:
        return
    seen.add(key)
    files.append(ContextFile(path=path.resolve(), label=label, required=False, relate=False, source=source))


def expand_related_context_files(files: List[ContextFile], payload: Dict[str, Any], base_dir: Path) -> List[ContextFile]:
    project_raw = payload.get("project") or payload.get("项目路径") or payload.get("project_root")
    if not project_raw:
        return files
    project_root = resolve_path(str(project_raw), base_dir)
    expanded: List[ContextFile] = []
    seen: set[str] = set()
    for item in files:
        key = str(item.path.resolve()).lower()
        if key not in seen:
            seen.add(key)
            expanded.append(item)
        if not item.relate:
            continue
        frontmatter = parse_simple_yaml_frontmatter(item.path)
        relation_paths = collect_relation_paths(frontmatter, project_root)
        for relation_path, label, source in relation_paths:
            add_unique_context(expanded, seen, relation_path, label, source)
            if source in {"相关人物", "相关势力"} and relation_path is not None:
                nested_frontmatter = parse_simple_yaml_frontmatter(relation_path)
                for nested_path, nested_label, nested_source in collect_first_degree_paths(nested_frontmatter, project_root):
                    add_unique_context(expanded, seen, nested_path, nested_label, f"{source}->{nested_source}")
    return expanded


def collect_relation_paths(frontmatter: Dict[str, Any], project_root: Path) -> List[tuple[Optional[Path], str, str]]:
    results: List[tuple[Optional[Path], str, str]] = []
    relation_fields = [
        ("相关人物", "人物", "相关人物"),
        ("相关势力", "势力", "相关势力"),
        ("相关素材", "素材", "相关素材"),
        ("相关伏笔", "伏笔", "相关伏笔"),
        ("一次关联人物", "人物", "一次关联人物"),
        ("一次关联势力", "势力", "一次关联势力"),
    ]
    for key, category, source in relation_fields:
        for name in as_list(frontmatter.get(key)):
            results.append((find_named_file(project_root, category, name), f"{source}-{name}", source))
    for raw_path in as_list(frontmatter.get("前置文件")) + as_list(frontmatter.get("后续文件")):
        path = resolve_path(raw_path, project_root)
        results.append((path if path.exists() else None, f"关联文件-{Path(raw_path).name}", "前置/后续文件"))
    return results


def collect_first_degree_paths(frontmatter: Dict[str, Any], project_root: Path) -> List[tuple[Optional[Path], str, str]]:
    results: List[tuple[Optional[Path], str, str]] = []
    relation_fields = [
        ("一次关联人物", "人物", "一次关联人物"),
        ("一次关联势力", "势力", "一次关联势力"),
    ]
    for key, category, source in relation_fields:
        for name in as_list(frontmatter.get(key)):
            results.append((find_named_file(project_root, category, name), f"{source}-{name}", source))
    return results


def render_context_file(item: ContextFile) -> str:
    label = item.label or item.path.name
    if not item.path.exists() or not item.path.is_file():
        if item.required:
            raise FileNotFoundError(f"context file not found: {item.path}")
        return f"## {label}\n\n> 可选文件不存在：`{item.path}`\n"
    content = item.path.read_text(encoding="utf-8", errors="replace")
    return f"## {label}\n\n路径：`{item.path}`\n\n```markdown\n{content}\n```\n"


def normalize_text_block(value: Any, base_dir: Path) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if value.get("path") or value.get("路径"):
            path = resolve_path(str(value.get("path") or value.get("路径")), base_dir)
            return path.read_text(encoding="utf-8", errors="replace")
        if value.get("text") or value.get("文本"):
            return str(value.get("text") or value.get("文本"))
    if isinstance(value, list):
        return "\n".join(str(item) for item in value)
    return str(value)


def normalize_optional_text_block(*values: Any, base_dir: Path) -> str:
    for value in values:
        text = normalize_text_block(value, base_dir).strip()
        if text:
            return text
    return ""


def infer_agent_name(payload: Dict[str, Any], system_prompt: str) -> str:
    raw = payload.get("agent") or payload.get("agent_name") or payload.get("agent名称")
    if raw is not None and str(raw).strip():
        return str(raw).strip()
    frontmatter = parse_yaml_subset(system_prompt.splitlines()[1:]) if system_prompt.startswith("---\n") else {}
    for key in ("name", "agent", "title"):
        value = frontmatter.get(key)
        if value:
            return str(value).strip()
    for line in system_prompt.splitlines():
        text = line.strip()
        if text.startswith("#"):
            return text.lstrip("#").strip() or "自定义md提示词agent"
    return "自定义md提示词agent"


def build_prompt(payload: Dict[str, Any], request_path: Path) -> str:
    base_dir = Path(payload.get("base_dir") or payload.get("基础目录") or request_path.parent).resolve()
    task_type = str(payload.get("task_type") or payload.get("任务类型") or "小说写作任务")
    target = str(payload.get("target") or payload.get("生成目标") or "")
    system_prompt = normalize_optional_text_block(
        payload.get("system_prompt"),
        payload.get("系统提示词"),
        payload.get("prompt"),
        payload.get("提示词"),
        payload.get("agent_prompt"),
        payload.get("agent_md"),
        payload.get("agent_markdown"),
        payload.get("md_prompt"),
        base_dir=base_dir,
    )
    agent_name = infer_agent_name(payload, system_prompt)
    user_prompt = normalize_text_block(payload.get("user_prompt") or payload.get("用户提示词"), base_dir)
    context_files = expand_related_context_files(normalize_context_files(payload, base_dir), payload, base_dir)
    extra = payload.get("extra") or payload.get("额外信息") or {}

    parts: List[str] = []
    parts.append(f"# 小说写作 Agent 请求\n")
    parts.append(f"## Agent\n\n{agent_name}\n")
    parts.append(f"## 任务类型\n\n{task_type}\n")
    if target:
        parts.append(f"## 生成目标\n\n{target}\n")
    if system_prompt:
        parts.append(f"## System Prompt\n\n{system_prompt}\n")
    if user_prompt:
        parts.append(f"## 用户提示词\n\n{user_prompt}\n")
    if extra:
        parts.append("## 额外信息\n")
        parts.append("```json\n" + json.dumps(extra, ensure_ascii=False, indent=2) + "\n```\n")
    parts.append("## 上下文文件全文\n")
    if not context_files:
        parts.append("无。\n")
    for item in context_files:
        parts.append(render_context_file(item))
    parts.append(
        "## 输出要求\n\n"
        "请严格基于以上 system prompt、用户提示词和上下文文件全文输出。"
        "如果需要新增人物、势力、设定或伏笔，必须明确标记“新增项”。"
        "如果发现上下文冲突，先报告冲突，不要强行写。\n"
    )
    return "\n".join(parts)


def default_output_dir(payload: Dict[str, Any], request_path: Path) -> Path:
    raw = payload.get("output_dir") or payload.get("输出目录")
    if raw:
        return resolve_path(str(raw), request_path.parent)
    project_root = payload.get("project") or payload.get("项目路径")
    if project_root:
        return resolve_path(str(project_root), request_path.parent) / "11-调度与生成" / "agent-runs"
    return request_path.parent / "agent-runs"


def timestamp_slug() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def run_llm_call(payload: Dict[str, Any], prompt_path: Path, output_path: Path) -> subprocess.CompletedProcess[str]:
    model = str(payload.get("model") or payload.get("模型") or "MoreCode/gpt-5.5")
    max_tokens = str(payload.get("max_tokens") or payload.get("最大输出token") or "8192")
    temperature = str(payload.get("temperature") or payload.get("温度") or "0.3")
    command_text = " ".join(
        [
            "&",
            ps_quote(str(MYCLI)),
            "agent-cli",
            "llm-call",
            "--model",
            ps_quote(model),
            "--prompt-file",
            ps_quote(str(prompt_path)),
            "--out",
            ps_quote(str(output_path)),
            "--max-tokens",
            ps_quote(max_tokens),
            "--temperature",
            ps_quote(temperature),
        ]
    )
    command = [
        "pwsh",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        command_text,
    ]
    env = dict(**__import__("os").environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    return subprocess.run(command, text=True, capture_output=True, encoding="utf-8", errors="replace", env=env)


def ps_quote(value: str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def should_split_output_files(payload: Dict[str, Any]) -> bool:
    value = payload.get("split_output_files", payload.get("拆分输出文件", False))
    return bool(value)


def split_output_base(payload: Dict[str, Any], request_path: Path) -> Path:
    raw = payload.get("split_output_base") or payload.get("拆分输出根目录") or payload.get("target") or payload.get("生成目标")
    project_raw = payload.get("project") or payload.get("项目路径") or payload.get("base_dir") or payload.get("基础目录")
    target_base = resolve_path(str(project_raw), request_path.parent) if project_raw else request_path.parent
    if raw:
        return resolve_path(str(raw), target_base)
    return target_base


def safe_output_child(base: Path, raw_path: str) -> Path:
    text = str(raw_path).strip().replace("/", "\\")
    if not text:
        raise ValueError("empty FILE path")
    candidate = Path(text)
    if ".." in candidate.parts:
        raise ValueError(f"unsafe FILE path: {raw_path}")
    resolved_base = base.resolve()
    resolved = candidate.resolve() if candidate.is_absolute() else (resolved_base / candidate).resolve()
    if resolved != resolved_base and resolved_base not in resolved.parents:
        raise ValueError(f"FILE path escapes split output base: {raw_path}")
    return resolved


def apply_split_output_files(output_path: Path, base: Path) -> Dict[str, Any]:
    text = output_path.read_text(encoding="utf-8", errors="replace") if output_path.exists() else ""
    matches = list(FILE_BLOCK_RE.finditer(text))
    block_style = "angle"
    if not matches:
        matches = list(PLAIN_FILE_BLOCK_RE.finditer(text))
        block_style = "plain"
    written: List[str] = []
    errors: List[str] = []
    for match in matches:
        raw_path = match.group("path")
        content = match.group("content").strip()
        try:
            target = safe_output_child(base, raw_path)
            write_text(target, content + "\n")
            written.append(str(target))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{raw_path}: {exc}")
    return {
        "ok": bool(matches) and not errors,
        "base": str(base),
        "block_style": block_style,
        "blocks": len(matches),
        "written": written,
        "errors": errors,
    }


def command_build_prompt(args: argparse.Namespace) -> int:
    request_path = Path(args.request).resolve()
    payload = read_json(request_path)
    prompt = build_prompt(payload, request_path)
    output_path = Path(args.out).resolve() if args.out else default_output_dir(payload, request_path) / f"{timestamp_slug()}-提示词.md"
    write_text(output_path, prompt)
    print(str(output_path))
    return 0


def command_collect_context(args: argparse.Namespace) -> int:
    request_path = Path(args.request).resolve()
    payload = read_json(request_path)
    base_dir = Path(payload.get("base_dir") or payload.get("基础目录") or request_path.parent).resolve()
    context_files = expand_related_context_files(normalize_context_files(payload, base_dir), payload, base_dir)
    result = {
        "request": str(request_path),
        "context_files": [
            {
                "path": str(item.path),
                "label": item.label or item.path.name,
                "required": item.required,
                "source": item.source,
            }
            for item in context_files
        ],
    }
    output_path = Path(args.out).resolve() if args.out else default_output_dir(payload, request_path) / f"{timestamp_slug()}-关联上下文.json"
    write_text(output_path, json.dumps(result, ensure_ascii=False, indent=2))
    print(str(output_path))
    return 0


def dump_yaml_value(value: Any) -> str:
    if isinstance(value, list):
        return "[" + ", ".join(str(item) for item in value) + "]"
    return str(value)


def read_frontmatter_and_body(path: Path) -> tuple[Dict[str, Any], str]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    yaml_lines: List[str] = []
    body_start = 0
    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            body_start = index + 1
            break
        yaml_lines.append(line)
    if body_start == 0:
        return {}, text
    body = "\n".join(lines[body_start:])
    return parse_yaml_subset(yaml_lines), body


def write_frontmatter_and_body(path: Path, frontmatter: Dict[str, Any], body: str) -> None:
    lines = ["---"]
    for key, value in frontmatter.items():
        lines.append(f"{key}: {dump_yaml_value(value)}")
    lines.append("---")
    lines.append("")
    lines.append(body.lstrip("\n"))
    write_text(path, "\n".join(lines))


def merge_unique(existing: Any, additions: Any) -> List[str]:
    result: List[str] = []
    for item in as_list(existing) + as_list(additions):
        if item not in result:
            result.append(item)
    return result


def apply_relations_payload(payload: Dict[str, Any], result_path: Path, dry_run: bool = False) -> Dict[str, Any]:
    base_dir = Path(payload.get("项目路径") or payload.get("project") or result_path.parent).resolve()
    target_raw = payload.get("目标文件") or payload.get("target")
    if not target_raw:
        raise ValueError("relation JSON missing 目标文件/target")
    target_path = resolve_path(str(target_raw), base_dir)
    frontmatter, body = read_frontmatter_and_body(target_path)
    updates = payload.get("写入YAML") or payload.get("yaml") or {}
    if not isinstance(updates, dict):
        raise ValueError("relation JSON 写入YAML/yaml must be an object")
    for key, value in updates.items():
        frontmatter[key] = merge_unique(frontmatter.get(key), value)
    if not dry_run:
        write_frontmatter_and_body(target_path, frontmatter, body)
    result = {
        "ok": True,
        "dry_run": bool(dry_run),
        "target": str(target_path),
        "updated_keys": list(updates.keys()),
        "frontmatter": frontmatter,
    }
    write_text(result_path, json.dumps(result, ensure_ascii=False, indent=2))
    return result


def should_auto_apply_relations(payload: Dict[str, Any]) -> bool:
    agent_name = str(payload.get("agent") or payload.get("agent_name") or payload.get("agent名称") or "")
    task_type = str(payload.get("task_type") or payload.get("任务类型") or "")
    is_relation_task = "关联判断" in agent_name or "关联判断" in task_type
    if not is_relation_task:
        return False
    value = payload.get("auto_apply_relations", payload.get("自动应用关联", True))
    return bool(value)


def command_apply_relations(args: argparse.Namespace) -> int:
    relation_path = Path(args.relation_json).resolve()
    payload = read_json_relaxed(relation_path)
    output_path = Path(args.out).resolve() if args.out else relation_path.with_suffix(".apply-result.json")
    apply_relations_payload(payload, output_path, dry_run=bool(args.dry_run))
    print(str(output_path))
    return 0


def command_run(args: argparse.Namespace) -> int:
    request_path = Path(args.request).resolve()
    payload = read_json(request_path)
    run_dir = default_output_dir(payload, request_path) / timestamp_slug()
    prompt_path = run_dir / "提示词.md"
    output_path = run_dir / "输出.md"
    meta_path = run_dir / "run.json"
    prompt = build_prompt(payload, request_path)
    write_text(prompt_path, prompt)
    completed = run_llm_call(payload, prompt_path, output_path)
    if completed.returncode == 0 and not output_path.exists() and completed.stdout:
        write_text(output_path, completed.stdout)
    if completed.returncode == 0:
        target_raw = payload.get("target") or payload.get("生成目标")
        project_raw = payload.get("project") or payload.get("项目路径") or payload.get("base_dir") or payload.get("基础目录")
        if target_raw and output_path.exists():
            target_base = resolve_path(str(project_raw), request_path.parent) if project_raw else request_path.parent
            target_path = resolve_path(str(target_raw), target_base)
            write_text(target_path, output_path.read_text(encoding="utf-8", errors="replace"))
    split_result: Optional[Dict[str, Any]] = None
    if completed.returncode == 0 and should_split_output_files(payload) and output_path.exists():
        split_result = apply_split_output_files(output_path, split_output_base(payload, request_path))
    meta = {
        "ok": completed.returncode == 0,
        "request": str(request_path),
        "prompt": str(prompt_path),
        "output": str(output_path),
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }
    if completed.returncode == 0 and payload.get("target") and output_path.exists():
        meta["target"] = str(resolve_path(str(payload.get("target")), resolve_path(str(payload.get("project") or payload.get("base_dir") or request_path.parent), request_path.parent)))
    if split_result is not None:
        meta["split_output_files"] = split_result
    if completed.returncode == 0 and should_auto_apply_relations(payload):
        try:
            relation_payload = read_json_relaxed(output_path)
            apply_result_path = output_path.with_suffix(".apply-result.json")
            meta["auto_apply_relations"] = apply_relations_payload(relation_payload, apply_result_path)
            meta["auto_apply_relations"]["result_path"] = str(apply_result_path)
        except Exception as exc:  # noqa: BLE001
            meta["auto_apply_relations"] = {"ok": False, "error": str(exc)}
    write_text(meta_path, json.dumps(meta, ensure_ascii=False, indent=2))
    if completed.returncode != 0:
        print(str(meta_path))
        print(completed.stderr, file=sys.stderr)
        return completed.returncode
    print(str(output_path))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Novel writing JSON-driven agent runner")
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build-prompt", help="Build a prompt from a JSON request")
    build.add_argument("request", help="Path to request JSON")
    build.add_argument("--out", default="", help="Optional output prompt path")
    build.set_defaults(func=command_build_prompt)

    run = sub.add_parser("run", help="Build prompt and call model via mycli agent-cli llm-call")
    run.add_argument("request", help="Path to request JSON")
    run.set_defaults(func=command_run)

    collect = sub.add_parser("collect-context", help="Expand related context files from a JSON request")
    collect.add_argument("request", help="Path to request JSON")
    collect.add_argument("--out", default="", help="Optional output JSON path")
    collect.set_defaults(func=command_collect_context)

    apply_rel = sub.add_parser("apply-relations", help="Apply relation JSON into target Markdown YAML")
    apply_rel.add_argument("relation_json", help="Path to relation JSON")
    apply_rel.add_argument("--dry-run", action="store_true", help="Do not write target Markdown")
    apply_rel.add_argument("--out", default="", help="Optional result JSON path")
    apply_rel.set_defaults(func=command_apply_relations)
    return parser


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
