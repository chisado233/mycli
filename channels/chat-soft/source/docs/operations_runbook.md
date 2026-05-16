# Chat Soft 运行与运维手册

更新时间：2026-04-24

本文档用于统一记录 `Chat Soft` 各模块的：

- 更新方式
- 重启方式
- 启动方式
- 验证方式
- 任务进度查看方式
- 常见排错方式

适用对象：

- 远端服务器上的 `chat-soft` 主服务
- 本机 `Codex Mirror`
- 本机 `Codex VS Code Bridge`
- 本机桌面端
- 本机移动端

---

## 1. 目录与组件

项目根目录：

- `D:\agent_workspace\projects\chat_soft`

服务器部署目录：

- `/opt/chat_soft`

主要组件：

- 主服务：`@chat-soft/server`
- 桌面端：`@chat-soft/desktop`
- 移动端：`@chat-soft/mobile`
- Codex 镜像服务：`@chat-soft/codex-mirror-server`
- Codex 镜像调试页：`@chat-soft/codex-mirror-debug`
- VS Code 插件桥接：`tools/codex-vscode-bridge`

---

## 2. 服务器主服务

当前线上服务器的实际运行方式：

- 项目目录：`/opt/chat_soft`
- 服务目录：`/opt/chat_soft/server/api`
- 进程管理：`PM2`
- 服务名：`chat-soft-server`
- 端口：`3000`
- 健康检查：`/health`

注意：

- 这个服务没有定义根路由 `/`
- 访问 `http://SERVER_IP:3000/` 返回 `404` 是正常现象
- 正确验证地址是 `http://SERVER_IP:3000/health`

### 2.1 首次部署或补装环境

服务器需要：

- Node.js 20+
- npm
- PM2

如果 `pnpm` 不在 `PATH` 中，统一使用绝对路径：

```bash
/usr/local/bin/pnpm
```

如果 `pm2` 不在 `PATH` 中，统一使用绝对路径：

```bash
/usr/local/bin/pm2
```

安装 `pnpm`：

```bash
npm install -g pnpm@10.18.0
```

安装 `PM2`：

```bash
npm install -g pm2
```

### 2.2 首次启动

在服务器执行：

```bash
cd /opt/chat_soft
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
HOST=0.0.0.0 PORT=3000 /usr/local/bin/pm2 start /opt/chat_soft/server/api/dist/index.js --name chat-soft-server
/usr/local/bin/pm2 save
```

### 2.3 日常更新

在服务器执行：

```bash
cd /opt/chat_soft
git pull
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
/usr/local/bin/pm2 restart chat-soft-server
```

如果不是 `git pull` 方式更新，而是直接覆盖项目目录，也同样执行后 3 条命令即可。

### 2.4 启动与重启

启动服务：

```bash
/usr/local/bin/pm2 start /opt/chat_soft/server/api/dist/index.js --name chat-soft-server
```

重启服务：

```bash
/usr/local/bin/pm2 restart chat-soft-server
```

停止服务：

```bash
/usr/local/bin/pm2 stop chat-soft-server
```

删除服务：

```bash
/usr/local/bin/pm2 delete chat-soft-server
```

查看状态：

```bash
/usr/local/bin/pm2 list
```

### 2.5 服务器验证

本机回环验证：

```bash
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/api/agents
curl http://127.0.0.1:3000/api/conversations
```

公网验证：

```bash
curl http://SERVER_IP:3000/health
```

正常时应看到：

- `/health` 返回 `{"ok":true}`
- `/api/agents` 返回 agent 列表
- `/api/conversations` 返回会话列表

### 2.6 服务器日志

查看服务日志：

```bash
/usr/local/bin/pm2 logs chat-soft-server
```

查看最近状态：

```bash
/usr/local/bin/pm2 list
```

如果只想确认端口是否被监听：

```bash
ss -ltnp | grep :3000
```

### 2.7 常见问题

访问 `/` 返回 `404`：

