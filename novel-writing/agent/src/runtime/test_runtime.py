import shutil
import sys
import tempfile
import unittest
from pathlib import Path


CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.append(str(CURRENT_DIR))

from runtime import runtime


class RuntimeTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.project_root = Path(__file__).resolve().parents[2]
        self.temp_dir = Path(tempfile.mkdtemp(prefix="runtime-workflow-test-"))
        self.temp_workflow_root = self.temp_dir / "workspace" / "agent_workflow"
        shutil.copytree(self.project_root / "workspace" / "agent_workflow", self.temp_workflow_root)

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_runtime_can_execute_workflow_template(self) -> None:
        runner = runtime(
            workflow_path=str(self.temp_workflow_root / "agent_workflow.json"),
            llm_overrides={
                "provider": "mock",
                "model": "mock-runtime-test",
                "max_steps": 4,
                "openclaw_config_path": str(self.project_root / "config" / "llm.json"),
            },
        )

        result = runner.run("执行一次最小多 agent 串行协作测试，并为每个节点生成交付物。")

        self.assertTrue(result["ok"])
        self.assertEqual(result["execution_order"], ["node_1", "node_2"])

        node1_output = self.temp_workflow_root / "nodes" / "node1" / "output"
        node2_output = self.temp_workflow_root / "nodes" / "node2" / "output"

        self.assertTrue((node1_output / "node1_workflow_analysis.md").exists())
        self.assertTrue((node1_output / "node1_handoff_summary.md").exists())
        self.assertTrue((node2_output / "workflow_final_delivery.md").exists())
        self.assertTrue((node2_output / "workflow_delivery_manifest.json").exists())
        self.assertTrue((self.temp_workflow_root / "runtime_execution_result.json").exists())
        self.assertTrue((self.temp_workflow_root / "runtime_bus" / "messages").exists())
        self.assertTrue((self.temp_workflow_root / "runtime_bus" / "tasks").exists())
        self.assertTrue((self.temp_workflow_root / "session_store" / "default" / "snapshot.json").exists())
        self.assertTrue((self.temp_workflow_root / "session_store" / "default" / "turns.jsonl").exists())

    def test_runtime_can_accept_node_finish_request(self) -> None:
        runner = runtime(
            workflow_path=str(self.temp_workflow_root / "agent_workflow.json"),
            llm_overrides={
                "provider": "mock",
                "model": "mock-runtime-test",
                "max_steps": 4,
                "openclaw_config_path": str(self.project_root / "config" / "llm.json"),
            },
        )

        self.assertIsNotNone(runner.bus)
        if runner.bus is None:
            self.fail("runtime bus was not initialized")

        root = runner.bus.create_channel_message(
            channel="terminal",
            node_id="node_1",
            to_agent="agent_1",
            text="请处理当前节点",
            context_id="ctx_main",
        )
        accepted = runner._accept_finish_request(
            node_id="node_1",
            current_message=root,
            request={
                "agent_id": "agent_1",
                "node_id": "node_1",
                "task_id": root["task_id"],
                "context_id": "ctx_main",
                "current_message_id": root["message_id"],
                "message": "当前节点目标已经完成，产物已写入 output，可以进入下一节点。",
            },
        )
        task = runner.bus.load_task(root["task_id"])

        self.assertTrue(accepted["ok"])
        self.assertEqual(runner.node_finish_requests["node_1"]["agent_id"], "agent_1")
        self.assertEqual(task["status"], "completed")
        self.assertTrue(task["final_response_message_id"])


if __name__ == "__main__":
    unittest.main()
