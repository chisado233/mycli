from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from runtime_bus import RuntimeBus


class RuntimeBusTestCase(unittest.TestCase):
    def test_runtime_bus_can_send_reply_and_handoff(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            bus = RuntimeBus(tmp_dir)
            root = bus.create_channel_message(
                channel="terminal",
                node_id="node_1",
                to_agent="agent_1",
                text="请开始处理任务",
                context_id="ctx_main",
            )
            child = bus.send_task(
                from_agent="agent_1",
                to_agent="agent_2",
                node_id="node_1",
                task_id=root["task_id"],
                context_id="ctx_main",
                text="请分析输入材料",
            )
            reply = bus.reply_task(
                from_agent="agent_2",
                reply_to_message_id=child["message_id"],
                text="分析完成",
            )
            handoff = bus.handoff_reply(
                from_agent="agent_1",
                to_agent="agent_3",
                task_id=root["task_id"],
                handoff_note={
                    "reason": "agent_3 更适合直接回复",
                    "summary": "已完成前置分析",
                    "suggested_reply_style": "简洁清晰",
                    "risks": [],
                },
            )

            task = bus.load_task(root["task_id"])
            self.assertEqual(reply["reply_to"], child["message_id"])
            self.assertEqual(task["current_owner_agent"], "agent_3")
            self.assertEqual(handoff["to_agent"], "agent_3")
            self.assertTrue((Path(tmp_dir) / "runtime_bus" / "messages" / f"{root['message_id']}.json").exists())

    def test_context_compression_preserves_compression_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            bus = RuntimeBus(tmp_dir)
            root = bus.create_channel_message(
                channel="terminal",
                node_id="node_1",
                to_agent="agent_1",
                text="请开始处理任务",
                context_id="ctx_main",
            )
            for _ in range(35):
                bus.record_event(
                    agent_id="agent_1",
                    context_id="ctx_main",
                    task_id=root["task_id"],
                    message_id=root["message_id"],
                    node_id="node_1",
                    event_type="assistant_reply",
                    content={"text": "x" * 200},
                )

            compressed = bus.maybe_compress_context(
                agent_id="agent_1",
                context_id="ctx_main",
                max_tokens=50,
                recent_history_events=5,
            )

            summary_path = Path(tmp_dir) / "runtime_bus" / "contexts" / "ctx_main" / "summary.json"
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            history_lines = (Path(tmp_dir) / "runtime_bus" / "agents" / "agent_1" / "history.jsonl").read_text(
                encoding="utf-8"
            ).splitlines()

            self.assertTrue(compressed)
            self.assertIn("compressed history for agent_1", summary["summary"])
            self.assertEqual(len(summary["recent_raw_events"]), 5)
            self.assertEqual(len(history_lines), 6)


if __name__ == "__main__":
    unittest.main()
