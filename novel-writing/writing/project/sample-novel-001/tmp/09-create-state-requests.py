from __future__ import annotations

import json
from pathlib import Path

PROJECT = Path(r"D:\agent_workspace\capability-library\mycli\novel-writing\writing\project\sample-novel-001")
AGENT = Path(r"D:\agent_workspace\capability-library\mycli\novel-writing\writing\agents\09-卷级状态表-agent.md")
TMP = PROJECT / "tmp"

COMMON_VOLUME_FILES = [
    PROJECT / "outlines" / "volume" / "00-总卷纲.md",
    PROJECT / "outlines" / "volume" / "01-第一卷-觉醒与魅魔契约.md",
    PROJECT / "outlines" / "volume" / "02-第二卷-星海学院与剑冢试炼.md",
    PROJECT / "outlines" / "volume" / "03-第三卷-深渊夜庭与血月王庭.md",
    PROJECT / "outlines" / "volume" / "04-第四卷-昆墟天门与万狐幻局.md",
    PROJECT / "outlines" / "volume" / "05-第五卷-钢穹裂港与机娘回收战.md",
    PROJECT / "outlines" / "volume" / "06-第六卷-多界战场与神庭圣痕.md",
    PROJECT / "outlines" / "volume" / "07-第七卷-神门降临与诸界反神.md",
]

COMMON_CONTEXT = [
    (PROJECT / "assets" / "planning" / "00-作品企划.md", "正式作品企划"),
    (PROJECT / "assets" / "worldview" / "00-世界观总览.md", "世界观总览"),
    (PROJECT / "assets" / "worldview" / "04-力量体系.md", "力量体系"),
    (PROJECT / "assets" / "characters" / "00-人物总览.md", "人物总览"),
    (PROJECT / "assets" / "factions" / "势力总览.md", "势力总览"),
    (PROJECT / "outlines" / "rough" / "00-故事粗纲.md", "故事线粗纲"),
    (PROJECT / "outlines" / "emotion" / "00-情感线粗纲.md", "情感线粗纲"),
]

CHARACTERS = [
    ("苏念", PROJECT / "assets" / "characters" / "01-主角团" / "苏念.md", "主角"),
    ("林清雪", PROJECT / "assets" / "characters" / "01-主角团" / "林清雪.md", "主角团"),
    ("莉莉娅", PROJECT / "assets" / "characters" / "01-主角团" / "莉莉娅.md", "主角团"),
    ("克露露", PROJECT / "assets" / "characters" / "01-主角团" / "克露露.md", "主角团"),
    ("青璃", PROJECT / "assets" / "characters" / "01-主角团" / "青璃.md", "主角团"),
    ("诺雅", PROJECT / "assets" / "characters" / "01-主角团" / "诺雅.md", "主角团"),
    ("白九璃", PROJECT / "assets" / "characters" / "01-主角团" / "白九璃.md", "主角团"),
    ("希尔薇", PROJECT / "assets" / "characters" / "01-主角团" / "希尔薇.md", "主角团"),
    ("伊芙琳", PROJECT / "assets" / "characters" / "01-主角团" / "伊芙琳.md", "主角团"),
    ("影弥", PROJECT / "assets" / "characters" / "01-主角团" / "影弥.md", "主角团"),
    ("白金神使", PROJECT / "assets" / "characters" / "02-反派" / "白金神使.md", "反派"),
    ("黑契会首领", PROJECT / "assets" / "characters" / "02-反派" / "黑契会首领.md", "反派"),
    ("梦魇主母", PROJECT / "assets" / "characters" / "02-反派" / "梦魇主母.md", "反派"),
    ("血月王庭保守派代表", PROJECT / "assets" / "characters" / "02-反派" / "血月王庭保守派代表.md", "反派"),
    ("黑莲魔修", PROJECT / "assets" / "characters" / "02-反派" / "黑莲魔修.md", "反派"),
    ("军工财团董事", PROJECT / "assets" / "characters" / "02-反派" / "军工财团董事.md", "反派"),
    ("江海镇守使", PROJECT / "assets" / "characters" / "03-配角" / "江海镇守使.md", "配角"),
    ("星海学院召唤系导师", PROJECT / "assets" / "characters" / "03-配角" / "星海学院召唤系导师.md", "配角"),
    ("林清雪同学竞争者", PROJECT / "assets" / "characters" / "03-配角" / "林清雪同学竞争者.md", "配角"),
]

