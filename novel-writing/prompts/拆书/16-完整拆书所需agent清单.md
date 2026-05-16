# 完整拆解一本书需要用到的 Agent 清单

## 0. 总结结论

如果用户要求“完整拆解一本书”，不要只用一个拆书 agent 从头跑到尾。

推荐使用以下核心 agent 链路：

```text
调度/总控 agent
  ↓
批次高质量素材拆解 agent（5章一批）
  ↓
阶段汇总 agent（约50章或每卷一次）
  ↓
文风拆解 agent（每阶段一次 + 全书一次）
  ↓
全书统一 agent（全书结束后）
  ↓
最终汇总审核评估 agent
  ↓
精选入库/索引整理
```

可选闭环：

```text
还原写作 agent → 还原对比评估 agent
```

这个闭环不是正式拆书必须步骤，而是用来验证“内容拆解 + 文风拆解”是否足够支持后续 AI 写作。

---

## 1. 调度/总控 Agent

### 用途

负责规划整本书的拆解流程，不直接深度拆原文。

它要决定：

- 原书路径。
- 输出项目路径。
- 批次范围。
- 每批传入哪些上下文。
- 调用哪个 agent prompt。
- request JSON 如何写。
- 每轮跑完如何验收。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\00-拆书总控agent.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\00-使用者如何拆书.md
```

### 实际执行时

当前 assistant 也可以直接承担调度 agent 职责：生成 request JSON、运行 `mycli novel-writing agent run`、检查产物。

### 是否必须

必须。完整拆一本书需要它做批次规划和质量控制。

---

## 2. 原文导入/章节准备 Agent

### 用途

当原书还没有整理成章节文件时，用于导入、切分、命名、建立 catalog。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\01-原文导入切分agent.md
```

### 是否必须

视情况而定。

如果原书已经在：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\书名\章节
```

并且已有 `catalog.json`，则可以跳过。

---

## 3. 批次高质量素材拆解 Agent

### 用途

这是完整拆书的主力 agent。

负责按 5 章一批输出：

- 剧情内容拆解。
- 可复用素材库。
- 场景素材。
- 爽点素材。
- 伏笔素材。
- 人物设定阶段素材。
- 情感线推进阶段素材。
- 力量体系阶段素材。
- 世界设定阶段素材。
- 完整故事概要阶段素材。
- 文学风格片段素材。
- 灵活记录。
- 质量自检。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\03A-章节批量粗拆agent.md
```

虽然文件名叫“章节批量粗拆”，但当前实际使用时，它已经通过模块化 prompt 承担“素材库分类版高质量拆书”的任务。

### 必须传入的模块

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\01-素材库总规则.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\02-场景素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\03-爽点素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\04-伏笔素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\05-人物设定素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\06-情感线推进模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\07-力量体系素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\08-世界设定素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\09-完整故事概要模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\10-文学风格收集模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\11-灵活记录模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\12-剧情内容拆解模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\15-质量自检模板.md
```

### 批次粒度

推荐：

```text
目标章节：5章
上下文章节：前后约10章
```

例：目标 `031-035`，上下文 `021-045`。

### 是否必须

必须。完整拆书主要靠它覆盖全书。

---

## 4. 高光素材摘录 Agent

### 用途

用于从重点章节中补充高光片段、名场面、搞笑点、抽象点、金句、爽点片段。

它适合在批次拆解后，对 A 级章节或用户特别关注章节做二次摘录。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\15-高光素材摘录agent.md
```

### 是否必须

可选。

如果批次高质量拆解已经足够好，可以不单独跑。若某些名场面需要更精细研究，建议追加。

---

## 5. 阶段汇总 Agent

### 用途

每 50 章或每卷汇总一次，把多个批次的碎片合并为阶段级档案。

负责：

- 阶段主线推进。
- 阶段人物变化。
- 阶段情感线变化。
- 阶段力量体系变化。
- 阶段世界设定变化。
- 阶段伏笔状态。
- 阶段高价值素材筛选。
- 阶段低质量素材剔除。
- 阶段滚动摘要。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\05-阶段汇总agent.md
```

### 必须传入的模块

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\04-伏笔素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\05-人物设定素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\06-情感线推进模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\07-力量体系素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\08-世界设定素材模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\09-完整故事概要模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\14-最终统一模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\15-质量自检模板.md
```

### 输入策略

不要塞入所有原文。优先传：

- 每个 batch 的 `00-总览`。
- 每个 batch 的 `03-索引`。
- 人物设定素材。
- 情感线推进素材。
- 力量体系素材。
- 世界设定素材。
- 伏笔素材。
- 质量自检。

### 是否必须

必须。否则全书统一时上下文会爆炸。

---

## 6. 文风拆解 Agent

### 用途

负责拆原作的叙述风格，不负责复述剧情。

输出：

- 文风总览。
- 叙述节奏。
- 吐槽与笑点。
- 爽点表达。
- 对话风格。
- 设定说明方式。
- 章节钩子。
- 可迁移句法。
- 不可照搬表达。
- 写作 agent 输入用的文风控制卡。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\16-文风拆解agent.md
```

### 必须传入的模块

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\10-文学风格收集模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\13-文风拆解模板.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\15-质量自检模板.md
```

