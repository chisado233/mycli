# Chat Soft Server 部署说明

更新时间：2026-04-19

本文档说明服务器上 `Chat Soft` 主服务的实际部署方式。

当前推荐方案：

- 代码目录：`/opt/chat_soft`
- 服务目录：`/opt/chat_soft/server/api`
- 进程管理：`PM2`
- 包管理：`pnpm`
- 默认端口：`3000`

## 1. 环境要求

服务器需要安装：

- Node.js 20+
- npm

安装 `pnpm`：

```bash
npm install -g pnpm@10.18.0
```

安装 `PM2`：

```bash
npm install -g pm2
```

如果命令不在 `PATH` 中，直接使用：

```bash
/usr/local/bin/pnpm
/usr/local/bin/pm2
```

## 2. 上传项目

把整个 `chat_soft` 目录上传到服务器，例如：

```bash
scp -r chat_soft root@YOUR_SERVER_IP:/opt/chat_soft
```

## 3. 安装依赖与构建

```bash
cd /opt/chat_soft
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
```

## 4. 启动服务

```bash
cd /opt/chat_soft
HOST=0.0.0.0 PORT=3000 /usr/local/bin/pm2 start /opt/chat_soft/server/api/dist/index.js --name chat-soft-server
/usr/local/bin/pm2 save
```

## 5. 检查状态

```bash
/usr/local/bin/pm2 list
curl http://127.0.0.1:3000/health
```

预期返回：

```json
{"ok":true}
```

注意：

- 根路径 `/` 没有定义路由
- 访问 `http://SERVER_IP:3000/` 返回 `404` 是正常的
- 请用 `/health` 验证服务是否可用

## 6. 更新服务

```bash
cd /opt/chat_soft
git pull
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
/usr/local/bin/pm2 restart chat-soft-server
```

## 7. 查看日志

```bash
/usr/local/bin/pm2 logs chat-soft-server
```

## 8. 需要开放的端口

- `3000`

## 9. 第一版连接方式

- HTTP API：`http://SERVER_IP:3000`
- 健康检查：`http://SERVER_IP:3000/health`
- WebSocket：`ws://SERVER_IP:3000/ws`
