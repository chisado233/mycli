# novel-writing deconstruction

## Summary

小说拆解 / 拆书模块。用于讨论和后续实现文风、剧情走势、感情线、人物弧光、爽点钩子等分析能力。

## Source

`D:\agent_workspace\capability-library\skill-library\novel-writing\modules\deconstruction.md`

## Command List

- `open`
- `show`
- `init`

## Usage Examples

```powershell
mycli novel-writing deconstruction open
mycli novel-writing deconstruction show
mycli novel-writing deconstruction init "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\天命反派，开局拿下女帝师尊"
```

## init

创建完整拆书工作区，并生成第一批 `001-005` 的 request 示例。

默认输出到：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\deconstruction\<书名>
```

默认不复制原文章节，只在工作区 `01-原文\章节\README.md` 中记录原章节目录。需要复制章节时加 `--copy-chapters`。
