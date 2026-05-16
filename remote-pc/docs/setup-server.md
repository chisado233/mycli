# 服务器 WireGuard Hub 部署说明

目标服务器：腾讯云 CVM，公网 IP `49.232.183.40`。

第一版服务器只做 WireGuard Hub，不做控制中心。

## 1. 上传/创建安装脚本

把项目中的脚本放到服务器：

```text
server/install-wireguard-openanolis.sh
```

也可以直接在服务器上创建同名文件。

## 2. 执行安装

在服务器 root 下执行：

```bash
chmod +x install-wireguard-openanolis.sh
./install-wireguard-openanolis.sh
```

脚本会：

- 安装 WireGuard 工具。
- 启用 IPv4 forwarding。
- 创建 `/etc/wireguard`。
- 生成服务器 WireGuard keypair。
- 创建初始 `/etc/wireguard/wg0.conf`，但不会覆盖已有配置。

## 3. 腾讯云安全组

需要在腾讯云安全组开放：

```text
UDP 51820
```

不要向公网开放：

```text
TCP 445  SMB
TCP 5985 WinRM HTTP
TCP 5986 WinRM HTTPS
```

## 4. 加入 A/B peer

A/B Windows 客户端生成 WireGuard 公钥后，在服务器 `/etc/wireguard/wg0.conf` 中加入：

```ini
[Peer]
PublicKey = <A_PUBLIC_KEY>
AllowedIPs = 10.66.0.2/32
PersistentKeepalive = 25

[Peer]
PublicKey = <B_PUBLIC_KEY>
AllowedIPs = 10.66.0.3/32
PersistentKeepalive = 25
```

## 5. 启动服务

```bash
systemctl enable --now wg-quick@wg0
systemctl status wg-quick@wg0 --no-pager
wg show
```

## 6. 修改配置后重启

```bash
systemctl restart wg-quick@wg0
wg show
```

## 7. 验证

当 A/B 客户端连接后，在服务器执行：

```bash
ping -c 3 10.66.0.2
ping -c 3 10.66.0.3
wg show
```

`wg show` 中应能看到 peer handshake。
