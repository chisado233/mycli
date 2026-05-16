# 排错手册

## 1. WireGuard 不通

在 A/B 上：

```powershell
ping 10.66.0.1
ping 10.66.0.2
ping 10.66.0.3
```

在服务器上：

```bash
wg show
systemctl status wg-quick@wg0 --no-pager
```

检查：

- 腾讯云安全组是否开放 UDP 51820。
- A/B 客户端是否使用正确服务器公钥。
- 服务器是否登记 A/B 公钥。
- AllowedIPs 是否为 `10.66.0.0/24`。

## 2. SMB 端口不通

```powershell
Test-NetConnection 10.66.0.3 -Port 445
```

如果失败：

- 目标电脑是否开启文件共享。
- Windows 防火墙是否允许 `10.66.0.0/24` 访问 SMB。
- 网络位置是否为专用网络。

## 3. net use 失败

查看现有连接：

```powershell
net use
```

删除旧连接：

```powershell
net use X: /delete /y
net use \\10.66.0.3\D$ /delete /y
```

重新连接：

```powershell
net use X: \\10.66.0.3\D$ /user:remote_admin * /persistent:yes
```

## 4. 盘符冲突

修改：

```text
config/drive-maps.local.json
```

把 `localLetter` 改成未占用盘符。

## 5. remote-run 失败

检查目标 SSH：

```powershell
Test-NetConnection 10.66.0.3 -Port 22
ssh remote_admin@10.66.0.3 hostname
```

如果 SSH 不通：

- 目标电脑是否安装 OpenSSH Server。
- sshd 服务是否运行。
- 防火墙是否允许 WireGuard 网段访问 TCP 22。
- `devices.local.json` 中 `sshUser` 和 `sshKeyPath` 是否正确。
