import os
from typing import Any, Dict, List

import yaml

from system_prompt_component_type import system_prompt_component_type


class skill_prompt(system_prompt_component_type):
    """负责收集技能信息并生成技能相关的 system prompt。"""

    def on_init(self) -> None:
        self.skill_data: Dict[str, Any] = {
            "enabled_skill_ids": [],
            "official_skill_root": r"D:\agent_workspace\skills",
            "custom_skill_root": r"D:\agent_workspace\self_created_skills",
            "show_all_installed_skills": False,
            "skills": [],
        }
        self.apply_change(**self.component_config)

    def apply_change(self, **kwargs: Any) -> None:
        if "official_skill_root" in kwargs and kwargs["official_skill_root"]:
            self.skill_data["official_skill_root"] = kwargs["official_skill_root"]

        if "custom_skill_root" in kwargs and kwargs["custom_skill_root"]:
            self.skill_data["custom_skill_root"] = kwargs["custom_skill_root"]

        if "show_all_installed_skills" in kwargs:
            self.skill_data["show_all_installed_skills"] = bool(kwargs["show_all_installed_skills"])

        enabled_skill_ids = kwargs.get("enabled_skill_ids")
        if enabled_skill_ids is None:
            enabled_skill_ids = self._extract_enabled_skill_ids_from_agent_config()
        if enabled_skill_ids is not None:
            self.skill_data["enabled_skill_ids"] = enabled_skill_ids

        self.skill_data["skills"] = self.get_skill_info()

    def _extract_enabled_skill_ids_from_agent_config(self) -> List[str]:
        enabled_skill_ids: List[str] = []
        for skill_item in self.agent_config.get("skill", []):
            if not isinstance(skill_item, dict):
                continue
            enabled = str(skill_item.get("enable", "")).lower() == "true"
            skill_id = skill_item.get("id")
            if enabled and skill_id:
                enabled_skill_ids.append(skill_id)
        return enabled_skill_ids

    def _load_skill_meta(self, skill_path: str) -> Dict[str, Any]:
        skill_md = os.path.join(skill_path, "SKILL.md")
        if not os.path.exists(skill_md):
            return {}

        try:
            with open(skill_md, "r", encoding="utf-8") as file:
                content = file.read().strip()
        except OSError:
            return {}

        if not content.startswith("---"):
            return {}

        parts = content.split("---", 2)
        if len(parts) < 3:
            return {}

        frontmatter = parts[1].strip()
        try:
            meta = yaml.safe_load(frontmatter)
        except yaml.YAMLError:
            meta = self._fallback_parse_frontmatter(frontmatter)

        if not isinstance(meta, dict):
            meta = self._fallback_parse_frontmatter(frontmatter)

        return meta if isinstance(meta, dict) else {}

    def _fallback_parse_frontmatter(self, frontmatter: str) -> Dict[str, Any]:
        """
        容错解析简单 frontmatter。

        一些旧 skill 的 YAML 并不严格，这里至少兜底 name / description。
        """
        meta: Dict[str, Any] = {}
        for raw_line in frontmatter.splitlines():
            line = raw_line.strip()
            if not line or ":" not in line:
                continue
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()
            if key in {"name", "description", "version"} and value:
                meta[key] = value
        return meta

    def get_skill_info(self) -> List[Dict[str, Any]]:
        skills: List[Dict[str, Any]] = []
        roots = [
            ("官方技能", self.skill_data["official_skill_root"]),
            ("自建技能", self.skill_data["custom_skill_root"]),
        ]
        enabled_skill_ids = set(self.skill_data.get("enabled_skill_ids", []))
        show_all_installed_skills = self.skill_data.get("show_all_installed_skills", False)

        for skill_type, root_path in roots:
            if not root_path or not os.path.exists(root_path):
                continue

            for skill_dir in sorted(os.listdir(root_path)):
                skill_path = os.path.join(root_path, skill_dir)
                if not os.path.isdir(skill_path):
                    continue

                meta = self._load_skill_meta(skill_path)
                if not meta:
                    continue

                skill_name = meta.get("name", skill_dir)
                is_enabled = skill_name in enabled_skill_ids or skill_dir in enabled_skill_ids

                if not show_all_installed_skills and enabled_skill_ids and not is_enabled:
                    continue

                skills.append(
                    {
                        "name": skill_name,
                        "description": meta.get("description", ""),
                        "type": skill_type,
                        "path": skill_path,
                        "enabled": is_enabled,
                    }
                )

        return skills

    def build_system_prompt(self) -> str:
        lines: List[str] = ["# Available Skills"]
        skills = self.skill_data.get("skills", [])

        if not skills:
            if self.skill_data.get("show_all_installed_skills", False):
                lines.append("No installed skills are currently available.")
            else:
                lines.append("No enabled skills are currently available.")
            return "\n".join(lines)

        if self.skill_data.get("show_all_installed_skills", False):
            lines.append("Installed skills are listed below. Enabled status is shown for each skill:")
        else:
            lines.append("You can leverage the following skills when they match the task:")

        for skill in skills:
            description = skill.get("description", "").strip() or "No description provided."
            if self.skill_data.get("show_all_installed_skills", False):
                status = "enabled" if skill.get("enabled") else "disabled"
                lines.append(f"- {skill['name']} ({skill['type']}, {status}): {description}")
            else:
                lines.append(f"- {skill['name']} ({skill['type']}): {description}")

        return "\n".join(lines)
