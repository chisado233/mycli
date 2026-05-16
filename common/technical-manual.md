# mycli 维护与技术手册

## 1. 文档目的

这份文档面向后续维护 `mycli` 的技术人员。

目标是帮助后续继续做这些事情：

- 新增能力包
- 调整命令注册结构
- 修改帮助展示逻辑
- 接入已有外部 CLI
- 排查运行时问题

---

## 2. 当前目录结构

当前根目录：

```text
D:\agent_workspace\capability-library\mycli
```

关键文件：

- `mycli.ps1`
  PowerShell 主入口包装器
- `mycli.cmd`
  Windows 命令行包装器
- `common\cli.ps1`
  核心运行时实现
- `common\requirements.md`
  需求与设计收敛文档
- `common\user-manual.md`
  面向用户的使用手册
- `common\technical-manual.md`
  本文档

包目录示例：

```text
mycli\
  opencode\
    cli.package.json
    README.md
```

---

## 3. 核心设计模型

`mycli` 的核心对象有 4 类：

- `package`
  能力包
- `subpackage`
  子包，目录即层级
- `command`
  包内可执行命令
- `help`
  包级文档，来自 `README.md`

核心设计原则：

- 包树使用目录结构表示
- 每个包目录使用 `cli.package.json` 作为注册中心
- 每个包目录使用 `README.md` 作为 `--help` 数据源
- `entry` 统一使用绝对路径
- 命令参数采用结构化 `args`
- 外部 CLI 可以通过“直接转发”或“前缀转发”接入

---

## 4. 运行时职责分层

### `mycli.ps1`

负责把用户输入传给核心脚本：

- 作为 PowerShell 入口
- 调用 `common\cli.ps1`

### `mycli.cmd`

负责兼容 `cmd` 场景：

- 作为批处理入口
- 再转到 PowerShell 入口

### `common\cli.ps1`

这是整个系统的核心。

主要职责：

- 参数解析
- 路径与包定位
- 包配置读取与写入
- 命令注册与更新
- README 帮助读取与写入
- 已注册命令的实际执行

---

## 5. 包结构约定

任意包目录都应当至少包含：

- `cli.package.json`
- `README.md`

示例：

```text
D:\agent_workspace\capability-library\mycli\opencode\
  cli.package.json
  README.md
```

嵌套包示例：

```text
D:\agent_workspace\capability-library\mycli\dev\
  cli.package.json
  README.md
  opencli\
    cli.package.json
    README.md
```

---

## 6. `cli.package.json` 结构

当前最核心字段：

```json
{
  "name": "opencode",
  "summary": "Forwarding package for the existing opencode CLI",
  "source": "D:\\agent_workspace\\projects\\opencode",
  "commands": [
    {
      "name": "run",
      "summary": "Run opencode with a message",
      "args": [
        {
          "name": "message",
          "required": false,
          "summary": "Message to send to opencode",
          "type": "string"
        }
      ],
      "prefixArgs": [
        "run"
      ],
      "entry": "C:\\Users\\38188\\AppData\\Roaming\\npm\\opencode.ps1"
    }
  ]
}
```

字段说明：

- `name`
  包名，通常等于目录名
- `summary`
  顶层 `list` 或子包展示时的一句话简介
- `source`
  来源描述，推荐绝对路径，也允许自定义文本
- `commands`
  命令注册数组

命令对象字段：

- `name`
  命令名
- `summary`
  命令简介
- `args`
  结构化参数说明
- `entry`
  绝对路径入口
- `prefixArgs`
  可选。固定插入到实际执行前面的参数数组

---

## 7. `prefixArgs` 的作用

这是当前支持“原生 CLI 包装”的关键机制。

### 直接透传

例如：

```json
{
  "name": "native",
  "summary": "Forward all remaining arguments to opencode",
  "args": [],
  "entry": "C:\\Users\\38188\\AppData\\Roaming\\npm\\opencode.ps1"
}
```

此时：

```powershell
mycli opencode native run hello
```

会执行：

```powershell
opencode run hello
```

### 前缀转发

例如：

```json
{
  "name": "run",
  "summary": "Run opencode with a message",
  "args": [],
  "prefixArgs": ["run"],
  "entry": "C:\\Users\\38188\\AppData\\Roaming\\npm\\opencode.ps1"
}
```

此时：

```powershell
mycli opencode run hello
```

会执行：

```powershell
opencode run hello
```

所以：

- `native` 适合原样透传
- `prefixArgs` 适合把原生子命令重定义成 `mycli` 的直接命令

---

## 8. 当前命令行为

### 顶层

- `mycli --help`
- `mycli list`
- `mycli package list`
- `mycli package register`
- `mycli package register-full`

### 包级

- `mycli <package> --help`
- `mycli <package> list`
- `mycli <package> command list`
- `mycli <package> command register`
- `mycli <package> command register-many`
- `mycli <package> command update`
- `mycli <package> help update`
- `mycli <package> <command> [args...]`

### 包树

包树使用空格层级解析，例如：

```powershell
mycli dev opencli list
mycli dev opencli command list
```

注册包时使用路径式：