- 正常现象
- 这个项目没有首页路由
- 用 `/health` 检查是否存活

`listen EADDRINUSE: address already in use 0.0.0.0:3000`：

- 说明 `3000` 端口已经被现有服务占用
- 不要手工重复执行 `pnpm --filter @chat-soft/server start`
- 先看：

```bash
ss -ltnp | grep :3000
/usr/local/bin/pm2 list
```

如果确认是旧服务异常占用，再执行：

```bash
/usr/local/bin/pm2 restart chat-soft-server
```

`pnpm: command not found`：

- 直接使用：

```bash
/usr/local/bin/pnpm
```

`pm2: command not found`：

- 直接使用：

```bash
/usr/local/bin/pm2
```

本机 `curl http://127.0.0.1:3000/health` 正常，但公网访问失败：

- 先确认服务已监听 `0.0.0.0:3000`
- 再检查云服务器安全组是否放行 `3000`
- 再检查系统防火墙是否放行 `3000`

### 2.8 维护时的最短操作路径

只更新代码并重启：

```bash
cd /opt/chat_soft
git pull
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
/usr/local/bin/pm2 restart chat-soft-server
```

只检查是否还活着：

```bash
curl http://127.0.0.1:3000/health
```

只看服务日志：

```bash
/usr/local/bin/pm2 logs chat-soft-server
```

---

## 3. Codex 镜像服务

说明：

- 这是本机运行的本地服务
- 默认端口：`3090`
- 当前启动命令应使用新的构建入口，不能再用旧的 `dist/index.js`

### 3.1 本机更新

在本机项目目录执行：

```powershell
cd D:\agent_workspace\projects\chat_soft
git pull
pnpm install
pnpm --filter @chat-soft/codex-mirror-server build
pnpm --filter @chat-soft/codex-mirror-debug build
```

### 3.2 本机启动

开发模式：

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm dev:codex-mirror-server
```

生产构建启动：

```powershell
cd D:\agent_workspace\projects\chat_soft\server\codex-mirror
node dist/server/codex-mirror/src/index.js
```

### 3.3 本机重启

如果是前台终端运行：

- 先 `Ctrl+C`
- 再重新执行启动命令

如果是后台 `Start-Process` 跑的：

先杀掉监听 `3090` 端口的进程：

```powershell
Get-NetTCPConnection -LocalPort 3090 -State Listen | Select-Object -ExpandProperty OwningProcess
Stop-Process -Id <PID> -Force
```

然后重新启动：

```powershell
cd D:\agent_workspace\projects\chat_soft\server\codex-mirror
node dist/server/codex-mirror/src/index.js
```

### 3.4 本机验证

建议统一使用：

```powershell
curl.exe --noproxy "*" http://127.0.0.1:3090/health
curl.exe --noproxy "*" http://127.0.0.1:3090/api/codex-mirror/status
curl.exe --noproxy "*" http://127.0.0.1:3090/api/codex-mirror/models
curl.exe --noproxy "*" http://127.0.0.1:3090/api/codex-mirror/sessions
```

说明：

- 当前机器上 `Invoke-RestMethod` 可能因为代理链路异常返回 `502`
- 本地联调优先用 `curl.exe --noproxy "*"`

### 3.5 发送测试消息

先创建会话：

```powershell
curl.exe --noproxy "*" -X POST "http://127.0.0.1:3090/api/codex-mirror/sessions" -H "Content-Type: application/json" --data-binary "{\"modelId\":\"gpt-5.4\"}"
```

再向某个会话发消息：

```powershell
curl.exe --noproxy "*" -X POST "http://127.0.0.1:3090/api/codex-mirror/sessions/<SESSION_ID>/messages" -H "Content-Type: application/json" --data-binary "{\"text\":\"请只回复四个汉字\",\"waitForConfirmation\":true}"
```

查看消息：

```powershell
curl.exe --noproxy "*" "http://127.0.0.1:3090/api/codex-mirror/sessions/<SESSION_ID>/messages"
```

### 3.6 调试页启动

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm dev:codex-mirror-debug
```

