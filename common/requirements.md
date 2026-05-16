# mycli Capability Requirements

## 文档目的

这份文档用于沉淀 `D:\agent_workspace\capability-library\mycli` 的需求讨论，并收敛成第一版可实现规范。

目标不是做长期完美设计，而是先明确一套足够稳定、能直接开始实现的 mycli 包体系。

---

## 目标概述

把 `skill`、脚本、能力入口逐步封装成可发现、可说明、可执行的 mycli 包，通过统一入口 `mycli` 对外暴露。

第一版重点目标：

- 用 `mycli` 统一发现能力
- 用包和子包组织能力树
- 用 `cli.package.json` 保存注册信息
- 用 `README.md` 保存包级帮助文档
- 支持单命令注册、批量命令注册、完整包一次性注册
- 支持命令更新与包级帮助更新

---

## 核心模型

- `mycli`：统一入口命令
- `package`：对外暴露的能力包
- `sub-package`：包的子层级，继续复用包逻辑
- `command`：包内具体执行动作
- `cli.package.json`：包级注册中心
- `README.md`：包级详细帮助文档

关系说明：

- `skill` 和 `mycli package` 不做固定一一映射
- 一个 `skill` 可以对应多个 `mycli package`
- 一个 `mycli package` 也可以聚合多个 `skill`
- 最终归属关系由注册动作决定
- `command` 才是最小独立注册单元

---

## 目录规范

包树采用“目录即层级”的表达方式。

示例：

```text
D:\agent_workspace\capability-library\mycli\
  dev\
    cli.package.json
    README.md
    opencli\
      cli.package.json
      README.md
      commands\
        init.ps1
        inspect.ps1
```

约定：

- 每个包使用独立目录
- 包模板文件放在包目录内
- 包级帮助内容放在包目录下的 `README.md`
- 子包通过目录嵌套表达
- 命令实现可以拆成独立执行文件
- `entry` 使用绝对路径

---

## 交互规范

### 顶层

`mycli`

- 默认等价于 `mycli --help`

`mycli --help`

- 展示顶层 mycli 用法
- 说明如何列包、查看包信息、查看包命令、执行命令、注册和更新

`mycli list`

- 列出所有顶层 mycli 包
- 第一版仅展示：
  - 包名
  - 一句话简介
- 第一版不展示 `source`

### 包级

`mycli <package...>`

- 默认等价于 `mycli <package...> --help`
- 包内操作采用空格层级式写法

示例：

```powershell
mycli dev opencli list
mycli dev opencli --help
```

`mycli <package...> --help`

- 展示包的详细信息
- 详细内容读取该包目录下的 `README.md`

`mycli <package...> list`

- 同时列出该包下的子包和命令
- 输出按两个区块分开展示：
  - `Subpackages`
  - `Commands`

`Subpackages` 区块展示：

- 子包名
- 一句话简介

`Commands` 区块展示：

- 命令名
- 参数
- 参数说明
- 一句话说明

目标是让用户在 `list` 页看完就能直接使用。

### 子包级

子包及更深层级继续复用顶层 `mycli` 的 `list`、`--help` 和命令发现逻辑。

示例：

```powershell
mycli dev list
mycli dev opencli list
mycli dev opencli --help
mycli dev opencli init
```

### 命令级

第一版暂不单独实现：

```powershell
mycli <package...> <command> --help
```

命令详细信息统一维护在包目录下的 `README.md`。

---

## 注册与更新模型

系统支持两种工作模式：

### 1. 分步注册

- 先注册包
- 再注册单条命令或批量命令
- 再补包级帮助内容

### 2. 一次性完整注册

- 一次完成包信息、多个命令、包级帮助内容注册

---

## 命令体系

### 包管理

第一版采用：

- `mycli package register`
- `mycli package register-full`
- `mycli package list`

第一版不提供：

- `mycli package remove`

原因：

- 包是目录级结构
- 可能带子包
- 还包含 `README.md`
- 误删风险高

### 命令管理

第一版采用：

