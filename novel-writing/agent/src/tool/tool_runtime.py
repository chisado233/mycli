from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional, Type

from tool_base import BaseTool, ToolContext, ToolExecutionError, ToolInputError, ToolResult


class ToolRegistry:
    """管理工具注册与实例化。"""

    def __init__(self) -> None:
        self._tool_classes: Dict[str, Type[BaseTool]] = {}

    def register(self, tool_class: Type[BaseTool]) -> Type[BaseTool]:
        if not tool_class.name:
            raise ValueError("tool class must define a non-empty `name`")
        self._tool_classes[tool_class.name] = tool_class
        return tool_class

    def get_tool_class(self, tool_name: str) -> Type[BaseTool]:
        if tool_name not in self._tool_classes:
            raise KeyError(f"tool not found: {tool_name}")
        return self._tool_classes[tool_name]

    def create_tool(self, tool_name: str, context: Optional[ToolContext] = None) -> BaseTool:
        tool_class = self.get_tool_class(tool_name)
        return tool_class(context=context)

    def list_tool_names(self) -> List[str]:
        return sorted(self._tool_classes.keys())

    def list_definitions(
        self,
        tool_names: Optional[Iterable[str]] = None,
        context: Optional[ToolContext] = None,
    ) -> List[Dict[str, Any]]:
        target_names = list(tool_names) if tool_names is not None else self.list_tool_names()
        definitions: List[Dict[str, Any]] = []
        for tool_name in target_names:
            tool = self.create_tool(tool_name, context=context)
            definitions.append(tool.get_definition())
        return definitions


class ToolRuntime:
    """参考 OpenClaw 风格的最小工具运行环境。"""

    def __init__(self, registry: ToolRegistry, context: Optional[ToolContext] = None) -> None:
        self.registry = registry
        self.context = context or ToolContext()

    def get_tool_descriptions(self, tool_names: Optional[Iterable[str]] = None) -> List[Dict[str, Any]]:
        return self.registry.list_definitions(tool_names=tool_names, context=self.context)

    def build_tools_prompt(self, tool_names: Optional[Iterable[str]] = None) -> str:
        definitions = self.get_tool_descriptions(tool_names=tool_names)
        lines = [
            "## Tooling",
            "Tool availability (filtered by policy):",
            "Tool names are case-sensitive. Call tools exactly as listed.",
        ]
        for definition in definitions:
            lines.append(f"- {definition['name']}: {definition['description']}")
        return "\n".join(lines)

    def invoke(self, tool_name: str, params: Optional[Dict[str, Any]] = None) -> ToolResult:
        try:
            tool = self.registry.create_tool(tool_name, context=self.context)
            normalized_params = tool.validate_params(params)
            return tool.execute(normalized_params)
        except ToolInputError as exc:
            return ToolResult(
                ok=False,
                tool_name=tool_name,
                content="",
                error=str(exc),
                data={"error_type": "ToolInputError"},
            )
        except ToolExecutionError as exc:
            return ToolResult(
                ok=False,
                tool_name=tool_name,
                content="",
                error=str(exc),
                data={"error_type": "ToolExecutionError"},
            )
        except Exception as exc:  # noqa: BLE001
            return ToolResult(
                ok=False,
                tool_name=tool_name,
                content="",
                error=str(exc),
                data={"error_type": type(exc).__name__},
            )