### 调用频率

建议：

```text
每阶段 50 章跑一次阶段文风拆解
全书结束后再跑一次全书文风统一
```

### 是否必须

必须。用户目标是服务后续 AI 写作，文风拆解不能省。

---

## 7. 全书统一 Agent

### 用途

全书拆完后，把阶段汇总统一成最终全局档案。

负责输出：

- 完整人物设定。
- 完整情感线推进。
- 完整力量体系。
- 完整世界设定。
- 伏笔总表。
- 全书剧情概要。
- 全书爽点模型。
- 全书文风总览。
- 全书可复用写作模板。
- 正式入库精选素材候选。

### 当前状态

目前已有统一模板：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\14-最终统一模板.md
```

但目前还没有单独的：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\19-全书统一agent.md
```

因此当前可临时用 `05-阶段汇总agent.md` + `14-最终统一模板.md` 来跑全书统一，但更推荐后续补一个专门的全书统一 agent。

### 是否必须

必须。没有全书统一，人物、情感线、力量体系、世界设定、伏笔都会停留在碎片状态。

---

## 8. 最终汇总审核评估 Agent

### 用途

只检查阶段汇总、全书统一和正式入库候选是否完整、准确、可追溯、可迁移。

默认不对每个 5 章批次单独跑审核 agent，因为批次数量太多，成本和调度复杂度过高。批次层只依赖模型自检和调度 agent 的轻量检查。

审核 agent 重点识别：

- 章节覆盖遗漏。
- 素材空泛。
- 伏笔状态错误。
- 人物/情感线/力量体系/世界设定碎片未统一。
- 证据不足。
- 抄袭/照搬风险。
- 阶段/全书汇总是否只是简单拼接。
- 精选入库候选是否质量不足。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\13-审核评估agent.md
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\15-质量自检模板.md
```

### 调用频率

建议：

```text
5章批次：不跑审核 agent，只做轻量检查。
阶段汇总：可选审核，重要阶段建议审核。
全书统一：必须审核。
正式入库前：必须审核精选素材候选。
```

### 是否必须

必须，但只要求在最终汇总层使用。完整拆一本书不能只相信模型自检，但也不应对每个小批次都跑审核。

---

## 9. 索引更新 Agent

### 用途

维护全书索引：章节索引、人物索引、伏笔索引、设定索引、素材索引、阶段索引。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\07-索引更新agent.md
```

### 当前建议

如果批次拆解和阶段汇总已经输出 `03-索引`，可以先由调度 agent 直接管理索引；当全书范围变大后，再单独跑索引更新 agent。

### 是否必须

中长篇推荐使用。700 章以上基本必须使用，否则后期检索困难。

---

## 10. 还原写作 Agent（验证闭环，可选）

### 用途

用于验证拆书质量。

它读取：

- 内容拆解。
- 文风控制卡。

然后写出结构与风格练习稿。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\17-还原写作agent.md
```

### 是否必须

不是完整拆书必须步骤。

但如果用户想验证“拆出来的东西能不能指导 AI 写作”，建议每 50 章抽 3-5 章跑一次。

---

## 11. 还原对比评估 Agent（验证闭环，可选）

### 用途

比较：

- 原文。
- 内容拆解。
- 文风拆解。
- 还原写作稿。

判断当前 prompt 是否足够支撑还原写作，并提出调参建议。

### 当前可用 prompt

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\18-还原对比评估agent.md
```

### 是否必须

可选。用于优化拆书系统，不是正式产物链路必须项。

---

## 12. 完整拆书推荐执行顺序

以一本 700 章长篇为例：

```text
1. 调度 agent 检查原书目录、catalog、输出目录。
2. 如果章节未整理，先跑原文导入/章节准备 agent。
3. 批次高质量素材拆解 agent：5章一批，覆盖全书。
4. 每完成约50章，跑阶段汇总 agent。
5. 每完成约50章，跑文风拆解 agent。
6. 每个阶段汇总后执行轻量检查；重要阶段可跑审核评估 agent。
7. 全书所有阶段完成后，跑全书统一 agent。
8. 全书统一后，必须跑审核评估 agent 做总验收。
9. 如需要验证写作可用性，抽样跑还原写作 agent + 还原对比评估 agent。
10. 最后由调度 agent 整理精选素材候选，等待人工确认后入 material-library。
```

---

## 13. 最小必需 Agent 组合

如果只保留最少 agent，完整拆书至少需要：

```text
1. 调度/总控 agent
2. 批次高质量素材拆解 agent
3. 阶段汇总 agent
4. 文风拆解 agent
5. 全书统一 agent
6. 最终汇总审核评估 agent
```

可选增强：

```text
7. 原文导入/章节准备 agent
8. 高光素材摘录 agent
9. 索引更新 agent
10. 还原写作 agent
11. 还原对比评估 agent
```

---

## 14. 当前缺口

当前系统主要缺一个专门的全书统一 agent：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\19-全书统一agent.md
```

已有 `14-最终统一模板.md`，但它只是模块模板，不是完整 agent prompt。

如果用户下一步要求继续完善，优先创建 `19-全书统一agent.md`，再把本清单写入 `00-使用者如何拆书.md` 的 agent 编排章节。
