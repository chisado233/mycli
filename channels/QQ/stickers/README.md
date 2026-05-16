# QQ 表情包库

这个目录放 QQ channel 可发送的本地表情包文件。

推荐格式：

- `.png`
- `.jpg` / `.jpeg`
- `.gif`
- `.webp`

命名建议：

- 用短英文/拼音/数字命名，便于命令调用，例如：`nanguo.png`、`666.gif`、`jile.jpg`。
- 一个表情一个文件，不要在文件名里放太复杂的符号。

发送示例：

```powershell
node D:\agent_workspace\capability-library\skill-library\qq-napcat-channel\scripts\qq-send.js sticker --default-group --name nanguo
node D:\agent_workspace\capability-library\skill-library\qq-napcat-channel\scripts\qq-send.js sticker --default-group --file D:\agent_workspace\channel\QQ\stickers\nanguo.png
```