构建：

```powershell
pnpm --filter @chat-soft/codex-mirror-debug build
```

---

## 4. VS Code Codex Bridge

目录：

- `D:\agent_workspace\projects\chat_soft\tools\codex-vscode-bridge`

### 4.1 更新

```powershell
cd D:\agent_workspace\projects\chat_soft\tools\codex-vscode-bridge
npm install
npm run build
```

### 4.2 启动方式

这个模块不是独立 exe，而是 VS Code 扩展。

使用方式：

1. 在 VS Code 打开该目录
2. 确保扩展已安装/加载
3. 执行 `Developer: Reload Window`

### 4.3 常用命令

在 VS Code 命令面板中可用：

- `Chat Soft Codex: Start Bridge`
- `Chat Soft Codex: Stop Bridge`
- `Chat Soft Codex: Show Available Models`
- `Chat Soft Codex: Reset Conversation History`
- `Chat Soft Codex: Bind Current Thread`

### 4.4 验证

验证思路：

- VS Code 里能看到扩展已启用
- 输出面板里能看到 `Chat Soft Codex Bridge`
- 手机端/服务端能看到 `Codex Agent`
- 发送消息后 bridge 有日志

### 4.5 日志

看 VS Code 输出面板：

- `View`
- `Output`
- 右上角通道选择 `Chat Soft Codex Bridge`

---

## 5. 桌面端

### 5.1 更新与构建

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm install
pnpm --filter @chat-soft/desktop build
```

### 5.2 开发启动

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm dev:desktop
```

### 5.3 本地 agent 启动

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm --filter @chat-soft/desktop agent:start
```

说明：

- 这个命令会启动本地 agent 网关
- 默认连本机 `http://127.0.0.1:3000`
- 如果要连云服务器，启动前先设置环境变量 `CHAT_SOFT_SERVER_BASE_URL`
- 启动后会自动向服务器注册至少两个 agent：
  - `llm-chat`
  - `opencode`
- `opencode` agent 会调用本机安装好的 `opencodecli` 或 `opencode` CLI
- 手机端拉取到最新会话列表后，可以像和普通好友聊天一样直接给 `代码开发助手` 发送文本消息
- `opencode` agent 现已支持在聊天中直接用指令管理 session 和模型

如果本机没有把 CLI 加进环境变量，`opencode` agent 会在会话里回复启动失败原因。

连接云服务器示例：

```powershell
$env:CHAT_SOFT_SERVER_BASE_URL = "http://39.106.125.149:3000"
cd D:\agent_workspace\projects\chat_soft
pnpm --filter @chat-soft/desktop agent:start
```

如果要让 `opencode` 以自动批准模式执行本地读写和命令操作，可以再加：

```powershell
$env:CHAT_SOFT_SERVER_BASE_URL = "http://39.106.125.149:3000"
$env:CHAT_SOFT_OPENCODE_AUTO_APPROVE = "true"
cd D:\agent_workspace\projects\chat_soft
pnpm --filter @chat-soft/desktop agent:start
```

说明：

- 这会给 `opencode run` 自动附加 `--dangerously-skip-permissions`
- 适合你希望手机端体验尽量接近本地终端直连时使用
- 风险也更高，手机里发出的文件操作、命令执行、目录创建会直接落地到本机

如果你不想每次手动设置环境变量，可以直接双击运行：

```text
D:\agent_workspace\projects\chat_soft\start_opencode_agent.cmd
```

`opencode` 会话内可用指令：

```text
/help
/providers
/models
/model provider/model
/session
/session current
/session use <SESSION_ID>
/session reset
```

说明：

- `/providers` 查看当前本机已配置的 provider
- `/models` 查看可用模型
- `/model provider/model` 切换后续消息使用的模型
- `/session` 查看可切换的历史 session
- `/session use <SESSION_ID>` 绑定到指定 session，继续那条会话
- `/session reset` 清空当前绑定，下一条普通消息会新建 session

