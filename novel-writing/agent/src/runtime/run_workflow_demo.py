from __future__ import annotations

import argparse
import json
from pathlib import Path

from runtime import runtime


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the workflow demo with configurable LLM settings.")
    parser.add_argument("--provider", default="mock", help="LLM provider to use for the workflow demo")
    parser.add_argument("--model", default="mock-workflow-demo", help="LLM model to use for the workflow demo")
    parser.add_argument("--max-steps", type=int, default=4, help="Max agent loop steps")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[2]
    workflow_path = project_root / "workspace" / "agent_workflow" / "agent_workflow.json"
    demo_task = (
        "请基于当前 agent_workflow 模板完成一次多 agent 协作演示："
        "node_1 负责分析 workflow 结构并形成中间交付，"
        "node_2 负责消费 node_1 的交付并形成最终说明。"
    )
    runner = runtime(
        workflow_path=str(workflow_path),
        llm_overrides={
            "provider": args.provider,
            "model": args.model,
            "max_steps": args.max_steps,
            "openclaw_config_path": str(project_root / "config" / "llm.json"),
        },
    )
    result = runner.run(demo_task)
    summary = {
        "ok": result["ok"],
        "execution_order": result["execution_order"],
        "state": result["state"],
        "result_path": result["result_path"],
        "generated_files": {
            node["node_id"]: node["generated_files"]
            for node in result["nodes"]
        },
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
