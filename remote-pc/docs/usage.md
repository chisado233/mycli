# 使用说明

## 1. 日常文件操作

先连接目标电脑：

```powershell
.\scripts\remote-connect.ps1 B
```

然后直接操作映射盘：

```powershell
Get-ChildItem X:\
Copy-Item X:\abc.txt C:\abc.txt
Copy-Item C:\abc.txt X:\abc.txt
Set-Content X:\note.txt "hello"
Get-Content X:\note.txt
Remove-Item X:\old.txt
```

这就是主要使用方式。

## 2. 查看连接状态

```powershell
.\scripts\remote-status.ps1 B
```

会检查：

- WireGuard IP 是否可 ping。
- SMB 445 是否可连接。
- SSH 22 是否可连接。
- 预期盘符是否存在、是否可读。

## 3. 修复连接

```powershell
.\scripts\remote-repair.ps1 B
```

会删除旧映射并重新映射。

## 4. 断开映射

```powershell
.\scripts\remote-disconnect.ps1 B
```

只删除网络盘映射，不关闭 WireGuard。

## 5. 远程执行命令

需要先在目标 Windows 配置 OpenSSH Server 或 PowerShell SSH Remoting。

```powershell
.\scripts\remote-run.ps1 B "hostname"
.\scripts\remote-run.ps1 B "Get-Process | Select-Object -First 5"
.\scripts\remote-run.ps1 B "cd D:\Projects\repo; git status"
```

普通文件操作不要用 `remote-run`，直接用映射盘。

## 6. 常见问题

### X: 不存在

先执行：

```powershell
.\scripts\remote-status.ps1 B
.\scripts\remote-connect.ps1 B -Force
```

### SMB 445 不通

检查：

- WireGuard 是否连接。
- 目标电脑 Windows 防火墙是否允许 WireGuard 网段访问文件共享。
- 目标电脑是否开启文件和打印机共享。

### 管理共享 C$ / D$ 无法访问

检查：

- 使用的账户是否是管理员。
- 目标电脑是否启用管理共享。
- 本地账户远程 UAC 限制是否影响管理共享。
