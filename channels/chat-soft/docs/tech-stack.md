# 技术选型

## 语言/运行时
| 技术 | 版本 | 选型原因 |
|------|------|---------|
| Node.js | 24.x | Bridge 服务端，Fastify/TypeScript 生态成熟 |
| TypeScript | 5.9 | 全栈类型安全，协议定义统一 |
| Java | 17 | Android 原生层（ForegroundService） |
| Python | 3.x | LLM worker（已废弃，被 SSE 替代） |

## 核心依赖
| 库/框架 | 版本 | 用途 | 选型原因 |
|---------|------|------|---------|
| Fastify | 5.x | 云服务器 HTTP+WS | 性能好、插件生态丰富 |
| React | 19.x | 手机端 UI | Capacitor 默认、SSE 渲染 |
| Capacitor | 7.x | Android 原生包装 | 轻量 WebView 容器 |
| ws | 8.x | WebSocket 客户端/服务端 | Node.js WS 标准库 |
| marked | 15.x | Markdown 渲染 | 轻量（260KB min） |
| @capacitor/local-notifications | 7.x | Android 通知 | 原生通知栏（暂缓） |
| pnpm | 10.x | monorepo 管理 | workspace 协议，快 |

## 开发工具
| 工具 | 用途 |
|------|------|
| ADB | Android 调试 + APK 安装 |
| Gradle | Android 构建 |
| PuTTY plink | SSH 到云服务器部署 |
| PM2 | 云服务器进程管理 |
| mycli | 本机统一命令入口 |

## 选型约束
- Android WebView 不支持 `Notification` API → 改用 Capacitor LocalNotifications
- opencode serve 没有官方文档 API → 通过探索发现 `/event` 端点
- `opencode --format json` 不输出 text 事件 → 弃用，改用 SSE