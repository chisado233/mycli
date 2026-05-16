param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Position = 1, Mandatory = $true)]
    [string]$Out,

    [string]$Title = "",
    [string]$Author = "",
    [string]$Platform = "fanqie"
)

$collector = Join-Path $PSScriptRoot "collector.ps1"
& $collector import-text -InputFile $InputFile -Out $Out -Title $Title -Author $Author -Platform $Platform
