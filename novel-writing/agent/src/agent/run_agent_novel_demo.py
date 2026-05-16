from __future__ import annotations

import json

from agent import agent


def main() -> None:
    runner = agent()
    result = runner.agent_loop(
        "请在当前 workspace 中创建一个小说项目文件夹，为它建立基础文件结构，并写一篇两千字左右的中文小说，保存到项目文件里。"
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
