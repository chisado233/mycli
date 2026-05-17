Set-StrictMode -Version Latest

$script:WorkspaceConfigRoot = 'D:\agent_workspace'
$script:WorkspaceConfigTypes = @('tmp', 'var', 'logs', 'cache', 'config', 'data', 'downloads', 'backups')

function ConvertTo-WorkspaceSafeSegments {
    param([Parameter(Mandatory = $true)][string]$Name)
    $segments = @()
    foreach ($part in (($Name -replace '/', '\') -split '\\+')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($part -eq '.' -or $part -eq '..') { throw "Invalid workspace segment: $part" }
        if ($part -ne $part.Trim() -or $part.EndsWith('.')) { throw "Invalid workspace segment: $part" }
        if ($part -match '[\[\]]') { throw "Invalid wildcard segment: $part" }
        if ([System.IO.Path]::IsPathRooted($part)) { throw "Invalid rooted workspace segment: $part" }
        if ($part.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw "Invalid workspace segment: $part" }
        if ($part -match '^(?i)(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(\..*)?$') { throw "Reserved workspace segment: $part" }
        $segments += $part
    }
    if ($segments.Count -eq 0) { throw 'Workspace name must contain at least one segment.' }
    return $segments
}

function Get-WorkspaceConfigPath {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $path = [System.IO.Path]::Combine($script:WorkspaceConfigRoot, 'config', $Domain)
    foreach ($segment in (ConvertTo-WorkspaceSafeSegments -Name $Name)) {
        $path = [System.IO.Path]::Combine($path, $segment)
    }
    return [System.IO.Path]::Combine($path, 'workspace-config.json')
}

function New-WorkspaceConfigObject {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $segments = ConvertTo-WorkspaceSafeSegments -Name $Name
    $paths = [ordered]@{}
    foreach ($type in $script:WorkspaceConfigTypes) {
        $path = [System.IO.Path]::Combine($script:WorkspaceConfigRoot, $type, $Domain)
        foreach ($segment in $segments) {
            $path = [System.IO.Path]::Combine($path, $segment)
        }
        $paths[$type] = $path
    }
    [pscustomobject]@{
        schema = 'mycli.workspace-config.v1'
        domain = $Domain
        name = ($segments -join '/')
        workspaceRoot = $script:WorkspaceConfigRoot
        generatedAt = (Get-Date).ToString('o')
        paths = $paths
    }
}

function Ensure-WorkspaceConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $config = New-WorkspaceConfigObject -Domain $Domain -Name $Name
    foreach ($type in $script:WorkspaceConfigTypes) {
        [System.IO.Directory]::CreateDirectory([string]$config.paths.$type) | Out-Null
    }
    $path = Get-WorkspaceConfigPath -Domain $Domain -Name $Name
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    }
    return $path
}

function Get-WorkspaceConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $path = Ensure-WorkspaceConfig -Domain $Domain -Name $Name
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-MyCliWorkspaceConfig {
    param([Parameter(Mandatory = $true)][string]$PackagePath)
    return Get-WorkspaceConfig -Domain 'mycli' -Name $PackagePath
}

function Get-MyCliWorkspacePath {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][ValidateSet('tmp', 'var', 'logs', 'cache', 'config', 'data', 'downloads', 'backups')][string]$Type
    )
    $config = Get-MyCliWorkspaceConfig -PackagePath $PackagePath
    return [string]$config.paths.$Type
}
