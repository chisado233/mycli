$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultOutDir = "D:\agent_workspace\tmp\qq-avatar"

function Show-Usage {
@"
Usage:
  mycli channels QQ avatar <qq> [size] [out]

Arguments:
  qq      QQ number to download avatar for.
  size    Avatar size, commonly 100 or 640. Defaults to 640.
  out     Optional output file or directory. Defaults to D:\agent_workspace\tmp\qq-avatar.

Examples:
  mycli channels QQ avatar 381889153
  mycli channels QQ avatar 381889153 100
  mycli channels QQ avatar 381889153 640 D:\agent_workspace\tmp\qq-avatar\381889153.jpg
"@ | Write-Output
}

if ($args.Count -lt 1 -or $args[0] -in @("--help", "-h", "help")) {
    Show-Usage
    exit 0
}

$Qq = [string]$args[0]
if ($Qq -notmatch '^[0-9]+$') {
    throw "QQ number must contain digits only: $Qq"
}

$Size = if ($args.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($args[1])) { [string]$args[1] } else { "640" }
if ($Size -notmatch '^[0-9]+$') {
    throw "Avatar size must be numeric: $Size"
}

$OutArg = if ($args.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($args[2])) { [string]$args[2] } else { $DefaultOutDir }

if ([System.IO.Path]::GetExtension($OutArg)) {
    $OutFile = $OutArg
    $OutDir = Split-Path -Parent $OutFile
    if ([string]::IsNullOrWhiteSpace($OutDir)) {
        $OutDir = (Get-Location).Path
        $OutFile = Join-Path $OutDir $OutArg
    }
} else {
    $OutDir = $OutArg
    $OutFile = Join-Path $OutDir ("{0}_s{1}.jpg" -f $Qq, $Size)
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Url = "https://q1.qlogo.cn/g?b=qq&nk=$Qq&s=$Size"
Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 90 -UseBasicParsing

$File = Get-Item -LiteralPath $OutFile
[pscustomobject]@{
    qq = $Qq
    size = $Size
    url = $Url
    path = $File.FullName
    bytes = $File.Length
} | ConvertTo-Json -Depth 3
