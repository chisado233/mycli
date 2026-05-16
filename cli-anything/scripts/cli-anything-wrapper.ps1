$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $packageRoot "source"
$cliHubRoot = Join-Path $sourceRoot "cli-hub"
$registryPath = Join-Path $sourceRoot "registry.json"
$publicRegistryPath = Join-Path $sourceRoot "public_registry.json"

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}

if (-not $python) {
    Write-Error "python was not found on PATH. CLI-Anything cli-hub requires Python >= 3.10."
    exit 127
}

if (-not (Test-Path -LiteralPath (Join-Path $cliHubRoot "cli_hub\cli.py"))) {
    Write-Error "CLI-Anything cli-hub source was not found at '$cliHubRoot'. The embedded source may be incomplete."
    exit 1
}

if (-not (Test-Path -LiteralPath $registryPath)) {
    Write-Error "CLI-Anything registry was not found at '$registryPath'."
    exit 1
}

if (-not (Test-Path -LiteralPath $publicRegistryPath)) {
    Write-Error "CLI-Anything public registry was not found at '$publicRegistryPath'."
    exit 1
}

$cacheDir = Join-Path $env:USERPROFILE ".cli-hub"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$registryCache = Join-Path $cacheDir "registry_cache.json"
$publicRegistryCache = Join-Path $cacheDir "public_registry_cache.json"

$registryJson = Get-Content -LiteralPath $registryPath -Raw
$publicRegistryJson = Get-Content -LiteralPath $publicRegistryPath -Raw

@{
    _cached_at = $now
    data = $registryJson | ConvertFrom-Json
} | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $registryCache -Encoding UTF8

@{
    _cached_at = $now
    data = $publicRegistryJson | ConvertFrom-Json
} | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $publicRegistryCache -Encoding UTF8

$env:PYTHONPATH = if ($env:PYTHONPATH) { "$cliHubRoot;$env:PYTHONPATH" } else { $cliHubRoot }
$env:PYTHONUTF8 = "1"
$env:CLI_HUB_NO_ANALYTICS = "1"

Push-Location $sourceRoot
try {
    & $python.Source -m cli_hub.cli @args
    $code = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
    exit $code
} finally {
    Pop-Location
}
