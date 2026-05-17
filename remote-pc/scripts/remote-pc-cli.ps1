param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $PSScriptRoot

function Get-RemotePcWorkspaceConfigForCli {
    $module = Join-Path (Split-Path -Parent $PackageRoot) 'common\workspace-config.ps1'
    . $module
    Get-MyCliWorkspaceConfig -PackagePath 'remote-pc'
}

function Get-RemotePcConfigRootForCli {
    $workspaceConfig = Get-RemotePcWorkspaceConfigForCli
    [string]$workspaceConfig.paths.config
}

function Get-RemotePcToolRootForCli {
    'D:\agent_workspace\tools\mycli\remote-pc'
}

function Import-RemotePcEnvFile {
    $envPath = Join-Path (Get-RemotePcConfigRootForCli) 'relay.env.local'
    if (-not (Test-Path -LiteralPath $envPath)) { return }
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) { continue }
        [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1], 'Process')
    }
}

Import-RemotePcEnvFile

function Show-RemotePcUsage {
@"
remote-pc native commands:
  status <target>
  connect <target> [-Force] [-NoPersistent]
  disconnect <target>
  repair <target>
  run <target> <command> [-TimeoutSeconds N]
  wg-status
  wg-start
    wg-stop
    wg-restart
  configure [secretsPath] [A|B]
    command-server-start
  command-server-stop
  command-server-status
  relay-health
  relay-run <command>
  test-relay-file
  paths

Examples:
  mycli remote-pc status B
  mycli remote-pc wg-status
  mycli remote-pc command-server-start
  mycli remote-pc relay-run "hostname"
"@
}

if ($Command -in @('--help', '-h') -or (($Rest -contains '--help') -or ($Rest -contains '-h') -or ($Rest -contains 'help'))) {
    Show-RemotePcUsage
    exit 0
}

function Invoke-PackageScript {
    param([Parameter(Mandatory)][string]$Name, [string[]]$Args = @())
    $scriptPath = Join-Path $PackageRoot "scripts\$Name"
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Missing script: $scriptPath" }
    & $scriptPath @Args
    $lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) { exit $lastExitCodeVariable.Value }
    exit 0
}

function Exit-WithNativeCode {
    $lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) { exit $lastExitCodeVariable.Value }
    exit 0
}

function Get-WireGuardExe {
    $candidates = @(
        (Join-Path (Get-RemotePcToolRootForCli) 'wireguard\wireguard.exe'),
        'C:\Program Files\WireGuard\wireguard.exe',
        (Join-Path $PackageRoot 'wireguard\bin\wireguard.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "WireGuard executable not found. Expected workspace copy under $(Join-Path (Get-RemotePcToolRootForCli) 'wireguard\wireguard.exe') or official install under C:\Program Files\WireGuard."
}

function Get-ClientAConfig {
    $path = Join-Path (Get-RemotePcConfigRootForCli) 'wireguard\client-a.local.conf'
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing WireGuard client config: $path" }
    $path
}

function Get-RemotePcLocalDeviceName {
    $devicesPath = Join-Path (Get-RemotePcConfigRootForCli) 'devices.local.json'
    if (-not (Test-Path -LiteralPath $devicesPath)) { return 'A' }
    $config = Get-Content -LiteralPath $devicesPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($config.localDevice)) { return 'A' }
    $config.localDevice.ToUpperInvariant()
}

function Get-ClientConfig {
    $localDevice = Get-RemotePcLocalDeviceName
    $configName = 'client-{0}.local' -f $localDevice.ToLowerInvariant()
    $path = Join-Path (Get-RemotePcConfigRootForCli) "wireguard\$configName.conf"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing WireGuard client config: $path. Run scripts\configure-from-secrets.ps1 first."
    }
    [pscustomobject]@{
        LocalDevice = $localDevice
        Name = $configName
        Path = $path
    }
}

function Get-WireGuardServiceName {
    param([Parameter(Mandatory)][string]$ConfigName)
    "WireGuardTunnel`$$ConfigName"
}

function Get-CommandServerScript {
    $path = Join-Path $PackageRoot 'command-server\command_server.py'
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing command server script: $path" }
    $path
}

