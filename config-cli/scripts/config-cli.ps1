param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$InputArgs
)

$ErrorActionPreference = 'Stop'

$ConfigRoot = 'D:\agent_workspace\config'

function Show-Usage {
  @"
config-cli

Usage:
  config-cli --help
  config-cli list [--json]
  config-cli find <name> [--json]
  config-cli validate

Config root:
  $ConfigRoot

Contract:
  Every *.json config under the config root is detected automatically and must have a top-level description field.

Output fields:
  name         Uses top-level name when present; otherwise the relative JSON path without extension.
  description  Uses top-level description.
  path         Absolute JSON file path.

Notes:
  Detection is recursive. New *.json files placed anywhere under $ConfigRoot are included on the next command run.
"@
}

function Test-JsonPropertyExists {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  return $null -ne ($Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
}

function Get-ConfigRecords {
  if (-not (Test-Path -LiteralPath $ConfigRoot -PathType Container)) {
    throw "Config root not found: $ConfigRoot"
  }

  $files = Get-ChildItem -LiteralPath $ConfigRoot -File -Filter '*.json' -Recurse | Sort-Object FullName
  $records = New-Object System.Collections.ArrayList
  $errors = New-Object System.Collections.ArrayList

  foreach ($file in $files) {
    try {
      $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
      $json = $raw | ConvertFrom-Json
    } catch {
      [void]$errors.Add("Invalid JSON: $($file.FullName) ($($_.Exception.Message))")
      continue
    }

    try {
      $relativePath = [System.IO.Path]::GetRelativePath($ConfigRoot, $file.FullName)
    } catch {
      $configRootResolved = [System.IO.Path]::GetFullPath($ConfigRoot)
      if (-not $configRootResolved.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $configRootResolved += [System.IO.Path]::DirectorySeparatorChar
      }
      $configRootUri = [System.Uri]::new($configRootResolved)
      $fileUri = [System.Uri]::new([System.IO.Path]::GetFullPath($file.FullName))
      $relativePath = [System.Uri]::UnescapeDataString(
        $configRootUri.MakeRelativeUri($fileUri).ToString().Replace('/', '\\')
      )
    }
    if (-not (Test-JsonPropertyExists -Object $json -Name 'description')) {
      if ($relativePath -match '^mycli\\' -and [System.IO.Path]::GetFileName($file.FullName) -ne 'workspace-config.json') {
        [void]$records.Add([pscustomobject]@{
          name = [System.IO.Path]::ChangeExtension($relativePath, $null).TrimEnd('.')
          description = 'mycli package workspace config/data file'
          path = $file.FullName
        })
        continue
      }
      [void]$errors.Add("Missing top-level description field: $($file.FullName)")
      continue
    }

    $description = [string]$json.description
    if ([string]::IsNullOrWhiteSpace($description)) {
      [void]$errors.Add("Empty top-level description field: $($file.FullName)")
      continue
    }
    $name = [System.IO.Path]::ChangeExtension($relativePath, $null).TrimEnd('.')
    if ((Test-JsonPropertyExists -Object $json -Name 'name') -and -not [string]::IsNullOrWhiteSpace([string]$json.name)) {
      $name = [string]$json.name
    }

    [void]$records.Add([pscustomobject]@{
      name = $name
      description = $description
      path = $file.FullName
    })
  }

  return [pscustomobject]@{
    records = @($records)
    errors = @($errors)
  }
}

function Write-Records {
  param(
    [Parameter(Mandatory = $true)]$Records,
    [Parameter(Mandatory = $true)][bool]$AsJson
  )

  $recordList = @($Records)

  if ($AsJson) {
    $recordList | ConvertTo-Json -Depth 8
    return
  }

  if ($recordList.Count -eq 0) {
    Write-Output 'No configs found.'
    return
  }

  $recordList | Format-Table -AutoSize name, description, path
}

$command = 'list'
$remaining = @()
if ($InputArgs -and $InputArgs.Count -gt 0) {
  $command = $InputArgs[0]
  if ($InputArgs.Count -gt 1) {
    $remaining = @($InputArgs[1..($InputArgs.Count - 1)])
  }
}

$asJson = $remaining -contains '--json'
$remaining = @($remaining | Where-Object { $_ -ne '--json' })

switch ($command) {
  { $_ -in @('--help', '-h', 'help') } {
    Show-Usage
    exit 0
  }
  'list' {
    $result = Get-ConfigRecords
    if ($result.errors.Count -gt 0) {
      $result.errors | ForEach-Object { Write-Error $_ }
      exit 1
    }
    Write-Records -Records $result.records -AsJson $asJson
    exit 0
  }
  'find' {
    if ($remaining.Count -lt 1 -or [string]::IsNullOrWhiteSpace($remaining[0])) {
      throw 'find requires a config name.'
    }

    $query = $remaining[0]
    $result = Get-ConfigRecords
    if ($result.errors.Count -gt 0) {
      $result.errors | ForEach-Object { Write-Error $_ }
      exit 1
    }

    $normalizedQuery = $query -replace '/', '\'
    $matches = @($result.records | Where-Object {
      $_.name -eq $query -or
      $_.name -eq $normalizedQuery -or
      [System.IO.Path]::GetFileNameWithoutExtension($_.path) -eq $query
    })

    if ($matches.Count -eq 0) {
      Write-Error "Config not found: $query"
      exit 1
    }

    Write-Records -Records $matches -AsJson $asJson
    exit 0
  }
  'validate' {
    $result = Get-ConfigRecords
    if ($result.errors.Count -gt 0) {
      $result.errors | ForEach-Object { Write-Error $_ }
      exit 1
    }
    Write-Output "OK: $($result.records.Count) config(s) valid."
    exit 0
  }
  default {
    Write-Error "Unknown command: $command"
    Show-Usage
    exit 1
  }
}