FACTIONS = [
    ("神明世界-神庭秩序", PROJECT / "assets" / "factions" / "T0-神明世界-神庭秩序.md"),
    ("地球-华夏大秘境镇守体系", PROJECT / "assets" / "factions" / "T1-地球-华夏大秘境镇守体系.md"),
    ("深渊世界-魔巢诸侯", PROJECT / "assets" / "factions" / "T1-深渊世界-魔巢诸侯.md"),
    ("修仙世界-昆墟宗门联盟", PROJECT / "assets" / "factions" / "T1-修仙世界-昆墟宗门联盟.md"),
    ("机甲世界-钢穹机甲联合体", PROJECT / "assets" / "factions" / "T1-机甲世界-钢穹机甲联合体.md"),
    ("巨龙世界-龙渊古龙诸巢", PROJECT / "assets" / "factions" / "T1-巨龙世界-龙渊古龙诸巢.md"),
    ("地球-江海市前期势力", PROJECT / "assets" / "factions" / "T2-地球-江海市前期势力.md"),
    ("女主原世界关联势力", PROJECT / "assets" / "factions" / "T2-女主原世界关联势力.md"),
]


def context(path: Path, label: str) -> dict:
    return {"path": str(path), "label": label, "required": True}


def base_payload(kind: str, name: str, target: str) -> dict:
    return {
        "target": target,
        "agent_md": {"path": str(AGENT)},
        "agent": "09-卷级状态表-agent",
        "task_type": f"阶段09-单{kind}卷级状态轨迹-{name}",
        "model": "MoreCode/gpt-5.5",
        "max_tokens": 20000,
        "temperature": 0.25,
        "base_dir": r"D:\agent_workspace\capability-library\mycli\novel-writing\writing",
        "project": str(PROJECT),
        "output_dir": str(PROJECT / "tmp" / "agent-runs" / "09-卷级状态轨迹" / ("characters" if kind == "人物" else "factions") / name),
    }


def character_prompt(name: str, role: str) -> str:
    return (
        f"请只生成【{name}】这一名{role}的卷级状态轨迹，直接输出完整 Markdown 正文，不要 FILE 分块，不要代码围栏。"
        "必须严格按照《人物卷级状态轨迹模板》的结构填写，不要删减模板关键栏目。"
        "目标是记录该人物在卷0开篇前、第一卷结束、第二卷结束……第七卷结束这些卷分界点的状态。"
        "状态来源统一标记为“计划状态”。重点必须细写：实力等级/阶位、力量体系变化、新增能力、能力代价/限制、契约状态、情感阶段、情感推进证据、与苏念关系、与主角团关系、资源装备、伤势/污染、掌握信息、隐瞒秘密、下卷承接。"
        "不要写成每卷剧情复述，而要写状态变化表。男主名为苏念；林清雪不是召唤物；所有亲密进展只写隐晦氛围/关系阶段/契约同步/称呼变化等合规表达。不得出现旧名，不要使用“接口”等技术化语言。"
    )


def faction_prompt(name: str) -> str:
    return (
        f"请只生成【{name}】这一势力/势力组的卷级状态轨迹，直接输出完整 Markdown 正文，不要 FILE 分块，不要代码围栏。"
        "必须严格按照《势力卷级状态轨迹模板》的结构填写，不要删减模板关键栏目。"
        "目标是记录该势力在卷0开篇前、第一卷结束、第二卷结束……第七卷结束这些卷分界点的状态。"
        "状态来源统一标记为“计划状态”。重点必须细写：公开立场、暗线立场、主力量体系、最高战力、中坚战力规模、神庭/圣痕影响、代表人物状态、对苏念认知、对主角团情感/信任态度、资源/战力损失收益、与其他势力关系、下卷行动计划。"
        "不要写成每卷剧情复述，而要写状态变化表。不得出现旧名，不要使用“接口”等技术化语言。"
    )


def write_request(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    for name, asset, role in CHARACTERS:
        payload = base_payload("人物", name, f"states\\volume\\characters\\{name}.md")
        payload["user_prompt"] = character_prompt(name, role)
        payload["context_files"] = [
            context(PROJECT / "states" / "volume" / "00-人物卷级状态轨迹模板.md", "人物卷级状态轨迹模板"),
            context(asset, f"人物资产-{name}"),
            *[context(p, p.name) for p in COMMON_VOLUME_FILES],
            *[context(p, label) for p, label in COMMON_CONTEXT],
        ]
        write_request(TMP / f"09-人物状态轨迹-{name}.json", payload)

    for name, asset in FACTIONS:
        payload = base_payload("势力", name, f"states\\volume\\factions\\{name}.md")
        payload["user_prompt"] = faction_prompt(name)
        payload["context_files"] = [
            context(PROJECT / "states" / "volume" / "00-势力卷级状态轨迹模板.md", "势力卷级状态轨迹模板"),
            context(asset, f"势力资产-{name}"),
            *[context(p, p.name) for p in COMMON_VOLUME_FILES],
            *[context(p, label) for p, label in COMMON_CONTEXT],
        ]
        write_request(TMP / f"09-势力状态轨迹-{name}.json", payload)


if __name__ == "__main__":
    main()