- `mycli <package...> command register <command>`
- `mycli <package...> command register-many`
- `mycli <package...> command list`
- `mycli <package...> command update <command>`

是否支持 `command remove`：

- 目前未正式定为第一版必做项
- 当前优先级低于注册和更新

### 帮助管理

第一版采用：

- `mycli <package...> help update`

说明：

- 修改目标是包目录下的 `README.md`
- 直接接收 Markdown 文本内容
- 不通过文件路径输入

---

## 包注册规范

### 包注册命令

包注册采用路径式包名，便于与目录结构直接对齐。

示例：

```powershell
mycli package register dev/opencli --summary "OpenCLI 相关能力" --source "D:\agent_workspace\capability-library\skill-library\opencli"
```

该命令会：

- 创建包目录
- 生成 `cli.package.json`
- 生成 `README.md` 模板

### 完整包注册命令

示例：

```powershell
mycli package register-full dev/opencli --summary "OpenCLI 相关能力" --source "D:\agent_workspace\capability-library\skill-library\opencli" --commands '[{"name":"init","summary":"初始化项目","args":[{"name":"name","required":true,"summary":"项目名称"}],"entry":"D:\\scripts\\init.ps1"}]' --help "# OpenCLI`n`n## 简介`n..."
```

用途：

- 一次性导入包信息
- 一次性注册多条命令
- 一次性写入包级帮助内容

---

## 命令注册规范

### 单命令注册

注册动作采用直接传参方式，不依赖交互式输入。

示例：

```powershell
mycli dev opencli command register init --summary "初始化项目" --entry "D:\agent_workspace\capability-library\mycli\dev\opencli\commands\init.ps1" --args '[{"name":"name","required":true,"summary":"项目名称"},{"name":"template","required":false,"summary":"模板名","type":"string","default":"basic"}]'
```

### 批量命令注册

示例：

```powershell
mycli dev opencli command register-many --commands '[{"name":"init","summary":"初始化项目","args":[{"name":"name","required":true,"summary":"项目名称"}],"entry":"D:\\commands\\init.ps1"},{"name":"inspect","summary":"查看项目信息","args":[{"name":"target","required":true,"summary":"目标路径","type":"path"}],"entry":"D:\\commands\\inspect.ps1"}]'
```

说明：

- 结构化参数直接通过命令行传入 JSON
- 单条注册适合日常维护
- 批量注册适合导入完整命令集

### 命令更新

示例：

```powershell
mycli dev opencli command update init --summary "初始化 OpenCLI 项目" --entry "D:\agent_workspace\capability-library\mycli\dev\opencli\commands\init.ps1" --args '[{"name":"name","required":true,"summary":"项目名称"},{"name":"template","required":false,"summary":"模板名","type":"string","default":"starter"}]'
```

更新目标包括：

- `summary`
- `args`
- `entry`

---

## 帮助更新规范

包级帮助修改命名采用：

```powershell
mycli <package...> help update
```

示例：

```powershell
mycli dev opencli help update --content "# OpenCLI`n`n## 简介`nOpenCLI 相关能力包。`n`n## 命令列表`n- init: 初始化项目"
```

说明：

- 直接传 Markdown 文本
- 最终写入包目录下的 `README.md`

---

## `cli.package.json` 规范

### 最小字段

包模板最少字段包括：

- `name`
- `summary`
- `source`
- `commands`

其中：

- `source` 允许输入自定义文本，推荐使用绝对路径
- `commands` 是统一注册中心

### 包配置示例

```json
{
  "name": "opencli",
  "summary": "OpenCLI 相关能力",
  "source": "D:\\agent_workspace\\capability-library\\skill-library\\opencli",
  "commands": [
    {
      "name": "init",
      "summary": "初始化项目",
      "args": [
        {
          "name": "name",
          "required": true,
          "summary": "项目名称"
        },
        {
          "name": "template",
          "required": false,
          "summary": "模板名",
          "type": "string",
          "default": "basic"
        }
      ],
      "entry": "D:\\agent_workspace\\capability-library\\cli\\dev\\opencli\\commands\\init.ps1"
    }
  ]
}
```

---

## 命令对象规范

### 最小字段

命令对象最少字段包括：

- `name`
- `summary`
- `args`
- `entry`

### `args` 对象规范

每个参数采用统一结构：

- 必填：
  - `name`
  - `required`
  - `summary`
- 可选：
  - `type`
  - `default`

### 参数示例

```json
[
  {
    "name": "name",
    "required": true,
    "summary": "项目名称"
  },
  {
    "name": "template",
    "required": false,
    "summary": "模板名",
    "type": "string",
    "default": "basic"
  }
]
```

---

## `README.md` 模板规范

包级 `README.md` 模板最少包含：

- 包名
- 简介
- 来源
- 命令列表
- 每个命令的详细说明
- 使用示例

### 模板示例

```md
# OpenCLI

