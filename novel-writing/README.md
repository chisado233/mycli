# novel-writing

小说写作 skill 的 `mycli` 工作入口，用于快速定位主 skill 文件、查看讨论稿，并进入拆书 / 素材 / 写作等子模块。

## Source

```text
D:\agent_workspace\capability-library\skill-library\novel-writing
```

## Usage

```powershell
mycli novel-writing open
mycli novel-writing skill
mycli novel-writing discussion
mycli novel-writing show
mycli novel-writing deconstruction --help
mycli novel-writing deconstruction open
mycli novel-writing deconstruction show
mycli novel-writing deconstruction init "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\天命反派，开局拿下女帝师尊"
```

## Commands

### `open`

打印小说写作 skill 的工作目录、`SKILL.md` 和 `DISCUSSION.md` 路径。

```powershell
mycli novel-writing open
```

### `skill`

打印 `SKILL.md` 路径。

```powershell
mycli novel-writing skill
```

### `discussion`

打印 `DISCUSSION.md` 路径。

```powershell
mycli novel-writing discussion
```

### `show`

显示当前 `DISCUSSION.md` 内容，方便继续讨论与修改。

```powershell
mycli novel-writing show
```

## Deconstruction subpackage

拆书能力位于子包：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\deconstruction
```

常用命令：

```powershell
mycli novel-writing deconstruction open
mycli novel-writing deconstruction show
mycli novel-writing deconstruction init <book-dir> [--out <workspace-dir>] [--name <display-name>] [--copy-chapters] [--force]
```

`deconstruction init` 会创建完整拆书工作区，并生成第一批 request 示例。默认输出到：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\deconstruction\<书名>
```

默认不复制原文章节，只在工作区 `01-原文\章节\README.md` 中记录原章节目录；需要复制章节时加 `--copy-chapters`。

## Safety notes

- `open`、`skill`、`discussion`、`show` 是只读定位/查看命令。
- `deconstruction init` 会创建目录和文件；覆盖或补齐已有工作区时才使用 `--force`。
- 写作或拆书任务先读取 `SKILL.md` / `DISCUSSION.md` / 子模块 README，再修改内容。
