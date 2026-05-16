import shutil
import unittest
from pathlib import Path

from agent_chat_group import agent_chat_group
from agent_identity import agent_identity
from heartbeats import Heartbeats
from node_information import node_infomation
from project_context import Project_Context
from runtime_prompt import Runtime
from silent_replies import Silent_Replies
from skill_prompt import skill_prompt
from system_prompt import system_prompt
from tool_call_style import Tool_Call_Style
from tooling import Tooling
from workspace_prompt import Workspace


class SystemPromptComponentTestCase(unittest.TestCase):
    def setUp(self) -> None:
        sandbox_temp_root = Path(__file__).resolve().parent / ".tmp_test"
        sandbox_temp_root.mkdir(parents=True, exist_ok=True)
        self.temp_dir = sandbox_temp_root / "system-prompt-test"
        shutil.rmtree(self.temp_dir, ignore_errors=True)
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self.official_root = self.temp_dir / "skills"
        self.custom_root = self.temp_dir / "self_created_skills"
        self.official_root.mkdir(parents=True, exist_ok=True)
        self.custom_root.mkdir(parents=True, exist_ok=True)

        self._write_skill(
            self.official_root / "project-skill-manager",
            "---\n"
            "name: project-skill-manager\n"
            "description: 管理项目与技能的官方技能\n"
            "---\n"
            "body",
        )
        self._write_skill(
            self.custom_root / "mxai",
            "---\n"
            "name: mxai\n"
            "description: mxai 创作助手\n"
            "---\n"
            "body",
        )
        self._write_skill(
            self.custom_root / "video-helper",
            "---\n"
            "name: video-helper\n"
            "description: 视频处理辅助技能\n"
            "---\n"
            "body",
        )
        (self.temp_dir / "memory.md").write_text("项目记忆：优先保证组件接口稳定。", encoding="utf-8")
        (self.temp_dir / "node_infomation.md").write_text("当前节点负责接收任务并分发给下游 agent。", encoding="utf-8")

        self.agent_config = {
            "id": "agent-example1",
            "system_prompt_component": [
                {
                    "id": "agent_identity",
                    "config": {
                        "role": "multi-agent coordinator",
                        "description": "负责协调多个子 agent 完成复杂任务。",
                        "goals": ["拆解任务", "协调技能", "同步上下文"],
                    },
                },
                {
                    "id": "Tooling",
                    "config": {
                        "enable": "true",
                    },
                },
                {
                    "id": "Tool_Call_Style",
                    "config": {
                        "enable": "true",
                    },
                },
                {
                    "id": "skill_prompt",
                    "config": {
                        "enable": "true",
                        "official_skill_root": str(self.official_root),
                        "custom_skill_root": str(self.custom_root),
                        "show_all_installed_skills": True,
                    },
                },
                {
                    "id": "agent_chat_group",
                    "config": {
                        "enable": "true",
                    },
                },
                {
                    "id": "Workspace",
                    "config": {
                        "enable": "true",
                        "notes": ["优先在当前工作区内完成操作。"],
                    },
                },
                {
                    "id": "node_infomation",
                    "config": {
                        "enable": "true",
                        "node_infomation": "node_infomation.md",
                    },
                },
                {
                    "id": "Project_Context",
                    "config": {
                        "enable": "true",
                        "memory": "memory.md",
                    },
                },
                {
                    "id": "Silent_Replies",
                    "config": {
                        "enable": "true",
                        "token": "SILENT_REPLY",
                    },
                },
                {
                    "id": "Heartbeats",
                    "config": {
                        "enable": "true",
                    },
                },
                {
                    "id": "Runtime",
                    "config": {
                        "enable": "true",
                        "shell": "powershell",
                        "channel": "terminal",
                    },
                },
            ],
            "skill": [
                {"id": "project-skill-manager", "enable": "true"},
                {"id": "mxai", "enable": "true"},
            ],
            "tool": [
                {"id": "read / write / edit / apply_patch / grep / find / ls / exec / process", "enbale": "true"},
                {"id": "memory_search", "enable": "true"},
                {"id": "cron", "enable": "true"},
                {"id": "subagent", "enable": "true"},
            ],
            "heartbeat": {"enable": "true"},
            "workspace": str(self.temp_dir),
            "Relationship with other agents": {
                "Superior": [{"id": "agent-supervisor", "connect": "true"}],
                "Peer": ["agent-peer"],
                "Subordinate": [{"id": "agent-worker", "connect": "true"}],
            },
            "agent_capability": {
                "can_delegate": True,
                "allowed_targets": ["agent-worker", "all"],
                "can_reply_user": True,
            },
        }

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _write_skill(self, skill_dir: Path, content: str) -> None:
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "SKILL.md").write_text(content, encoding="utf-8")

    def _component_config(self, component_id: str) -> dict:
        for item in self.agent_config["system_prompt_component"]:
            if item["id"] == component_id:
                return item["config"]
        self.fail(f"missing component config: {component_id}")
        return {}

    def test_agent_identity_can_render_and_update(self) -> None:
        component = agent_identity(
            component_id="agent_identity",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("agent_identity"),
            agent_config=self.agent_config,
        )

        initial_prompt = component.get_system_prompt()
        self.assertIn("agent-example1", initial_prompt)
        self.assertIn("multi-agent coordinator", initial_prompt)
        self.assertIn("拆解任务", initial_prompt)

        component.change(role="workflow architect", goals=["统一组件接口"])
        updated_prompt = component.get_system_prompt()
        self.assertIn("workflow architect", updated_prompt)
        self.assertIn("统一组件接口", updated_prompt)
        self.assertNotIn("拆解任务", updated_prompt)

    def test_skill_prompt_only_renders_enabled_skills(self) -> None:
        component = skill_prompt(
            component_id="skill_prompt",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("skill_prompt"),
            agent_config=self.agent_config,
        )

        prompt = component.get_system_prompt()
        self.assertIn("project-skill-manager", prompt)
        self.assertIn("mxai", prompt)
        self.assertIn("官方技能", prompt)
        self.assertIn("自建技能", prompt)

        component.change(enabled_skill_ids=["mxai"], show_all_installed_skills=False)
        updated_prompt = component.get_system_prompt()
        self.assertIn("mxai", updated_prompt)
        self.assertNotIn("project-skill-manager", updated_prompt)
        self.assertNotIn("video-helper", updated_prompt)

    def test_skill_prompt_can_show_all_installed_skills(self) -> None:
        component = skill_prompt(
            component_id="skill_prompt",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("skill_prompt"),
            agent_config=self.agent_config,
        )

        component.change(show_all_installed_skills=True)
        prompt = component.get_system_prompt()
        self.assertIn("project-skill-manager", prompt)
        self.assertIn("mxai", prompt)
        self.assertIn("video-helper", prompt)
        self.assertIn("enabled", prompt)
        self.assertIn("disabled", prompt)

    def test_agent_chat_group_can_render_relationships(self) -> None:
        component = agent_chat_group(
            component_id="agent_chat_group",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("agent_chat_group"),
            agent_config=self.agent_config,
        )

        prompt = component.get_system_prompt()
        self.assertIn("agent-example1", prompt)
        self.assertIn("agent-supervisor", prompt)
        self.assertIn("agent-peer", prompt)
        self.assertIn("agent-worker", prompt)
        self.assertIn("Allowed delegate targets: agent-worker, all", prompt)
        self.assertIn("Can reply to user: yes", prompt)

    def test_node_information_can_load_legacy_file_name(self) -> None:
        component = node_infomation(
            component_id="node_infomation",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("node_infomation"),
            agent_config=self.agent_config,
        )

        prompt = component.get_system_prompt()
        self.assertIn("Node Information", prompt)
        self.assertIn("node_infomation.md", prompt)
        self.assertIn("当前节点负责接收任务并分发给下游 agent。", prompt)

    def test_system_prompt_can_assemble_multiple_components(self) -> None:
        identity_component = agent_identity(
            component_id="agent_identity",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("agent_identity"),
            agent_config=self.agent_config,
        )
        group_component = agent_chat_group(
            component_id="agent_chat_group",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("agent_chat_group"),
            agent_config=self.agent_config,
        )
        tooling_component = Tooling(
            component_id="Tooling",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Tooling"),
            agent_config=self.agent_config,
        )
        tool_style_component = Tool_Call_Style(
            component_id="Tool_Call_Style",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Tool_Call_Style"),
            agent_config=self.agent_config,
        )
        skills_component = skill_prompt(
            component_id="skill_prompt",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("skill_prompt"),
            agent_config=self.agent_config,
        )
        workspace_component = Workspace(
            component_id="Workspace",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Workspace"),
            agent_config=self.agent_config,
        )
        node_component = node_infomation(
            component_id="node_infomation",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("node_infomation"),
            agent_config=self.agent_config,
        )
        context_component = Project_Context(
            component_id="Project_Context",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Project_Context"),
            agent_config=self.agent_config,
        )
        silent_component = Silent_Replies(
            component_id="Silent_Replies",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Silent_Replies"),
            agent_config=self.agent_config,
        )
        heartbeat_component = Heartbeats(
            component_id="Heartbeats",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Heartbeats"),
            agent_config=self.agent_config,
        )
        runtime_component = Runtime(
            component_id="Runtime",
            agent_id=self.agent_config["id"],
            component_config=self._component_config("Runtime"),
            agent_config=self.agent_config,
        )

        manager = system_prompt(self.agent_config)
        manager.bind_components(
            [
                identity_component,
                group_component,
                tooling_component,
                tool_style_component,
                skills_component,
                workspace_component,
                node_component,
                context_component,
                silent_component,
                heartbeat_component,
                runtime_component,
            ]
        )

        prompt = manager.get_sys_prompt()
        self.assertIn("# Agent Identity", prompt)
        self.assertIn("## Tooling", prompt)
        self.assertIn("## Tool Call Style", prompt)
        self.assertIn("# Available Skills", prompt)
        self.assertIn("## Agent Chat Group", prompt)
        self.assertIn("## Workspace", prompt)
        self.assertIn("## Node Information", prompt)
        self.assertIn("# Project Context", prompt)
        self.assertIn("## Silent Replies", prompt)
        self.assertIn("## Heartbeats", prompt)
        self.assertIn("## Runtime", prompt)

        manager.update_component(
            "agent_identity",
            role="workflow architect",
            goals=["维护 system prompt 结构"],
        )
        updated_prompt = manager.get_sys_prompt()
        self.assertIn("workflow architect", updated_prompt)
        self.assertIn("维护 system prompt 结构", updated_prompt)

    def test_system_prompt_auto_bind_components_from_config(self) -> None:
        manager = system_prompt(self.agent_config)
        prompt = manager.get_sys_prompt()

        self.assertIn("# Agent Identity", prompt)
        self.assertIn("## Tooling", prompt)
        self.assertIn("## Tool Call Style", prompt)
        self.assertIn("# Available Skills", prompt)
        self.assertIn("## Agent Chat Group", prompt)
        self.assertIn("## Workspace", prompt)
        self.assertIn("## Node Information", prompt)
        self.assertIn("# Project Context", prompt)
        self.assertIn("项目记忆：优先保证组件接口稳定。", prompt)
        self.assertIn("## Silent Replies", prompt)
        self.assertIn("## Heartbeats", prompt)
        self.assertIn("## Runtime", prompt)

    def test_project_context_reloads_file_changes_on_next_prompt_read(self) -> None:
        manager = system_prompt(self.agent_config)
        initial_prompt = manager.get_sys_prompt()
        self.assertIn("项目记忆：优先保证组件接口稳定。", initial_prompt)

        (self.temp_dir / "memory.md").write_text("项目记忆：共享信息池已更新为实时文档。", encoding="utf-8")

        updated_prompt = manager.get_sys_prompt()
        self.assertIn("项目记忆：共享信息池已更新为实时文档。", updated_prompt)
        self.assertNotIn("项目记忆：优先保证组件接口稳定。", updated_prompt)

    def test_project_context_survives_runtime_only_component_updates(self) -> None:
        manager = system_prompt(self.agent_config)
        initial_prompt = manager.get_sys_prompt()
        self.assertIn("# Project Context", initial_prompt)
        self.assertIn("项目记忆：优先保证组件接口稳定。", initial_prompt)

        manager.update_all_components(
            agent_id="agent-example1",
            node_id="node_1",
            task_id="task_123",
            current_message_id="msg_123",
        )
        updated_prompt = manager.get_sys_prompt()

        self.assertIn("# Project Context", updated_prompt)
        self.assertIn("项目记忆：优先保证组件接口稳定。", updated_prompt)

    def test_print_system_prompt(self) -> None:
        manager = system_prompt(self.agent_config)
        prompt = manager.get_sys_prompt()

        print("\n=== SYSTEM PROMPT START ===")
        print(prompt)
        print("=== SYSTEM PROMPT END ===\n")

        self.assertTrue(prompt.strip())


if __name__ == "__main__":
    unittest.main()
