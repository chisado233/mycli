$Root = 'D:\agent_workspace\capability-library\mycli\channels\QQ'
$Qq = '--help'
Set-Location (Join-Path $Root 'napcat')
cmd.exe /c launcher-user.bat $Qq *>> (Join-Path $Root 'logs\napcat.task.log')