### 5.4 验证

重点看：

- 桌面窗口是否正常打开
- 是否能拉到会话列表
- 是否能正常发送文本消息
- agent 是否在线
- 手机上的会话列表里是否出现 `代码开发助手`
- 给 `代码开发助手` 发一条文本后是否收到 CLI 返回结果

---

## 6. 移动端

### 6.1 前端更新

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm install
pnpm --filter @chat-soft/mobile build
pnpm --filter @chat-soft/mobile cap:sync
```

### 6.2 开发预览

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm dev:mobile
```

### 6.3 Android 构建同步

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm --filter @chat-soft/mobile cap:sync
```

如果要从 Android Studio 构建：

- 打开 `apps/mobile/android`
- 重新同步 Gradle
- 构建并安装

### 6.4 USB 安装常用命令

确认设备：

```powershell
adb devices
```

安装 APK：

```powershell
adb install -r <APK_PATH>
```

彻底重装：

```powershell
adb uninstall <包名>
adb install <APK_PATH>
```

### 6.5 移动端验证

重点看：

- 应用是否能正常打开
- 是否能拉到会话列表
- 文本发送接收是否正常
- agent 会话是否可见
- 媒体消息是否能显示正确类型

### 6.6 网页端公网部署记录（2026-04-24）

当前已把 `@chat-soft/mobile` 作为网页端部署到阿里云服务器，可用手机浏览器访问：

```text
http://39.106.125.149/
```

当前实际运行方式：

- 前端构建产物目录：`/www/wwwroot/chat-soft`
- 静态网页进程管理：`PM2`
- 静态网页服务名：`chat-soft-web`
- 静态网页端口：`80`
- 后端 API 地址：`http://39.106.125.149:3000`
- 后端服务名：`chat-soft-server`

本次更新内容：

- 给网页端增加前端访问门禁：
  - 用户名：`chisado`
  - 密码：`chisado233`
  - 登录状态保存在浏览器 `localStorage`。
  - 这是轻量前端门禁，不等同于后端鉴权；如需更强安全，应改为后端鉴权或 Nginx/BT Basic Auth。
- 修复单会话/默认会话场景下输入发送不可用：
  - 新增有效会话兜底逻辑，会优先使用当前会话，其次使用第一个会话，最后兜底到 `primary`。
- 修复手机网页会话页底部输入栏不可见：
  - 聊天页使用 `100dvh` 高度并禁止整页溢出。
  - 消息列表区域单独滚动。
  - 底部 composer 固定参与布局并提高层级，避免被消息列表挤出屏幕。

本地构建命令：

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm --filter @chat-soft/mobile build
```

当前手动同步部署流程：

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm --filter @chat-soft/mobile build

# 上传 apps/mobile/dist 到服务器临时目录 /tmp/chat-soft-dist-upload
# 然后在服务器执行：
```

```bash
set -e
ts=$(date +%Y%m%d%H%M%S)
mkdir -p /www/wwwroot/chat-soft
if [ -n "$(ls -A /www/wwwroot/chat-soft 2>/dev/null)" ]; then
  tar -C /www/wwwroot -czf /www/wwwroot/chat-soft.backup.$ts.tar.gz chat-soft
fi
rm -rf /www/wwwroot/chat-soft/*
cp -a /tmp/chat-soft-dist-upload/. /www/wwwroot/chat-soft/
/usr/local/bin/pm2 restart chat-soft-web --update-env
```

验证命令：

```powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://39.106.125.149/" -TimeoutSec 10
Invoke-WebRequest -UseBasicParsing -Uri "http://39.106.125.149:3000/health" -TimeoutSec 10
```

预期：

- 网页返回 `200`。
- 后端健康检查返回 `{"ok":true}`。
- 手机打开网页后先显示登录页，登录后进入会话列表。
- 进入会话后底部能看到 `+ / 输入消息 发送` 输入栏。

---

