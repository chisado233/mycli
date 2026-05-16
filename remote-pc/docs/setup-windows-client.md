# Windows 客户端部署说明

适用于 A/B 两台 Windows 电脑。

## 1. 安装 WireGuard

安装 WireGuard for Windows：

```text
https://www.wireguard.com/install/
```

## 2. 生成客户端密钥

可以在 WireGuard GUI 中新建空隧道生成密钥，也可以使用 `wg.exe`。

A 使用：

```text
wireguard/client-a.example.conf
```

B 使用：

```text
wireguard/client-b.example.conf
```

替换：

```text
<A_PRIVATE_KEY>
<B_PRIVATE_KEY>
<SERVER_PUBLIC_KEY>
```

然后把 A/B 公钥加入服务器 `/etc/wireguard/wg0.conf`。

## 3. 启动 WireGuard

在 A/B 上分别启用对应隧道。

验证：

```powershell
ping 10.66.0.1
ping 10.66.0.2
ping 10.66.0.3
```

## 4. 创建专用管理员账户

建议在 A/B 都创建：

```text
remote_admin
```

并加入 Administrators 组。

不要把密码写入项目文件。

## 5. 开启文件共享和 SMB 防火墙

确保 Windows 已开启文件和打印机共享。

SMB 只应允许 WireGuard 网段 `10.66.0.0/24` 访问。

可先用系统防火墙 UI 配置。后续脚本可再自动化。

## 6. 测试管理共享

在 A 上测试访问 B：

```powershell
Test-NetConnection 10.66.0.3 -Port 445
net use X: \\10.66.0.3\D$ /user:remote_admin * /persistent:yes
Get-ChildItem X:\
```

在 B 上测试访问 A：

```powershell
Test-NetConnection 10.66.0.2 -Port 445
net use V: \\10.66.0.2\D$ /user:remote_admin * /persistent:yes
Get-ChildItem V:\
```

## 7. 配置项目本地文件

在每台电脑的项目目录中：

```powershell
Copy-Item .\config\devices.example.json .\config\devices.local.json
Copy-Item .\config\drive-maps.example.json .\config\drive-maps.local.json
```

然后修改 `localDevice`：

```json
"localDevice": "A"
```

或：

```json
"localDevice": "B"
```

## 8. 使用脚本

```powershell
.\scripts\remote-status.ps1 B
.\scripts\remote-connect.ps1 B
Copy-Item X:\abc.txt C:\abc.txt
Set-Content X:\note.txt "hello"
.\scripts\remote-disconnect.ps1 B
```
