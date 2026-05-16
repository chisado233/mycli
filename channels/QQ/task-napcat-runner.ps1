$Root = 'D:\agent_workspace\channel\QQ'
$Qq = '3279329186'
Set-Location (Join-Path $Root 'napcat')
cmd.exe /c launcher-user.bat $Qq *>> (Join-Path $Root 'logs\napcat.task.log')