## 简介

OpenCLI 相关能力包。

## 来源

D:\agent_workspace\capability-library\skill-library\opencli

## 命令列表

- `init`
- `inspect`

## 命令说明

### init

初始化项目。

参数：

- `name`：项目名称，必填
- `template`：模板名，可选，默认 `basic`

### inspect

查看项目或目标信息。

参数：

- `target`：目标路径，必填

## 使用示例

```powershell
mycli dev opencli list
mycli dev opencli init demo
```
```

---

## 第一版已确认决策

1. 顶层命令名采用 `mycli`
2. `skill` 与 `mycli package` 不做固定映射关系，命令注册时决定归属
3. 注册流程支持分步注册与完整注册两种模式
4. 命令参数采用结构化定义
5. 包模板文件名采用 `cli.package.json`
6. 包模板最少字段包括 `name`、`summary`、`source`、`commands`
7. 命令对象最少字段包括 `name`、`summary`、`args`、`entry`
8. `source` 字段允许自定义文本，推荐使用绝对路径
9. `entry` 字段使用绝对路径
10. `args` 中每个参数采用统一结构，支持可选字段 `type`、`default`
11. `mycli <package...> list` 需要直接展示命令、参数和参数说明
12. 第一版 `mycli list` 仅展示包名和简介
13. 每个 mycli 包使用独立目录，包模板放在对应包目录内
14. 命令统一登记在 `cli.package.json` 的 `commands` 数组中
15. `mycli <package...> --help` 读取包目录下的 `README.md`
16. 第一版暂不单独实现 `mycli <package...> <command> --help`
17. 注册包时同时生成 `README.md` 模板
18. `README.md` 模板最少包含包名、简介、来源、命令列表、命令说明、使用示例
19. 注册命令采用完整子命令风格
20. 包管理命令第一版采用 `mycli package register`、`mycli package register-full`、`mycli package list`
21. mycli 包支持子包，且子包逻辑与顶层一致
22. mycli 包树采用“目录即层级”
23. `mycli <package...> list` 需要同时列出子包和命令
24. `mycli <package...> list` 的输出按 `Subpackages` 和 `Commands` 分区展示
25. 子包注册采用路径式包名，如 `dev/opencli`
26. 包内操作采用空格层级式写法，如 `mycli dev opencli list`
27. 注册动作采用直接传参方式，不依赖交互输入
28. 命令注册时结构化参数通过命令行直接传入 JSON
29. 命令注册支持单条和批量两种方式
30. 系统支持一次性注册完整包内容，包括包信息、多个命令和帮助内容
31. 一次性完整注册命名采用 `mycli package register-full`
32. 第一版不支持删包命令
33. 第一版支持命令更新
34. 第一版支持包级帮助更新
35. 命令修改命名采用 `mycli <package...> command update <command>`，包级帮助修改命名采用 `mycli <package...> help update`
36. `mycli <package...> help update` 直接接收 Markdown 文本内容

---

## 后续实现建议

建议实现顺序：

1. 先实现 `mycli list`、`mycli <package...> list`、`mycli <package...> --help`
2. 再实现 `package register`
3. 再实现 `command register` 和 `command register-many`
4. 再实现 `command update` 和 `help update`
5. 最后实现 `package register-full`

这样可以先把“发现和读取”链路打通，再补“写入和更新”。



