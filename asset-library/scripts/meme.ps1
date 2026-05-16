param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$ErrorActionPreference = 'Stop'
$MemeDir = 'D:\agent_workspace\capability-library\mycli\asset-library\memes'
$QqSend = 'D:\agent_workspace\capability-library\skill-library\qq-napcat-channel\scripts\qq-send.js'
$Exts = @('.png', '.jpg', '.jpeg', '.gif', '.webp')

function Ensure-MemeDir {
  if (-not (Test-Path $MemeDir)) { New-Item -ItemType Directory -Path $MemeDir -Force | Out-Null }
}

function Get-MemeFiles {
  Ensure-MemeDir
  Get-ChildItem -Path $MemeDir -File | Where-Object { $Exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name
}

function Resolve-MemePath([string]$Name) {
  Ensure-MemeDir
  if (-not $Name) { throw 'Missing meme name.' }
  if ([System.IO.Path]::GetExtension($Name)) {
    $candidate = Join-Path $MemeDir $Name
    if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
  } else {
    foreach ($ext in $Exts) {
      $candidate = Join-Path $MemeDir ($Name + $ext)
      if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
  }
  throw "Meme not found: $Name"
}

function Show-Help {
@"
asset-library meme

Meme directory:
  $MemeDir

Usage:
  mycli asset-library meme list
  mycli asset-library meme dir
  mycli asset-library meme path <name>
  mycli asset-library meme send [--group <id>|--user <id>|--default-group|--default-user] --name <name> [--caption <text>]
  mycli asset-library meme send [--group <id>|--user <id>|--default-group|--default-user] --file <path-or-url> [--caption <text>]

Examples:
  mycli asset-library meme list
  mycli asset-library meme path 彩叶哭哭
  mycli asset-library meme send --default-group --name 彩叶哭哭
"@
}

function Parse-OptionValue([string[]]$Items, [string]$Key) {
  for ($i = 0; $i -lt $Items.Count; $i++) {
    if ($Items[$i] -eq $Key -and $i + 1 -lt $Items.Count) { return $Items[$i + 1] }
  }
  return $null
}

$cmd = if ($Args.Count -gt 0) { $Args[0] } else { 'help' }
$rest = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }

switch ($cmd) {
  'help' { Show-Help }
  '--help' { Show-Help }
  '-h' { Show-Help }
  'dir' { Ensure-MemeDir; Write-Output $MemeDir }
  'list' {
    $files = Get-MemeFiles
    if (-not $files) { Write-Output "No memes found in $MemeDir"; break }
    $files | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
  }
  'path' {
    if ($rest.Count -lt 1) { throw 'Usage: meme path <name>' }
    Resolve-MemePath ($rest -join ' ')
  }
  'send' {
    $sendArgs = @('sticker') + $rest
    $name = Parse-OptionValue $rest '--name'
    if ($name) {
      $file = Resolve-MemePath $name
      $sendArgs = @('sticker')
      for ($i = 0; $i -lt $rest.Count; $i++) {
        if ($rest[$i] -eq '--name') { $i++; continue }
        $sendArgs += $rest[$i]
      }
      $sendArgs += @('--file', $file)
    }
    & node $QqSend @sendArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  default { throw "Unknown meme command: $cmd" }
}
