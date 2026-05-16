import shutil
import sys
import tempfile
import unittest
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
RUNTIME_DIR = CURRENT_DIR.parent / "runtime"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.append(str(RUNTIME_DIR))

from builtin_tools import registry
from tool_base import ToolContext
from tool_runtime import ToolRuntime


class ToolRuntimeTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp(prefix="tool-runtime-test-"))
        (self.temp_dir / "notes.txt").write_text("hello tool runtime", encoding="utf-8")
        (self.temp_dir / "subdir").mkdir(exist_ok=True)
        (self.temp_dir / "subdir" / "sample.py").write_text("print('hi')", encoding="utf-8")
        self.runtime = ToolRuntime(registry=registry, context=ToolContext(workspace_dir=str(self.temp_dir)))

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_list_tool_descriptions(self) -> None:
        definitions = self.runtime.get_tool_descriptions()
        tool_names = {item["name"] for item in definitions}
        self.assertIn("echo", tool_names)
        self.assertIn("read", tool_names)
        self.assertIn("write", tool_names)
        self.assertIn("edit", tool_names)
        self.assertIn("apply_patch", tool_names)
        self.assertIn("grep", tool_names)
        self.assertIn("ls", tool_names)
        self.assertIn("find", tool_names)
        self.assertIn("exec", tool_names)
        self.assertIn("process", tool_names)
        self.assertIn("agent_request_finish_node", tool_names)

    def test_read_tool(self) -> None:
        result = self.runtime.invoke("read", {"path": "notes.txt"})
        self.assertTrue(result.ok)
        self.assertIn("hello tool runtime", result.content)

    def test_ls_tool(self) -> None:
        result = self.runtime.invoke("ls", {"path": "."})
        self.assertTrue(result.ok)
        self.assertIn("notes.txt", result.content)
        self.assertIn("subdir", result.content)

    def test_write_tool(self) -> None:
        result = self.runtime.invoke("write", {"path": "draft.txt", "content": "draft content"})
        self.assertTrue(result.ok)
        self.assertEqual((self.temp_dir / "draft.txt").read_text(encoding="utf-8"), "draft content")

    def test_edit_tool(self) -> None:
        result = self.runtime.invoke(
            "edit",
            {"path": "notes.txt", "old_text": "hello", "new_text": "updated"},
        )
        self.assertTrue(result.ok)
        self.assertIn("updated tool runtime", (self.temp_dir / "notes.txt").read_text(encoding="utf-8"))

    def test_apply_patch_tool(self) -> None:
        result = self.runtime.invoke(
            "apply_patch",
            {"path": "notes.txt", "old_text": "tool runtime", "new_text": "patched runtime"},
        )
        self.assertTrue(result.ok)
        self.assertIn("patched runtime", (self.temp_dir / "notes.txt").read_text(encoding="utf-8"))

    def test_find_tool(self) -> None:
        result = self.runtime.invoke("find", {"pattern": "**/*.py"})
        self.assertTrue(result.ok)
        self.assertIn("sample.py", result.content)

    def test_grep_tool(self) -> None:
        result = self.runtime.invoke("grep", {"pattern": "print", "glob": "**/*.py"})
        self.assertTrue(result.ok)
        self.assertIn("sample.py:1", result.content)

    def test_exec_tool(self) -> None:
        result = self.runtime.invoke("exec", {"command": "python -c \"print('ok')\""})
        self.assertTrue(result.ok)
        self.assertIn("ok", result.content)

    def test_process_tool(self) -> None:
        started = self.runtime.invoke("process", {"action": "start", "command": "python -c \"print('bg')\""})
        self.assertTrue(started.ok)
        process_id = started.data["process_id"]

        polled = self.runtime.invoke("process", {"action": "poll", "process_id": process_id})
        self.assertTrue(polled.ok)
        self.assertIn(polled.data["status"], {"running", "finished"})

    def test_agent_config_update_tool(self) -> None:
        config_path = self.temp_dir / "agent.json"
        config_path.write_text(
            '{"llm":{"provider":"old-provider","model":"old-model","max_tokens":1024},"heartbeat":{"enable":"false"}}',
            encoding="utf-8",
        )
        result = self.runtime.invoke(
            "agent_config_update",
            {
                "path": str(config_path),
                "updates": {
                    "llm": {
                        "provider": "mytokenland",
                        "model": "claude-sonnet-4-6",
                        "max_tokens": 8192,
                    },
                    "heartbeat": {"enable": "true"},
                },
            },
        )
        self.assertTrue(result.ok)
        updated = (self.temp_dir / "agent.json").read_text(encoding="utf-8")
        self.assertIn('"provider": "mytokenland"', updated)
        self.assertIn('"model": "claude-sonnet-4-6"', updated)
        self.assertIn('"max_tokens": 8192', updated)
        self.assertIn('"enable": "true"', updated)

    def test_agent_bus_tools_support_handoff_and_temporary_permission_change(self) -> None:
        runtime_bus_root = self.temp_dir / "workflow"
        runtime_bus_root.mkdir(parents=True, exist_ok=True)
        from runtime_bus import RuntimeBus

        bus = RuntimeBus(str(runtime_bus_root))
        root = bus.create_channel_message(
            channel="terminal",
            node_id="node_1",
            to_agent="agent_1",
            text="请开始处理任务",
            context_id="ctx_main",
        )
        self.runtime = ToolRuntime(
            registry=registry,
            context=ToolContext(
                workspace_dir=str(self.temp_dir),
                runtime={
                    "bus": bus,
                    "agent_id": "agent_1",
                    "node_id": "node_1",
                    "task_id": root["task_id"],
                    "context_id": "ctx_main",
                    "current_message_id": root["message_id"],
                    "agent_capability": {
                        "can_delegate": True,
                        "allowed_targets": ["agent_2"],
                        "can_request_temporary_permission_change": True,
                    },
                    "session_permissions": {},
                    "agent_config_path_map": {},
                },
            ),
        )

        sent = self.runtime.invoke("agent_send_task", {"to_agent": "agent_2", "text": "请分析输入"})
        handoff = self.runtime.invoke(
            "agent_handoff_reply",
            {
                "to_agent": "agent_2",
                "reason": "需要更合适的回复者",
                "summary": "已经完成前置分析",
                "suggested_reply_style": "简洁清晰",
                "risks": ["无"],
            },
        )
        permission = self.runtime.invoke(
            "agent_request_permission_change",
            {
                "target_agent": "agent_2",
                "scope": "temporary",
                "changes": {"can_delegate": True, "allowed_targets": ["all"]},
                "reason": "需要继续分发任务",
            },
        )

        task = bus.load_task(root["task_id"])

        self.assertTrue(sent.ok)
        self.assertTrue(handoff.ok)
        self.assertTrue(permission.ok)
        self.assertEqual(task["current_owner_agent"], "agent_2")
        self.assertEqual(task["status"], "handoff_in_progress")
        self.assertEqual(
            self.runtime.context.runtime["session_permissions"][root["task_id"]]["agent_2"]["allowed_targets"],
            ["all"],
        )

    def test_agent_request_finish_node_tool_records_runtime_request(self) -> None:
        runtime_bus_root = self.temp_dir / "workflow-finish"
        runtime_bus_root.mkdir(parents=True, exist_ok=True)
        from runtime_bus import RuntimeBus

        bus = RuntimeBus(str(runtime_bus_root))
        root = bus.create_channel_message(
            channel="terminal",
            node_id="node_1",
            to_agent="agent_1",
            text="请开始处理任务",
            context_id="ctx_main",
        )
        self.runtime = ToolRuntime(
            registry=registry,
            context=ToolContext(
                workspace_dir=str(self.temp_dir),
                runtime={
                    "bus": bus,
                    "agent_id": "agent_1",
                    "node_id": "node_1",
                    "task_id": root["task_id"],
                    "context_id": "ctx_main",
                    "current_message_id": root["message_id"],
                },
            ),
        )

        result = self.runtime.invoke(
            "agent_request_finish_node",
            {"message": "当前节点目标已经完成，产物已写入 output，建议进入下一节点。"},
        )

        self.assertTrue(result.ok)
        self.assertEqual(self.runtime.context.runtime["node_finish_request"]["node_id"], "node_1")
        self.assertIn("当前节点目标已经完成", self.runtime.context.runtime["node_finish_request"]["message"])

    def test_print_tool_runtime_demo(self) -> None:
        print("\n=== TOOLS PROMPT START ===")
        print(self.runtime.build_tools_prompt())
        print("=== TOOLS PROMPT END ===")

        print("\n=== TOOL CALL DEMO START ===")
        for tool_name, params in [
            ("echo", {"text": "hello"}),
            ("read", {"path": "notes.txt"}),
            ("write", {"path": "demo.txt", "content": "demo content"}),
            ("edit", {"path": "demo.txt", "old_text": "demo", "new_text": "updated"}),
            ("apply_patch", {"path": "demo.txt", "old_text": "updated", "new_text": "patched"}),
            ("grep", {"pattern": "print", "glob": "**/*.py"}),
            ("ls", {"path": "."}),
            ("find", {"pattern": "**/*.py"}),
            ("agent_config_update", {"path": "demo-config.json", "updates": {"llm": {"model": "demo-model"}}}),
            ("process", {"action": "list"}),
        ]:
            if tool_name == "agent_config_update":
                (self.temp_dir / "demo-config.json").write_text('{"llm":{"model":"old-model"}}', encoding="utf-8")
            result = self.runtime.invoke(tool_name, params)
            print(f"[{tool_name}]")
            print(result.to_dict())
        print("=== TOOL CALL DEMO END ===\n")

        self.assertTrue(True)


if __name__ == "__main__":
    unittest.main()
