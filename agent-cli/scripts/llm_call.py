#!/usr/bin/env python3
r"""Direct model API caller for mycli agent-cli llm-call.

This script intentionally uses only the Python standard library. It reads the
workspace model registry from D:\agent_workspace\config\models.json, resolves
models by provider/model, infers the API protocol from the provider's npm field,
and performs one-shot chat, vision, image generation, or image edit requests.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


CONFIG_PATH = Path(r"D:\agent_workspace\config\models.json")
DEFAULT_PICTURE_DIR = Path(r"D:\agent_workspace\tmp\llm-picture")


try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


class LlmCallError(Exception):
    pass


def fail(message: str) -> None:
    print(f"[llm-call] {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8-sig") as f:
            return json.load(f)
    except FileNotFoundError:
        raise LlmCallError(f"Required JSON file not found: {path}")
    except json.JSONDecodeError as exc:
        raise LlmCallError(f"Failed to parse JSON file {path}: {exc}")


def read_text_file(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8-sig")
    except Exception as exc:  # noqa: BLE001
        raise LlmCallError(f"Failed to read prompt file {path}: {exc}")


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "mycli-agent-cli-llm-call/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read()
            content_type = resp.headers.get("content-type", "")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise LlmCallError(f"HTTP {exc.code} while fetching prompt URL {url}: {body[:1000]}")
    except Exception as exc:  # noqa: BLE001
        raise LlmCallError(f"Failed to fetch prompt URL {url}: {exc}")

    charset = "utf-8"
    match = re.search(r"charset=([^;\s]+)", content_type, flags=re.I)
    if match:
        charset = match.group(1).strip('"')
    return raw.decode(charset, errors="replace")


def split_model_name(model: str) -> Tuple[str, str]:
    if not model or "/" not in model:
        raise LlmCallError("--model must use provider/model format, for example custom-aiapi-meccy-top/gpt-5.4")
    provider, model_id = model.split("/", 1)
    if not provider or not model_id:
        raise LlmCallError("--model must use provider/model format with non-empty provider and model")
    return provider, model_id


def protocol_from_npm(npm: str) -> str:
    mapping = {
        "@ai-sdk/openai-compatible": "openai-compatible",
        "@ai-sdk/openai": "openai",
        "@ai-sdk/anthropic": "anthropic",
        "@ai-sdk/google": "gemini",
        "@ai-sdk/google-generative-ai": "gemini",
    }
    if npm in mapping:
        return mapping[npm]
    raise LlmCallError(f"Unsupported provider npm protocol '{npm}'. Add an adapter before using this provider.")


def normalize_base_url(base_url: str) -> str:
    return (base_url or "").rstrip("/")


def resolve_model(config: Dict[str, Any], model_name: str) -> Dict[str, Any]:
    provider_id, model_id = split_model_name(model_name)
    providers = config.get("provider") or {}
    if provider_id not in providers:
        raise LlmCallError(f"Provider '{provider_id}' was not found in {CONFIG_PATH}")
    provider = providers[provider_id]
    models = provider.get("models") or {}
    if model_id not in models:
        raise LlmCallError(f"Model '{model_id}' was not found under provider '{provider_id}' in {CONFIG_PATH}")
    model = models[model_id] or {}
    options = provider.get("options") or {}
    base_url = normalize_base_url(str(options.get("baseURL") or options.get("baseUrl") or ""))
    api_key = str(options.get("apiKey") or "")
    npm = str(provider.get("npm") or "")
    protocol = protocol_from_npm(npm)
    actual_model = str(model.get("name") or model_id)

    if not base_url:
        raise LlmCallError(f"Provider '{provider_id}' has no options.baseURL in {CONFIG_PATH}")
    if not api_key:
        raise LlmCallError(f"Provider '{provider_id}' has no options.apiKey in {CONFIG_PATH}")

    return {
        "provider_id": provider_id,
        "model_id": model_id,
        "model_name": actual_model,
        "provider": provider,
        "model": model,
        "protocol": protocol,
        "base_url": base_url,
        "api_key": api_key,
    }


def redacted_model_info(resolved: Dict[str, Any]) -> Dict[str, Any]:
    provider = resolved["provider"]
    options = provider.get("options") or {}
    return {
        "provider": resolved["provider_id"],
        "model": resolved["model_id"],
        "requestModel": resolved["model_name"],
        "protocol": resolved["protocol"],
        "npm": provider.get("npm"),
        "name": provider.get("name"),
        "baseURL": options.get("baseURL") or options.get("baseUrl"),
        "apiKey": "***" if options.get("apiKey") else None,
        "modalities": (resolved["model"] or {}).get("modalities"),
        "limit": (resolved["model"] or {}).get("limit"),
    }


def list_models(config: Dict[str, Any]) -> None:
    providers = config.get("provider") or {}
    for provider_id in sorted(providers.keys()):
        provider = providers[provider_id]
        try:
            protocol = protocol_from_npm(str(provider.get("npm") or ""))
        except LlmCallError:
            protocol = "unsupported"
        for model_id in sorted((provider.get("models") or {}).keys()):
            model = (provider.get("models") or {}).get(model_id) or {}
            modalities = model.get("modalities") or {}
            input_modes = ",".join(modalities.get("input") or []) or "?"
            output_modes = ",".join(modalities.get("output") or []) or "?"
            print(f"{provider_id}/{model_id}\t{protocol}\tinput:{input_modes}\toutput:{output_modes}")


def infer_task(args: argparse.Namespace) -> str:
    if args.task:
        return args.task
    if args.image or args.image_url:
        return "vision"
    return "chat"


def compose_prompt(args: argparse.Namespace) -> str:
    parts: List[str] = []
    if args.prompt:
        parts.append(args.prompt)
    for path in args.prompt_file or []:
        parts.append(read_text_file(path))
    for url in args.prompt_url or []:
        parts.append(fetch_text(url))
    prompt = "\n\n".join(part for part in parts if part is not None)
    return prompt


def compose_system(args: argparse.Namespace) -> str:
    parts: List[str] = []
    if args.system:
        parts.append(args.system)
    for path in args.system_file or []:
        parts.append(read_text_file(path))
    return "\n\n".join(parts)


def guess_mime(path_or_url: str, default: str = "image/png") -> str:
    guessed, _ = mimetypes.guess_type(path_or_url)
    return guessed or default


def image_path_to_data_url(path: str) -> str:
    p = Path(path)
    if not p.exists():
        raise LlmCallError(f"Image file not found: {path}")
    try:
        data = p.read_bytes()
    except Exception as exc:  # noqa: BLE001
        raise LlmCallError(f"Failed to read image file {path}: {exc}")
    mime = guess_mime(path)
    return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"


def collect_image_inputs(args: argparse.Namespace) -> List[Dict[str, str]]:
    images: List[Dict[str, str]] = []
    for path in args.image or []:
        images.append({"kind": "data_url", "value": image_path_to_data_url(path), "source": path, "mime": guess_mime(path)})
    for url in args.image_url or []:
        images.append({"kind": "url", "value": url, "source": url, "mime": guess_mime(url)})
    return images


def http_json(method: str, url: str, headers: Dict[str, str], payload: Any, stream: bool = False) -> Any:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req_headers = {"Content-Type": "application/json", **headers}
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            if stream:
                for chunk in iter(lambda: resp.readline(), b""):
                    if not chunk:
                        break
                    text = chunk.decode("utf-8", errors="replace")
                    sys.stdout.write(text)
                    sys.stdout.flush()
                return {"streamed": True}
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise LlmCallError(f"HTTP {exc.code} from {url}: {body[:4000]}")
    except Exception as exc:  # noqa: BLE001
        raise LlmCallError(f"Request failed for {url}: {exc}")

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw_text": raw}


def http_multipart(url: str, headers: Dict[str, str], fields: Dict[str, str], files: List[Tuple[str, str]]) -> Any:
    boundary = "----mycli-llm-call-" + uuid.uuid4().hex
    body = bytearray()

    def add_line(value: bytes) -> None:
        body.extend(value + b"\r\n")

    for name, value in fields.items():
        add_line(f"--{boundary}".encode())
        add_line(f'Content-Disposition: form-data; name="{name}"'.encode())
        add_line(b"")
        add_line(str(value).encode("utf-8"))

    for field_name, path in files:
        p = Path(path)
        if not p.exists():
            raise LlmCallError(f"Image file not found: {path}")
        filename = p.name
        mime = guess_mime(path, "application/octet-stream")
        add_line(f"--{boundary}".encode())
        add_line(f'Content-Disposition: form-data; name="{field_name}"; filename="{filename}"'.encode())
        add_line(f"Content-Type: {mime}".encode())
        add_line(b"")
        body.extend(p.read_bytes())
        body.extend(b"\r\n")

    add_line(f"--{boundary}--".encode())
    req_headers = {**headers, "Content-Type": f"multipart/form-data; boundary={boundary}"}
    req = urllib.request.Request(url, data=bytes(body), headers=req_headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        body_text = exc.read().decode("utf-8", errors="replace")
        raise LlmCallError(f"HTTP {exc.code} from {url}: {body_text[:4000]}")
    except Exception as exc:  # noqa: BLE001
        raise LlmCallError(f"Multipart request failed for {url}: {exc}")

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw_text": raw}


def openai_messages(system: str, prompt: str, images: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    messages: List[Dict[str, Any]] = []
    if system:
        messages.append({"role": "system", "content": system})
    if images:
        content: List[Dict[str, Any]] = []
        if prompt:
            content.append({"type": "text", "text": prompt})
        for image in images:
            content.append({"type": "image_url", "image_url": {"url": image["value"]}})
        messages.append({"role": "user", "content": content})
    else:
        messages.append({"role": "user", "content": prompt})
    return messages


def invoke_openai_chat(resolved: Dict[str, Any], args: argparse.Namespace, task: str, prompt: str, system: str, images: List[Dict[str, str]]) -> Any:
    url = f"{resolved['base_url']}/chat/completions"
    payload: Dict[str, Any] = {
        "model": resolved["model_name"],
        "messages": openai_messages(system, prompt, images),
    }
    if args.temperature is not None:
        payload["temperature"] = args.temperature
    if args.max_tokens is not None:
        payload["max_tokens"] = args.max_tokens
    if args.stream:
        payload["stream"] = True
    return http_json("POST", url, {"Authorization": f"Bearer {resolved['api_key']}"}, payload, stream=args.stream)


def invoke_openai_image_generate(resolved: Dict[str, Any], args: argparse.Namespace, prompt: str) -> Any:
    url = f"{resolved['base_url']}/images/generations"
    payload: Dict[str, Any] = {
        "model": resolved["model_name"],
        "prompt": prompt,
        "n": args.n,
    }
    if args.size:
        payload["size"] = args.size
    return http_json("POST", url, {"Authorization": f"Bearer {resolved['api_key']}"}, payload)


def invoke_openai_image_edit(resolved: Dict[str, Any], args: argparse.Namespace, prompt: str) -> Any:
    if not args.image:
        raise LlmCallError("--task image-edit requires at least one local --image path for OpenAI-compatible image edit API")
    url = f"{resolved['base_url']}/images/edits"
    fields = {"model": resolved["model_name"], "prompt": prompt, "n": str(args.n)}
    if args.size:
        fields["size"] = args.size
    files = [("image", path) for path in args.image]
    return http_multipart(url, {"Authorization": f"Bearer {resolved['api_key']}"}, fields, files)


def anthropic_content(prompt: str, images: List[Dict[str, str]]) -> List[Dict[str, Any]] | str:
    if not images:
        return prompt
    content: List[Dict[str, Any]] = []
    if prompt:
        content.append({"type": "text", "text": prompt})
    for image in images:
        if image["kind"] == "url":
            content.append({"type": "image", "source": {"type": "url", "url": image["value"]}})
        else:
            value = image["value"]
            match = re.match(r"data:([^;]+);base64,(.*)", value, flags=re.S)
            if not match:
                raise LlmCallError(f"Invalid image data URL for {image['source']}")
            content.append({"type": "image", "source": {"type": "base64", "media_type": match.group(1), "data": match.group(2)}})
    return content


def invoke_anthropic_chat(resolved: Dict[str, Any], args: argparse.Namespace, task: str, prompt: str, system: str, images: List[Dict[str, str]]) -> Any:
    url = f"{resolved['base_url']}/messages"
    payload: Dict[str, Any] = {
        "model": resolved["model_name"],
        "max_tokens": args.max_tokens or 4096,
        "messages": [{"role": "user", "content": anthropic_content(prompt, images)}],
    }
    if system:
        payload["system"] = system
    if args.temperature is not None:
        payload["temperature"] = args.temperature
    return http_json("POST", url, {"x-api-key": resolved["api_key"], "anthropic-version": "2023-06-01"}, payload)


def gemini_parts(prompt: str, images: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    parts: List[Dict[str, Any]] = []
    if prompt:
        parts.append({"text": prompt})
    for image in images:
        if image["kind"] == "url":
            raise LlmCallError("Gemini native adapter does not support --image-url yet; use a local --image path")
        match = re.match(r"data:([^;]+);base64,(.*)", image["value"], flags=re.S)
        if not match:
            raise LlmCallError(f"Invalid image data URL for {image['source']}")
        parts.append({"inline_data": {"mime_type": match.group(1), "data": match.group(2)}})
    return parts


def invoke_gemini_chat(resolved: Dict[str, Any], args: argparse.Namespace, task: str, prompt: str, system: str, images: List[Dict[str, str]]) -> Any:
    base = resolved["base_url"]
    sep = "&" if "?" in base else "?"
    url = f"{base}/v1beta/models/{urllib.parse.quote(resolved['model_name'], safe='')}:generateContent{sep}key={urllib.parse.quote(resolved['api_key'])}"
    parts = gemini_parts(prompt, images)
    if system:
        parts.insert(0, {"text": f"System instruction:\n{system}"})
    payload: Dict[str, Any] = {"contents": [{"role": "user", "parts": parts}]}
    gen_config: Dict[str, Any] = {}
    if args.temperature is not None:
        gen_config["temperature"] = args.temperature
    if args.max_tokens is not None:
        gen_config["maxOutputTokens"] = args.max_tokens
    if gen_config:
        payload["generationConfig"] = gen_config
    return http_json("POST", url, {}, payload)


def invoke_call(resolved: Dict[str, Any], args: argparse.Namespace, task: str, prompt: str, system: str, images: List[Dict[str, str]]) -> Any:
    protocol = resolved["protocol"]
    if task in {"chat", "vision"}:
        if protocol in {"openai-compatible", "openai"}:
            return invoke_openai_chat(resolved, args, task, prompt, system, images)
        if protocol == "anthropic":
            return invoke_anthropic_chat(resolved, args, task, prompt, system, images)
        if protocol == "gemini":
            return invoke_gemini_chat(resolved, args, task, prompt, system, images)
    if task == "image-generate":
        if protocol in {"openai-compatible", "openai"}:
            if args.image_api in {"auto", "images"}:
                try:
                    return invoke_openai_image_generate(resolved, args, prompt)
                except LlmCallError:
                    if args.image_api == "images":
                        raise
            return invoke_openai_chat(resolved, args, task, prompt, system, images)
        if protocol == "gemini":
            return invoke_gemini_chat(resolved, args, task, prompt, system, images)
        raise LlmCallError(f"Protocol {protocol} does not support image-generate in llm-call")
    if task == "image-edit":
        if protocol in {"openai-compatible", "openai"}:
            if args.image_api in {"auto", "images"}:
                try:
                    return invoke_openai_image_edit(resolved, args, prompt)
                except LlmCallError:
                    if args.image_api == "images":
                        raise
            return invoke_openai_chat(resolved, args, task, prompt, system, images)
        if protocol == "gemini":
            return invoke_gemini_chat(resolved, args, task, prompt, system, images)
        raise LlmCallError(f"Protocol {protocol} does not support image-edit in llm-call")
    raise LlmCallError(f"Unsupported task: {task}")


def extract_text(raw: Any, protocol: str) -> str:
    if not isinstance(raw, dict):
        return str(raw)
    if "raw_text" in raw:
        return str(raw["raw_text"])
    if "choices" in raw and raw["choices"]:
        choice = raw["choices"][0]
        message = choice.get("message") or {}
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            texts = []
            for item in content:
                if isinstance(item, dict):
                    if item.get("type") in {"text", "output_text"} and "text" in item:
                        texts.append(str(item["text"]))
                    elif "text" in item:
                        texts.append(str(item["text"]))
            return "\n".join(texts)
    if "content" in raw and isinstance(raw["content"], list):
        texts = []
        for item in raw["content"]:
            if isinstance(item, dict) and item.get("type") == "text":
                texts.append(str(item.get("text") or ""))
        return "\n".join(texts)
    if "candidates" in raw and raw["candidates"]:
        texts = []
        for cand in raw["candidates"]:
            for part in ((cand.get("content") or {}).get("parts") or []):
                if "text" in part:
                    texts.append(str(part["text"]))
        return "\n".join(texts)
    return json.dumps(raw, ensure_ascii=False, indent=2)


def extract_usage(raw: Any) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    if isinstance(raw.get("usage"), dict):
        usage = raw["usage"]
        return {
            "input_tokens": usage.get("prompt_tokens") or usage.get("input_tokens"),
            "output_tokens": usage.get("completion_tokens") or usage.get("output_tokens"),
            "total_tokens": usage.get("total_tokens"),
        }
    if isinstance(raw.get("usageMetadata"), dict):
        usage = raw["usageMetadata"]
        return {
            "input_tokens": usage.get("promptTokenCount"),
            "output_tokens": usage.get("candidatesTokenCount"),
            "total_tokens": usage.get("totalTokenCount"),
        }
    return {}


def image_output_paths(args: argparse.Namespace, count: int, extension: str) -> List[Path]:
    if args.out:
        out = Path(args.out)
        if count <= 1:
            return [out]
        stem = out.stem
        suffix = out.suffix or extension
        return [out.with_name(f"{stem}-{i + 1:03d}{suffix}") for i in range(count)]
    out_dir = Path(args.out_dir) if args.out_dir else DEFAULT_PICTURE_DIR
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return [out_dir / f"llm-picture-{stamp}-{i + 1:03d}{extension}" for i in range(count)]


def save_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def save_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def download_binary(url: str) -> Tuple[bytes, str]:
    req = urllib.request.Request(url, headers={"User-Agent": "mycli-agent-cli-llm-call/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            data = resp.read()
            content_type = resp.headers.get("content-type", "")
    except Exception as exc:  # noqa: BLE001
        raise LlmCallError(f"Failed to download generated image {url}: {exc}")
    ext = mimetypes.guess_extension(content_type.split(";")[0].strip()) or Path(urllib.parse.urlparse(url).path).suffix or ".png"
    return data, ext


def data_url_to_bytes(value: str) -> Tuple[bytes, str]:
    match = re.match(r"data:([^;]+);base64,(.*)", value, flags=re.S)
    if not match:
        raise LlmCallError("Invalid data image URL")
    mime = match.group(1)
    data = base64.b64decode(re.sub(r"\s+", "", match.group(2)))
    ext = mimetypes.guess_extension(mime) or ".png"
    return data, ext


def find_images(raw: Any, text: str) -> List[Tuple[str, str]]:
    found: List[Tuple[str, str]] = []
    if isinstance(raw, dict):
        for item in raw.get("data") or []:
            if not isinstance(item, dict):
                continue
            if item.get("b64_json"):
                found.append(("base64", str(item["b64_json"])))
            if item.get("url"):
                found.append(("url", str(item["url"])))
        for cand in raw.get("candidates") or []:
            for part in ((cand.get("content") or {}).get("parts") or []):
                inline = part.get("inline_data") or part.get("inlineData")
                if inline and inline.get("data"):
                    mime = inline.get("mime_type") or inline.get("mimeType") or "image/png"
                    found.append(("data_url", f"data:{mime};base64,{inline['data']}"))
    if text:
        for data_url in re.findall(r"data:image/[^\s)'\"]+;base64,[A-Za-z0-9+/=\r\n]+", text):
            found.append(("data_url", data_url))
        for url in re.findall(r"https?://[^\s)'\"]+\.(?:png|jpg|jpeg|webp|gif)(?:\?[^\s)'\"]*)?", text, flags=re.I):
            found.append(("url", url))
    return found


def save_extracted_images(args: argparse.Namespace, raw: Any, text: str) -> List[Dict[str, str]]:
    images = find_images(raw, text)
    saved: List[Dict[str, str]] = []
    prepared: List[Tuple[bytes, str]] = []
    for kind, value in images:
        if kind == "base64":
            prepared.append((base64.b64decode(re.sub(r"\s+", "", value)), ".png"))
        elif kind == "data_url":
            prepared.append(data_url_to_bytes(value))
        elif kind == "url":
            prepared.append(download_binary(value))
    if not prepared:
        return saved
    paths = image_output_paths(args, len(prepared), prepared[0][1] or ".png")
    for idx, (data, ext) in enumerate(prepared):
        path = paths[idx]
        if not path.suffix:
            path = path.with_suffix(ext or ".png")
        save_bytes(path, data)
        saved.append({"path": str(path), "mime": guess_mime(str(path)), "bytes": str(len(data))})
    return saved


def standard_result(resolved: Dict[str, Any], task: str, raw: Any, text: str, saved_images: List[Dict[str, str]]) -> Dict[str, Any]:
    return {
        "provider": resolved["provider_id"],
        "model": resolved["model_id"],
        "requestModel": resolved["model_name"],
        "protocol": resolved["protocol"],
        "task": task,
        "content": text,
        "images": saved_images,
        "usage": extract_usage(raw),
        "raw": raw,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Call configured LLM APIs directly via provider/model from models.json.")
    parser.add_argument("--model")
    parser.add_argument("--task", choices=["chat", "vision", "image-generate", "image-edit"])
    parser.add_argument("--prompt")
    parser.add_argument("--prompt-file", action="append")
    parser.add_argument("--prompt-url", action="append")
    parser.add_argument("--system")
    parser.add_argument("--system-file", action="append")
    parser.add_argument("--image", action="append")
    parser.add_argument("--image-url", action="append")
    parser.add_argument("--output", choices=["text", "json", "raw"], default="text")
    parser.add_argument("--stream", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--out-dir")
    parser.add_argument("--size")
    parser.add_argument("--n", type=int, default=1)
    parser.add_argument("--temperature", type=float)
    parser.add_argument("--max-tokens", type=int)
    parser.add_argument("--image-api", choices=["auto", "images", "chat"], default="auto")
    parser.add_argument("--list-models", action="store_true")
    parser.add_argument("--show-model", action="store_true")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config = load_json(CONFIG_PATH)
        if args.list_models:
            list_models(config)
            return 0
        if not args.model:
            raise LlmCallError("Missing required --model <provider/model>. Use --list-models to inspect available models.")
        resolved = resolve_model(config, args.model)
        if args.show_model:
            print(json.dumps(redacted_model_info(resolved), ensure_ascii=False, indent=2))
            return 0

        task = infer_task(args)
        prompt = compose_prompt(args)
        system = compose_system(args)
        if not prompt and task in {"chat", "vision", "image-generate", "image-edit"}:
            raise LlmCallError("Missing prompt input. Provide --prompt, --prompt-file, or --prompt-url.")
        images = collect_image_inputs(args)
        if task == "vision" and not images:
            raise LlmCallError("--task vision requires --image or --image-url")
        raw = invoke_call(resolved, args, task, prompt, system, images)
        if args.stream:
            return 0
        text = extract_text(raw, resolved["protocol"])
        saved_images = save_extracted_images(args, raw, text) if task in {"image-generate", "image-edit"} else []
        result = standard_result(resolved, task, raw, text, saved_images)

        if args.output == "raw":
            output_text = json.dumps(raw, ensure_ascii=False, indent=2)
        elif args.output == "json":
            output_text = json.dumps(result, ensure_ascii=False, indent=2)
        else:
            output_text = text or ""

        if args.out and output_text:
            save_text(Path(args.out), output_text)

        if args.output == "text":
            if text:
                print(text)
            for image in saved_images:
                print(f"Saved image: {image['path']}")
            if task in {"image-generate", "image-edit"} and not saved_images:
                print("[llm-call] No image was detected in the response.", file=sys.stderr)
        else:
            print(output_text)
        return 0
    except LlmCallError as exc:
        fail(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
