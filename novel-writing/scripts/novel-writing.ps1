param(
    [string]$Action = "open",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$SkillRoot = "D:\agent_workspace\capability-library\skill-library\novel-writing"
$SkillMd = Join-Path $SkillRoot "SKILL.md"
$DiscussionMd = Join-Path $SkillRoot "DISCUSSION.md"

switch ($Action) {
    "open" {
        Write-Output "Novel Writing Skill"
        Write-Output "Root: $SkillRoot"
        Write-Output "SKILL.md: $SkillMd"
        Write-Output "DISCUSSION.md: $DiscussionMd"
    }
    "skill" {
        Write-Output $SkillMd
    }
    "discussion" {
        Write-Output $DiscussionMd
    }
    "show" {
        if (-not (Test-Path -LiteralPath $DiscussionMd)) {
            throw "Discussion file not found: $DiscussionMd"
        }
        Get-Content -LiteralPath $DiscussionMd -Raw
    }
    default {
        throw "Unknown action '$Action'. Available actions: open, skill, discussion, show."
    }
}
