from typing import Any, Dict, Optional


class system_prompt_component_type:
    """所有 system prompt 动态组件的基类。"""

    def __init__(
        self,
        component_id: str,
        agent_id: str = "",
        component_config: Optional[Dict[str, Any]] = None,
        agent_config: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.component_id = component_id
        self.agent_id = agent_id
        self.component_config = component_config or {}
        self.agent_config = agent_config or {}
        self.runtime_params: Dict[str, Any] = {}
        self.system_prompt = ""

        self.on_init()
        self.refresh()

    def on_init(self) -> None:
        """组件初始化扩展点。"""

    def change(self, **kwargs: Any) -> str:
        """
        对外统一更新入口。

        外部通过该接口传参，基类负责串联内部更新流程；
        具体组件只需要按需覆写内部钩子方法。
        """
        self.runtime_params.update(kwargs)
        self.before_change(**kwargs)
        self.apply_change(**kwargs)
        self.after_change(**kwargs)
        self.refresh()
        return self.system_prompt

    def before_change(self, **kwargs: Any) -> None:
        """更新前置钩子。"""

    def apply_change(self, **kwargs: Any) -> None:
        """核心更新逻辑钩子。"""

    def after_change(self, **kwargs: Any) -> None:
        """更新后置钩子。"""

    def refresh(self) -> str:
        """统一触发 system prompt 重建。"""
        self.before_refresh()
        prompt = self.build_system_prompt()
        self.system_prompt = prompt or ""
        self.after_refresh()
        return self.system_prompt

    def before_refresh(self) -> None:
        """重建提示词前的扩展点。"""

    def build_system_prompt(self) -> str:
        """具体组件生成自身 system prompt 的核心逻辑。"""
        return ""

    def after_refresh(self) -> None:
        """重建提示词后的扩展点。"""

    def set_component_config(self, component_config: Optional[Dict[str, Any]] = None) -> str:
        """更新组件静态配置，并重新生成提示词。"""
        self.component_config = component_config or {}
        return self.refresh()

    def set_agent_config(self, agent_config: Optional[Dict[str, Any]] = None) -> str:
        """更新 agent 全局配置，并重新生成提示词。"""
        self.agent_config = agent_config or {}
        return self.refresh()

    def get_system_prompt(self) -> str:
        return self.system_prompt

