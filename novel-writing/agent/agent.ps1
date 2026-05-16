param(
    [Parameter(Position = 0)]
    [string]$Action = "open",

    [Parameter(Position = 1)]
    [string]$Name,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$PackageRoot = "D:\agent_workspace\capability-library\mycli\novel-writing\agent"
$DesignPath = Join-Path $PackageRoot "AGENT_DESIGN.md"
$PromptsRoot = Join-Path $PackageRoot "prompts"
$Runner = Join-Path $PackageRoot "novel_agent_runner.py"

switch ($Action) {
    "open" {
        Write-Output $PackageRoot
    }
    "show" {
        Get-Content -LiteralPath $DesignPath -Raw
    }
    "prompts" {
        if (-not (Test-Path -LiteralPath $PromptsRoot)) {
            Write-Output "No prompts directory found: $PromptsRoot"
            return
        }
        Get-ChildItem -LiteralPath $PromptsRoot -Filter "*.md" | Sort-Object Name | ForEach-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        }
    }
    "prompt" {
        if (-not $Name) {
            throw "Usage: mycli novel-writing agent prompt <name>"
        }
        $promptPath = Join-Path $PromptsRoot ($Name + ".md")
        if (-not (Test-Path -LiteralPath $promptPath)) {
            throw "Prompt template not found: $promptPath"
        }
        Get-Content -LiteralPath $promptPath -Raw
    }
    "build-prompt" {
        if (-not $Name) {
            throw "Usage: mycli novel-writing agent build-prompt <request.json> [--out <prompt.md>]"
        }
        & python $Runner build-prompt $Name @RemainingArgs
    }
    "collect-context" {
        if (-not $Name) {
            throw "Usage: mycli novel-writing agent collect-context <request.json> [--out <result.json>]"
        }
        & python $Runner collect-context $Name @RemainingArgs
    }
    "run" {
        if (-not $Name) {
            throw "Usage: mycli novel-writing agent run <request.json>"
        }
        & python $Runner run $Name @RemainingArgs
    }
    "apply-relations" {
        if (-not $Name) {
            throw "Usage: mycli novel-writing agent apply-relations <relation.json> [--dry-run]"
        }
        & python $Runner apply-relations $Name @RemainingArgs
    }
    default {
        throw "Unknown action '$Action'. Available actions: open, show, prompts, prompt, build-prompt, collect-context, run, apply-relations."
    }
}
