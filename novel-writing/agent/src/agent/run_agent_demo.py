from __future__ import annotations

import json

from agent import agent


def main() -> None:
    runner = agent()
    result = runner.agent_loop("请读取当前 workspace，并用一句话说明你能使用哪些核心文件工具。")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
