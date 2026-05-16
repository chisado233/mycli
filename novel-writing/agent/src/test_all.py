from __future__ import annotations

import importlib
import importlib.util
import sys
import unittest
from pathlib import Path


CURRENT_DIR = Path(__file__).resolve().parent
TEST_MODULES = [
    ("llm", "test_llm"),
    ("tool", "test_tool_runtime"),
    ("system_prompt_component", "test_system_prompt"),
    ("agent", "test_agent"),
    ("runtime", "test_runtime_bus"),
    ("runtime", "test_scaffold_workflow"),
    ("runtime", "test_runtime"),
]
SHARED_MODULE_NAMES = [
    "agent",
    "builtin_tools",
    "channel",
    "llm",
    "runtime",
    "runtime_bus",
    "scaffold_workflow",
    "system_prompt",
    "tool",
    "tool_base",
    "tool_runtime",
]


def _load_module_from_path(module_name: str, module_path: Path):
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"failed to load test module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def load_tests(loader: unittest.TestLoader, tests: unittest.TestSuite, pattern: str) -> unittest.TestSuite:
    suite = unittest.TestSuite()
    suite.addTests(tests)

    for relative_dir, module_name in TEST_MODULES:
        module_dir = CURRENT_DIR / relative_dir
        if str(module_dir) not in sys.path:
            sys.path.insert(0, str(module_dir))
        for shared_name in SHARED_MODULE_NAMES:
            sys.modules.pop(shared_name, None)
        module = _load_module_from_path(
            f"mult_agent_{relative_dir}_{module_name}",
            module_dir / f"{module_name}.py",
        )
        suite.addTests(loader.loadTestsFromModule(module))

    return suite
