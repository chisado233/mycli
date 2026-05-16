
from typing import Any, Dict, Iterable, List, Optional

from agent_identity import agent_identity
from agent_chat_group import agent_chat_group
from agent_message_context import Agent_Message_Context
from heartbeats import Heartbeats
from node_information import node_infomation
from project_context import Project_Context
from runtime_prompt import Runtime
from sandbox_prompt import Sandbox
from silent_replies import Silent_Replies
from skill_prompt import skill_prompt
from system_prompt_component_type import system_prompt_component_type
from tool_call_style import Tool_Call_Style
from tooling import Tooling
from workspace_prompt import Workspace


class system_prompt:
    """负责 system prompt 组件装载、更新和拼装。"""

    COMPONENT_REGISTRY = {
        "agent_identity": agent_identity,
        "agent_chat_group": agent_chat_group,
        "Agent_Message_Context": Agent_Message_Context,
        "Tooling": Tooling,
        "Tool_Call_Style": Tool_Call_Style,
        "skill_prompt": skill_prompt,
        "Workspace": Workspace,
        "Sandbox": Sandbox,
        "node_infomation": node_infomation,
        "Project_Context": Project_Context,
        "Silent_Replies": Silent_Replies,
        "Heartbeats": Heartbeats,
        "Runtime": Runtime,
    }

    def __init__(self, agent_config: Optional[Dict[str, Any]] = None) -> None:
        self.agent_config = agent_config or {}
        self.agent_id = self.agent_config.get("id", "")
        self.component_configs: List[Dict[str, Any]] = []
        self.components: List[system_prompt_component_type] = []
        self.component_map: Dict[str, system_prompt_component_type] = {}

        self.load_component_config()
        self.auto_bind_components()

    def load_component_config(self) -> List[Dict[str, Any]]:
        """读取当前 agent 的 system prompt 组件配置。"""
        component_configs = self.agent_config.get("system_prompt_component", [])
        self.component_configs = component_configs if isinstance(component_configs, list) else []
        return self.component_configs

    def bind_components(
        self, component_instances: Optional[Iterable[system_prompt_component_type]] = None
    ) -> List[system_prompt_component_type]:
        """
        绑定已实例化的组件。

        这里只负责结构和注册，不负责动态 import；
        后续可在这里补充按 id 自动加载组件类的逻辑。
        """
        self.components = list(component_instances or [])
        self.component_map = {component.component_id: component for component in self.components}
        return self.components

    def auto_bind_components(self) -> List[system_prompt_component_type]:
        """根据配置自动实例化可用组件。"""
        instances: List[system_prompt_component_type] = []
        for item in self.component_configs:
            if not isinstance(item, dict):
                continue
            component_id = item.get("id")
            component_config = item.get("config", {})
            if not component_id or not self._component_enabled(component_config):
                continue
            component_class = self.COMPONENT_REGISTRY.get(component_id)
            if component_class is None:
                continue
            instances.append(
                component_class(
                    component_id=component_id,
                    agent_id=self.agent_id,
                    component_config=component_config,
                    agent_config=self.agent_config,
                )
            )
        return self.bind_components(instances)

    def _component_enabled(self, component_config: Any) -> bool:
        if not isinstance(component_config, dict):
            return True
        if "enable" not in component_config:
            return True
        value = component_config.get("enable")
        if isinstance(value, bool):
            return value
        return str(value).lower() != "false"

    def add_component(self, component: system_prompt_component_type) -> system_prompt_component_type:
        """注册单个组件实例。"""
        self.component_map[component.component_id] = component
        self.components = list(self.component_map.values())
        return component

    def update_component(self, component_id: str, **kwargs: Any) -> str:
        """统一调用单个组件的更新接口。"""
        component = self.component_map.get(component_id)
        if component is None:
            raise KeyError(f"system prompt component not found: {component_id}")
        return component.change(**kwargs)

    def update_all_components(self, **kwargs: Any) -> Dict[str, str]:
        """统一向所有组件分发更新参数。"""
        result: Dict[str, str] = {}
        for component in self.components:
            result[component.component_id] = component.change(**kwargs)
        return result

    def refresh_all_components(self) -> Dict[str, str]:
        """不传额外参数，仅触发所有组件重建提示词。"""
        result: Dict[str, str] = {}
        for component in self.components:
            result[component.component_id] = component.refresh()
        return result

    def get_sys_prompt(self) -> str:
        """获取并拼装所有组件输出的 system prompt。"""
        prompt_parts = []
        for component in self.components:
            prompt = component.get_system_prompt().strip()
            if prompt:
                prompt_parts.append(prompt)
        return "\n\n".join(prompt_parts)
