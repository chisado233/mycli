$Root = 'D:\agent_workspace\capability-library\mycli\channels\QQ'
Set-Location $Root
$env:CI = 'true'
node.exe (Join-Path $Root 'qq-bridge.js') *>> (Join-Path $Root 'logs\bridge.task.log')
