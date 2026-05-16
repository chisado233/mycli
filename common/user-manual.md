# mycli 用户使用手册

## 1. 这是什么

`mycli` 是一套统一的能力入口。

它把脚本、skill、已有 CLI 工具，组织成可以：

- 发现
- 查看说明
- 直接执行

的命令体系。

你可以把它理解成一个“能力总入口”。

---

## 2. 命令入口

如果已经把 `D:\agent_workspace\capability-library\mycli` 加入 `PATH`，可以直接使用：

```powershell
mycli --help
```

如果当前环境还没有刷新，也可以直接用完整路径：

```powershell
D:\agent_workspace\capability-library\mycli\mycli.ps1 --help
```

或：

```powershell
D:\agent_workspace\capability-library\mycli\mycli.cmd --help
```

---

## 3. 基本概念

- `package`
  一个能力包，对外暴露一组相关命令
- `subpackage`
  包下面的子包，继续按同样逻辑组织
- `command`
  包里的具体执行动作
- `cli.package.json`
  包的注册文件
- `README.md`
  包的详细说明文档

---

## 4. 常用命令

### 查看顶层帮助

```powershell
mycli --help
```

用于查看 `mycli` 自己的用法。

### 查看所有顶层包

```powershell
mycli list
```

会列出：

- 包名
- 包简介

### 查看某个包的说明

```powershell
mycli <package> --help
```

例如：

```powershell
mycli opencode --help
```

这会读取该包目录下的 `README.md`。

### 查看某个包里有哪些子包和命令

```powershell
mycli <package> list
```

例如：

```powershell
mycli opencode list
```

输出会分成两部分：

- `Subpackages`
- `Commands`

命令列表里会直接展示：

- 命令名
- 参数
- 参数说明
- 命令简介

### 执行某个包里的命令

```powershell
mycli <package> <command> [args...]
```

例如：

```powershell
mycli opencode run "hello"
mycli opencode models --help
```

---

## 5. 包和子包

`mycli` 支持包树结构。

例如：

```powershell
mycli dev list
mycli dev opencli list
mycli dev opencli --help
```

也就是说：

- 顶层可以有包
- 包下面可以继续有子包
- 子包下面还可以继续有子包

每一层都支持：

- `list`
- `--help`
- 直接执行命令

---

## 6. opencode 的两种使用方式

`opencode` 目前已经接入 `mycli`，并且支持两种模式。

### 方式一：直接映射命令

适合平时直接使用：

```powershell
mycli opencode run "hello"
mycli opencode agent --help
mycli opencode models --help
mycli opencode session --help
```

这类命令会自动转发到原生 `opencode` 的对应子命令。

### 方式二：native 原生透传

适合完全按原生命令习惯来用：

```powershell
mycli opencode native --help
mycli opencode native run hello
mycli opencode native models --help
```

这会把 `native` 后面的所有参数原样交给原生 `opencode`。

---

## 7. 什么时候看 `list`，什么时候看 `--help`

推荐这样理解：

- `mycli --help`
  看 `mycli` 自己怎么用
- `mycli list`
  看有哪些能力包
- `mycli <package> list`
  看这个包里有哪些子包和命令
- `mycli <package> --help`
  看这个包的完整说明文档

一个简单的工作流通常是：

```powershell
mycli list
mycli opencode list
mycli opencode --help
mycli opencode run "hello"
```

如果你要用 workflow 能力，推荐流程是：

```powershell
mycli list
mycli agent-workflow list
mycli agent-workflow --help
mycli agent-workflow validate D:\agent_workspace\capability-library\agent-system-rules\agent-workflow\examples\script_echo_flow
```

如果你要新建一个 workflow 项目，推荐：

```powershell
mycli agent-workflow init D:\agent_workspace\projects\my-flow --workflow-id my_flow --name "My Flow"
mycli agent-workflow scaffold D:\agent_workspace\projects\my-flow
mycli agent-workflow validate D:\agent_workspace\projects\my-flow
```

---

## 8. 常见问题

### 1. 为什么 `mycli` 命令找不到

通常是因为终端还没有刷新，或者 `PATH` 还没生效。

解决方法：

- 重新打开一个新的终端窗口
- 或者直接使用完整路径执行 `mycli.ps1` / `mycli.cmd`

### 2. 为什么 `mycli <package> --help` 没有内容

因为包级帮助来自该包目录下的 `README.md`。

如果这个文件还没有写内容，`--help` 就只会显示已有文档内容。

### 3. 为什么某个命令存在但跑不起来

通常是以下原因之一：

- `entry` 指向的绝对路径不存在
- 命令实际依赖的外部环境没有安装
- 命令本身来自外部 CLI，而该 CLI 当前不可用

这时先看：

```powershell
mycli <package> list
mycli <package> --help
```

确认命令说明和注册入口是否正确。

---

## 9. 推荐使用习惯

- 先用 `mycli list` 找包
- 再用 `mycli <package> list` 找命令
- 需要详细说明时再看 `mycli <package> --help`
- 有原生 CLI 的包，优先用直接映射命令；需要完全原样时再用 `native`
- 单次 agent 调用优先用 `agent-cli`
- 多步骤、可等待、可审核、带运行状态的流程优先用 `agent-workflow`

---

## 10. 当前文件位置

核心入口：

- `D:\agent_workspace\capability-library\mycli\mycli.ps1`
- `D:\agent_workspace\capability-library\mycli\mycli.cmd`

核心运行时：

- `D:\agent_workspace\capability-library\mycli\common\cli.ps1`

示例包：

- `D:\agent_workspace\capability-library\mycli\opencode`
