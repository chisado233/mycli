[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$scriptPath = Join-Path $PSScriptRoot "llm_call.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Error "llm-call Python implementation not found: $scriptPath"
    exit 1
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}
if ($null -eq $python) {
    Write-Error "Python was not found in PATH. llm-call requires Python 3."
    exit 1
}

& $python.Source $scriptPath @CommandArgs
exit $LASTEXITCODE
