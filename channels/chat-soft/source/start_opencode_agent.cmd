@echo off
setlocal

set CHAT_SOFT_SERVER_BASE_URL=http://39.106.125.149:3000
set CHAT_SOFT_AGENT_CLI_PATH=D:\agent_workspace\capability-library\mycli\mycli.ps1
set CHAT_SOFT_AGENT_CLI_AGENT=opencode/private-assistant
set CHAT_SOFT_AGENT_CLI_CWD=D:\agent_workspace

cd /d D:\agent_workspace\projects\chat_soft

echo Starting Chat Soft private-assistant agent via agent-cli...
echo SERVER=%CHAT_SOFT_SERVER_BASE_URL%
echo AGENT_CLI=%CHAT_SOFT_AGENT_CLI_PATH%
echo AGENT=%CHAT_SOFT_AGENT_CLI_AGENT%
echo CWD=%CHAT_SOFT_AGENT_CLI_CWD%
echo.

pnpm --filter @chat-soft/desktop agent:start
