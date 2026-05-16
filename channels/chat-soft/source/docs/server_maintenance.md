# Chat Soft 服务器维护手册

更新时间：2026-04-19

本文档只覆盖服务器上的 `Chat Soft` 主服务维护。

适用范围：

- 服务器项目目录：`/opt/chat_soft`
- 服务目录：`/opt/chat_soft/server/api`
- 进程管理：`PM2`
- 服务名：`chat-soft-server`
- 默认端口：`3000`

## 1. 当前部署事实

当前服务器不是用 `systemd` 托管，也不是依赖 Docker 常驻运行。

当前实际运行方式：

- 使用 `PM2` 托管 Node 进程
- 实际启动文件：`/opt/chat_soft/server/api/dist/index.js`
- 对外监听：`0.0.0.0:3000`
- 健康检查：`/health`

注意：

- 访问 `http://SERVER_IP:3000/` 返回 `404` 是正常现象
- 根路径 `/` 没有定义路由
- 正确检查地址是 `http://SERVER_IP:3000/health`

## 2. 环境要求

服务器需要安装：

- Node.js 20+
- npm
- pnpm 10.18.0
- PM2

如果命令不在 `PATH` 中，统一使用绝对路径：

```bash
/usr/local/bin/pnpm
/usr/local/bin/pm2
```

## 3. 首次部署

### 3.1 安装工具

```bash
npm install -g pnpm@10.18.0
npm install -g pm2
```

### 3.2 安装依赖并构建

```bash
cd /opt/chat_soft
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
```

### 3.3 用 PM2 启动

```bash
cd /opt/chat_soft
HOST=0.0.0.0 PORT=3000 /usr/local/bin/pm2 start /opt/chat_soft/server/api/dist/index.js --name chat-soft-server
/usr/local/bin/pm2 save
```

### 3.4 启动后验证

```bash
curl http://127.0.0.1:3000/health
```

预期返回：

```json
{"ok":true}
```

## 4. 日常更新

代码更新后，在服务器执行：

```bash
cd /opt/chat_soft
git pull
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
/usr/local/bin/pm2 restart chat-soft-server
```

如果不是 `git pull`，而是直接覆盖项目目录，也照样执行后 3 条命令。

## 5. 常用运维命令

查看状态：

```bash
/usr/local/bin/pm2 list
```

查看日志：

```bash
/usr/local/bin/pm2 logs chat-soft-server
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

重新创建服务：

```bash
cd /opt/chat_soft
HOST=0.0.0.0 PORT=3000 /usr/local/bin/pm2 start /opt/chat_soft/server/api/dist/index.js --name chat-soft-server
/usr/local/bin/pm2 save
```

确认端口监听：

```bash
ss -ltnp | grep :3000
```

## 6. 服务验证

本机验证：

```bash
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/api/agents
curl http://127.0.0.1:3000/api/conversations
```

公网验证：

```bash
curl http://SERVER_IP:3000/health
```

正常结果：

- `/health` 返回 `{"ok":true}`
- `/api/agents` 返回 JSON
- `/api/conversations` 返回 JSON

## 7. 常见故障

### 7.1 访问 `/` 返回 404

这是正常现象。

原因：

- 服务没有定义首页路由 `/`
- 不能用首页判断服务是否启动

正确检查方式：

```bash
curl http://127.0.0.1:3000/health
```

### 7.2 `listen EADDRINUSE: address already in use 0.0.0.0:3000`

说明 `3000` 已经被已有进程占用，常见原因是 `PM2` 已经在托管服务。

先检查：

```bash
ss -ltnp | grep :3000
/usr/local/bin/pm2 list
```

如果服务本来就在运行，不要重复执行前台 `start` 命令。

正确做法：

```bash
/usr/local/bin/pm2 restart chat-soft-server
```

### 7.3 `pnpm: command not found`

改用绝对路径：

```bash
/usr/local/bin/pnpm
```

如果还没安装：

```bash
npm install -g pnpm@10.18.0
```

### 7.4 `pm2: command not found`

改用绝对路径：

```bash
/usr/local/bin/pm2
```

如果还没安装：

```bash
npm install -g pm2
```

### 7.5 本机可访问，公网不可访问

如果本机执行：

```bash
curl http://127.0.0.1:3000/health
```

返回正常，但公网打不开，通常是以下原因：

- 云服务器安全组未放行 `3000`
- 系统防火墙未放行 `3000`
- 反向代理未配置

先确认监听：

```bash
ss -ltnp | grep :3000
```

## 8. 推荐的最短维护流程

更新并重启：

```bash
cd /opt/chat_soft
git pull
/usr/local/bin/pnpm install --frozen-lockfile
/usr/local/bin/pnpm --filter @chat-soft/server build
/usr/local/bin/pm2 restart chat-soft-server
```

只查看运行状态：

```bash
/usr/local/bin/pm2 list
curl http://127.0.0.1:3000/health
```

只查看日志：

```bash
/usr/local/bin/pm2 logs chat-soft-server
```
