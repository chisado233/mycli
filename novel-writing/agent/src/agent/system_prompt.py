from __future__ import annotations

import json
import sys
import importlib.util
from pathlib import Path
from typing import Any, Dict


CURRENT_DIR = Path(__file__).resolve().parent
SRC_DIR = CURRENT_DIR.parent
SYSTEM_PROMPT_COMPONENT_DIR = SRC_DIR / "system_prompt_component"


def _load_component_system_prompt_class():
    module_path = SYSTEM_PROMPT_COMPONENT_DIR / "system_prompt.py"
    spec = importlib.util.spec_from_file_location("system_prompt_component_module", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"failed to load system prompt component module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    if str(SYSTEM_PROMPT_COMPONENT_DIR) not in sys.path:
        sys.path.insert(0, str(SYSTEM_PROMPT_COMPONENT_DIR))
    spec.loader.exec_module(module)
    return module.system_prompt


ComponentSystemPrompt = _load_component_system_prompt_class()


class AgentSystemPrompt:
    """agent 侧的 system prompt 封装。"""

    def __init__(self, agent_config: Dict[str, Any]) -> None:
        self.agent_config = agent_config
        self.manager = ComponentSystemPrompt(agent_config)

    @classmethod
    def from_config_file(cls, config_path: str) -> "AgentSystemPrompt":
        path = Path(config_path)
        payload = json.loads(path.read_text(encoding="utf-8"))
        return cls(payload)

    def get_prompt(self) -> str:
        return self.manager.get_sys_prompt()

    def update_all_components(self, **kwargs: Any) -> Dict[str, str]:
        return self.manager.update_all_components(**kwargs)

    def update_component(self, component_id: str, **kwargs: Any) -> str:
        return self.manager.update_component(component_id, **kwargs)