```powershell
mycli package register dev/opencli --summary "..." --source "..."
```

---

## 9. 主要内部函数

下面这些函数是后续改动时最常碰到的核心点。

### 路径与包定位

- `Get-PackageSegmentsFromString`
- `Get-PackageDirectory`
- `Get-PackageConfigPath`
- `Get-PackageReadmePath`
- `Test-PackageExists`
- `Find-PackageMatch`

用途：

- 把用户输入映射到包目录
- 做包层级识别
- 读取配置与 README

### 注册数据标准化

- `Get-OptionalMemberValue`
- `ConvertTo-NormalizedCommand`
- `Get-JsonValue`

用途：

- 校验配置
- 统一命令对象结构
- 解析命令行里传入的 JSON

### 配置读写

- `New-PackageConfigObject`
- `Save-PackageConfig`
- `Get-PackageConfig`
- `Save-PackageConfigObject`

用途：

- 生成包模板
- 保存更新后的包配置

### 包注册

- `Ensure-PackageDirectory`
- `Ensure-AncestorPackages`
- `Register-Package`
- `Register-PackageFull`

用途：

- 自动创建包目录
- 自动补祖先包
- 生成默认 README

### 命令管理

- `Add-CommandToPackage`
- `Update-CommandInPackage`
- `Handle-CommandManagement`

用途：

- 单命令注册
- 批量命令注册
- 命令更新

### 帮助管理

- `New-DefaultReadme`
- `Handle-HelpManagement`
- `Show-PackageHelp`

用途：

- 初始化 README
- 更新 README
- 输出 `--help`

### 执行链路

- `Invoke-RegisteredCommand`
- `Invoke-Cli`

用途：

- 真正执行注册命令
- 顶层路由分发

---

## 10. README 与 `--help` 的关系

当前规则很简单：

- `mycli <package> --help`
- `mycli <package>`

都会读取该包目录下的 `README.md`。

所以如果你想修改包级帮助，不需要改运行时逻辑，直接：

- 用命令更新 README
- 或直接编辑对应包的 `README.md`

这也是为什么包说明尽量写在 Markdown，而不是 JSON 里。

---

## 11. 新增一个包的推荐流程

### 分步方式

1. 注册包

```powershell
mycli package register demo/tools --summary "Demo tools" --source "D:\demo"
```

2. 注册命令

```powershell
mycli demo tools command register hello --summary "Say hello" --entry "D:\demo\hello.ps1" --args "[]"
```

3. 更新 README

```powershell
mycli demo tools help update --content "# demo tools`n`n## Summary`nDemo tools"
```

### 一次性方式

```powershell
mycli package register-full demo/tools --summary "Demo tools" --source "D:\demo" --commands "[{""name"":""hello"",""summary"":""Say hello"",""args"":[],""entry"":""D:\\demo\\hello.ps1""}]" --help "# demo tools`n`n## Summary`nDemo tools"
```

---

## 12. 接入现有外部 CLI 的推荐方式

如果已有一个原生 CLI，比如 `opencode`，推荐同时提供两层接法。

### 第一层：native 原生透传

保留一个：

- `native`

示例：

```json
{
  "name": "native",
  "summary": "Forward all remaining arguments to opencode",
  "args": [],
  "entry": "C:\\Users\\38188\\AppData\\Roaming\\npm\\opencode.ps1"
}
```

这样可以保证永远有一条“完整原生能力”的后门。

### 第二层：常用命令重定义

把常用子命令注册成 `mycli` 直达命令，例如：

- `run`
- `models`
- `agent`
- `session`

通过 `prefixArgs` 做映射。

这套模式适合后续继续接：

- 现有 CLI 工具
- Python 脚本入口
- Node CLI
- PowerShell 工具链

---

## 13. 当前已知设计边界

当前版本有这些边界，后续改动时要心里有数：

- 包级帮助来自 `README.md`，不是结构化帮助系统
- 目前没有正式的 `command remove`
- 目前不支持 `package remove`
- 目前未单独实现 `mycli <package> <command> --help`
- 参数校验以“展示和注册约束”为主，不是完整执行期参数解析器
- `entry` 必须是绝对路径

这些不是 bug，而是第一版有意保持简单的边界。

---

## 14. 调整时的推荐优先级

后续如果继续扩展，建议优先顺序是：

1. 文档先更新
2. 再改 `common\cli.ps1`
3. 再补测试用例
4. 最后批量调整已有包

这样能减少“运行时变了，但包文档和注册结构还没跟上”的情况。

---

## 15. 回归验证建议

每次改完运行时，至少回归这些命令：

```powershell
mycli --help
mycli list
mycli package list
mycli opencode --help
mycli opencode list
mycli opencode run --help
mycli opencode native run --help
```

如果动了注册逻辑，再补：

```powershell
mycli package register qa/demo --summary "QA Demo" --source "D:\qa"
mycli qa demo command register hello --summary "Hello" --entry "D:\qa\hello.ps1" --args "[]"
mycli qa demo help update --content "# qa demo"
mycli qa demo list
```

测试结束后再清理临时包。

