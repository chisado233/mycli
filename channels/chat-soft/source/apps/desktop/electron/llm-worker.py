from __future__ import annotations

import json
import sys
from pathlib import Path


def read_stdin() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        raise RuntimeError("empty stdin payload")
    return json.loads(raw)


def main() -> int:
    payload = read_stdin()
    llm_source_dir = Path(payload["llmSourceDir"]).resolve()
    if not llm_source_dir.exists():
        raise RuntimeError(f"llm source dir not found: {llm_source_dir}")
    sys.path.insert(0, str(llm_source_dir))

    from llm import LLM  # type: ignore

    config_path = str(Path(payload["configPath"]).resolve())
    llm = LLM.from_openclaw_config(config_path)
    action = str(payload.get("action", "")).strip()

    if action == "list_models":
        models: list[dict[str, str]] = []
        for provider, config in llm.provider_configs.items():
            raw_models = config.get("models", [])
            if not isinstance(raw_models, list):
                continue
            for model in raw_models:
                if isinstance(model, str) and model.strip():
                    models.append({"provider": provider, "model": model.strip()})
                    continue
                if isinstance(model, dict):
                    model_id = str(model.get("id", "")).strip()
                    if model_id:
                        models.append({"provider": provider, "model": model_id})
        print(json.dumps({"ok": True, "models": models}, ensure_ascii=False))
        return 0

    if action == "chat":
        response = llm.call_chat(
            provider=str(payload["provider"]),
            model=str(payload["model"]),
            messages=payload.get("messages", []),
            temperature=float(payload.get("temperature", 1)),
            max_tokens=int(payload.get("maxTokens", 1024)),
        )
        print(
            json.dumps(
                {
                    "ok": response.ok,
                    "provider": response.provider,
                    "model": response.model,
                    "content": response.message.content,
                    "error": response.error,
                },
                ensure_ascii=False,
            )
        )
        return 0

    raise RuntimeError(f"unknown action: {action}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(str(exc))
        raise SystemExit(1)
