from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scaffold_workflow import scaffold_workflow


class ScaffoldWorkflowTest(unittest.TestCase):
    def test_scaffold_generates_expected_structure(self) -> None:
        workflow = {
            "nodes": [
                {
                    "id": "node_1",
                    "description": "First stage",
                    "agent": [
                        {"id": "agent_1", "config_path": "agent_workflow\\config\\node1\\agent_1.json"},
                        {"id": "agent_2", "config_path": "agent_workflow\\config\\node1\\agent_2.json"},
                    ],
                    "agent_relationship": {
                        "agent_1": {"Superior": [], "Peer": [], "Subordinate": ["agent_2"]},
                        "agent_2": {"Superior": ["agent_1"], "Peer": [], "Subordinate": []},
                    },
                },
                {
                    "id": "node_2",
                    "description": "Second stage",
                    "agent": [
                        {"id": "agent_3", "config_path": "agent_workflow\\config\\node2\\agent_3.json"},
                    ],
                    "agent_relationship": {
                        "agent_3": {"Superior": [], "Peer": [], "Subordinate": []},
                    },
                },
            ],
            "id_map": {"node_1": ["node_2"], "node_2": []},
        }

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            workflow_path = tmp_path / "agent_workflow.json"
            workflow_path.write_text(json.dumps(workflow, ensure_ascii=False, indent=2), encoding="utf-8")

            target_dir = tmp_path / "generated_workflow"
            result = scaffold_workflow(workflow_path=workflow_path, target_dir=target_dir, overwrite=True, clean=False)

            self.assertTrue(result["ok"])
            self.assertTrue((target_dir / "agent_workflow.json").exists())
            self.assertTrue((target_dir / "agent_workflow_info.md").exists())
            self.assertTrue((target_dir / "demo_task.md").exists())

            self.assertTrue((target_dir / "nodes" / "node1" / "input" / "node_info.md").exists())
            self.assertTrue((target_dir / "nodes" / "node1" / "input" / "agent_1_info.md").exists())
            self.assertTrue((target_dir / "nodes" / "node1" / "output").exists())
            self.assertTrue((target_dir / "config" / "node1" / "agent_1.json").exists())
            self.assertTrue((target_dir / "config" / "node2" / "agent_3.json").exists())


if __name__ == "__main__":
    unittest.main()
