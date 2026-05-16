[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$oldEntry = Join-Path $PSScriptRoot '..\mycli-old\mycli.ps1'
if (-not (Test-Path -LiteralPath $oldEntry)) {
    Write-Error "mycli-old entry not found: $oldEntry"
    exit 1
}

& $oldEntry @CliArgs
$exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $exitCodeVariable -and $null -ne $exitCodeVariable.Value) {
    exit $exitCodeVariable.Value
}
