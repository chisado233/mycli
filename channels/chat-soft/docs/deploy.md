# 部署运维

## 部署步骤

### 云服务器（49.232.183.40）
```bash
# 上传源码
pscp -P 22 -hostkey <HOSTKEY> server/api/src/index.ts root@49.232.183.40:/opt/chat_soft/server/api/src/index.ts

# 重启
pm2 restart chat-soft-server
```

### 本机 Bridge
```powershell
# 构建
pnpm --filter @chat-soft/desktop build

# 启动
mycli channels chat-soft start-detached

# 停止
mycli channels chat-soft stop-detached

# 查看状态
mycli channels chat-soft status-detached
```

### 手机 APK
```powershell
# 构建
pnpm --filter @chat-soft/mobile build
npx cap sync android
.\gradlew.bat assembleDebug

# 安装
adb install -r app/build-alt/outputs/apk/debug/chat-soft-mobile-debug.apk
```

## 启动/停止

```powershell
# 启动 bridge（含自动拉起 opencode serve）
D:\agent_workspace\capability-library\mycli\mycli.ps1 channels chat-soft start-detached

# 停止 bridge
D:\agent_workspace\capability-library\mycli\mycli.ps1 channels chat-soft stop-detached

# 云服务器重启
plink -ssh root@49.232.183.40 "pm2 restart chat-soft-server"
```

## 日志位置
| 日志类型 | 路径 |
|---------|------|
| Bridge stdout | `channels/chat-soft/logs/local-agent.detached.out.log` |
| Bridge stderr | `channels/chat-soft/logs/local-agent.detached.err.log` |
| 云服务器 | `49.232.183.40:/root/.pm2/logs/chat-soft-server-*.log` |

## 开机自启
已注册 Windows Task Scheduler，登录时自动执行 `mycli channels chat-soft start-detached`。
管理命令：`mycli startup commands`

## 备份策略
- 源码备份：`D:\agent_workspace\backups\chat-soft\`（按日期目录）
- 云服务器 DB：`/opt/chat_soft/data/db.json`

## 常见问题

### 开机后 bridge 不工作
检查 stale serve 进程：`netstat -ano | findstr 4096`。Bridge 的 `connectSSE()` 会自动 kill 旧 serve 并重启。

### 手机发消息没回复
1. 检查 bridge 日志：`Get-Content channels/chat-soft/logs/local-agent.detached.err.log -Tail 20`
2. 确认 opencode serve 是否运行：`netstat -ano | findstr 4096`
3. 检查云服务器 DB 是否损坏：SSH 后检查 `/opt/chat_soft/data/db.json`
4. 如果 DB 损坏，用 `node -e "require('fs').writeFileSync(...)"` 重置

### Session 卡住
发 `/abort` 中断当前 turn，如果不行则 `/session new` 创建新 session。

### 模型切换不生效
opencode serve 不响应 `agentId`/`modelId`，需改 `D:\agent_workspace\agent\opencode\opencode.json`。