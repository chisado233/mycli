param(
    [Parameter(Position = 0)]
    [string]$Module,

    [Parameter(Position = 1)]
    [string]$Action = "open",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$moduleFiles = @{
    "collector" = "collector.md"
    "deconstruction" = "deconstruction.md"
    "project" = "project-manager.md"
    "writing-skill-library" = "writing-skill-library.md"
    "material-library" = "material-library.md"
}

if (-not $moduleFiles.ContainsKey($Module)) {
    throw "Unknown novel-writing module '$Module'. Available modules: $($moduleFiles.Keys -join ', ')."
}

$moduleRoot = "D:\agent_workspace\capability-library\skill-library\novel-writing\modules"
$modulePath = Join-Path $moduleRoot $moduleFiles[$Module]

switch ($Action) {
    "open" {
        Write-Output $modulePath
    }
    "show" {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            throw "Module discussion file not found: $modulePath"
        }
        Get-Content -LiteralPath $modulePath -Raw
    }
    default {
        throw "Unknown action '$Action'. Available actions: open, show."
    }
}
