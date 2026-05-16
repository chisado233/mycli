# GitHub 热点抓取任务

## 背景
这是工程部生命周期系统的真实任务测试。要求 engineering-leader 自己完成信息抓取、整理和汇报，不再拆给 builder。目标是验证 leader 在允许亲自做信息整理任务时，能按 task-hall/task-link 完成闭环。

## 目标
抓取并整理当前 GitHub 热点项目，输出可读 Markdown 报告。

## 工作范围
- 获取 GitHub Trending 或等价公开来源的当前热门仓库信息。
- 至少整理 10 个项目。
- 每个项目包含：仓库名、链接、主要语言/技术、简介、热度指标（如 stars today / total stars，如可获得）、为什么值得关注。
- 输出 Markdown 报告到 `D:\agent_workspace\tmp\github-hot-repos\github-hot-repos.md`。
- 可使用网页/命令/公开 API；不使用 token，不登录，不调用需要密钥的服务。

## 不做范围
- 不克隆大型仓库。
- 不写爬虫长期服务。
- 不 push、不部署、不发送外部消息。
- 不使用 GitHub token 或任何密钥。

## 交付物
- `D:\agent_workspace\tmp\github-hot-repos\github-hot-repos.md`
- task-link report

## 验收标准
- 报告至少包含 10 个项目。
- 每个项目有链接和简要说明。
- 明确说明数据来源和抓取/整理时间。
- 如果 GitHub Trending 无法访问，说明替代来源和限制。
- 最终必须通过 `mycli task-hall task-link report` 提交。

## 推荐 agent 类型
engineering-leader

## 汇报方式
必须使用 task-link report；最终聊天回复不能替代正式提交。
