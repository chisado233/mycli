from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys


CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.append(str(CURRENT_DIR))

from session_store import SessionContextStore


class SessionContextStoreTestCase(unittest.TestCase):
    def test_session_store_persists_turns_and_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            store = SessionContextStore(tmp_dir)

            turn = store.record_turn(
                user_message="你好",
                assistant_message="你好，我在这儿。",
                metadata={"stage": "opening"},
            )
            snapshot = store.sync_runtime_result(
                workflow_path="demo/agent_workflow.json",
                state={"node_1": "done"},
                execution_order=["node_1"],
                final_response="你好，我在这儿。",
                result_path="runtime_execution_result.json",
                log_path="runtime_execution.log",
                trace_md_path="runtime_llm_trace.md",
                dialogue_log_path="dialogue_log.md",
            )

            turns = store.list_turns()

            self.assertEqual(turn["turn_index"], 1)
            self.assertEqual(len(turns), 1)
            self.assertEqual(turns[0]["assistant_message"], "你好，我在这儿。")
            self.assertEqual(snapshot["run_count"], 1)
            self.assertEqual(snapshot["turn_count"], 1)
            self.assertTrue(Path(store.snapshot_path).exists())
            self.assertTrue(Path(store.turns_path).exists())
