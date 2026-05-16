from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional

from builtin_tools import registry
from tool_base import ToolContext, ToolResult
from tool_runtime import ToolRuntime


class tool:
    """
    工具管理入口。

    对外提供三类能力：
    - 注册/发现工具
    - 获取可调用工具描述，用于 system prompt / schema 暴露
    - 统一执行工具
    """

    def __init__(self, workspace_dir: str = "", runtime: Optional[Dict[str, Any]] = None) -> None:
        self.context = ToolContext(workspace_dir=workspace_dir, runtime=runtime or {})
        self.runtime = ToolRuntime(registry=registry, context=self.context)

    def 注册(self) -> List[str]:
        """返回已注册工具名称列表。"""
        return self.runtime.registry.list_tool_names()

    def get_tool_definitions(self, tool_names: Optional[Iterable[str]] = None) -> List[Dict[str, Any]]:
        """返回工具描述、参数 schema 和返回 schema。"""
        return self.runtime.get_tool_descriptions(tool_names=tool_names)

    def build_tool_system_prompt(self, tool_names: Optional[Iterable[str]] = None) -> str:
        """形成 tool 系统提示词片段。"""
        return self.runtime.build_tools_prompt(tool_names=tool_names)

    def invoke(self, tool_name: str, params: Optional[Dict[str, Any]] = None) -> ToolResult:
        """统一进行 tool 调用。"""
        return self.runtime.invoke(tool_name, params)
