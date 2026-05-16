# 配置文件说明

复制模板后再填写真实配置：

```powershell
Copy-Item .\config\devices.example.json .\config\devices.local.json
Copy-Item .\config\drive-maps.example.json .\config\drive-maps.local.json
```

不要把真实私钥、密码写进这些 JSON。

## devices.local.json

包含：

- WireGuard 服务器信息。
- 本机设备名：`localDevice`。
- A/B 的 WireGuard IP。
- SMB 用户名。
- SSH 用户名和 key 路径。

每台电脑上应把 `localDevice` 设置成当前电脑：

```json
"localDevice": "A"
```

或：

```json
"localDevice": "B"
```

## drive-maps.local.json

包含双向盘符映射规则。

默认：

```text
A->B: B C/D/E 映射到 A X/Y/Z
B->A: A C/D/E 映射到 B U/V/W
```

如果本机盘符冲突，修改 `localLetter`。
