# 原文章节位置

本项目默认不复制原文章节，避免占用空间和产生多份原文。

原文章节目录：

``text
D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\天命反派，开局拿下女帝师尊\章节
``

调度 agent 生成 request 时，应把上面的原文章节文件作为 context_files 传入。

如需要复制原文章节到本项目，重新执行：

``powershell
mycli novel-writing deconstruction init --book "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\天命反派，开局拿下女帝师尊" --out "D:\agent_workspace\capability-library\mycli\novel-writing\deconstruction\天命反派，开局拿下女帝师尊" --copy-chapters --force
``
