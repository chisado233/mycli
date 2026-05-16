$ErrorActionPreference = "Stop"

$ghCandidates = @(
    "C:\Program Files\GitHub CLI\gh.exe",
    "C:\Program Files (x86)\GitHub CLI\gh.exe"
)

$gh = $null
foreach ($candidate in $ghCandidates) {
    if (Test-Path -LiteralPath $candidate) {
        $gh = $candidate
        break
    }
}

if (-not $gh) {
    $command = Get-Command gh -ErrorAction SilentlyContinue
    if ($command) {
        $gh = $command.Source
    }
}

if (-not $gh) {
    Write-Error "GitHub CLI (gh.exe) was not found. Install it with: winget install --id GitHub.cli -e"
    exit 127
}

if (-not $env:HTTPS_PROXY -and -not $env:HTTP_PROXY -and -not $env:ALL_PROXY) {
    $env:HTTPS_PROXY = "http://127.0.0.1:7890"
    $env:HTTP_PROXY = "http://127.0.0.1:7890"
    $env:ALL_PROXY = "http://127.0.0.1:7890"
}

& $gh @args
$code = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
exit $code
