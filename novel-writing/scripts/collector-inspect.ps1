param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$InputFile
)

$collector = Join-Path $PSScriptRoot "collector.ps1"
& $collector inspect -InputFile $InputFile
