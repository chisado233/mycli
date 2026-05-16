# Remote PC Bridge Control

轻量版远程电脑桥接控制项目。

目标：A/B 两台 Windows 电脑都不在公网，通过腾讯云服务器建立 WireGuard 私有网络；接入后把远端电脑的盘映射成本机盘符，然后直接用本地 PowerShell 操作远端文件。

核心使用体验：

```powershell
.\scripts\remote-connect.ps1 B

Copy-Item X:\abc.txt C:\abc.txt
Set-Content X:\note.txt "hello"
Remove-Item X:\old.txt
```

## 当前产物

```text
requirements-discussion.md     需求讨论与决策
technical-design.md            轻量版技术设计
server/                        服务器部署脚本
wireguard/                     WireGuard 配置模板
config/                        A/B 设备与盘符映射配置模板
scripts/                       Windows 本地脚本
docs/                          部署说明
```

## 快速流程

1. 服务器部署 WireGuard：见 `docs/setup-server.md`。
2. A/B Windows 安装 WireGuard：见 `docs/setup-windows-client.md`。
3. 复制配置模板：

```powershell
Copy-Item .\config\devices.example.json .\config\devices.local.json
Copy-Item .\config\drive-maps.example.json .\config\drive-maps.local.json
```

4. 在 A/B 各自电脑上设置 `devices.local.json` 里的 `localDevice`。
5. 测试状态：

```powershell
.\scripts\remote-status.ps1 B
```

6. 映射盘符：

```powershell
.\scripts\remote-connect.ps1 B
```

7. 像本地盘一样使用：

```powershell
Get-ChildItem X:\
Copy-Item X:\abc.txt C:\abc.txt
Set-Content X:\note.txt "hello"
```

## 注意

- 不要把真实私钥、密码写入仓库。
- SMB 445 不要暴露到公网。
- 远程命令端口不要暴露到公网。
- 第一版是轻量版，服务器不做中心审计和权限拦截。
