# asset-library

素材库命令包，用于管理和使用本地素材资源。当前主要能力是 meme / 表情包素材的列出、路径解析和发送。

## Meme / 表情包素材

素材目录：

```text
D:\agent_workspace\capability-library\mycli\asset-library\memes
```

支持扩展名：`.png`、`.jpg`、`.jpeg`、`.gif`、`.webp`。

## Usage

```powershell
mycli asset-library meme help
mycli asset-library meme dir
mycli asset-library meme list
mycli asset-library meme path <name>
mycli asset-library meme send --default-group --name <name> [--caption <text>]
mycli asset-library meme send --group <group-id> --name <name> [--caption <text>]
mycli asset-library meme send --user <user-id> --name <name> [--caption <text>]
mycli asset-library meme send --default-group --file <path-or-url> [--caption <text>]
```

## Command details

- `meme dir` — 打印 meme 素材目录。
- `meme list` — 列出素材文件名、大小和更新时间。
- `meme path <name>` — 解析素材完整路径；`<name>` 可带扩展名，也可省略扩展名。
- `meme send ... --name <name>` — 先从素材目录解析 `<name>`，再通过 QQ/NapCat 发送。
- `meme send ... --file <path-or-url>` — 直接发送本地文件或 URL，不经过素材名解析。

## Examples

```powershell
mycli asset-library meme dir
mycli asset-library meme list
mycli asset-library meme path 彩叶哭哭
mycli asset-library meme send --default-group --name 彩叶哭哭
mycli asset-library meme send --group 123456789 --name 彩叶哭哭 --caption "摸摸头"
```

## Safety notes

- `dir`、`list`、`path` 是只读操作。
- `send` 会向外部群或用户发送消息，属于外部通信动作；除非用户明确要求并给出目标，否则不要主动发送。
- 找不到素材时会报错 `Meme not found: <name>`，不会自动下载或创建素材。
