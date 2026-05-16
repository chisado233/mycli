from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, Optional


@dataclass
class ToolContext:
    workspace_dir: str = ""
    runtime: Dict[str, Any] = field(default_factory=dict)
    extra: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ToolResult:
    ok: bool
    tool_name: str
    content: str
    data: Dict[str, Any] = field(default_factory=dict)
    error: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "tool_name": self.tool_name,
            "content": self.content,
            "data": self.data,
            "error": self.error,
        }


class ToolInputError(ValueError):
    """工具输入参数不合法。"""


class ToolExecutionError(RuntimeError):
    """工具执行失败。"""


class BaseTool(ABC):
    """
    工具定义模板类。

    每个具体工具至少需要补全：
    - name
    - description
    - input_schema
    - execute()
    """

    name: str = ""
    description: str = ""
    input_schema: Dict[str, Any] = {"type": "object", "properties": {}, "required": []}
    output_schema: Dict[str, Any] = {
        "type": "object",
        "properties": {
            "ok": {"type": "boolean"},
            "content": {"type": "string"},
            "data": {"type": "object"},
            "error": {"type": "string"},
        },
    }

    def __init__(self, context: Optional[ToolContext] = None) -> None:
        self.context = context or ToolContext()

    def get_definition(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "description": self.description,
            "parameters": self.input_schema,
            "returns": self.output_schema,
        }

    def validate_params(self, params: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        normalized = params or {}
        if not isinstance(normalized, dict):
            raise ToolInputError(f"tool `{self.name}` params must be an object")

        required_fields = self.input_schema.get("required", [])
        for field_name in required_fields:
            if field_name not in normalized:
                raise ToolInputError(f"tool `{self.name}` missing required field: {field_name}")
        return normalized

    @abstractmethod
    def execute(self, params: Dict[str, Any]) -> ToolResult:
        """执行具体工具逻辑。"""