function Get-RemotePcSecrets {
    $path = Join-Path (Get-RemotePcConfigRootForCli) 'secrets.local.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-RemotePcCommandConfig {
    $secrets = Get-RemotePcSecrets
    $localDevice = Get-RemotePcLocalDeviceName
    $devicesPath = Join-Path (Get-RemotePcConfigRootForCli) 'devices.local.json'
    $commandHost = if ($localDevice -eq 'B') { '10.66.0.3' } else { '10.66.0.2' }
    if (Test-Path -LiteralPath $devicesPath) {
        $devices = Get-Content -LiteralPath $devicesPath -Raw | ConvertFrom-Json
        if ($devices.devices.$localDevice -and -not [string]::IsNullOrWhiteSpace($devices.devices.$localDevice.wireguardIp)) {
            $commandHost = $devices.devices.$localDevice.wireguardIp
        }
    }
    $serverIp = '10.66.0.1'
    if ($secrets -and $secrets.network.server -and -not [string]::IsNullOrWhiteSpace($secrets.network.server.wireguardIp)) {
        $serverIp = $secrets.network.server.wireguardIp
    }
    [pscustomobject]@{
        Host = if ($env:REMOTE_PC_COMMAND_HOST) { $env:REMOTE_PC_COMMAND_HOST } elseif ($secrets -and $secrets.commandServer.host -and $secrets.commandServer.host -ne 'auto') { $secrets.commandServer.host } else { $commandHost }
        Port = if ($env:REMOTE_PC_COMMAND_PORT) { [int]$env:REMOTE_PC_COMMAND_PORT } elseif ($secrets -and $secrets.commandServer.port) { [int]$secrets.commandServer.port } else { 18082 }
        AllowedClient = if ($env:REMOTE_PC_COMMAND_ALLOWED_CLIENT) { $env:REMOTE_PC_COMMAND_ALLOWED_CLIENT } elseif ($secrets -and $secrets.commandServer.allowedClient) { $secrets.commandServer.allowedClient } else { $serverIp }
        Cwd = if ($env:REMOTE_PC_COMMAND_CWD) { $env:REMOTE_PC_COMMAND_CWD } elseif ($secrets -and $secrets.commandServer.cwd) { $secrets.commandServer.cwd } else { 'D:\agent_workspace' }
        TimeoutSeconds = if ($env:REMOTE_PC_COMMAND_TIMEOUT) { [int]$env:REMOTE_PC_COMMAND_TIMEOUT } elseif ($secrets -and $secrets.commandServer.timeoutSeconds) { [int]$secrets.commandServer.timeoutSeconds } else { 180 }
        Token = if ($env:REMOTE_PC_COMMAND_TOKEN) { $env:REMOTE_PC_COMMAND_TOKEN } elseif ($secrets -and $secrets.commandServer.token) { $secrets.commandServer.token } else { '' }
    }
}

function Get-CommandServerProcesses {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*command_server.py*' -and $_.CommandLine -like '*remote-pc*' }
}

function ConvertTo-UrlSafeBase64 {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function Get-RemotePcRelayConfig {
    $secrets = Get-RemotePcSecrets
    $hostName = if ($env:REMOTE_PC_RELAY_HOST) { $env:REMOTE_PC_RELAY_HOST } elseif ($secrets -and $secrets.relay.host) { $secrets.relay.host } else { '49.232.183.40' }
    $userName = if ($env:REMOTE_PC_RELAY_USER) { $env:REMOTE_PC_RELAY_USER } elseif ($secrets -and $secrets.relay.sshUser) { $secrets.relay.sshUser } else { 'root' }
    $hostKey = if ($env:REMOTE_PC_RELAY_HOSTKEY) { $env:REMOTE_PC_RELAY_HOSTKEY } elseif ($secrets -and $secrets.relay.hostKey) { $secrets.relay.hostKey } else { '' }
    $keyPath = if ($env:REMOTE_PC_RELAY_KEY) { $env:REMOTE_PC_RELAY_KEY } elseif ($secrets -and $secrets.relay.sshPrivateKeyPath) { $secrets.relay.sshPrivateKeyPath } else { '' }
    $plinkPath = if ($env:REMOTE_PC_RELAY_PLINK) { $env:REMOTE_PC_RELAY_PLINK } elseif ($secrets -and $secrets.relay.plinkPath) { $secrets.relay.plinkPath } else { 'C:\Program Files\PuTTY\plink.exe' }
    if ([string]::IsNullOrWhiteSpace($keyPath)) {
        $keyPath = Join-Path $env:USERPROFILE '.ssh\remote_pc_relay_ed25519'
    }
    [pscustomobject]@{
        Host = $hostName
        User = $userName
        HostKey = $hostKey
        KeyPath = [Environment]::ExpandEnvironmentVariables($keyPath)
        PlinkPath = [Environment]::ExpandEnvironmentVariables($plinkPath)
    }
}

function Invoke-ServerCommand {
    param([Parameter(Mandatory)][string]$RemoteCommand)
    $relay = Get-RemotePcRelayConfig
    $usePlink = $false
    if (-not [string]::IsNullOrWhiteSpace($relay.PlinkPath) -and (Test-Path -LiteralPath $relay.PlinkPath)) {
        if ($relay.KeyPath -and $relay.KeyPath.ToLowerInvariant().EndsWith('.ppk')) {
            $usePlink = $true
        }
    }

    if ($usePlink) {
        $plink = $relay.PlinkPath
        $args = @('-ssh', '-batch', '-no-antispoof', '-P', '22')
        if (-not [string]::IsNullOrWhiteSpace($relay.HostKey)) { $args += @('-hostkey', $relay.HostKey) }
        if (Test-Path -LiteralPath $relay.KeyPath) { $args += @('-i', $relay.KeyPath) }
        $args += ("$($relay.User)@$($relay.Host)")
        $args += $RemoteCommand
        & $plink @args
        return
    }

    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $ssh) { throw 'OpenSSH client not found in PATH.' }
    $args = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
    if (Test-Path -LiteralPath $relay.KeyPath) { $args += @('-i', $relay.KeyPath) }
    $args += ("$($relay.User)@$($relay.Host)")
    $args += $RemoteCommand
    & $ssh.Source @args
}

