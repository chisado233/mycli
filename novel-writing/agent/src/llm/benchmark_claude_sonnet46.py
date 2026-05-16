from __future__ import annotations

import json
import statistics
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List

from llm import LLM


CONFIG_PATH = Path(r"D:\agent_workspace\projects\mult_agent\config\llm.json")
PROVIDER = "mytokenland"
MODEL = "claude-sonnet-4-6"
OUTPUT_PATH = Path(r"D:\agent_workspace\projects\mult_agent\src\llm\benchmark_claude_sonnet46_result.json")


def percentile(values: List[float], ratio: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, int(round((len(ordered) - 1) * ratio))))
    return ordered[index]


def summarize_latencies(latencies: List[float]) -> Dict[str, float]:
    if not latencies:
        return {"count": 0, "avg_seconds": 0.0, "p50_seconds": 0.0, "p95_seconds": 0.0, "max_seconds": 0.0}
    return {
        "count": len(latencies),
        "avg_seconds": round(statistics.mean(latencies), 3),
        "p50_seconds": round(percentile(latencies, 0.50), 3),
        "p95_seconds": round(percentile(latencies, 0.95), 3),
        "max_seconds": round(max(latencies), 3),
    }


def call_once(client: LLM, messages: List[Dict[str, Any]], max_tokens: int) -> Dict[str, Any]:
    started = time.perf_counter()
    response = client.call_chat(
        provider=PROVIDER,
        model=MODEL,
        messages=messages,
        temperature=0.0,
        max_tokens=max_tokens,
    )
    elapsed = time.perf_counter() - started
    content = response.message.content or ""
    returned_model = ""
    if isinstance(response.raw_response, dict):
        returned_model = str(response.raw_response.get("model", ""))
    completion_tokens = int(response.usage.completion_tokens or 0)
    chars = len(content)
    return {
        "ok": response.ok,
        "latency_seconds": round(elapsed, 3),
        "finish_reason": response.finish_reason,
        "error": response.error,
        "content_preview": content[:200],
        "content_length_chars": chars,
        "completion_tokens": completion_tokens,
        "tokens_per_second": round(completion_tokens / elapsed, 3) if elapsed > 0 and completion_tokens > 0 else 0.0,
        "chars_per_second": round(chars / elapsed, 3) if elapsed > 0 and chars > 0 else 0.0,
        "returned_model": returned_model,
    }


def run_multiturn(client: LLM) -> Dict[str, Any]:
    conversation: List[Dict[str, str]] = [
        {"role": "system", "content": "你是一个简洁、准确的中文助手。"}
    ]
    prompts = [
        "用一句话介绍你自己。",
        "现在再用两句话解释什么是多轮对话测试。",
        "请列出三个会影响响应速度的常见因素，每点不超过12个字。",
        "基于前文，用80字以内总结如何提高并发稳定性。",
        "最后，用一句话确认你记得我们正在测试 claude-sonnet-4-6。",
    ]
    turns: List[Dict[str, Any]] = []
    for turn_index, prompt in enumerate(prompts, start=1):
        conversation.append({"role": "user", "content": prompt})
        result = call_once(client, conversation, max_tokens=512)
        turns.append({"turn": turn_index, "prompt": prompt, **result})
        if result["ok"]:
            conversation.append({"role": "assistant", "content": result["content_preview"]})
        else:
            break

    latencies = [item["latency_seconds"] for item in turns if item["ok"]]
    return {
        "turns": turns,
        "summary": {
            "success_count": sum(1 for item in turns if item["ok"]),
            "failure_count": sum(1 for item in turns if not item["ok"]),
            **summarize_latencies(latencies),
            "avg_tokens_per_second": round(
                statistics.mean([item["tokens_per_second"] for item in turns if item["ok"] and item["tokens_per_second"] > 0]),
                3,
            ) if any(item["ok"] and item["tokens_per_second"] > 0 for item in turns) else 0.0,
            "avg_chars_per_second": round(
                statistics.mean([item["chars_per_second"] for item in turns if item["ok"] and item["chars_per_second"] > 0]),
                3,
            ) if any(item["ok"] and item["chars_per_second"] > 0 for item in turns) else 0.0,
        },
    }


def run_output_speed(client: LLM) -> Dict[str, Any]:
    messages = [
        {"role": "system", "content": "你是一个简洁、准确的中文助手。"},
        {
            "role": "user",
            "content": "请写一段约900到1100字的中文说明，主题是“如何评估大模型的响应速度、输出速度与并发能力”，要求自然分段。",
        },
    ]
    result = call_once(client, messages, max_tokens=1400)
    return result


def run_concurrency(client: LLM, concurrency: int) -> Dict[str, Any]:
    def worker(job_index: int) -> Dict[str, Any]:
        messages = [
            {"role": "system", "content": "你是一个简洁、准确的中文助手。"},
            {"role": "user", "content": f"这是第{job_index}个并发请求。请只回复：OK-{job_index}"},
        ]
        return call_once(client, messages, max_tokens=64)

    started = time.perf_counter()
    results: List[Dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(worker, index) for index in range(1, concurrency + 1)]
        for future in as_completed(futures):
            results.append(future.result())
    wall_seconds = time.perf_counter() - started

    latencies = [item["latency_seconds"] for item in results if item["ok"]]
    returned_model_counts: Dict[str, int] = {}
    for item in results:
        returned_model = item.get("returned_model", "") or "(empty)"
        returned_model_counts[returned_model] = returned_model_counts.get(returned_model, 0) + 1

    return {
        "concurrency": concurrency,
        "wall_seconds": round(wall_seconds, 3),
        "success_count": sum(1 for item in results if item["ok"]),
        "failure_count": sum(1 for item in results if not item["ok"]),
        "returned_model_counts": returned_model_counts,
        "latency_summary": summarize_latencies(latencies),
        "results": sorted(results, key=lambda item: item["content_preview"]),
    }


def main() -> None:
    client = LLM.from_openclaw_config(str(CONFIG_PATH))

    warmup = call_once(
        client,
        [
            {"role": "system", "content": "你是一个简洁、准确的中文助手。"},
            {"role": "user", "content": "回复 OK"},
        ],
        max_tokens=32,
    )
    multiturn = run_multiturn(client)
    output_speed = run_output_speed(client)
    concurrency = [run_concurrency(client, value) for value in (1, 2, 4, 8)]

    payload = {
        "provider": PROVIDER,
        "requested_model": MODEL,
        "config_path": str(CONFIG_PATH),
        "notes": [
            "This benchmark uses non-streaming requests.",
            "Output speed is approximated by completion_tokens/second and chars/second over full request time.",
            "The provider may route the requested model name to another backend model; returned_model captures the actual response value.",
        ],
        "warmup": warmup,
        "multiturn": multiturn,
        "output_speed": output_speed,
        "concurrency": concurrency,
    }
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
