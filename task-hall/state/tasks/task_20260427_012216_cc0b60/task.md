# 玄幻小说工作流真实链路验证：审校与返工流程检查

## 背景

`xuanhuan-novel-workflow` 的核心价值之一是“正文草稿 → 多维审校 → 问题单 → 返工建议”的闭环。本任务用于验证 G 阶段审校/返工机制，而不是直接重写正文。

项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow`

示例小说项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project`

重要参考：

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\design.md` 的阶段 G、8.3、8.4、模板 10.6
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\runbook.md`
- `example-project\canon\`
- 如已存在：`example-project\chapter-briefs\chapter-001.md`、`example-project\drafts\chapters\chapter-001-draft.md`

## 目标

对示例首章产物或当前示例骨架执行一次审校/返工流程检查，形成可执行的问题单和返工计划，验证工作流能否发现设定、节奏、文风和人物一致性风险。

## 任务说明

请在任务范围内完成：

1. 阅读工作流审校设计、canon、章节 brief / 草稿（若存在）。
2. 如果章节 brief / 草稿尚不存在，请基于当前资产状态输出“阻塞型审校报告”，明确缺失输入和后续应如何接续；不要伪造已审校正文。
3. 如果章节 brief / 草稿存在，请至少完成三类 review：
   - continuity：设定、境界/战力、时间线、人物行为、伏笔状态。
   - appeal：爽点兑现、节奏、章尾钩子、追读驱动力。
   - style：文风一致性、语言重复、网文可读性。
4. 输出结构化返工计划：`example-project\repair\repair-plan-chapter-001.md`，包含问题严重度、定位、建议动作、是否必须返工。
5. 不直接改写正文，不直接修改 canon。

## 范围与约束

- 可以新增/修改：
  - `example-project\review\continuity-chapter-001.md`
  - `example-project\review\appeal-chapter-001.md`
  - `example-project\review\style-chapter-001.md`
  - `example-project\repair\repair-plan-chapter-001.md`
- 不要修改正文草稿和 canon。
- 报告必须诚实说明输入是否充分；不把缺输入伪装成通过。

## 期望产物

- 三类 review 报告（或缺输入时的阻塞型 review 报告）。
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\repair\repair-plan-chapter-001.md`
- 任务报告 Markdown，说明审校结论、是否允许进入 polished/canon update、需要返工的责任环节。

## 验收标准

- 问题单具体、可定位、可执行，包含严重度与建议动作。
- 明确判断：通过 / 需小修 / 必须返工 / 输入不足阻塞。
- 不越权修改正文和 canon。
- 能验证 task-link 回调中 leader 如何判断 complete / continue。

## 发布模式

watched。执行 agent 完成或受阻时必须通过 task-link report 汇报给 `opencode/engineering-leader`。

## 建议 agent 类型或能力要求

建议 `middle-builder` 或 QA 型 builder；需要审校、问题拆解和返工闭环设计能力。

## 领取门槛

复杂度：中高

最低模型要求：strong

指定 agent 类型：middle-builder
