from __future__ import annotations

import json
from pathlib import Path

PROJECT = Path(r"D:\agent_workspace\capability-library\mycli\novel-writing\writing\project\sample-novel-001")
AGENT = Path(r"D:\agent_workspace\capability-library\mycli\novel-writing\writing\agents\11-小篇章状态表-agent.md")
TMP = PROJECT / "tmp"
ARC = PROJECT / "outlines" / "arc" / "volume-01"

ARC_FILES = [
    ARC / "00-第一卷小篇章总览.md",
    ARC / "01-倒序强钩子与魅魔契约.md",
    ARC / "02-职业觉醒与低评召唤师.md",
    ARC / "03-莉莉娅适应地球与林清雪吃醋.md",
    ARC / "04-镜湖小秘境前置训练.md",
    ARC / "05-高考小秘境初段打脸.md",
    ARC / "06-秘境异常与黑契会暗线.md",
    ARC / "07-二阶突破与江海重点关注.md",
    ARC / "08-旧港裂隙与青璃呼唤.md",
]

COMMON = [
    PROJECT / "outlines" / "volume" / "01-第一卷-觉醒与魅魔契约.md",
    PROJECT / "states" / "arc" / "volume-01" / "00-相关人物提取.md",
    PROJECT / "states" / "volume" / "00-卷级状态索引.md",
]

PEOPLE = [
    ("苏念", PROJECT / "assets" / "characters" / "01-主角团" / "苏念.md", PROJECT / "states" / "volume" / "characters" / "苏念.md", "01—08，全卷核心"),
    ("莉莉娅", PROJECT / "assets" / "characters" / "01-主角团" / "莉莉娅.md", PROJECT / "states" / "volume" / "characters" / "莉莉娅.md", "01—08，第一契约女主"),
    ("林清雪", PROJECT / "assets" / "characters" / "01-主角团" / "林清雪.md", PROJECT / "states" / "volume" / "characters" / "林清雪.md", "01—08，现实侧女主"),
    ("青璃", PROJECT / "assets" / "characters" / "01-主角团" / "青璃.md", PROJECT / "states" / "volume" / "characters" / "青璃.md", "08，卷末呼唤钩子"),
    ("江海镇守使", PROJECT / "assets" / "characters" / "03-配角" / "江海镇守使.md", None, "06—08，官方代表"),
    ("星海学院召唤系导师", PROJECT / "assets" / "characters" / "03-配角" / "星海学院召唤系导师.md", None, "07，学院关注"),
    ("林清雪同学竞争者", PROJECT / "assets" / "characters" / "03-配角" / "林清雪同学竞争者.md", None, "02—05，低评嘲讽/竞争"),
    ("方明远", PROJECT / "assets" / "characters" / "03-配角" / "方明远.md", None, "01—07，考务记录"),
    ("周远山", PROJECT / "assets" / "characters" / "03-配角" / "周远山.md", None, "02—04，班主任/资源压力"),
    ("唐绯雨", PROJECT / "assets" / "characters" / "03-配角" / "唐绯雨.md", None, "03、07—08，黑市情报"),
    ("秦牧野", PROJECT / "assets" / "characters" / "02-反派" / "秦牧野.md", None, "08，旧港阶段boss"),
]


def cf(path: Path, label: str) -> dict:
    return {"path": str(path), "label": label, "required": True}


def main() -> None:
    for name, asset, volume_state, scope in PEOPLE:
        ctx = [cf(asset, f"人物资产-{name}")]
        if volume_state is not None:
            ctx.append(cf(volume_state, f"卷级状态-{name}"))
        ctx.extend(cf(p, p.name) for p in COMMON)
        ctx.extend(cf(p, p.name) for p in ARC_FILES)
        payload = {
            "target": f"states\\arc\\volume-01\\characters\\{name}.md",
            "agent_md": {"path": str(AGENT)},
            "agent": "11-小篇章状态表-agent",
            "task_type": f"阶段11-第一卷单人物小篇章状态-{name}",
            "model": "MoreCode/gpt-5.5",
            "max_tokens": 12000,
            "temperature": 0.25,
            "base_dir": r"D:\agent_workspace\capability-library\mycli\novel-writing\writing",
            "project": str(PROJECT),
            "output_dir": str(PROJECT / "tmp" / "agent-runs" / "11-第一卷单人物小篇章状态" / name),
            "user_prompt": (
                f"请只生成【{name}】在第一卷各小篇章的相关人物状态，直接输出完整 Markdown 正文，不要 FILE 分块，不要代码围栏。"
                f"该人物相关范围：{scope}。不相关的小篇章可标记为“未登场/仅被提及/无状态变化”，不要硬编戏份。"
                "要求简短但抓住主要信息：每个相关小篇章写起点状态、终点状态、实力/力量体系变化、情感/关系变化、掌握信息变化、资源/伤势/污染变化、下一篇章承接。"
                "只写人物状态，不写势力状态，不复述完整剧情。"
                "必须遵守第一卷设定：第一章直接是苏念和莉莉娅性爱/事后状态；亲密高刺激节点每3—5章一次；第一卷末约二阶；林清雪不是召唤物；不得出现旧名；不要使用“接口”等技术化语言。"
            ),
            "context_files": ctx,
        }
        (TMP / f"11-小篇章人物状态-{name}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