## 7. 一键常用流程

### 7.1 服务器更新 + 重启 + 验证

```bash
cd /opt/chat_soft
git pull
/usr/local/bin/pnpm install
/usr/local/bin/pnpm --filter @chat-soft/server build
systemctl restart chat-soft
systemctl status chat-soft --no-pager
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/api/agents
curl http://127.0.0.1:3000/api/conversations
```

### 7.2 本机 Codex 镜像更新 + 重启 + 验证

```powershell
cd D:\agent_workspace\projects\chat_soft
pnpm install
pnpm --filter @chat-soft/codex-mirror-server build
Get-NetTCPConnection -LocalPort 3090 -State Listen | Select-Object -ExpandProperty OwningProcess
Stop-Process -Id <PID> -Force
cd D:\agent_workspace\projects\chat_soft\server\codex-mirror
node dist/server/codex-mirror/src/index.js
```

新开一个终端验证：

```powershell
curl.exe --noproxy "*" http://127.0.0.1:3090/health
curl.exe --noproxy "*" http://127.0.0.1:3090/api/codex-mirror/status
curl.exe --noproxy "*" http://127.0.0.1:3090/api/codex-mirror/sessions
```

### 7.3 VS Code Bridge 更新 + 重新加载

```powershell
cd D:\agent_workspace\projects\chat_soft\tools\codex-vscode-bridge
npm install
npm run build
```

然后在 VS Code 执行：

- `Developer: Reload Window`

---

## 8. 任务进度怎么看

### 8.1 看本地代码状态

```powershell
git -C D:\agent_workspace\projects\chat_soft status --short
git -C D:\agent_workspace\projects\chat_soft log --oneline -n 10
```

### 8.2 看某个模块是否已经构建

主服务：

```powershell
Test-Path D:\agent_workspace\projects\chat_soft\server\api\dist\index.js
```

Codex 镜像：

```powershell
Test-Path D:\agent_workspace\projects\chat_soft\server\codex-mirror\dist\server\codex-mirror\src\index.js
```

桥接扩展：

```powershell
Test-Path D:\agent_workspace\projects\chat_soft\tools\codex-vscode-bridge\dist\extension.js
```

### 8.3 看服务是否在线

服务器主服务：

```bash
systemctl status chat-soft --no-pager
```

本机 Codex 镜像：

```powershell
Get-NetTCPConnection -LocalPort 3090 -State Listen
```

### 8.4 看当前文档与方案进度

重点文档：

- [operations_runbook.md](D:/agent_workspace/projects/chat_soft/docs/operations_runbook.md)
- [codex_mirror_requirements_and_architecture.md](D:/agent_workspace/projects/chat_soft/docs/codex_mirror_requirements_and_architecture.md)
- [codex_mirror_technical_validation.md](D:/agent_workspace/projects/chat_soft/docs/codex_mirror_technical_validation.md)

---

## 9. 常见排错顺序

如果你不知道先查哪里，就按这个顺序：

1. 先确认进程/端口是否真的起来了
2. 再打 `/health`
3. 再看日志
4. 再看是不是旧构建产物/旧入口
5. 再看是不是代理问题

本机联调常见坑：

- PowerShell 自带请求工具走错代理
- 杀掉的是旧进程，但新进程没真正拉起
- 启动命令仍然指向旧的构建入口

服务器常见坑：

- `pnpm` 路径不对
- 重启后立刻 `curl`，服务还没完全起来
- `git pull` 拉到的是新代码，但没重新 build

---

## 10. 当前建议

日常最稳的工作习惯：

- 服务器用绝对路径 `/usr/local/bin/pnpm`
- 本机接口验证统一用 `curl.exe --noproxy "*"`
- Codex 镜像启动统一用：

```powershell
node D:\agent_workspace\projects\chat_soft\server\codex-mirror\dist\server\codex-mirror\src\index.js
```

- 每次改完 bridge 记得：
  - `npm run build`
  - VS Code `Reload Window`
