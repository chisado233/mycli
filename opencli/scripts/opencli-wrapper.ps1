$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $packageRoot "source"
$entry = Join-Path $sourceRoot "dist\src\main.js"
$node = Get-Command node -ErrorAction SilentlyContinue

if (-not $node) {
    Write-Error "node was not found on PATH. OpenCLI requires Node.js >= 21."
    exit 127
}

if (-not (Test-Path -LiteralPath $entry)) {
    Write-Error "OpenCLI entry was not found at '$entry'. The embedded source may be incomplete; rebuild or refresh mycli opencli source."
    exit 1
}

Push-Location $sourceRoot
try {
    & $node.Source $entry @args
    $code = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
    exit $code
} finally {
    Pop-Location
}