function Invoke-RelayRequest {
    param([Parameter(Mandatory)][string]$PathAndQuery)
    $commandConfig = Get-RemotePcCommandConfig
    $remoteCommand = "curl -sS --max-time 180 'http://$($commandConfig.Host):$($commandConfig.Port)$PathAndQuery'"
    Invoke-ServerCommand -RemoteCommand $remoteCommand
}

switch ($Command) {
    $null { Show-RemotePcUsage; exit 0 }
    '' { Show-RemotePcUsage; exit 0 }
    'help' { Show-RemotePcUsage; exit 0 }
    'paths' {
        $localDevice = Get-RemotePcLocalDeviceName
        $workspaceConfig = Get-RemotePcWorkspaceConfigForCli
        [pscustomobject]@{
            PackageRoot = $PackageRoot
            Config = [string]$workspaceConfig.paths.config
            Tools = Get-RemotePcToolRootForCli
            LocalDevice = $localDevice
            WireGuardConfig = Join-Path ([string]$workspaceConfig.paths.config) ('wireguard\client-{0}.local.conf' -f $localDevice.ToLowerInvariant())
            Logs = [string]$workspaceConfig.paths.logs
        } | Format-List
        exit 0
    }
    'status' { Invoke-PackageScript -Name 'remote-status.ps1' -Args $Rest }
    'connect' { Invoke-PackageScript -Name 'remote-connect.ps1' -Args $Rest }
    'disconnect' { Invoke-PackageScript -Name 'remote-disconnect.ps1' -Args $Rest }
    'repair' { Invoke-PackageScript -Name 'remote-repair.ps1' -Args $Rest }
    'run' { Invoke-PackageScript -Name 'remote-run.ps1' -Args $Rest }
    'configure' {
        $configureArgs = @()
        if ($Rest -and $Rest.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($Rest[0])) { $configureArgs += @('-SecretsPath', $Rest[0]) }
        if ($Rest -and $Rest.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($Rest[1])) { $configureArgs += @('-LocalDevice', $Rest[1]) }
        & (Join-Path $PackageRoot 'scripts\configure-from-secrets.ps1') @configureArgs
        $lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        if ($lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) { exit $lastExitCodeVariable.Value }
        exit 0
    }
    'wg-status' {
        Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Format-Table -AutoSize
        Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'WireGuard' -or $_.Name -match 'client-a|WireGuard' } | Format-Table -AutoSize
        Invoke-ServerCommand -RemoteCommand 'wg show'
        Exit-WithNativeCode
    }
    'wg-start' {
        $conf = Get-ClientConfig
        $serviceName = Get-WireGuardServiceName -ConfigName $conf.Name
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne 'Running') { Start-Service -Name $service.Name }
            Get-Service -Name $service.Name | Format-Table -AutoSize
        } else {
            $wg = Get-WireGuardExe
            & $wg /installtunnelservice $conf.Path
        }
        Exit-WithNativeCode
    }
    'wg-stop' { $conf = Get-ClientConfig; & (Get-WireGuardExe) /uninstalltunnelservice $conf.Name; Exit-WithNativeCode }
    'wg-restart' {
        $wg = Get-WireGuardExe
        $conf = Get-ClientConfig
        & $wg /uninstalltunnelservice $conf.Name 2>$null
        Start-Sleep -Seconds 2
        & $wg /installtunnelservice $conf.Path
        Exit-WithNativeCode
    }
    'command-server-start' {
        $scriptPath = Get-CommandServerScript
        $workspaceConfig = Get-RemotePcWorkspaceConfigForCli
        $logDir = [string]$workspaceConfig.paths.logs
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $commandConfig = Get-RemotePcCommandConfig
        New-NetFirewallRule -DisplayName "Remote Bridge Command $($commandConfig.Port) WireGuard" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $commandConfig.Port -RemoteAddress "$($commandConfig.AllowedClient)/32" -Profile Any -ErrorAction SilentlyContinue | Out-Null
        $existing = Get-CommandServerProcesses
        if ($existing) { $existing | Select-Object ProcessId,CommandLine | Format-List; exit 0 }
        $args = @($scriptPath, '--host', $commandConfig.Host, '--port', ([string]$commandConfig.Port), '--allow', $commandConfig.AllowedClient, '--cwd', $commandConfig.Cwd, '--timeout', ([string]$commandConfig.TimeoutSeconds), '--log', (Join-Path $logDir 'command-server.log'))
        if (-not [string]::IsNullOrWhiteSpace($commandConfig.Token)) { $args += @('--token', $commandConfig.Token) }
        $p = Start-Process -FilePath 'python' -ArgumentList $args -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 2
        Get-Process -Id $p.Id | Select-Object Id,ProcessName,StartTime | Format-List
        exit 0
    }
    'command-server-stop' {
        $procs = Get-CommandServerProcesses
        if (-not $procs) { Write-Host 'Command server is not running.'; exit 0 }
        foreach ($proc in $procs) { Stop-Process -Id $proc.ProcessId -Force }
        Write-Host "Stopped command server process(es): $($procs.ProcessId -join ', ')"
        exit 0
    }
    'command-server-status' {
        $procs = Get-CommandServerProcesses
        if ($procs) { $procs | Select-Object ProcessId,CommandLine | Format-List } else { Write-Host 'Command server is not running.' }
        netstat -ano | Select-String ':18082'
        exit 0
    }
    'relay-health' { Invoke-RelayRequest -PathAndQuery '/health'; Exit-WithNativeCode }
    'relay-run' {
        if (-not $Rest -or $Rest.Count -lt 1) { throw 'relay-run requires a PowerShell command string.' }
        $cmd = $Rest -join ' '
        $cmd64 = ConvertTo-UrlSafeBase64 -Text $cmd
        Invoke-RelayRequest -PathAndQuery "/run?cmd64=$cmd64"
        Exit-WithNativeCode
    }
    'test-relay-file' {
        $workspaceConfig = Get-RemotePcWorkspaceConfigForCli
        $testDir = Join-Path ([string]$workspaceConfig.paths.tmp) 'wireguard-self-test'
        if (-not (Test-Path -LiteralPath $testDir)) { New-Item -ItemType Directory -Path $testDir -Force | Out-Null }
        $filePath = Join-Path $testDir 'from-a-via-wireguard.txt'
        Set-Content -LiteralPath $filePath -Value "hello from A via WireGuard relay $(Get-Date -Format o)" -Encoding UTF8
        New-NetFirewallRule -DisplayName 'Remote Bridge Test HTTP 18080 WireGuard' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 18080 -RemoteAddress 10.66.0.1/32 -Profile Any -ErrorAction SilentlyContinue | Out-Null
        $listening = netstat -ano | Select-String ':18080'
        if (-not $listening) {
            Start-Process -FilePath 'python' -ArgumentList @('-m','http.server','18080','--bind','10.66.0.2','--directory',$testDir) -WindowStyle Hidden | Out-Null
            Start-Sleep -Seconds 2
        }
        Invoke-ServerCommand -RemoteCommand 'curl -sS --max-time 10 http://10.66.0.2:18080/from-a-via-wireguard.txt; echo; wg show'
        Exit-WithNativeCode
    }
    default { throw "Unknown remote-pc command '$Command'. Use: mycli remote-pc native help" }
}
