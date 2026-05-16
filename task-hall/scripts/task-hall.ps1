param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

if ($null -eq $CommandArgs) { $CommandArgs = @() }

$script:PackageRoot = Split-Path -Parent $PSScriptRoot
$script:StateRoot = Join-Path $script:PackageRoot "state"
$script:TasksRoot = Join-Path $script:StateRoot "tasks"
$script:RequestsRoot = Join-Path $script:StateRoot "requests"
$script:TaskLinksRoot = Join-Path $script:StateRoot "task-links"
$script:CallbackQueueRoot = Join-Path $script:StateRoot "callback-queue"
$script:MonitorRoot = Join-Path $script:PackageRoot "monitor"
$script:ListingsPath = Join-Path $script:StateRoot "listings.json"
$script:EventsPath = Join-Path $script:StateRoot "events.jsonl"
$script:AgentCliScriptPath = Join-Path (Split-Path -Parent $script:PackageRoot) "agent-cli\scripts\agent-cli.ps1"
$script:MyCliScriptPath = Join-Path (Split-Path -Parent $script:PackageRoot) "mycli.ps1"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

function Write-TaskHallError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    } catch {
        Write-TaskHallError "Failed to read '$Path'. $($_.Exception.Message)"
    }
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content,
        [bool]$EmitBom = $true
    )
    try {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $encoding = if ($EmitBom) { $script:Utf8WithBom } else { $script:Utf8NoBom }
        [System.IO.File]::WriteAllText($Path, $Content, $encoding)
    } catch {
        Write-TaskHallError "Failed to write '$Path'. $($_.Exception.Message)"
    }
}

function Ensure-TaskHallState {
    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TasksRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:RequestsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TaskLinksRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:CallbackQueueRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:MonitorRoot -Force | Out-Null
    if (-not (Test-Path -LiteralPath $script:ListingsPath)) {
        Write-Utf8Text -Path $script:ListingsPath -Content "[]`r`n"
    }
    if (-not (Test-Path -LiteralPath $script:EventsPath)) {
        Write-Utf8Text -Path $script:EventsPath -Content "" -EmitBom $false
    }
}

function Invoke-TaskHallLifecycleWake {
    param(
        [string]$Reason,
        [string]$TaskId = "",
        [int]$ListedLimit = 2,
        [int]$CallbackLimit = 5,
        [string]$Cwd = "D:\agent_workspace"
    )

    Ensure-TaskHallState
    $wakeRoot = Join-Path $script:StateRoot "lifecycle-wake"
    New-Item -ItemType Directory -Path $wakeRoot -Force | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $safeReason = if ([string]::IsNullOrWhiteSpace($Reason)) { "event" } else { ($Reason -replace '[^a-zA-Z0-9_.-]', '_') }
    $wakeId = "wake_${stamp}_${safeReason}"
    $outPath = Join-Path $wakeRoot ("{0}.out.txt" -f $wakeId)
    $errPath = Join-Path $wakeRoot ("{0}.err.txt" -f $wakeId)
    $metaPath = Join-Path $wakeRoot ("{0}.json" -f $wakeId)

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script:MyCliScriptPath,
        "task-hall", "lifecycle-tick",
        "--listed-limit", [string]$ListedLimit,
        "--callback-limit", [string]$CallbackLimit,
        "--cwd", $Cwd
    )

    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $outPath -RedirectStandardError $errPath
    $record = [ordered]@{
        wake_id = $wakeId
        reason = $Reason
        task_id = $TaskId
        pid = $process.Id
        started_at = (Get-Date).ToString("o")
        listed_limit = $ListedLimit
        callback_limit = $CallbackLimit
        cwd = $Cwd
        command = "mycli task-hall lifecycle-tick --listed-limit $ListedLimit --callback-limit $CallbackLimit --cwd $Cwd"
        stdout = $outPath
        stderr = $errPath
    }
    Write-Utf8Text -Path $metaPath -Content (($record | ConvertTo-Json -Depth 10) + "`r`n")
    Add-Event -Type "lifecycle.wake_started" -TaskId $TaskId -Data @{ wake_id = $wakeId; reason = $Reason; pid = $process.Id; stdout = $outPath; stderr = $errPath }
    Write-Host "Lifecycle wake started: $wakeId pid=$($process.Id)"
}

function Invoke-LifecycleWakeCommand {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--reason", "--task-id", "--listed-limit", "--callback-limit", "--cwd")
    $reason = Get-OptionValue -Args $InputArgs -Name "--reason" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "manual")
    $taskId = Get-OptionValue -Args $InputArgs -Name "--task-id" -Default ""
    $listedRaw = Get-OptionValue -Args $InputArgs -Name "--listed-limit" -Default "2"
    $callbackRaw = Get-OptionValue -Args $InputArgs -Name "--callback-limit" -Default "5"
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    $listedLimit = 2
    $callbackLimit = 5
    if (-not [int]::TryParse($listedRaw, [ref]$listedLimit)) { Write-TaskHallError "Invalid listed limit '$listedRaw'." }
    if (-not [int]::TryParse($callbackRaw, [ref]$callbackLimit)) { Write-TaskHallError "Invalid callback limit '$callbackRaw'." }
    Invoke-TaskHallLifecycleWake -Reason $reason -TaskId $taskId -ListedLimit $listedLimit -CallbackLimit $callbackLimit -Cwd $cwd
}

function New-RequestId {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 6)
    return "req_${stamp}_${suffix}"
}

function Get-RequestDir {
    param([string]$RequestId)
    return (Join-Path $script:RequestsRoot $RequestId)
}

function ConvertTo-HashtableDeep {
    param([object]$InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [char] -or $InputObject -is [bool] -or $InputObject -is [byte] -or $InputObject -is [int] -or $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal] -or $InputObject -is [datetime]) {
        return $InputObject
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) { $result[[string]$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key] }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) { $items += ,(ConvertTo-HashtableDeep -InputObject $item) }
        return $items
    }
    $properties = @($InputObject.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $result = @{}
        foreach ($prop in $properties) { $result[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value }
        return $result
    }
    return $InputObject
}

function Read-JsonFileAsHashtable {
    param([string]$Path)
    try {
        return ConvertTo-HashtableDeep -InputObject ((Read-Utf8Text -Path $Path) | ConvertFrom-Json)
    } catch {
        Write-TaskHallError "Failed to parse JSON file '$Path'. $($_.Exception.Message)"
    }
}

function Get-JsonObjectFromAgentOutput {
    param([string]$Output)
    $trimmed = $Output.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        Write-TaskHallError "Frontdesk agent returned empty output."
    }
    try {
        return ConvertTo-HashtableDeep -InputObject ($trimmed | ConvertFrom-Json)
    } catch {
        # agent-cli silent output can prepend session metadata. Extract the first JSON object span.
    }

    $start = $trimmed.IndexOf('{')
    $end = $trimmed.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        Write-TaskHallError "Could not find JSON object in frontdesk agent output.`n$Output"
    }
    $candidate = $trimmed.Substring($start, $end - $start + 1)
    try {
        return ConvertTo-HashtableDeep -InputObject ($candidate | ConvertFrom-Json)
    } catch {
        Write-TaskHallError "Failed to parse frontdesk agent JSON output. $($_.Exception.Message)`n$Output"
    }
}

function Invoke-AgentCliRunText {
    param(
        [string]$Agent,
        [string]$Prompt,
        [string]$Cwd = "D:\agent_workspace",
        [string]$SessionName = "task-hall-frontdesk",
        [string]$SessionId = $null
    )
    if (-not (Test-Path -LiteralPath $script:AgentCliScriptPath)) {
        Write-TaskHallError "agent-cli script not found: '$script:AgentCliScriptPath'."
    }
    $runArgs = @("run", "--agent", $Agent, "--return_mode", "silent", "--session_name", $SessionName, "--cwd", $Cwd)
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $runArgs += @("--session", $SessionId) }
    $runArgs += @("--prompt", $Prompt)
    $output = & $script:AgentCliScriptPath @runArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-TaskHallError "agent-cli run failed with exit code $LASTEXITCODE.`n$output"
    }
    return $output
}

function New-TaskFromMarkdownContent {
    param(
        [string]$Markdown,
        [string]$Kind,
        [int]$Priority,
        [string[]]$Tags,
        [string]$Title,
        [bool]$Publish,
        [hashtable]$Extra = @{}
    )
    Ensure-TaskHallState
    $taskId = New-TaskId
    $taskDir = Get-TaskDir -TaskId $taskId
    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
    Write-Utf8Text -Path (Join-Path $taskDir "task.md") -Content $Markdown
    Write-Utf8Text -Path (Join-Path $taskDir "claims.jsonl") -Content "" -EmitBom $false
    Write-Utf8Text -Path (Join-Path $taskDir "submissions.jsonl") -Content "" -EmitBom $false

    $now = (Get-Date).ToString("o")
    $status = if ($Publish) { "listed" } else { "draft" }
    $meta = [ordered]@{
        id = $taskId
        title = $Title
        kind = $Kind
        status = $status
        priority = $Priority
        tags = $Tags
        created_at = $now
        updated_at = $now
        listed_at = if ($Publish) { $now } else { $null }
        claimed_by = $null
        task_md = "task.md"
        task_dir = $taskDir
        publish_mode = "detached"
        publisher_agent = $null
        publisher_session = $null
        required_agent_type = $null
        parent_id = $null
        child_ids = @()
        watchers = @()
        task_link = (Get-TaskLinkPath -TaskId $taskId)
    }
    foreach ($key in $Extra.Keys) { $meta[$key] = $Extra[$key] }
    Save-TaskMeta -Meta ([pscustomobject]$meta)
    Upsert-Listing -Meta ([pscustomobject]$meta)
    Add-Event -Type "task.uploaded" -TaskId $taskId -Data @{ status = $status; kind = $Kind; title = $Title }
    if ($Publish) { Add-Event -Type "task.published" -TaskId $taskId -Data @{} }
    return [pscustomobject]$meta
}

function Get-Listings {
    Ensure-TaskHallState
    try {
        $data = (Read-Utf8Text -Path $script:ListingsPath) | ConvertFrom-Json
    } catch {
        Write-TaskHallError "Failed to parse listings.json. $($_.Exception.Message)"
    }
    if ($null -eq $data) { return @() }
    if ($data -is [System.Array]) { return @($data) }
    return @($data)
}

function Save-Listings {
    param([object[]]$Listings)
    $json = @($Listings) | Sort-Object status, priority, created_at | ConvertTo-Json -Depth 10
    if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
    Write-Utf8Text -Path $script:ListingsPath -Content ($json + "`r`n")
}

function Add-Event {
    param(
        [string]$Type,
        [string]$TaskId,
        [hashtable]$Data = @{}
    )
    Ensure-TaskHallState
    $event = [ordered]@{
        ts = (Get-Date).ToString("o")
        type = $Type
        task_id = $TaskId
        data = $Data
    }
    $line = ($event | ConvertTo-Json -Compress -Depth 10)
    [System.IO.File]::AppendAllText($script:EventsPath, $line + "`n", $script:Utf8NoBom)
}

function Test-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )
    if (Test-ObjectProperty -Object $Object -Name $Name) { return $Object.$Name }
    return $Default
}

function Set-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Add-UniqueString {
    param(
        [object[]]$Items,
        [string]$Value
    )
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$item) -and -not $result.Contains([string]$item)) { $result.Add([string]$item) }
    }
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $result.Contains($Value)) { $result.Add($Value) }
    return @($result)
}

function Remove-StringValue {
    param(
        [object[]]$Items,
        [string]$Value
    )
    return @($Items | Where-Object { [string]$_ -ne $Value })
}

function Get-TaskLinkPath {
    param([string]$TaskId)
    return (Join-Path $script:TaskLinksRoot ("{0}.json" -f $TaskId))
}

function Save-TaskLinkState {
    param([object]$State)
    $json = $State | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path (Get-TaskLinkPath -TaskId ([string]$State.task_id)) -Content ($json + "`r`n")
}

function Get-TaskLinkState {
    param([string]$TaskId)
    $path = Get-TaskLinkPath -TaskId $TaskId
    if (Test-Path -LiteralPath $path) {
        return (Read-Utf8Text -Path $path) | ConvertFrom-Json
    }
    $meta = Load-TaskMeta -TaskId $TaskId
    $now = (Get-Date).ToString("o")
    return [pscustomobject][ordered]@{
        task_id = $TaskId
        status = "open"
        created_at = $now
        updated_at = $now
        publish_mode = [string](Get-ObjectPropertyValue -Object $meta -Name "publish_mode" -Default "detached")
        publisher_agent = Get-ObjectPropertyValue -Object $meta -Name "publisher_agent" -Default $null
        publisher_session = Get-ObjectPropertyValue -Object $meta -Name "publisher_session" -Default $null
        current_agent = Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default $null
        reports = @()
        callbacks = @()
        handoffs = @()
    }
}

function Add-CallbackQueueItem {
    param(
        [string]$TaskId,
        [string]$Reason,
        [hashtable]$Payload = @{}
    )
    Ensure-TaskHallState
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 6)
    $callbackId = "cb_${stamp}_${suffix}"
    $item = [ordered]@{
        id = $callbackId
        task_id = $TaskId
        reason = $Reason
        status = "pending"
        created_at = (Get-Date).ToString("o")
        updated_at = (Get-Date).ToString("o")
        payload = $Payload
    }
    Write-Utf8Text -Path (Join-Path $script:CallbackQueueRoot ("{0}.json" -f $callbackId)) -Content (($item | ConvertTo-Json -Depth 20) + "`r`n")
    Add-Event -Type "task.callback_queued" -TaskId $TaskId -Data @{ callback_id = $callbackId; reason = $Reason }
    return [pscustomobject]$item
}

function Invoke-CallbackArchive {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--status", "--older-than-days", "--dry-run")
    Ensure-TaskHallState
    $statusFilter = Get-OptionValue -Args $InputArgs -Name "--status" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "failed,skipped,dispatched")
    $daysRaw = Get-OptionValue -Args $InputArgs -Name "--older-than-days" -Default "0"
    $days = 0
    if (-not [int]::TryParse($daysRaw, [ref]$days)) { Write-TaskHallError "Invalid older-than-days '$daysRaw'." }
    $dryRun = (($InputArgs -join " ") -match "dry")
    $allowed = @($statusFilter -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $archiveRoot = Join-Path $script:CallbackQueueRoot "archive"
    if (-not $dryRun) { New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null }
    $cutoff = (Get-Date).AddDays(-1 * $days)
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $script:CallbackQueueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        $item = (Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json
        $status = [string](Get-ObjectPropertyValue -Object $item -Name "status" -Default "")
        if ($allowed -notcontains $status) { continue }
        if ($file.LastWriteTime -gt $cutoff) { continue }
        $dest = Join-Path $archiveRoot $file.Name
        if ($dryRun) { Write-Host "Would archive callback $($item.id) status=$status" }
        else { Move-Item -LiteralPath $file.FullName -Destination $dest -Force; Write-Host "Archived callback $($item.id) status=$status" }
        $count++
    }
    Write-Host "Archived callbacks: $count"
}

function Get-AgentPoolDefinitions {
    return @(
        [pscustomobject]@{ type = "engineering-leader"; agent = "opencode/engineering-leader"; model = "MoreCode/gpt-5.5"; max_concurrency = 2 },
        [pscustomobject]@{ type = "senior-builder"; agent = "opencode/senior-builder"; model = "MoreCode/gpt-5.5"; max_concurrency = 2 },
        [pscustomobject]@{ type = "middle-builder"; agent = "opencode/middle-builder"; model = "MoreCode/gpt-5.4"; max_concurrency = 3 },
        [pscustomobject]@{ type = "qa"; agent = "opencode/engineering-qa"; model = "MoreCode/gpt-5.4-pro"; max_concurrency = 1 },
        [pscustomobject]@{ type = "agent-creator"; agent = "opencode/engineering-agent-creator"; model = "MoreCode/gpt-5.4-pro"; max_concurrency = 1 }
    )
}

function Get-AgentSlotDefinitions {
    return Get-AgentPoolDefinitions
}

function Resolve-AgentType {
    param([string]$RequiredAgentType)
    $required = ([string]$RequiredAgentType).ToLowerInvariant()
    switch -Regex ($required) {
        "leader|engineering-leader|engineering_intake|implementation_plan|task_decomposition|delivery_prepare" { return "engineering-leader" }
        "senior|hard|technical_design|integration|code_build_hard" { return "senior-builder" }
        "middle|medium|maintenance|code_build_medium|builder" { return "middle-builder" }
        "qa|validation|review" { return "qa" }
        "agent-creator|agent_create|agent_update|agent" { return "agent-creator" }
        default { return "middle-builder" }
    }
}

function Get-AgentPoolForTask {
    param([object]$Meta)
    $requiredType = Resolve-AgentType -RequiredAgentType ([string](Get-ObjectPropertyValue -Object $Meta -Name "required_agent_type" -Default "middle-builder"))
    $pool = @(Get-AgentPoolDefinitions | Where-Object { $_.type -eq $requiredType } | Select-Object -First 1)
    if ($pool.Count -eq 0) { $pool = @(Get-AgentPoolDefinitions | Where-Object { $_.type -eq "middle-builder" } | Select-Object -First 1) }
    if ($pool.Count -eq 0) { return $null }
    $claimed = @(Get-Listings | Where-Object { $_.status -eq "claimed" })
    $active = 0
    foreach ($task in $claimed) {
        $taskType = Resolve-AgentType -RequiredAgentType ([string](Get-ObjectPropertyValue -Object $task -Name "required_agent_type" -Default "middle-builder"))
        if ($taskType -eq [string]$pool[0].type) { $active++ }
    }
    if ($active -ge [int]$pool[0].max_concurrency) { return $null }
    return $pool[0]
}

function Get-AgentSlotForTask {
    param([object]$Meta)
    return Get-AgentPoolForTask -Meta $Meta
}

function Repair-PublisherSessionForAgentRun {
    param(
        [string]$PublisherAgent,
        [string]$PublisherSession,
        [datetime]$Since
    )
    if ([string]::IsNullOrWhiteSpace($PublisherAgent) -or [string]::IsNullOrWhiteSpace($PublisherSession)) { return }
    Ensure-TaskHallState
    $patched = 0
    foreach ($row in @(Get-Listings)) {
        $created = Get-Date "2000-01-01"
        [DateTime]::TryParse([string](Get-ObjectPropertyValue -Object $row -Name "created_at" -Default ""), [ref]$created) | Out-Null
        if ($created -lt $Since.AddMinutes(-2)) { continue }
        if ([string](Get-ObjectPropertyValue -Object $row -Name "publisher_agent" -Default "") -ne $PublisherAgent) { continue }
        $existing = [string](Get-ObjectPropertyValue -Object $row -Name "publisher_session" -Default "")
        if (-not ([string]::IsNullOrWhiteSpace($existing) -or $existing -eq "unknown-session")) { continue }
        $taskId = [string]$row.id
        $meta = Load-TaskMeta -TaskId $taskId
        Set-ObjectPropertyValue -Object $meta -Name "publisher_session" -Value $PublisherSession
        Save-TaskMeta -Meta $meta
        Upsert-Listing -Meta $meta
        $link = Get-TaskLinkState -TaskId $taskId
        Set-ObjectPropertyValue -Object $link -Name "publisher_session" -Value $PublisherSession
        $link.updated_at = (Get-Date).ToString("o")
        Save-TaskLinkState -State $link
        Add-Event -Type "task.publisher_session_repaired" -TaskId $taskId -Data @{ publisher_agent = $PublisherAgent; publisher_session = $PublisherSession }
        $patched++
    }
    if ($patched -gt 0) { Write-Host "Repaired publisher session for $patched child task(s): $PublisherAgent session=$PublisherSession" }
}

function Get-AgentCliSessionIdFromOutput {
    param([string]$Output)
    foreach ($line in @($Output -split "\r?\n")) {
        if ($line -match '^sessionID:\s*(.+)$') { return $matches[1].Trim() }
    }
    return $null
}

function Get-TaskLastActivityTime {
    param([string]$TaskId)
    $times = New-Object System.Collections.Generic.List[datetime]
    $metaPath = Get-MetaPath -TaskId $TaskId
    if (Test-Path -LiteralPath $metaPath) { $times.Add((Get-Item -LiteralPath $metaPath).LastWriteTime) | Out-Null }
    $linkPath = Get-TaskLinkPath -TaskId $TaskId
    if (Test-Path -LiteralPath $linkPath) { $times.Add((Get-Item -LiteralPath $linkPath).LastWriteTime) | Out-Null }
    $taskDir = Get-TaskDir -TaskId $TaskId
    if (Test-Path -LiteralPath $taskDir) {
        foreach ($file in @(Get-ChildItem -LiteralPath $taskDir -File -ErrorAction SilentlyContinue)) { $times.Add($file.LastWriteTime) | Out-Null }
    }
    if ($times.Count -eq 0) { return Get-Date "2000-01-01" }
    return ($times | Sort-Object -Descending | Select-Object -First 1)
}

function Test-TaskHasActiveChildren {
    param([string]$TaskId)
    $activeChildren = @(Get-Listings | Where-Object { ([string](Get-ObjectPropertyValue -Object $_ -Name "parent_id" -Default "")) -eq $TaskId -and $_.status -notin @("done", "cancelled", "archived") })
    return ($activeChildren.Count -gt 0)
}

function Test-TaskLinkHasPublisherDecision {
    param([object]$Link)
    $status = [string](Get-ObjectPropertyValue -Object $Link -Name "status" -Default "")
    if ($status -in @("completed", "continued", "switched", "cancelled")) { return $true }
    if (Test-ObjectProperty -Object $Link -Name "completed_at") { return $true }
    if (Test-ObjectProperty -Object $Link -Name "continue_note") { return $true }
    $handoffs = @(Get-ObjectPropertyValue -Object $Link -Name "handoffs" -Default @())
    if ($handoffs.Count -gt 0) { return $true }
    return $false
}

function Invoke-RecoverWaitingPublishers {
    param([string[]]$InputArgs)
    $dryRun = (($InputArgs -join " ") -match "dry")
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--limit", "--stale-minutes", "--cwd", "--dry-run")
    Ensure-TaskHallState
    $limitRaw = Get-OptionValue -Args $InputArgs -Name "--limit" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "3")
    $limit = 3
    if (-not [int]::TryParse($limitRaw, [ref]$limit)) { Write-TaskHallError "Invalid limit '$limitRaw'." }
    $staleRaw = Get-OptionValue -Args $InputArgs -Name "--stale-minutes" -Default "1"
    $staleMinutes = 1
    if (-not [int]::TryParse($staleRaw, [ref]$staleMinutes)) { Write-TaskHallError "Invalid stale minutes '$staleRaw'." }
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    if ($dryRun) { Write-Host "Recover waiting-publisher dry-run enabled." }
    $processed = 0
    $linkFiles = @(Get-ChildItem -LiteralPath $script:TaskLinksRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($file in $linkFiles) {
        if ($processed -ge $limit) { break }
        $link = (Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json
        $taskId = [string](Get-ObjectPropertyValue -Object $link -Name "task_id" -Default "")
        if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
        $status = [string](Get-ObjectPropertyValue -Object $link -Name "status" -Default "")
        if ($status -ne "waiting_publisher") { continue }
        if (Test-TaskLinkHasPublisherDecision -Link $link) { continue }
        $reports = @(Get-ObjectPropertyValue -Object $link -Name "reports" -Default @())
        if ($reports.Count -eq 0) { continue }
        $last = Get-TaskLastActivityTime -TaskId $taskId
        $age = (New-TimeSpan -Start $last -End (Get-Date)).TotalMinutes
        if ($age -lt $staleMinutes) { continue }
        $meta = Load-TaskMeta -TaskId $taskId
        $publisherAgent = [string](Get-ObjectPropertyValue -Object $link -Name "publisher_agent" -Default (Get-ObjectPropertyValue -Object $meta -Name "publisher_agent" -Default ""))
        if ([string]::IsNullOrWhiteSpace($publisherAgent) -or $publisherAgent -like "system/*") { continue }
        $publisherSession = [string](Get-ObjectPropertyValue -Object $link -Name "publisher_session" -Default (Get-ObjectPropertyValue -Object $meta -Name "publisher_session" -Default ""))
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $latestReport = $reports | Select-Object -Last 1
        $reportPath = [string](Get-ObjectPropertyValue -Object $latestReport -Name "report_path" -Default "")
        $reportText = if (-not [string]::IsNullOrWhiteSpace($reportPath) -and (Test-Path -LiteralPath $reportPath)) { Read-Utf8Text -Path $reportPath } else { "" }
        $boundary = [guid]::NewGuid().ToString("N")
        $prompt = @"
你是 watched task 的发布者 agent。生命周期维护系统发现：执行 agent 已经通过 task-link report 汇报，但你尚未对该 task-link 做明确判断。

这不是执行 agent 未工作的问题；不要催执行 agent 重做。你必须作为发布者处理未决判断：

- 如果满足原任务验收标准：执行 `mycli task-hall task-link complete $taskId $publisherAgent "<验收结论>"`
- 如果还需要原执行 agent 继续：执行 `mycli task-hall task-link continue $taskId <executor-agent> "<明确继续指令>"`
- 如果执行 agent 不适合：执行 `mycli task-hall task-link switch-agent $taskId <new-agent-id> $publisherAgent "<交接说明>"`

处理后，如果你的上级任务也因此完成，你还需要按自己的上级 task-link report 规则补交或更新上级报告。

任务 ID：$taskId
任务目录：$($meta.task_dir)

任务 Markdown：
---TASK_BEGIN_$boundary---
$taskMarkdown
---TASK_END_$boundary---

task-link 状态：
---LINK_BEGIN_$boundary---
$($link | ConvertTo-Json -Depth 20)
---LINK_END_$boundary---

执行 agent 最新报告：
---REPORT_BEGIN_$boundary---
$reportText
---REPORT_END_$boundary---
"@
        if ($dryRun) {
            Write-Host "Would recover waiting publisher for task $taskId to $publisherAgent session=$publisherSession age=$([math]::Round($age, 1))m"
            $processed++
            continue
        }
        $output = Invoke-AgentCliRunText -Agent $publisherAgent -Prompt $prompt -Cwd $cwd -SessionName "task-hall-publisher-recover-$taskId" -SessionId $publisherSession
        $outPath = Join-Path $script:CallbackQueueRoot ("publisher-recover-{0}-{1}.output.txt" -f $taskId, (Get-Date -Format "yyyyMMdd_HHmmss"))
        Write-Utf8Text -Path $outPath -Content $output -EmitBom $false
        Set-ObjectPropertyValue -Object $link -Name "last_publisher_recover_output" -Value $outPath
        Set-ObjectPropertyValue -Object $link -Name "last_publisher_recovered_at" -Value (Get-Date).ToString("o")
        $link.updated_at = (Get-Date).ToString("o")
        Save-TaskLinkState -State $link
        Add-Event -Type "task_link.publisher_recovered" -TaskId $taskId -Data @{ agent = $publisherAgent; session = $publisherSession; output = $outPath }
        Write-Host "Recovered waiting publisher for task $taskId to $publisherAgent"
        $processed++
    }
    Write-Host "Recovered waiting publishers: $processed"
}

function Get-LifecycleSnapshot {
    Ensure-TaskHallState
    $listings = @(Get-Listings)
    $links = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $script:TaskLinksRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try { $links += ,((Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json) } catch {}
    }
    $callbacks = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $script:CallbackQueueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try { $callbacks += ,((Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json) } catch {}
    }
    $slots = @()
    foreach ($slot in @(Get-AgentPoolDefinitions)) {
        $tasks = @($listings | Where-Object { $_.status -eq "claimed" -and (Resolve-AgentType -RequiredAgentType ([string](Get-ObjectPropertyValue -Object $_ -Name "required_agent_type" -Default "middle-builder"))) -eq [string]$slot.type })
        $slots += [pscustomobject][ordered]@{
            type = $slot.type
            agent = $slot.agent
            model = $slot.model
            max_concurrency = $slot.max_concurrency
            active_count = $tasks.Count
            status = if ($tasks.Count -ge [int]$slot.max_concurrency) { "full" } elseif ($tasks.Count -gt 0) { "busy" } else { "idle" }
            task_ids = @($tasks | ForEach-Object { $_.id })
            tasks = @($tasks | Select-Object id, title, claimed_by, executor_session)
            last_activity = if ($tasks.Count -gt 0) { (($tasks | ForEach-Object { Get-TaskLastActivityTime -TaskId ([string]$_.id) }) | Sort-Object -Descending | Select-Object -First 1).ToString("o") } else { $null }
        }
    }
    return [pscustomobject][ordered]@{
        generated_at = (Get-Date).ToString("o")
        state_root = $script:StateRoot
        counts = [ordered]@{
            listed = @($listings | Where-Object { $_.status -eq "listed" }).Count
            claimed = @($listings | Where-Object { $_.status -eq "claimed" }).Count
            done = @($listings | Where-Object { $_.status -eq "done" }).Count
            pending_callbacks = @($callbacks | Where-Object { $_.status -eq "pending" }).Count
            active_links = @($links | Where-Object { $_.status -notin @("completed", "cancelled") }).Count
        }
        agents = $slots
        tasks = $listings
        task_links = $links
        callbacks = $callbacks
    }
}

function New-TaskId {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 6)
    return "task_${stamp}_${suffix}"
}

function Get-TaskDir {
    param([string]$TaskId)
    return (Join-Path $script:TasksRoot $TaskId)
}

function Get-MetaPath {
    param([string]$TaskId)
    return (Join-Path (Get-TaskDir -TaskId $TaskId) "meta.json")
}

function Get-ClaimsPath {
    param([string]$TaskId)
    return (Join-Path (Get-TaskDir -TaskId $TaskId) "claims.jsonl")
}

function Get-SubmissionsPath {
    param([string]$TaskId)
    return (Join-Path (Get-TaskDir -TaskId $TaskId) "submissions.jsonl")
}

function Load-TaskMeta {
    param([string]$TaskId)
    $path = Get-MetaPath -TaskId $TaskId
    if (-not (Test-Path -LiteralPath $path)) {
        Write-TaskHallError "Task '$TaskId' not found."
    }
    try {
        return (Read-Utf8Text -Path $path) | ConvertFrom-Json
    } catch {
        Write-TaskHallError "Failed to parse task meta for '$TaskId'. $($_.Exception.Message)"
    }
}

function Save-TaskMeta {
    param([object]$Meta)
    $path = Get-MetaPath -TaskId ([string]$Meta.id)
    $json = $Meta | ConvertTo-Json -Depth 10
    Write-Utf8Text -Path $path -Content ($json + "`r`n")
}

function Upsert-Listing {
    param([object]$Meta)
    $listings = @(Get-Listings)
    $kept = @($listings | Where-Object { $_.id -ne $Meta.id })
    $row = [ordered]@{
        id = [string]$Meta.id
        title = [string]$Meta.title
        kind = [string]$Meta.kind
        status = [string]$Meta.status
        priority = [int]$Meta.priority
        tags = @($Meta.tags)
        created_at = [string]$Meta.created_at
        listed_at = if ($Meta.PSObject.Properties.Name -contains 'listed_at') { $Meta.listed_at } else { $null }
        claimed_by = if ($Meta.PSObject.Properties.Name -contains 'claimed_by') { $Meta.claimed_by } else { $null }
        publish_mode = if ($Meta.PSObject.Properties.Name -contains 'publish_mode') { $Meta.publish_mode } else { "detached" }
        publisher_agent = if ($Meta.PSObject.Properties.Name -contains 'publisher_agent') { $Meta.publisher_agent } else { $null }
        publisher_session = if ($Meta.PSObject.Properties.Name -contains 'publisher_session') { $Meta.publisher_session } else { $null }
        required_agent_type = if ($Meta.PSObject.Properties.Name -contains 'required_agent_type') { $Meta.required_agent_type } else { $null }
        parent_id = if ($Meta.PSObject.Properties.Name -contains 'parent_id') { $Meta.parent_id } else { $null }
        child_ids = if ($Meta.PSObject.Properties.Name -contains 'child_ids') { @($Meta.child_ids) } else { @() }
        watchers = if ($Meta.PSObject.Properties.Name -contains 'watchers') { @($Meta.watchers) } else { @() }
        task_dir = [string]$Meta.task_dir
    }
    Save-Listings -Listings @($kept + [pscustomobject]$row)
}

function Remove-Listing {
    param([string]$TaskId)
    $listings = @(Get-Listings | Where-Object { $_.id -ne $TaskId })
    Save-Listings -Listings $listings
}

function Get-OptionValue {
    param(
        [string[]]$Args,
        [string]$Name,
        [string]$Default = $null
    )
    $normalized = @($Args | ForEach-Object { [string]$_ })
    for ($i = 0; $i -lt $normalized.Count; $i++) {
        $plain = $Name.TrimStart('-')
        $value = $normalized[$i]
        if ($value -eq $Name -or $value -eq $plain -or $value -eq ("--%{0}" -f $plain)) {
            if ($i + 1 -ge $normalized.Count) {
                Write-TaskHallError "Missing value for option '$Name'."
            }
            return $normalized[$i + 1]
        }
        if ($value -like "--%$plain=*" -or $value -like "$plain=*") {
            return (($value -split "=", 2)[1])
        }
    }
    return $Default
}

function Get-OptionValues {
    param(
        [string[]]$Args,
        [string]$Name
    )
    $values = New-Object System.Collections.Generic.List[string]
    $normalized = @($Args | ForEach-Object { [string]$_ })
    for ($i = 0; $i -lt $normalized.Count; $i++) {
        $plain = $Name.TrimStart('-')
        $value = $normalized[$i]
        if ($value -eq $Name -or $value -eq $plain -or $value -eq ("--%{0}" -f $plain)) {
            if ($i + 1 -ge $normalized.Count) {
                Write-TaskHallError "Missing value for option '$Name'."
            }
            $values.Add($normalized[$i + 1])
        } elseif ($value -like "--%$plain=*" -or $value -like "$plain=*") {
            $values.Add(($value -split "=", 2)[1])
        }
    }
    return @($values)
}

function Test-Flag {
    param(
        [string[]]$Args,
        [string]$Name
    )
    $plain = $Name.TrimStart('-')
    $normalized = @($Args | ForEach-Object { [string]$_ })
    foreach ($value in $normalized) {
        if ($value -eq $Name -or $value -eq $plain -or $value -eq ("--%{0}" -f $plain)) { return $true }
        if ($value.TrimStart('-') -eq $plain) { return $true }
    }
    return $false
}

function Get-PositionalArg {
    param(
        [string[]]$InputArgs,
        [int]$Index,
        [object]$Default = $null
    )
    if ($InputArgs.Count -gt $Index -and -not $InputArgs[$Index].StartsWith("--")) {
        return $InputArgs[$Index]
    }
    return $Default
}

function Assert-NoUnknownOptions {
    param(
        [string[]]$Args,
        [string[]]$Allowed
    )
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $value = $Args[$i]
        if ($value.StartsWith("--") -and ($Allowed -notcontains $value)) {
            Write-TaskHallError "Unknown option '$value'."
        }
    }
}

function Get-MarkdownTitle {
    param([string]$MarkdownPath)
    $content = Read-Utf8Text -Path $MarkdownPath
    foreach ($line in @($content -split "\r?\n")) {
        if ($line -match '^#\s+(.+)$') {
            return $matches[1].Trim()
        }
    }
    return (Split-Path -LeafBase $MarkdownPath)
}

function Set-TaskStatus {
    param(
        [string]$TaskId,
        [string]$Status,
        [hashtable]$Extra = @{}
    )
    $meta = Load-TaskMeta -TaskId $TaskId
    $old = [string]$meta.status
    $meta.status = $Status
    $meta.updated_at = (Get-Date).ToString("o")
    foreach ($key in $Extra.Keys) {
        $meta | Add-Member -NotePropertyName $key -NotePropertyValue $Extra[$key] -Force
    }
    Save-TaskMeta -Meta $meta
    if ($Status -eq "archived") {
        Remove-Listing -TaskId $TaskId
    } else {
        Upsert-Listing -Meta $meta
    }
    Add-Event -Type "task.status_changed" -TaskId $TaskId -Data @{ old = $old; new = $Status }
    return $meta
}

function Add-ClaimEvent {
    param(
        [string]$TaskId,
        [string]$Action,
        [string]$Agent,
        [string]$Result = $null
    )
    $record = [ordered]@{
        ts = (Get-Date).ToString("o")
        action = $Action
        agent = $Agent
        result = $Result
    }
    $line = $record | ConvertTo-Json -Compress -Depth 10
    [System.IO.File]::AppendAllText((Get-ClaimsPath -TaskId $TaskId), $line + "`n", $script:Utf8NoBom)
}

function Add-SubmissionEvent {
    param(
        [string]$TaskId,
        [string]$Status,
        [string]$Agent,
        [string]$Note = ""
    )
    $record = [ordered]@{
        ts = (Get-Date).ToString("o")
        status = $Status
        agent = $Agent
        note = $Note
    }
    $line = $record | ConvertTo-Json -Compress -Depth 10
    [System.IO.File]::AppendAllText((Get-SubmissionsPath -TaskId $TaskId), $line + "`n", $script:Utf8NoBom)
}

function Invoke-Init {
    Ensure-TaskHallState
    Write-Host "Task hall initialized: $script:StateRoot"
}

function Invoke-Upload {
    param(
        [string[]]$InputArgs,
        [bool]$PublishNow = $false
    )
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall upload <task.md> [--title <title>] [--kind scheduled|triggered|custom] [--priority <n>] [--tag <tag>] [--publish]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--title", "--kind", "--priority", "--tag", "--publish")
    $source = $InputArgs[0]
    if (-not (Test-Path -LiteralPath $source)) { Write-TaskHallError "Task markdown not found: '$source'." }
    $item = Get-Item -LiteralPath $source
    if ($item.PSIsContainer) { Write-TaskHallError "Task markdown path must be a file: '$source'." }

    $kindDefault = Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "custom"
    $kind = Get-OptionValue -Args $InputArgs -Name "--kind" -Default $kindDefault
    if ($kind -notin @("scheduled", "triggered", "custom")) { Write-TaskHallError "Invalid kind '$kind'. Use scheduled, triggered, or custom." }
    $titleDefault = Get-PositionalArg -InputArgs $InputArgs -Index 4 -Default (Get-MarkdownTitle -MarkdownPath $source)
    $priorityDefault = Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default "50"
    $title = Get-OptionValue -Args $InputArgs -Name "--title" -Default $titleDefault
    $priorityRaw = Get-OptionValue -Args $InputArgs -Name "--priority" -Default $priorityDefault
    $priority = 50
    if (-not [int]::TryParse($priorityRaw, [ref]$priority)) { Write-TaskHallError "Invalid priority '$priorityRaw'." }
    $tags = @(Get-OptionValues -Args $InputArgs -Name "--tag")
    if ($tags.Count -eq 0 -and $null -ne (Get-PositionalArg -InputArgs $InputArgs -Index 3)) {
        $tags = @($InputArgs[3] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $publish = $PublishNow -or (Test-Flag -Args $InputArgs -Name "--publish")

    Ensure-TaskHallState
    $taskId = New-TaskId
    $taskDir = Get-TaskDir -TaskId $taskId
    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $taskDir "task.md") -Force
    Write-Utf8Text -Path (Join-Path $taskDir "claims.jsonl") -Content "" -EmitBom $false
    Write-Utf8Text -Path (Join-Path $taskDir "submissions.jsonl") -Content "" -EmitBom $false

    $now = (Get-Date).ToString("o")
    $status = if ($publish) { "listed" } else { "draft" }
    $meta = [ordered]@{
        id = $taskId
        title = $title
        kind = $kind
        status = $status
        priority = $priority
        tags = $tags
        created_at = $now
        updated_at = $now
        listed_at = if ($publish) { $now } else { $null }
        claimed_by = $null
        task_md = "task.md"
        task_dir = $taskDir
        source_md = $item.FullName
        publish_mode = "detached"
        publisher_agent = $null
        publisher_session = $null
        required_agent_type = $null
        parent_id = $null
        child_ids = @()
        watchers = @()
        task_link = (Get-TaskLinkPath -TaskId $taskId)
    }
    Save-TaskMeta -Meta ([pscustomobject]$meta)
    Upsert-Listing -Meta ([pscustomobject]$meta)
    Add-Event -Type "task.uploaded" -TaskId $taskId -Data @{ status = $status; kind = $kind; title = $title }
    if ($publish) {
        Add-Event -Type "task.published" -TaskId $taskId -Data @{}
        Invoke-TaskHallLifecycleWake -Reason "task.published" -TaskId $taskId
    }
    Write-Host "Uploaded task: $taskId"
    Write-Host "Status: $status"
}

function Invoke-PublishRaw {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall publish-raw <task.md> [--title <title>] [--kind scheduled|triggered|custom] [--priority <n>] [--tag <tag>] [--draft] [--publish-mode watched|detached] [--publisher-agent <agent>] [--publisher-session <session>] [--required-agent-type <type>]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--title", "--kind", "--priority", "--tag", "--draft", "--publish-mode", "--publisher-agent", "--publisher-session", "--required-agent-type")
    $source = $InputArgs[0]
    if (-not (Test-Path -LiteralPath $source)) { Write-TaskHallError "Task markdown not found: '$source'." }
    $item = Get-Item -LiteralPath $source
    if ($item.PSIsContainer) { Write-TaskHallError "Task markdown path must be a file: '$source'." }
    $kind = Get-OptionValue -Args $InputArgs -Name "--kind" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "custom")
    if ($kind -notin @("scheduled", "triggered", "trigger", "custom")) { Write-TaskHallError "Invalid kind '$kind'. Use scheduled, triggered, or custom." }
    if ($kind -eq "trigger") { $kind = "triggered" }
    $priorityRaw = Get-OptionValue -Args $InputArgs -Name "--priority" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default "50")
    $priority = 50
    if (-not [int]::TryParse($priorityRaw, [ref]$priority)) { Write-TaskHallError "Invalid priority '$priorityRaw'." }
    $tags = @(Get-OptionValues -Args $InputArgs -Name "--tag")
    if ($tags.Count -eq 0 -and $null -ne (Get-PositionalArg -InputArgs $InputArgs -Index 3)) {
        $tags = @($InputArgs[3] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $title = Get-OptionValue -Args $InputArgs -Name "--title" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 4 -Default (Get-MarkdownTitle -MarkdownPath $source))
    $publishMode = Get-OptionValue -Args $InputArgs -Name "--publish-mode" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 5 -Default "watched")
    if ($publishMode -notin @("watched", "detached")) { Write-TaskHallError "Invalid publish mode '$publishMode'. Use watched or detached." }
    $publisherAgent = Get-OptionValue -Args $InputArgs -Name "--publisher-agent" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 6 -Default $null)
    $publisherSession = Get-OptionValue -Args $InputArgs -Name "--publisher-session" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 7 -Default $null)
    $requiredAgentType = Get-OptionValue -Args $InputArgs -Name "--required-agent-type" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 8 -Default $null)
    $publish = -not (Test-Flag -Args $InputArgs -Name "--draft")
    $extra = @{
        source_md = $item.FullName
        publish_mode = $publishMode
        publisher_agent = $publisherAgent
        publisher_session = $publisherSession
        required_agent_type = $requiredAgentType
    }
    $meta = New-TaskFromMarkdownContent -Markdown (Read-Utf8Text -Path $item.FullName) -Kind $kind -Priority $priority -Tags $tags -Title $title -Publish $publish -Extra $extra
    $link = Get-TaskLinkState -TaskId ([string]$meta.id)
    $link.publish_mode = $publishMode
    $link.publisher_agent = $publisherAgent
    $link.publisher_session = $publisherSession
    $link.updated_at = (Get-Date).ToString("o")
    Save-TaskLinkState -State $link
    Add-Event -Type "task.raw_published" -TaskId ([string]$meta.id) -Data @{ publish_mode = $publishMode; required_agent_type = $requiredAgentType }
    if ($publish) { Invoke-TaskHallLifecycleWake -Reason "task.raw_published" -TaskId ([string]$meta.id) }
    Write-Host "Raw task published: $($meta.id)"
    Write-Host "Status: $($meta.status)"
    Write-Host "Publish mode: $publishMode"
}

function Invoke-SubmitRequest {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall submit-request <request.json> [--draft] [--agent <frontdesk-agent>] [--priority <n>] [--tag <tag>]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--publish", "--draft", "--agent", "--priority", "--tag")
    $requestPath = $InputArgs[0]
    if (-not (Test-Path -LiteralPath $requestPath)) { Write-TaskHallError "Task request JSON not found: '$requestPath'." }
    $item = Get-Item -LiteralPath $requestPath
    if ($item.PSIsContainer) { Write-TaskHallError "Task request path must be a file: '$requestPath'." }
    $request = Read-JsonFileAsHashtable -Path $item.FullName
    $frontdeskAgent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default "opencode/task-hall-frontdesk"
    $publish = -not (Test-Flag -Args $InputArgs -Name "--draft")
    $priorityRaw = Get-OptionValue -Args $InputArgs -Name "--priority" -Default ""
    $overridePriority = $null
    if (-not [string]::IsNullOrWhiteSpace($priorityRaw)) {
        $parsedPriority = 50
        if (-not [int]::TryParse($priorityRaw, [ref]$parsedPriority)) { Write-TaskHallError "Invalid priority '$priorityRaw'." }
        $overridePriority = $parsedPriority
    }
    $overrideTags = @(Get-OptionValues -Args $InputArgs -Name "--tag")

    Ensure-TaskHallState
    $requestId = New-RequestId
    $requestDir = Get-RequestDir -RequestId $requestId
    New-Item -ItemType Directory -Path $requestDir -Force | Out-Null
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $requestDir "request.json") -Force

    $requestJson = $request | ConvertTo-Json -Depth 20
    $prompt = @"
你是 task-hall 前台 agent。请按照你的 frontdesk-v0.2 准则审核下面的任务请求 JSON。

要求：
- 只输出一个 JSON 对象，不要输出 Markdown 围栏，不要输出解释性前后缀。
- 如果请求不完整或不可接受，输出 accepted=false，并包含 reason、missing_information、request_resubmission、suggested_request_patch。
- 如果请求可接受且完整，输出 accepted=true、complexity、min_model_tier、task_markdown。
- task_markdown 必须包含“## 领取门槛”。

任务请求 JSON：
$requestJson
"@

    Write-Host "Submitting request to frontdesk agent: $frontdeskAgent"
    $agentOutput = Invoke-AgentCliRunText -Agent $frontdeskAgent -Prompt $prompt -SessionName "task-hall-frontdesk-$requestId"
    Write-Utf8Text -Path (Join-Path $requestDir "frontdesk.raw.txt") -Content $agentOutput -EmitBom $false
    $review = Get-JsonObjectFromAgentOutput -Output $agentOutput
    Write-Utf8Text -Path (Join-Path $requestDir "frontdesk-response.json") -Content (($review | ConvertTo-Json -Depth 20) + "`r`n")

    if (-not $review.ContainsKey("accepted") -or -not [bool]$review["accepted"]) {
        Write-Host "Request rejected by frontdesk: $requestId"
        if ($review.ContainsKey("reason")) { Write-Host "Reason: $($review["reason"])" }
        Write-Host "Frontdesk response: $(Join-Path $requestDir "frontdesk-response.json")"
        Add-Event -Type "request.rejected" -TaskId $requestId -Data @{ request_dir = $requestDir }
        return
    }
    if (-not $review.ContainsKey("task_markdown") -or [string]::IsNullOrWhiteSpace([string]$review["task_markdown"])) {
        Write-TaskHallError "Frontdesk accepted request but did not return task_markdown. Response: $(Join-Path $requestDir "frontdesk-response.json")"
    }

    $kind = if ($request.ContainsKey("request_type")) { [string]$request["request_type"] } else { "custom" }
    if ($kind -eq "triggered") { $kind = "trigger" }
    if ($kind -notin @("scheduled", "trigger", "custom")) { $kind = "custom" }
    $priority = if ($null -ne $overridePriority) { [int]$overridePriority } elseif ($request.ContainsKey("priority")) { [int]$request["priority"] } else { 50 }
    $tags = if ($overrideTags.Count -gt 0) { $overrideTags } elseif ($request.ContainsKey("tags")) { @($request["tags"]) } else { @() }
    $title = if ($request.ContainsKey("title") -and -not [string]::IsNullOrWhiteSpace([string]$request["title"])) { [string]$request["title"] } else { "Task from request $requestId" }

    $meta = New-TaskFromMarkdownContent -Markdown ([string]$review["task_markdown"]) -Kind $kind -Priority $priority -Tags $tags -Title $title -Publish $publish -Extra @{ source_request_id = $requestId; source_request_json = $item.FullName; frontdesk_response = (Join-Path $requestDir "frontdesk-response.json"); frontdesk_agent = $frontdeskAgent; complexity = if ($review.ContainsKey("complexity")) { $review["complexity"] } else { $null }; min_model_tier = if ($review.ContainsKey("min_model_tier")) { $review["min_model_tier"] } else { $null } }
    Add-Event -Type "request.accepted" -TaskId ([string]$meta.id) -Data @{ request_id = $requestId; request_dir = $requestDir; frontdesk_agent = $frontdeskAgent }
    if ($publish) { Invoke-TaskHallLifecycleWake -Reason "request.accepted" -TaskId ([string]$meta.id) }
    Write-Host "Request accepted: $requestId"
    Write-Host "Created task: $($meta.id)"
    Write-Host "Status: $($meta.status)"
    Write-Host "Task dir: $($meta.task_dir)"
}

function Invoke-Publish {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall publish <task-id>" }
    $meta = Load-TaskMeta -TaskId $InputArgs[0]
    if ($meta.status -eq "archived") { Write-TaskHallError "Archived task cannot be published." }
    if ($meta.status -eq "done") { Write-TaskHallError "Done task cannot be published." }
    if ($meta.status -eq "cancelled") { Write-TaskHallError "Cancelled task cannot be published." }
    $now = (Get-Date).ToString("o")
    Set-TaskStatus -TaskId $InputArgs[0] -Status "listed" -Extra @{ listed_at = $now; claimed_by = $null } | Out-Null
    Add-Event -Type "task.published" -TaskId $InputArgs[0] -Data @{}
    Invoke-TaskHallLifecycleWake -Reason "task.published" -TaskId $InputArgs[0]
    Write-Host "Published task: $($InputArgs[0])"
}

function Invoke-Tasks {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--status", "--kind", "--tag", "--json", "--all")
    $statusDefault = Get-PositionalArg -InputArgs $InputArgs -Index 0
    if ($statusDefault -eq "all") { $statusDefault = $null }
    $status = Get-OptionValue -Args $InputArgs -Name "--status" -Default $statusDefault
    $kind = Get-OptionValue -Args $InputArgs -Name "--kind" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 1)
    $tag = Get-OptionValue -Args $InputArgs -Name "--tag" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2)
    $json = (Test-Flag -Args $InputArgs -Name "--json") -or ($InputArgs -contains "json") -or ($InputArgs -contains "--json")
    $all = (Test-Flag -Args $InputArgs -Name "--all") -or ($InputArgs -contains "all")
    $items = @(Get-Listings)
    if (-not $all -and -not $status) { $items = @($items | Where-Object { $_.status -eq "listed" }) }
    elseif (-not $all) { $items = @($items | Where-Object { $_.status -ne "archived" }) }
    if ($status) { $items = @($items | Where-Object { $_.status -eq $status }) }
    if ($kind) { $items = @($items | Where-Object { $_.kind -eq $kind }) }
    if ($tag) { $items = @($items | Where-Object { @($_.tags) -contains $tag }) }
    $items = @($items | Sort-Object @{ Expression = "priority"; Descending = $true }, created_at)
    if ($json) {
        $items | ConvertTo-Json -Depth 10
        return
    }
    if ($items.Count -eq 0) {
        Write-Host "No tasks."
        return
    }
    $items | Select-Object id, status, kind, priority, title, claimed_by | Format-Table -AutoSize
}

function Invoke-Edit {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall edit <task-id> [title] [kind] [priority] [tagsCsv] [task.md]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--title", "--kind", "--priority", "--tag", "--task-md")
    $taskId = $InputArgs[0]
    $meta = Load-TaskMeta -TaskId $taskId

    $title = Get-OptionValue -Args $InputArgs -Name "--title" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 1)
    $kind = Get-OptionValue -Args $InputArgs -Name "--kind" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2)
    $priorityRaw = Get-OptionValue -Args $InputArgs -Name "--priority" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 3)
    $taskMd = Get-OptionValue -Args $InputArgs -Name "--task-md" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 5)
    $tags = @(Get-OptionValues -Args $InputArgs -Name "--tag")
    $tagsCsv = Get-PositionalArg -InputArgs $InputArgs -Index 4
    if ($tags.Count -eq 0 -and $null -ne $tagsCsv) {
        $tags = @($tagsCsv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    if ($title) { $meta.title = $title }
    if ($kind) {
        if ($kind -notin @("scheduled", "triggered", "custom")) { Write-TaskHallError "Invalid kind '$kind'. Use scheduled, triggered, or custom." }
        $meta.kind = $kind
    }
    if ($priorityRaw) {
        $priority = 50
        if (-not [int]::TryParse($priorityRaw, [ref]$priority)) { Write-TaskHallError "Invalid priority '$priorityRaw'." }
        $meta.priority = $priority
    }
    if ($tags.Count -gt 0) { $meta.tags = $tags }
    if ($taskMd) {
        if (-not (Test-Path -LiteralPath $taskMd)) { Write-TaskHallError "Task markdown not found: '$taskMd'." }
        $item = Get-Item -LiteralPath $taskMd
        if ($item.PSIsContainer) { Write-TaskHallError "Task markdown path must be a file: '$taskMd'." }
        Copy-Item -LiteralPath $taskMd -Destination (Join-Path ([string]$meta.task_dir) "task.md") -Force
        $meta.source_md = $item.FullName
    }

    $meta.updated_at = (Get-Date).ToString("o")
    Save-TaskMeta -Meta $meta
    if ($meta.status -ne "archived") { Upsert-Listing -Meta $meta }
    Add-Event -Type "task.edited" -TaskId $taskId -Data @{}
    Write-Host "Edited task: $taskId"
}

function Invoke-Show {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall show <task-id>" }
    $meta = Load-TaskMeta -TaskId $InputArgs[0]
    Write-Host "# $($meta.title)"
    Write-Host ""
    Write-Host "id: $($meta.id)"
    Write-Host "kind: $($meta.kind)"
    Write-Host "status: $($meta.status)"
    Write-Host "priority: $($meta.priority)"
    Write-Host "tags: $(@($meta.tags) -join ', ')"
    Write-Host "claimed_by: $($meta.claimed_by)"
    Write-Host "task_dir: $($meta.task_dir)"
    Write-Host ""
    Write-Host "--- task.md ---"
    Write-Host (Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md"))
}

function Invoke-Claim {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall claim <task-id> --agent <agent-id> [--claim-json <claim.json>] [--model <model-id>] [--model-tier <tier>] [--reason <text>] [--frontdesk-agent <agent>] [--no-frontdesk]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--agent", "--claim-json", "--model", "--model-tier", "--reason", "--frontdesk-agent", "--no-frontdesk")
    $agentDefault = Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "unknown-agent"
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default $agentDefault
    $taskId = $InputArgs[0]
    $meta = Load-TaskMeta -TaskId $taskId
    if ($meta.status -ne "listed") { Write-TaskHallError "Only listed tasks can be claimed. Current status: $($meta.status)." }
    $useFrontdesk = -not (($InputArgs -contains "--no-frontdesk") -or ($InputArgs -contains "no-frontdesk"))
    if ($useFrontdesk) {
        $frontdeskAgent = Get-OptionValue -Args $InputArgs -Name "--frontdesk-agent" -Default "opencode/task-hall-frontdesk"
        $claimJsonDefault = Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default ""
        if (-not [string]::IsNullOrWhiteSpace($claimJsonDefault) -and -not $claimJsonDefault.EndsWith(".json", [System.StringComparison]::OrdinalIgnoreCase)) { $claimJsonDefault = "" }
        $claimJsonPath = Get-OptionValue -Args $InputArgs -Name "--claim-json" -Default $claimJsonDefault
        if (-not [string]::IsNullOrWhiteSpace($claimJsonPath)) {
            if (-not (Test-Path -LiteralPath $claimJsonPath)) { Write-TaskHallError "Claim JSON not found: '$claimJsonPath'." }
            $claimRequest = Read-JsonFileAsHashtable -Path $claimJsonPath
        } else {
            $modelTierDefault = Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default ""
            $modelDefault = Get-PositionalArg -InputArgs $InputArgs -Index 3 -Default ""
            $reasonDefault = Get-PositionalArg -InputArgs $InputArgs -Index 4 -Default ""
            $model = Get-OptionValue -Args $InputArgs -Name "--model" -Default $modelDefault
            $modelTier = Get-OptionValue -Args $InputArgs -Name "--model-tier" -Default $modelTierDefault
            $reason = Get-OptionValue -Args $InputArgs -Name "--reason" -Default $reasonDefault
            if ([string]::IsNullOrWhiteSpace($modelTier)) { Write-TaskHallError "Frontdesk claim review requires --model-tier or --claim-json. Use --no-frontdesk to bypass manually." }
            $claimRequest = [ordered]@{
                task_id = $taskId
                agent_id = $agent
                model = $model
                model_tier = $modelTier
                claim_reason = $reason
            }
        }
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $claimJson = $claimRequest | ConvertTo-Json -Depth 20
        $prompt = @"
你是 task-hall 前台 agent。请按照你的 frontdesk-v0.2 准则审核下面的领取申请。

要求：
- 只输出一个 JSON 对象，不要输出 Markdown 围栏，不要输出解释性前后缀。
- 根据任务 Markdown 的“## 领取门槛”和领取申请 JSON 的 model_tier 判断是否允许领取。
- skill 不作为硬性拒绝条件。
- 输出 allowed、reason、required_tier、agent_tier。

任务 Markdown：
---TASK_MARKDOWN_BEGIN---
$taskMarkdown
---TASK_MARKDOWN_END---

领取申请 JSON：
$claimJson
"@
        Write-Host "Reviewing claim with frontdesk agent: $frontdeskAgent"
        $agentOutput = Invoke-AgentCliRunText -Agent $frontdeskAgent -Prompt $prompt -SessionName "task-hall-claim-$taskId"
        $claimReview = Get-JsonObjectFromAgentOutput -Output $agentOutput
        $reviewPath = Join-Path ([string]$meta.task_dir) ("claim-review-{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Write-Utf8Text -Path $reviewPath -Content (($claimReview | ConvertTo-Json -Depth 20) + "`r`n")
        if (-not $claimReview.ContainsKey("allowed") -or -not [bool]$claimReview["allowed"]) {
            $claimReviewReason = if ($claimReview.ContainsKey("reason")) { [string]$claimReview["reason"] } else { "frontdesk rejected" }
            Add-ClaimEvent -TaskId $taskId -Action "claim_rejected" -Agent $agent -Result $claimReviewReason
            Add-Event -Type "task.claim_rejected" -TaskId $taskId -Data @{ agent = $agent; review = $reviewPath }
            Write-Host "Claim rejected by frontdesk: $taskId"
            if ($claimReview.ContainsKey("reason")) { Write-Host "Reason: $($claimReview["reason"])" }
            Write-Host "Review: $reviewPath"
            return
        }
        $claimReviewReason = if ($claimReview.ContainsKey("reason")) { [string]$claimReview["reason"] } else { "frontdesk approved" }
        Add-ClaimEvent -TaskId $taskId -Action "claim_approved" -Agent $agent -Result $claimReviewReason
        Add-Event -Type "task.claim_approved" -TaskId $taskId -Data @{ agent = $agent; review = $reviewPath }
    }
    Set-TaskStatus -TaskId $taskId -Status "claimed" -Extra @{ claimed_by = $agent; claimed_at = (Get-Date).ToString("o") } | Out-Null
    Add-ClaimEvent -TaskId $taskId -Action "claimed" -Agent $agent
    Add-Event -Type "task.claimed" -TaskId $taskId -Data @{ agent = $agent }
    Write-Host "Claimed task: $taskId by $agent"
}

function Invoke-Release {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall release <task-id> --agent <agent-id>" }
    $agentDefault = Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "unknown-agent"
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default $agentDefault
    $meta = Load-TaskMeta -TaskId $InputArgs[0]
    if ($meta.status -ne "claimed") { Write-TaskHallError "Only claimed tasks can be released. Current status: $($meta.status)." }
    Set-TaskStatus -TaskId $InputArgs[0] -Status "listed" -Extra @{ claimed_by = $null } | Out-Null
    Add-ClaimEvent -TaskId $InputArgs[0] -Action "released" -Agent $agent
    Add-Event -Type "task.released" -TaskId $InputArgs[0] -Data @{ agent = $agent }
    Write-Host "Released task: $($InputArgs[0])"
}

function Invoke-Done {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall done <task-id> --agent <agent-id> [--result <text-or-path>]" }
    $agentDefault = Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "unknown-agent"
    $resultDefault = Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default ""
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default $agentDefault
    $result = Get-OptionValue -Args $InputArgs -Name "--result" -Default $resultDefault
    $meta = Load-TaskMeta -TaskId $InputArgs[0]
    if ($meta.status -notin @("claimed", "listed")) { Write-TaskHallError "Only listed or claimed tasks can be marked done. Current status: $($meta.status)." }
    Set-TaskStatus -TaskId $InputArgs[0] -Status "done" -Extra @{ done_by = $agent; done_at = (Get-Date).ToString("o"); result = $result } | Out-Null
    Add-ClaimEvent -TaskId $InputArgs[0] -Action "done" -Agent $agent -Result $result
    Add-Event -Type "task.done" -TaskId $InputArgs[0] -Data @{ agent = $agent; result = $result }
    Write-Host "Done task: $($InputArgs[0])"
}

function Invoke-Submit {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 2) { Write-TaskHallError "Usage: task-hall submit <task-id> <success|fail> [agent-id] [note]" }
    $taskId = $InputArgs[0]
    $resultStatus = $InputArgs[1]
    if ($resultStatus -notin @("success", "succeeded", "done", "ok", "fail", "failed", "failure")) {
        Write-TaskHallError "Submit result must be success or fail."
    }
    $agentDefault = Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default "unknown-agent"
    $noteDefault = Get-PositionalArg -InputArgs $InputArgs -Index 3 -Default ""
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default $agentDefault
    $note = Get-OptionValue -Args $InputArgs -Name "--note" -Default $noteDefault
    $meta = Load-TaskMeta -TaskId $taskId
    if ($meta.status -notin @("claimed", "listed")) { Write-TaskHallError "Only listed or claimed tasks can receive submissions. Current status: $($meta.status)." }

    if ($resultStatus -in @("success", "succeeded", "done", "ok")) {
        Set-TaskStatus -TaskId $taskId -Status "done" -Extra @{ done_by = $agent; done_at = (Get-Date).ToString("o"); result = $note } | Out-Null
        Add-SubmissionEvent -TaskId $taskId -Status "success" -Agent $agent -Note $note
        Add-ClaimEvent -TaskId $taskId -Action "submit_success" -Agent $agent -Result $note
        Add-Event -Type "task.submit_success" -TaskId $taskId -Data @{ agent = $agent; note = $note }
        Write-Host "Submitted success: $taskId"
        return
    }

    Set-TaskStatus -TaskId $taskId -Status "listed" -Extra @{ claimed_by = $null; last_failed_by = $agent; last_failed_at = (Get-Date).ToString("o"); last_failure_note = $note } | Out-Null
    Add-SubmissionEvent -TaskId $taskId -Status "fail" -Agent $agent -Note $note
    Add-ClaimEvent -TaskId $taskId -Action "submit_fail_relisted" -Agent $agent -Result $note
    Add-Event -Type "task.submit_fail_relisted" -TaskId $taskId -Data @{ agent = $agent; note = $note }
    Write-Host "Submitted failure and relisted: $taskId"
}

function Invoke-ReviewSubmission {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 2) { Write-TaskHallError "Usage: task-hall review-submission <task-id> <report.md> [--agent <reviewer-agent>]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--agent")
    $taskId = $InputArgs[0]
    $reportPath = $InputArgs[1]
    if (-not (Test-Path -LiteralPath $reportPath)) { Write-TaskHallError "Task report markdown not found: '$reportPath'." }
    $reportItem = Get-Item -LiteralPath $reportPath
    if ($reportItem.PSIsContainer) { Write-TaskHallError "Task report path must be a file: '$reportPath'." }
    $reviewerAgent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default "opencode/task-hall-reviewer"
    $meta = Load-TaskMeta -TaskId $taskId
    $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
    $reportMarkdown = Read-Utf8Text -Path $reportItem.FullName
    $prompt = @"
你是 task-hall 审核 agent。请按照你的 reviewer-v0.1 准则，根据原始任务 Markdown 和执行 agent 的任务报告 Markdown 进行审核。

要求：
- 只输出一个 JSON 对象，不要输出 Markdown 围栏，不要输出解释性前后缀。
- decision 只能是 complete、return_to_agent、relist_as_is、revise_and_relist 之一。
- 如果 revise_and_relist，revised_task_markdown 必须包含修订后的完整任务 Markdown。

原始任务 Markdown：
---TASK_MARKDOWN_BEGIN---
$taskMarkdown
---TASK_MARKDOWN_END---

任务报告 Markdown：
---REPORT_BEGIN---
$reportMarkdown
---REPORT_END---
"@
    Write-Host "Reviewing submission with reviewer agent: $reviewerAgent"
    $agentOutput = Invoke-AgentCliRunText -Agent $reviewerAgent -Prompt $prompt -SessionName "task-hall-review-$taskId"
    $review = Get-JsonObjectFromAgentOutput -Output $agentOutput
    $reviewPath = Join-Path ([string]$meta.task_dir) ("submission-review-{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Write-Utf8Text -Path $reviewPath -Content (($review | ConvertTo-Json -Depth 20) + "`r`n")
    Copy-Item -LiteralPath $reportItem.FullName -Destination (Join-Path ([string]$meta.task_dir) ("task-report-{0}.md" -f (Get-Date -Format "yyyyMMdd_HHmmss"))) -Force
    if (-not $review.ContainsKey("decision")) { Write-TaskHallError "Reviewer output missing decision. Review: $reviewPath" }
    $decision = [string]$review["decision"]
    switch ($decision) {
        "complete" {
            Set-TaskStatus -TaskId $taskId -Status "done" -Extra @{ reviewed_at = (Get-Date).ToString("o"); review_result = $decision; review_path = $reviewPath } | Out-Null
            Add-Event -Type "task.review_complete" -TaskId $taskId -Data @{ review = $reviewPath }
            Write-Host "Review complete: task marked done: $taskId"
            Write-Host "Review: $reviewPath"
            return
        }
        "return_to_agent" {
            Add-Event -Type "task.review_return_to_agent" -TaskId $taskId -Data @{ review = $reviewPath }
            Write-Host "Review result: return_to_agent"
            if ($review.ContainsKey("message_to_agent")) { Write-Host "Message: $($review["message_to_agent"])" }
            Write-Host "Review: $reviewPath"
            return
        }
        "relist_as_is" {
            Set-TaskStatus -TaskId $taskId -Status "listed" -Extra @{ claimed_by = $null; reviewed_at = (Get-Date).ToString("o"); review_result = $decision; review_path = $reviewPath } | Out-Null
            Add-Event -Type "task.review_relisted" -TaskId $taskId -Data @{ review = $reviewPath }
            Write-Host "Review result: relisted as-is: $taskId"
            Write-Host "Review: $reviewPath"
            return
        }
        "revise_and_relist" {
            if (-not $review.ContainsKey("revised_task_markdown") -or [string]::IsNullOrWhiteSpace([string]$review["revised_task_markdown"])) {
                Write-TaskHallError "Reviewer decision revise_and_relist requires revised_task_markdown. Review: $reviewPath"
            }
            Write-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md") -Content ([string]$review["revised_task_markdown"])
            Set-TaskStatus -TaskId $taskId -Status "listed" -Extra @{ claimed_by = $null; reviewed_at = (Get-Date).ToString("o"); review_result = $decision; review_path = $reviewPath } | Out-Null
            Add-Event -Type "task.review_revised_relisted" -TaskId $taskId -Data @{ review = $reviewPath }
            Write-Host "Review result: revised and relisted: $taskId"
            Write-Host "Review: $reviewPath"
            return
        }
        default { Write-TaskHallError "Unknown reviewer decision '$decision'. Review: $reviewPath" }
    }
}

function Invoke-TaskLinkReport {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 2) { Write-TaskHallError "Usage: task-hall task-link report <task-id> <report.md> [--agent <agent-id>] [--session <session-id>] [--status ready_for_review|blocked|progress]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--agent", "--session", "--status")
    $taskId = $InputArgs[0]
    $reportPath = $InputArgs[1]
    if (-not (Test-Path -LiteralPath $reportPath)) { Write-TaskHallError "Task report markdown not found: '$reportPath'." }
    $reportItem = Get-Item -LiteralPath $reportPath
    if ($reportItem.PSIsContainer) { Write-TaskHallError "Task report path must be a file: '$reportPath'." }
    $meta = Load-TaskMeta -TaskId $taskId
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default ([string](Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default "unknown-agent")))
    $session = Get-OptionValue -Args $InputArgs -Name "--session" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 3 -Default $null)
    $reportStatus = Get-OptionValue -Args $InputArgs -Name "--status" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 4 -Default "ready_for_review")
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dest = Join-Path ([string]$meta.task_dir) ("task-link-report-{0}.md" -f $stamp)
    Copy-Item -LiteralPath $reportItem.FullName -Destination $dest -Force
    Add-SubmissionEvent -TaskId $taskId -Status $reportStatus -Agent $agent -Note $dest
    $link = Get-TaskLinkState -TaskId $taskId
    $reports = @($link.reports)
    $reports += [pscustomobject][ordered]@{ ts = (Get-Date).ToString("o"); agent = $agent; session = $session; status = $reportStatus; report_path = $dest }
    $link.reports = @($reports)
    $link.status = "waiting_publisher"
    $link.current_agent = $agent
    $link.updated_at = (Get-Date).ToString("o")
    Save-TaskLinkState -State $link
    Add-Event -Type "task_link.reported" -TaskId $taskId -Data @{ agent = $agent; session = $session; status = $reportStatus; report = $dest }
    if ([string](Get-ObjectPropertyValue -Object $meta -Name "publish_mode" -Default "detached") -eq "watched") {
        Add-CallbackQueueItem -TaskId $taskId -Reason "task_link.reported" -Payload @{ agent = $agent; session = $session; report = $dest } | Out-Null
        Invoke-TaskHallLifecycleWake -Reason "task_link.reported" -TaskId $taskId
    }
    Write-Host "Task-link report recorded: $taskId"
    Write-Host "Report: $dest"
}

function Invoke-TaskLinkComplete {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall task-link complete <task-id> [--agent <agent-id>] [--result <text>]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--agent", "--result")
    $taskId = $InputArgs[0]
    $meta = Load-TaskMeta -TaskId $taskId
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default ([string](Get-ObjectPropertyValue -Object $meta -Name "publisher_agent" -Default "publisher")))
    $result = Get-OptionValue -Args $InputArgs -Name "--result" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default "completed by publisher")
    Set-TaskStatus -TaskId $taskId -Status "done" -Extra @{ done_by = $agent; done_at = (Get-Date).ToString("o"); result = $result } | Out-Null
    $link = Get-TaskLinkState -TaskId $taskId
    $link.status = "completed"
    Set-ObjectPropertyValue -Object $link -Name "completed_by" -Value $agent
    Set-ObjectPropertyValue -Object $link -Name "completed_at" -Value (Get-Date).ToString("o")
    Set-ObjectPropertyValue -Object $link -Name "result" -Value $result
    $link.updated_at = (Get-Date).ToString("o")
    Save-TaskLinkState -State $link
    Add-SubmissionEvent -TaskId $taskId -Status "complete" -Agent $agent -Note $result
    Add-Event -Type "task_link.completed" -TaskId $taskId -Data @{ agent = $agent; result = $result }
    Write-Host "Task-link completed: $taskId"
}

function Invoke-TaskLinkCancel {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall task-link cancel <task-id> [--agent <publisher-agent>] [--reason <text>]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--agent", "--reason")
    $taskId = $InputArgs[0]
    $meta = Load-TaskMeta -TaskId $taskId
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default ([string](Get-ObjectPropertyValue -Object $meta -Name "publisher_agent" -Default "publisher")))
    $reason = Get-OptionValue -Args $InputArgs -Name "--reason" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default "cancelled by publisher")
    Set-TaskStatus -TaskId $taskId -Status "cancelled" -Extra @{ cancelled_by = $agent; cancelled_at = (Get-Date).ToString("o"); cancel_reason = $reason } | Out-Null
    $link = Get-TaskLinkState -TaskId $taskId
    $link.status = "cancelled"
    Set-ObjectPropertyValue -Object $link -Name "cancelled_by" -Value $agent
    Set-ObjectPropertyValue -Object $link -Name "cancelled_at" -Value (Get-Date).ToString("o")
    Set-ObjectPropertyValue -Object $link -Name "cancel_reason" -Value $reason
    $link.updated_at = (Get-Date).ToString("o")
    Save-TaskLinkState -State $link
    Add-SubmissionEvent -TaskId $taskId -Status "cancelled" -Agent $agent -Note $reason
    Add-Event -Type "task_link.cancelled" -TaskId $taskId -Data @{ agent = $agent; reason = $reason }
    Write-Host "Task-link cancelled: $taskId"
}

function Invoke-TaskLinkContinue {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall task-link continue <task-id> [--agent <agent-id>] [--note <text>]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--agent", "--note")
    $taskId = $InputArgs[0]
    $meta = Load-TaskMeta -TaskId $taskId
    $agent = Get-OptionValue -Args $InputArgs -Name "--agent" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default ([string](Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default "unknown-agent")))
    $note = Get-OptionValue -Args $InputArgs -Name "--note" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default "continue requested")
    Set-TaskStatus -TaskId $taskId -Status "claimed" -Extra @{ claimed_by = $agent; continue_requested_at = (Get-Date).ToString("o"); continue_note = $note } | Out-Null
    $link = Get-TaskLinkState -TaskId $taskId
    $link.status = "continued"
    $link.current_agent = $agent
    Set-ObjectPropertyValue -Object $link -Name "continue_note" -Value $note
    $link.updated_at = (Get-Date).ToString("o")
    Save-TaskLinkState -State $link
    Add-SubmissionEvent -TaskId $taskId -Status "continue" -Agent $agent -Note $note
    Add-Event -Type "task_link.continued" -TaskId $taskId -Data @{ agent = $agent; note = $note }
    Invoke-TaskHallLifecycleWake -Reason "task_link.continued" -TaskId $taskId
    Write-Host "Task-link continued: $taskId"
}

function Invoke-DispatchContinues {
    param([string[]]$InputArgs)
    $dryRun = (($InputArgs -join " ") -match "dry")
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--limit", "--cwd", "--dry-run")
    Ensure-TaskHallState
    $limitRaw = Get-OptionValue -Args $InputArgs -Name "--limit" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "3")
    $limit = 3
    if (-not [int]::TryParse($limitRaw, [ref]$limit)) { Write-TaskHallError "Invalid limit '$limitRaw'." }
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    if ($dryRun) { Write-Host "Dispatch continues dry-run enabled." }
    $processed = 0
    $files = @(Get-ChildItem -LiteralPath $script:TaskLinksRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($file in $files) {
        if ($processed -ge $limit) { break }
        $link = (Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json
        if ([string](Get-ObjectPropertyValue -Object $link -Name "status" -Default "") -ne "continued") { continue }
        if (Test-ObjectProperty -Object $link -Name "last_continue_dispatch_output") { continue }
        $taskId = [string](Get-ObjectPropertyValue -Object $link -Name "task_id" -Default "")
        if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
        $meta = Load-TaskMeta -TaskId $taskId
        $agent = [string](Get-ObjectPropertyValue -Object $link -Name "current_agent" -Default (Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default ""))
        if ([string]::IsNullOrWhiteSpace($agent)) { continue }
        $sessionId = [string](Get-ObjectPropertyValue -Object $link -Name "executor_session" -Default (Get-ObjectPropertyValue -Object $meta -Name "executor_session" -Default ""))
        $note = [string](Get-ObjectPropertyValue -Object $link -Name "continue_note" -Default "continue requested")
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $boundary = [guid]::NewGuid().ToString("N")
        $reportPath = Join-Path ([string]$meta.task_dir) "report.md"
        $prompt = @"
你是 task-hall 任务执行 agent。发布者判断你的上一轮报告尚需继续，并通过 task-link continue 给出继续指令。

请不要从零开始。先检查任务目录、已有产物、上一轮报告和 task-link 状态，然后按继续指令补充工作。

继续指令：
---CONTINUE_BEGIN_$boundary---
$note
---CONTINUE_END_$boundary---

停止前必须写/更新 Markdown 报告到：`$reportPath`
并执行：`mycli task-hall task-link report $taskId "$reportPath" $agent <session-id>`
如果不知道 session id，使用 'unknown-session'。

任务 ID：$taskId
任务目录：$($meta.task_dir)

任务 Markdown：
---TASK_BEGIN_$boundary---
$taskMarkdown
---TASK_END_$boundary---

task-link 状态：
---LINK_BEGIN_$boundary---
$($link | ConvertTo-Json -Depth 20)
---LINK_END_$boundary---
"@
        if ($dryRun) {
            Write-Host "Would dispatch continue for task $taskId to $agent session=$sessionId"
            $processed++
            continue
        }
        $output = Invoke-AgentCliRunText -Agent $agent -Prompt $prompt -Cwd $cwd -SessionName "task-hall-continue-$taskId" -SessionId $sessionId
        $outPath = Join-Path ([string]$meta.task_dir) ("continue-output-{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Write-Utf8Text -Path $outPath -Content $output -EmitBom $false
        $newSession = Get-AgentCliSessionIdFromOutput -Output $output
        if (-not [string]::IsNullOrWhiteSpace($newSession)) {
            Set-ObjectPropertyValue -Object $meta -Name "executor_session" -Value $newSession
            Set-ObjectPropertyValue -Object $link -Name "executor_session" -Value $newSession
        }
        Set-ObjectPropertyValue -Object $meta -Name "last_continue_dispatched_at" -Value (Get-Date).ToString("o")
        Set-ObjectPropertyValue -Object $meta -Name "last_continue_dispatch_output" -Value $outPath
        Save-TaskMeta -Meta $meta
        Upsert-Listing -Meta $meta
        Set-ObjectPropertyValue -Object $link -Name "last_continue_dispatch_output" -Value $outPath
        Set-ObjectPropertyValue -Object $link -Name "last_continue_dispatched_at" -Value (Get-Date).ToString("o")
        $link.status = "active"
        $link.updated_at = (Get-Date).ToString("o")
        Save-TaskLinkState -State $link
        Add-Event -Type "task_link.continue_dispatched" -TaskId $taskId -Data @{ agent = $agent; session = $sessionId; output = $outPath }
        Write-Host "Dispatched continue for task $taskId to $agent"
        $processed++
    }
    Write-Host "Dispatched continues: $processed"
}

function Invoke-TaskLinkSwitchAgent {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 2) { Write-TaskHallError "Usage: task-hall task-link switch-agent <task-id> <new-agent-id> [--by <publisher-agent>] [--handoff <text-or-path>] [--force]" }
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--by", "--handoff", "--force")
    $taskId = $InputArgs[0]
    $newAgent = $InputArgs[1]
    $meta = Load-TaskMeta -TaskId $taskId
    $oldAgent = [string](Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default "")
    $by = Get-OptionValue -Args $InputArgs -Name "--by" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 2 -Default ([string](Get-ObjectPropertyValue -Object $meta -Name "publisher_agent" -Default "publisher")))
    $handoff = Get-OptionValue -Args $InputArgs -Name "--handoff" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 3 -Default "")
    $handoffSummaryMissing = [string]::IsNullOrWhiteSpace($handoff)
    if (-not $handoffSummaryMissing -and (Test-Path -LiteralPath $handoff)) { $handoff = Read-Utf8Text -Path $handoff }
    Set-TaskStatus -TaskId $taskId -Status "claimed" -Extra @{ claimed_by = $newAgent; claimed_at = (Get-Date).ToString("o"); switched_from = $oldAgent; switched_by = $by; handoff_summary_missing = $handoffSummaryMissing } | Out-Null
    Add-ClaimEvent -TaskId $taskId -Action "switched_from:$oldAgent" -Agent $newAgent -Result $handoff
    $link = Get-TaskLinkState -TaskId $taskId
    $handoffs = @($link.handoffs)
    $handoffs += [pscustomobject][ordered]@{ ts = (Get-Date).ToString("o"); from = $oldAgent; to = $newAgent; by = $by; handoff = $handoff; handoff_summary_missing = $handoffSummaryMissing }
    $link.handoffs = @($handoffs)
    $link.current_agent = $newAgent
    $link.status = "switched"
    $link.updated_at = (Get-Date).ToString("o")
    Save-TaskLinkState -State $link
    Add-Event -Type "task_link.agent_switched" -TaskId $taskId -Data @{ from = $oldAgent; to = $newAgent; by = $by; handoff_summary_missing = $handoffSummaryMissing }
    Invoke-TaskHallLifecycleWake -Reason "task_link.agent_switched" -TaskId $taskId
    Write-Host "Task-link switched: $taskId"
    Write-Host "From: $oldAgent"
    Write-Host "To: $newAgent"
}

function Invoke-DispatchSwitched {
    param([string[]]$InputArgs)
    $dryRun = (($InputArgs -join " ") -match "dry")
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--limit", "--cwd", "--dry-run")
    Ensure-TaskHallState
    $limitRaw = Get-OptionValue -Args $InputArgs -Name "--limit" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "3")
    $limit = 3
    if (-not [int]::TryParse($limitRaw, [ref]$limit)) { Write-TaskHallError "Invalid limit '$limitRaw'." }
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    if ($dryRun) { Write-Host "Dispatch switched dry-run enabled." }
    $processed = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $script:TaskLinksRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
        if ($processed -ge $limit) { break }
        $link = (Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json
        if ([string](Get-ObjectPropertyValue -Object $link -Name "status" -Default "") -ne "switched") { continue }
        if (Test-ObjectProperty -Object $link -Name "last_switch_dispatch_output") { continue }
        $taskId = [string](Get-ObjectPropertyValue -Object $link -Name "task_id" -Default "")
        if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
        $meta = Load-TaskMeta -TaskId $taskId
        $agent = [string](Get-ObjectPropertyValue -Object $link -Name "current_agent" -Default (Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default ""))
        if ([string]::IsNullOrWhiteSpace($agent)) { continue }
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $reports = @(Get-ObjectPropertyValue -Object $link -Name "reports" -Default @())
        $latestReport = $reports | Select-Object -Last 1
        $reportPath = if ($null -ne $latestReport) { [string](Get-ObjectPropertyValue -Object $latestReport -Name "report_path" -Default "") } else { "" }
        $reportText = if (-not [string]::IsNullOrWhiteSpace($reportPath) -and (Test-Path -LiteralPath $reportPath)) { Read-Utf8Text -Path $reportPath } else { "" }
        $handoffs = @(Get-ObjectPropertyValue -Object $link -Name "handoffs" -Default @())
        $handoff = $handoffs | Select-Object -Last 1
        $handoffText = if ($null -ne $handoff) { ($handoff | ConvertTo-Json -Depth 20) } else { "" }
        $boundary = [guid]::NewGuid().ToString("N")
        $reportPathTarget = Join-Path ([string]$meta.task_dir) "report.md"
        $prompt = @"
你是被 switch-agent 接手同一个 task-link 的新执行 agent。请不要从零盲做。

接手规则：
1. 阅读原任务说明、task-link 状态、已有报告和交接包。
2. 检查已有产物路径和实际工作区状态，不盲信前任总结。
3. 在当前任务边界内继续完成工作。
4. 停止前写/更新报告到：`$reportPathTarget`
5. 执行：`mycli task-hall task-link report $taskId "$reportPathTarget" $agent <session-id>`

任务 ID：$taskId
任务目录：$($meta.task_dir)

任务 Markdown：
---TASK_BEGIN_$boundary---
$taskMarkdown
---TASK_END_$boundary---

task-link 状态：
---LINK_BEGIN_$boundary---
$($link | ConvertTo-Json -Depth 20)
---LINK_END_$boundary---

最近报告：
---REPORT_BEGIN_$boundary---
$reportText
---REPORT_END_$boundary---

交接包：
---HANDOFF_BEGIN_$boundary---
$handoffText
---HANDOFF_END_$boundary---
"@
        if ($dryRun) {
            Write-Host "Would dispatch switched task $taskId to $agent"
            $processed++
            continue
        }
        $output = Invoke-AgentCliRunText -Agent $agent -Prompt $prompt -Cwd $cwd -SessionName "task-hall-switch-$taskId"
        $outPath = Join-Path ([string]$meta.task_dir) ("switch-output-{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Write-Utf8Text -Path $outPath -Content $output -EmitBom $false
        $newSession = Get-AgentCliSessionIdFromOutput -Output $output
        if (-not [string]::IsNullOrWhiteSpace($newSession)) {
            Set-ObjectPropertyValue -Object $meta -Name "executor_session" -Value $newSession
            Set-ObjectPropertyValue -Object $link -Name "executor_session" -Value $newSession
        }
        Set-ObjectPropertyValue -Object $meta -Name "last_switch_dispatched_at" -Value (Get-Date).ToString("o")
        Set-ObjectPropertyValue -Object $meta -Name "last_switch_dispatch_output" -Value $outPath
        Save-TaskMeta -Meta $meta
        Upsert-Listing -Meta $meta
        Set-ObjectPropertyValue -Object $link -Name "last_switch_dispatch_output" -Value $outPath
        Set-ObjectPropertyValue -Object $link -Name "last_switch_dispatched_at" -Value (Get-Date).ToString("o")
        $link.status = "active"
        $link.updated_at = (Get-Date).ToString("o")
        Save-TaskLinkState -State $link
        Add-Event -Type "task_link.switch_dispatched" -TaskId $taskId -Data @{ agent = $agent; session = $newSession; output = $outPath }
        Write-Host "Dispatched switched task $taskId to $agent"
        $processed++
    }
    Write-Host "Dispatched switched tasks: $processed"
}

function Invoke-TaskLinkShow {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall task-link show <task-id>" }
    $link = Get-TaskLinkState -TaskId $InputArgs[0]
    $link | ConvertTo-Json -Depth 20
}

function Invoke-TaskLink {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall task-link <report|complete|continue|cancel|switch-agent|show> ..." }
    $sub = $InputArgs[0]
    $rest = @()
    if ($InputArgs.Count -gt 1) { $rest = @($InputArgs[1..($InputArgs.Count - 1)]) }
    switch ($sub) {
        "report" { Invoke-TaskLinkReport -InputArgs $rest }
        "complete" { Invoke-TaskLinkComplete -InputArgs $rest }
        "continue" { Invoke-TaskLinkContinue -InputArgs $rest }
        "cancel" { Invoke-TaskLinkCancel -InputArgs $rest }
        "switch-agent" { Invoke-TaskLinkSwitchAgent -InputArgs $rest }
        "show" { Invoke-TaskLinkShow -InputArgs $rest }
        default { Write-TaskHallError "Unknown task-link command '$sub'." }
    }
}

function Invoke-Cancel {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall cancel <task-id>" }
    $meta = Load-TaskMeta -TaskId $InputArgs[0]
    if ($meta.status -eq "archived") { Write-TaskHallError "Archived task cannot be cancelled." }
    Set-TaskStatus -TaskId $InputArgs[0] -Status "cancelled" | Out-Null
    Write-Host "Cancelled task: $($InputArgs[0])"
}

function Invoke-TaskLinkLegacyLink {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 2) { Write-TaskHallError "Usage: task-hall link <parent-task-id> <child-task-id>" }
    $parentId = $InputArgs[0]
    $childId = $InputArgs[1]
    $parent = Load-TaskMeta -TaskId $parentId
    $child = Load-TaskMeta -TaskId $childId
    Set-ObjectPropertyValue -Object $parent -Name "child_ids" -Value (Add-UniqueString -Items @(Get-ObjectPropertyValue -Object $parent -Name "child_ids" -Default @()) -Value $childId)
    Set-ObjectPropertyValue -Object $child -Name "parent_id" -Value $parentId
    Save-TaskMeta -Meta $parent
    Save-TaskMeta -Meta $child
    Upsert-Listing -Meta $parent
    Upsert-Listing -Meta $child
    Add-Event -Type "task.linked" -TaskId $parentId -Data @{ child_id = $childId }
    Write-Host "Linked task: $parentId -> $childId"
}

function Invoke-TaskLinkLegacyUnlink {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 2) { Write-TaskHallError "Usage: task-hall unlink <parent-task-id> <child-task-id>" }
    $parentId = $InputArgs[0]
    $childId = $InputArgs[1]
    $parent = Load-TaskMeta -TaskId $parentId
    $child = Load-TaskMeta -TaskId $childId
    Set-ObjectPropertyValue -Object $parent -Name "child_ids" -Value (Remove-StringValue -Items @(Get-ObjectPropertyValue -Object $parent -Name "child_ids" -Default @()) -Value $childId)
    Set-ObjectPropertyValue -Object $child -Name "parent_id" -Value $null
    Save-TaskMeta -Meta $parent
    Save-TaskMeta -Meta $child
    Upsert-Listing -Meta $parent
    Upsert-Listing -Meta $child
    Add-Event -Type "task.unlinked" -TaskId $parentId -Data @{ child_id = $childId }
    Write-Host "Unlinked task: $parentId -/-> $childId"
}

function Invoke-Watch {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall watch <task-id> [watcher-id]" }
    $taskId = $InputArgs[0]
    $watcher = Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "unknown-watcher"
    $meta = Load-TaskMeta -TaskId $taskId
    Set-ObjectPropertyValue -Object $meta -Name "watchers" -Value (Add-UniqueString -Items @(Get-ObjectPropertyValue -Object $meta -Name "watchers" -Default @()) -Value $watcher)
    Save-TaskMeta -Meta $meta
    Upsert-Listing -Meta $meta
    Add-Event -Type "task.watched" -TaskId $taskId -Data @{ watcher = $watcher }
    Write-Host "Watching task: $taskId by $watcher"
}

function Invoke-Unwatch {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall unwatch <task-id> [watcher-id]" }
    $taskId = $InputArgs[0]
    $watcher = Get-PositionalArg -InputArgs $InputArgs -Index 1 -Default "unknown-watcher"
    $meta = Load-TaskMeta -TaskId $taskId
    Set-ObjectPropertyValue -Object $meta -Name "watchers" -Value (Remove-StringValue -Items @(Get-ObjectPropertyValue -Object $meta -Name "watchers" -Default @()) -Value $watcher)
    Save-TaskMeta -Meta $meta
    Upsert-Listing -Meta $meta
    Add-Event -Type "task.unwatched" -TaskId $taskId -Data @{ watcher = $watcher }
    Write-Host "Unwatched task: $taskId by $watcher"
}

function Invoke-CallbackQueue {
    param([string[]]$InputArgs)
    Ensure-TaskHallState
    $items = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $script:CallbackQueueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        $items += ,((Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json)
    }
    if ($InputArgs.Count -gt 0 -and $InputArgs[0] -eq "--json") { $items | ConvertTo-Json -Depth 20; return }
    if ($items.Count -eq 0) { Write-Host "No callback queue items."; return }
    $items | Sort-Object created_at | Select-Object id, task_id, reason, status, created_at | Format-Table -AutoSize
}

function Invoke-DispatchCallbacks {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--limit", "--agent", "--cwd", "--dry-run")
    Ensure-TaskHallState
    $limitRaw = Get-OptionValue -Args $InputArgs -Name "--limit" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "5")
    $limit = 5
    if (-not [int]::TryParse($limitRaw, [ref]$limit)) { Write-TaskHallError "Invalid limit '$limitRaw'." }
    $agentOverride = Get-OptionValue -Args $InputArgs -Name "--agent" -Default $null
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    $dryRun = Test-Flag -Args $InputArgs -Name "--dry-run"
    $files = @(Get-ChildItem -LiteralPath $script:CallbackQueueRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    $processed = 0
    foreach ($file in $files) {
        if ($processed -ge $limit) { break }
        $item = (Read-Utf8Text -Path $file.FullName) | ConvertFrom-Json
        if ([string](Get-ObjectPropertyValue -Object $item -Name "status" -Default "pending") -ne "pending") { continue }
        $taskId = [string]$item.task_id
        $meta = Load-TaskMeta -TaskId $taskId
        $publisherAgent = if ($agentOverride) { $agentOverride } else { [string](Get-ObjectPropertyValue -Object $meta -Name "publisher_agent" -Default "") }
        $publisherSession = [string](Get-ObjectPropertyValue -Object $meta -Name "publisher_session" -Default "")
        if ([string]::IsNullOrWhiteSpace($publisherAgent)) {
            Set-ObjectPropertyValue -Object $item -Name "status" -Value "failed"
            Set-ObjectPropertyValue -Object $item -Name "updated_at" -Value (Get-Date).ToString("o")
            Set-ObjectPropertyValue -Object $item -Name "error" -Value "missing publisher_agent"
            Write-Utf8Text -Path $file.FullName -Content (($item | ConvertTo-Json -Depth 20) + "`r`n")
            Add-Event -Type "task.callback_failed" -TaskId $taskId -Data @{ callback_id = $item.id; error = "missing publisher_agent" }
            continue
        }
        if ($publisherAgent -like "system/*") {
            Set-ObjectPropertyValue -Object $item -Name "status" -Value "skipped"
            Set-ObjectPropertyValue -Object $item -Name "updated_at" -Value (Get-Date).ToString("o")
            Set-ObjectPropertyValue -Object $item -Name "skip_reason" -Value "system publisher has no resumable agent session"
            Write-Utf8Text -Path $file.FullName -Content (($item | ConvertTo-Json -Depth 20) + "`r`n")
            Add-Event -Type "task.callback_skipped" -TaskId $taskId -Data @{ callback_id = $item.id; publisher_agent = $publisherAgent }
            Write-Host "Skipped callback $($item.id): system publisher"
            $processed++
            continue
        }
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $link = Get-TaskLinkState -TaskId $taskId
        $boundary = [guid]::NewGuid().ToString("N")
        $prompt = @"
你是 watched task 的发布者 agent。task-hall 有一个 task-link 回调需要你处理。

请阅读下面信息，判断这个任务是否完成、需要继续、需要切换 agent，或需要取消。

可用动作：
- 完成：mycli task-hall task-link complete $taskId $publisherAgent "<result>"
- 继续：mycli task-hall task-link continue $taskId <executor-agent> "<note>"
- 切换：mycli task-hall task-link switch-agent $taskId <new-agent-id> $publisherAgent "<handoff>"

注意：如果报告满足原任务验收标准，必须调用 complete 释放执行 agent slot；不要只在最终回复里说已收到。若不满足，必须 continue 或 switch-agent 给出明确下一步。

任务 ID：$taskId
回调原因：$($item.reason)

任务 Markdown：
---TASK_BEGIN_$boundary---
$taskMarkdown
---TASK_END_$boundary---

task-link 状态：
---LINK_BEGIN_$boundary---
$($link | ConvertTo-Json -Depth 20)
---LINK_END_$boundary---

callback payload：
---PAYLOAD_BEGIN_$boundary---
$($item.payload | ConvertTo-Json -Depth 20)
---PAYLOAD_END_$boundary---
"@
        if ($dryRun) {
            Write-Host "Would dispatch callback $($item.id) to $publisherAgent session=$publisherSession"
            $processed++
            continue
        }
        try {
            $output = Invoke-AgentCliRunText -Agent $publisherAgent -Prompt $prompt -Cwd $cwd -SessionName "task-hall-callback-$taskId" -SessionId $publisherSession
            $outPath = Join-Path $script:CallbackQueueRoot ("{0}.output.txt" -f $item.id)
            Write-Utf8Text -Path $outPath -Content $output -EmitBom $false
            Set-ObjectPropertyValue -Object $item -Name "status" -Value "dispatched"
            Set-ObjectPropertyValue -Object $item -Name "updated_at" -Value (Get-Date).ToString("o")
            Set-ObjectPropertyValue -Object $item -Name "dispatched_to" -Value $publisherAgent
            Set-ObjectPropertyValue -Object $item -Name "publisher_session" -Value $publisherSession
            Set-ObjectPropertyValue -Object $item -Name "output_path" -Value $outPath
            Write-Utf8Text -Path $file.FullName -Content (($item | ConvertTo-Json -Depth 20) + "`r`n")
            Add-Event -Type "task.callback_dispatched" -TaskId $taskId -Data @{ callback_id = $item.id; agent = $publisherAgent; session = $publisherSession; output = $outPath }
            Write-Host "Dispatched callback $($item.id) to $publisherAgent"
        } catch {
            Set-ObjectPropertyValue -Object $item -Name "status" -Value "failed"
            Set-ObjectPropertyValue -Object $item -Name "updated_at" -Value (Get-Date).ToString("o")
            Set-ObjectPropertyValue -Object $item -Name "error" -Value $_.Exception.Message
            Write-Utf8Text -Path $file.FullName -Content (($item | ConvertTo-Json -Depth 20) + "`r`n")
            Add-Event -Type "task.callback_failed" -TaskId $taskId -Data @{ callback_id = $item.id; error = $_.Exception.Message }
            Write-Host "Failed callback $($item.id): $($_.Exception.Message)"
        }
        $processed++
    }
    Write-Host "Processed callbacks: $processed"
}

function Invoke-DispatchListed {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--limit", "--agent", "--model", "--cwd", "--dry-run")
    $dryRun = (($InputArgs -join " ") -match "dry")
    Ensure-TaskHallState
    $limitRaw = Get-OptionValue -Args $InputArgs -Name "--limit" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "1")
    $limit = 1
    if (-not [int]::TryParse($limitRaw, [ref]$limit)) { Write-TaskHallError "Invalid limit '$limitRaw'." }
    $agentOverride = Get-OptionValue -Args $InputArgs -Name "--agent" -Default $null
    $model = Get-OptionValue -Args $InputArgs -Name "--model" -Default $null
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    $listed = @(Get-Listings | Where-Object { $_.status -eq "listed" } | Sort-Object @{ Expression = "priority"; Descending = $true }, created_at)
    $count = 0
    foreach ($row in $listed) {
        if ($count -ge $limit) { break }
        $taskId = [string]$row.id
        $meta = Load-TaskMeta -TaskId $taskId
        $slot = $null
        if ([string]::IsNullOrWhiteSpace($agentOverride)) {
            $slot = Get-AgentPoolForTask -Meta $meta
            if ($null -eq $slot) {
                $resolvedType = Resolve-AgentType -RequiredAgentType ([string](Get-ObjectPropertyValue -Object $meta -Name "required_agent_type" -Default "middle-builder"))
                Add-Event -Type "task.dispatch_waiting_capacity" -TaskId $taskId -Data @{ required_agent_type = Get-ObjectPropertyValue -Object $meta -Name "required_agent_type" -Default ""; resolved_agent_type = $resolvedType }
                Write-Host "Waiting capacity for task $taskId"
                continue
            }
        }
        $agent = if (-not [string]::IsNullOrWhiteSpace($agentOverride)) { $agentOverride } else { [string]$slot.agent }
        $agentModel = if (-not [string]::IsNullOrWhiteSpace($model)) { $model } elseif ($null -ne $slot) { [string]$slot.model } else { $null }
        $executorAgentType = if ($null -ne $slot) { [string]$slot.type } else { Resolve-AgentType -RequiredAgentType ([string](Get-ObjectPropertyValue -Object $meta -Name "required_agent_type" -Default "middle-builder")) }
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $boundary = [guid]::NewGuid().ToString("N")
        $reportPath = Join-Path ([string]$meta.task_dir) "report.md"
        $prompt = @"
你是工程部执行 agent。请处理下面 task-hall 任务。

## 绝对终止协议

本任务的结束方式不是在最终回答里说 done。无论完成、部分完成、受阻、失败或无法继续，你停止前都必须：

1. 写 Markdown 报告到：`$reportPath`
2. 执行提交命令：
   `mycli task-hall task-link report $taskId "$reportPath" $agent <session-id>`
3. 如果你不知道 session id，使用 'unknown-session'，但不能省略提交。
4. 只有完成了 task-link report，任务才算交回发布者；最终回答不能替代 task-hall 提交。
5. 提交后，如果你判断当前执行生命周期已结束，最终回复包含 `AGENT_CLI_LIFECYCLE_END`。

## 工作要求

1. 阅读任务 Markdown。
2. 在任务范围内完成工作，不越界修改无关文件。
3. 产出必要文件并验证。
4. 报告必须包含下面模板中的所有小节。

## 报告模板

```markdown
# 任务报告

## 状态
complete / partial / blocked / failed

## 完成内容
- ...

## 产物路径
- `D:\...`

## 验证结果
- 执行了什么命令或检查
- 结果是什么
- 如果无法验证，说明原因

## 未完成项
- 没有则写“无”

## 问题或阻塞
- 没有则写“无”

## 建议下一步
- ...
```

任务 ID：$taskId
任务目录：$($meta.task_dir)

开始施工前必须先检查任务目录是否已有 report、task-link-report、handoff、plan 或半成品，结合 task-link 状态判断真实进展，避免重复施工。

任务 Markdown：
---TASK_BEGIN_$boundary---
$taskMarkdown
---TASK_END_$boundary---
"@
        if ($dryRun) {
            Write-Host "Would dispatch listed task $taskId to $agent"
            $count++
            continue
        }
        Invoke-Claim -InputArgs @($taskId, $agent, "no-frontdesk")
        $runStartedAt = Get-Date
        $runArgs = @("run", "--agent", $agent, "--return_mode", "silent", "--session_name", "task-hall-exec-$taskId", "--cwd", $cwd)
        if (-not [string]::IsNullOrWhiteSpace($agentModel)) { $runArgs += @("--model", $agentModel) }
        $runArgs += @("--prompt", $prompt)
        $output = & $script:AgentCliScriptPath @runArgs 2>&1 | Out-String
        $outPath = Join-Path ([string]$meta.task_dir) "dispatch-output.txt"
        Write-Utf8Text -Path $outPath -Content $output -EmitBom $false
        $sessionId = Get-AgentCliSessionIdFromOutput -Output $output
        $claimedMeta = Load-TaskMeta -TaskId $taskId
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            Set-ObjectPropertyValue -Object $claimedMeta -Name "executor_session" -Value $sessionId
            Set-ObjectPropertyValue -Object $claimedMeta -Name "dispatched_at" -Value (Get-Date).ToString("o")
            Set-ObjectPropertyValue -Object $claimedMeta -Name "dispatch_output" -Value $outPath
        }
        Set-ObjectPropertyValue -Object $claimedMeta -Name "executor_agent" -Value $agent
        Set-ObjectPropertyValue -Object $claimedMeta -Name "executor_agent_type" -Value $executorAgentType
        Save-TaskMeta -Meta $claimedMeta
        Upsert-Listing -Meta $claimedMeta
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            Repair-PublisherSessionForAgentRun -PublisherAgent $agent -PublisherSession $sessionId -Since $runStartedAt
        }
        $link = Get-TaskLinkState -TaskId $taskId
        $link.status = "active"
        $link.current_agent = $agent
        Set-ObjectPropertyValue -Object $link -Name "executor_agent" -Value $agent
        Set-ObjectPropertyValue -Object $link -Name "executor_agent_type" -Value $executorAgentType
        Set-ObjectPropertyValue -Object $link -Name "executor_session" -Value $sessionId
        Set-ObjectPropertyValue -Object $link -Name "dispatch_output" -Value $outPath
        $link.updated_at = (Get-Date).ToString("o")
        Save-TaskLinkState -State $link
        Add-Event -Type "task.dispatched" -TaskId $taskId -Data @{ agent = $agent; session = $sessionId; output = $outPath }
        Write-Host "Dispatched task $taskId to $agent"
        $count++
    }
    Write-Host "Dispatched listed tasks: $count"
}

function Invoke-LifecycleTick {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--listed-limit", "--callback-limit", "--cwd", "--dry-run")
    $dryRun = (($InputArgs -join " ") -match "dry")
    $listedLimit = Get-OptionValue -Args $InputArgs -Name "--listed-limit" -Default "1"
    $callbackLimit = Get-OptionValue -Args $InputArgs -Name "--callback-limit" -Default "3"
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    $dry = if ($dryRun) { @("--dry-run") } else { @() }

    function Invoke-LifecycleTickStage {
        param(
            [string]$Name,
            [scriptblock]$Body
        )
        Write-Host "Lifecycle tick: $Name"
        try {
            & $Body
            Add-Event -Type "lifecycle.stage_completed" -TaskId "" -Data @{ stage = $Name; dry_run = $dryRun }
        } catch {
            $message = $_.Exception.Message
            Write-Host "Lifecycle stage failed: $Name - $message"
            Add-Event -Type "lifecycle.stage_failed" -TaskId "" -Data @{ stage = $Name; error = $message; dry_run = $dryRun }
        }
    }

    if ($dryRun) {
        Invoke-LifecycleTickStage -Name "dispatch callbacks" -Body { Invoke-DispatchCallbacks -InputArgs (@($callbackLimit, "--cwd", $cwd) + $dry) }
        Invoke-LifecycleTickStage -Name "recover waiting publishers" -Body { Invoke-RecoverWaitingPublishers -InputArgs (@("3", "--cwd", $cwd, "--stale-minutes", "1") + $dry) }
        Invoke-LifecycleTickStage -Name "dispatch continues" -Body { Invoke-DispatchContinues -InputArgs (@("3", "--cwd", $cwd) + $dry) }
        Invoke-LifecycleTickStage -Name "dispatch switched tasks" -Body { Invoke-DispatchSwitched -InputArgs (@("3", "--cwd", $cwd) + $dry) }
        Invoke-LifecycleTickStage -Name "recover claimed tasks" -Body { Invoke-RecoverClaimed -InputArgs (@("2", "--cwd", $cwd, "--stale-minutes", "10") + $dry) }
        Invoke-LifecycleTickStage -Name "dispatch listed tasks" -Body { Invoke-DispatchListed -InputArgs (@($listedLimit, "--cwd", $cwd) + $dry) }
        return
    }

    # Event-driven wake must make newly listed tasks claimable promptly.  Long-running
    # callback/continue/recover agent calls are still important, but they must not sit
    # in front of the listed-task dispatcher and make a fresh task appear stuck.
    Invoke-LifecycleTickStage -Name "dispatch listed tasks" -Body { Invoke-DispatchListed -InputArgs (@($listedLimit, "--cwd", $cwd) + $dry) }
    Invoke-LifecycleTickStage -Name "dispatch callbacks" -Body { Invoke-DispatchCallbacks -InputArgs (@($callbackLimit, "--cwd", $cwd) + $dry) }
    Invoke-LifecycleTickStage -Name "recover waiting publishers" -Body { Invoke-RecoverWaitingPublishers -InputArgs (@("3", "--cwd", $cwd, "--stale-minutes", "1") + $dry) }
    Invoke-LifecycleTickStage -Name "dispatch continues" -Body { Invoke-DispatchContinues -InputArgs (@("3", "--cwd", $cwd) + $dry) }
    Invoke-LifecycleTickStage -Name "dispatch switched tasks" -Body { Invoke-DispatchSwitched -InputArgs (@("3", "--cwd", $cwd) + $dry) }
}

function Invoke-RecoverClaimed {
    param([string[]]$InputArgs)
    $dryRun = (($InputArgs -join " ") -match "dry")
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--limit", "--stale-minutes", "--cwd", "--dry-run")
    Ensure-TaskHallState
    $limitRaw = Get-OptionValue -Args $InputArgs -Name "--limit" -Default (Get-PositionalArg -InputArgs $InputArgs -Index 0 -Default "2")
    $limit = 2
    if (-not [int]::TryParse($limitRaw, [ref]$limit)) { Write-TaskHallError "Invalid limit '$limitRaw'." }
    $staleRaw = Get-OptionValue -Args $InputArgs -Name "--stale-minutes" -Default "10"
    $staleMinutes = 10
    if (-not [int]::TryParse($staleRaw, [ref]$staleMinutes)) { Write-TaskHallError "Invalid stale minutes '$staleRaw'." }
    $cwd = Get-OptionValue -Args $InputArgs -Name "--cwd" -Default "D:\agent_workspace"
    if ($dryRun) { Write-Host "Recover dry-run enabled." }
    $claimed = @(Get-Listings | Where-Object { $_.status -eq "claimed" } | Sort-Object created_at)
    $processed = 0
    foreach ($row in $claimed) {
        if ($processed -ge $limit) { break }
        $taskId = [string]$row.id
        $meta = Load-TaskMeta -TaskId $taskId
        $last = Get-TaskLastActivityTime -TaskId $taskId
        $age = (New-TimeSpan -Start $last -End (Get-Date)).TotalMinutes
        $dispatchOutput = Join-Path ([string]$meta.task_dir) "dispatch-output.txt"
        $hasReport = @(Get-ChildItem -LiteralPath ([string]$meta.task_dir) -Filter "task-link-report-*.md" -File -ErrorAction SilentlyContinue).Count -gt 0
        $activeChildren = @(Get-Listings | Where-Object { ([string](Get-ObjectPropertyValue -Object $_ -Name "parent_id" -Default "")) -eq $taskId -and $_.status -notin @("done", "cancelled", "archived") })
        if ($activeChildren.Count -gt 0) {
            Add-Event -Type "task.recover_skipped_waiting_children" -TaskId $taskId -Data @{ child_count = $activeChildren.Count }
            continue
        }
        $dispatchedAt = Get-Date "2000-01-01"
        [DateTime]::TryParse([string](Get-ObjectPropertyValue -Object $meta -Name "dispatched_at" -Default ""), [ref]$dispatchedAt) | Out-Null
        $dispatchAge = if ($dispatchedAt.Year -gt 2000) { (New-TimeSpan -Start $dispatchedAt -End (Get-Date)).TotalMinutes } else { 999999 }
        $shouldRecover = (-not (Test-Path -LiteralPath $dispatchOutput)) -or (($dispatchAge -ge $staleMinutes) -and (-not $hasReport))
        if (-not $shouldRecover) { continue }
        $agent = [string](Get-ObjectPropertyValue -Object $meta -Name "claimed_by" -Default "")
        if ([string]::IsNullOrWhiteSpace($agent)) { continue }
        $sessionId = [string](Get-ObjectPropertyValue -Object $meta -Name "executor_session" -Default "")
        $taskMarkdown = Read-Utf8Text -Path (Join-Path ([string]$meta.task_dir) "task.md")
        $boundary = [guid]::NewGuid().ToString("N")
        $reportPath = Join-Path ([string]$meta.task_dir) "report.md"
        $prompt = @"
你是工程部执行 agent。生命周期维护系统检测到你领取的 task-hall 任务可能中断或尚未汇报，需要恢复。

## 绝对终止协议

本任务的结束方式不是在最终回答里说 done。无论你判断当前任务已经完成、部分完成、受阻、失败或无法继续，你停止前都必须：

1. 先检查是否已经存在报告：'$reportPath' 或 'task-link-report-*.md'。
2. 如果已完成但未提交，补写/更新 Markdown 报告到：`$reportPath`。
3. 执行提交命令：
   `mycli task-hall task-link report $taskId "$reportPath" $agent <session-id>`
4. 如果你不知道 session id，使用 'unknown-session'，但不能省略提交。
5. 只有完成了 task-link report，任务才算交回发布者；最终回答不能替代 task-hall 提交。
6. 提交后，如果当前执行生命周期已结束，最终回复包含 `AGENT_CLI_LIFECYCLE_END`。

任务 ID：$taskId
任务目录：$($meta.task_dir)

说明：heartbeat/recover 是兜底，不是常规推进。只有在你没有正在工作、没有正在监听的未完成 watched 子任务、且自己的任务尚未完成或尚未有效 report 时才应恢复。若你发现自己其实正在等待下游 task/callback，请不要重复施工，只记录等待状态或补交必要报告。

请继续或恢复处理：
1. 阅读任务 Markdown。
2. 检查当前产物和已有进度。
3. 如果任务完成、部分完成、受阻或无法完成，写 Markdown 报告。
4. 报告必须包含：状态、完成内容、产物路径、验证结果、未完成项、问题或阻塞、建议下一步。

任务 Markdown：
---TASK_BEGIN_$boundary---
$taskMarkdown
---TASK_END_$boundary---
"@
        if ($dryRun) {
            Write-Host "Would recover claimed task $taskId by $agent session=$sessionId age=$([math]::Round($age, 1))m"
            $processed++
            continue
        }
        $output = Invoke-AgentCliRunText -Agent $agent -Prompt $prompt -Cwd $cwd -SessionName "task-hall-recover-$taskId" -SessionId $sessionId
        $outPath = Join-Path ([string]$meta.task_dir) ("recover-output-{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        Write-Utf8Text -Path $outPath -Content $output -EmitBom $false
        $newSession = Get-AgentCliSessionIdFromOutput -Output $output
        if (-not [string]::IsNullOrWhiteSpace($newSession)) {
            Set-ObjectPropertyValue -Object $meta -Name "executor_session" -Value $newSession
        }
        Set-ObjectPropertyValue -Object $meta -Name "last_recovered_at" -Value (Get-Date).ToString("o")
        Set-ObjectPropertyValue -Object $meta -Name "last_recover_output" -Value $outPath
        Save-TaskMeta -Meta $meta
        Upsert-Listing -Meta $meta
        $link = Get-TaskLinkState -TaskId $taskId
        $link.status = "active"
        $link.current_agent = $agent
        Set-ObjectPropertyValue -Object $link -Name "executor_agent" -Value $agent
        $effectiveSession = if (-not [string]::IsNullOrWhiteSpace($newSession)) { $newSession } else { $sessionId }
        Set-ObjectPropertyValue -Object $link -Name "executor_session" -Value $effectiveSession
        Set-ObjectPropertyValue -Object $link -Name "last_recover_output" -Value $outPath
        $link.updated_at = (Get-Date).ToString("o")
        Save-TaskLinkState -State $link
        Add-Event -Type "task.recovered" -TaskId $taskId -Data @{ agent = $agent; session = $effectiveSession; output = $outPath }
        Write-Host "Recovered task $taskId by $agent"
        $processed++
    }
    Write-Host "Recovered claimed tasks: $processed"
}

function Invoke-MonitorExport {
    param([string[]]$InputArgs)
    Assert-NoUnknownOptions -Args $InputArgs -Allowed @("--json", "--out")
    $snapshot = Get-LifecycleSnapshot
    $json = $snapshot | ConvertTo-Json -Depth 30
    $out = Get-OptionValue -Args $InputArgs -Name "--out" -Default (Join-Path $script:MonitorRoot "lifecycle-state.json")
    Write-Utf8Text -Path $out -Content ($json + "`r`n") -EmitBom $false
    if (Test-Flag -Args $InputArgs -Name "--json") { $json; return }
    Write-Host "Lifecycle monitor state exported: $out"
}

function Invoke-Delete {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall delete <task-id>" }
    $taskId = $InputArgs[0]
    Load-TaskMeta -TaskId $taskId | Out-Null
    Remove-Listing -TaskId $taskId
    $taskDir = Get-TaskDir -TaskId $taskId
    if (Test-Path -LiteralPath $taskDir) {
        Remove-Item -LiteralPath $taskDir -Recurse -Force
    }
    Add-Event -Type "task.deleted" -TaskId $taskId -Data @{}
    Write-Host "Deleted task: $taskId"
}

function Invoke-Archive {
    param([string[]]$InputArgs)
    if ($InputArgs.Count -lt 1) { Write-TaskHallError "Usage: task-hall archive <task-id>" }
    $meta = Load-TaskMeta -TaskId $InputArgs[0]
    if ($meta.status -notin @("done", "cancelled", "draft", "listed", "claimed")) { Write-TaskHallError "Task cannot be archived from status: $($meta.status)." }
    Set-TaskStatus -TaskId $InputArgs[0] -Status "archived" | Out-Null
    Write-Host "Archived task: $($InputArgs[0])"
}

function Invoke-Status {
    $items = @(Get-Listings)
    $statuses = @("draft", "listed", "claimed", "done", "cancelled", "archived")
    Write-Host "Task Hall Status"
    Write-Host "State: $script:StateRoot"
    foreach ($status in $statuses) {
        $count = @($items | Where-Object { $_.status -eq $status }).Count
        Write-Host "- ${status}: $count"
    }
    Write-Host "- total listed index rows: $($items.Count)"
}

function Show-Usage {
    Write-Host @"
task-hall commands:
  init
  submit-request <request.json> [--draft] [--agent <frontdesk-agent>]
  publish-raw <task.md> [--draft] [--publish-mode watched|detached] [--publisher-agent <agent>] [--publisher-session <session>] [--required-agent-type <type>]
  upload <task.md> [kind] [priority] [tagsCsv] [title]
  upload-publish <task.md> [kind] [priority] [tagsCsv] [title]
  publish <task-id>
  tasks [status] [kind] [tag] [json|all]
  show <task-id>
  edit <task-id> [title] [kind] [priority] [tagsCsv] [task.md]
  claim <task-id> [agent-id] [--model-tier <tier>] [--model <model-id>] [--reason <text>]
  release <task-id> [agent-id]
  submit <task-id> <success|fail> [agent-id] [note]
  review-submission <task-id> <report.md> [--agent <reviewer-agent>]
  task-link report <task-id> <report.md> [--agent <agent-id>] [--session <session-id>]
  task-link complete <task-id> [--agent <publisher-agent>] [--result <text>]
  task-link continue <task-id> [--agent <agent-id>] [--note <text>]
  task-link cancel <task-id> [--agent <publisher-agent>] [--reason <text>]
  task-link switch-agent <task-id> <new-agent-id> [--by <publisher-agent>] [--handoff <text-or-path>] [--force]
  task-link show <task-id>
  link <parent-task-id> <child-task-id>
  unlink <parent-task-id> <child-task-id>
  watch <task-id> [watcher-id]
  unwatch <task-id> [watcher-id]
  callback-queue [--json]
  callback-archive [--status failed,skipped,dispatched] [--older-than-days <n>] [--dry-run]
  dispatch-callbacks [limit] [--agent <publisher-agent>] [--dry-run]
  recover-waiting-publishers [limit] [--stale-minutes <n>] [--dry-run]
  dispatch-continues [limit] [--dry-run]
  dispatch-switched [limit] [--dry-run]
  dispatch-listed [limit] [--agent <executor-agent>] [--dry-run]
  recover-claimed [limit] [--stale-minutes <n>] [--dry-run]
  lifecycle-tick [--listed-limit <n>] [--callback-limit <n>] [--dry-run]
  lifecycle-wake [--reason <text>] [--task-id <id>] [--listed-limit <n>] [--callback-limit <n>] [--cwd <path>]
  monitor-export [--json] [--out <path>]
  done <task-id> [agent-id] [result]
  cancel <task-id>
  delete <task-id>
  archive <task-id>
  status
"@
}

if ($CommandArgs.Count -eq 0) {
    Show-Usage
    exit 0
}

$command = $CommandArgs[0]
$rest = New-Object System.Collections.Generic.List[string]
if ($CommandArgs.Count -gt 1) {
    for ($index = 1; $index -lt $CommandArgs.Count; $index++) {
        $rest.Add([string]$CommandArgs[$index])
    }
}
$rest = @($rest)

switch ($command) {
    "init" { Invoke-Init }
    "submit-request" { Invoke-SubmitRequest -InputArgs $rest }
    "publish-raw" { Invoke-PublishRaw -InputArgs $rest }
    "upload" { Invoke-Upload -InputArgs $rest }
    "upload-publish" { Invoke-Upload -InputArgs $rest -PublishNow $true }
    "publish" { Invoke-Publish -InputArgs $rest }
    "tasks" { Invoke-Tasks -InputArgs $rest }
    "list" { Invoke-Tasks -InputArgs $rest }
    "show" { Invoke-Show -InputArgs $rest }
    "edit" { Invoke-Edit -InputArgs $rest }
    "claim" { Invoke-Claim -InputArgs $rest }
    "release" { Invoke-Release -InputArgs $rest }
    "submit" { Invoke-Submit -InputArgs $rest }
    "review-submission" { Invoke-ReviewSubmission -InputArgs $rest }
    "task-link" { Invoke-TaskLink -InputArgs $rest }
    "link" { Invoke-TaskLinkLegacyLink -InputArgs $rest }
    "unlink" { Invoke-TaskLinkLegacyUnlink -InputArgs $rest }
    "watch" { Invoke-Watch -InputArgs $rest }
    "unwatch" { Invoke-Unwatch -InputArgs $rest }
    "callback-queue" { Invoke-CallbackQueue -InputArgs $rest }
    "callback-archive" { Invoke-CallbackArchive -InputArgs $rest }
    "dispatch-callbacks" { Invoke-DispatchCallbacks -InputArgs $rest }
    "recover-waiting-publishers" { Invoke-RecoverWaitingPublishers -InputArgs $rest }
    "dispatch-continues" { Invoke-DispatchContinues -InputArgs $rest }
    "dispatch-switched" { Invoke-DispatchSwitched -InputArgs $rest }
    "dispatch-listed" { Invoke-DispatchListed -InputArgs $rest }
    "recover-claimed" { Invoke-RecoverClaimed -InputArgs $rest }
    "lifecycle-tick" { Invoke-LifecycleTick -InputArgs $rest }
    "lifecycle-wake" { Invoke-LifecycleWakeCommand -InputArgs $rest }
    "monitor-export" { Invoke-MonitorExport -InputArgs $rest }
    "done" { Invoke-Done -InputArgs $rest }
    "cancel" { Invoke-Cancel -InputArgs $rest }
    "delete" { Invoke-Delete -InputArgs $rest }
    "archive" { Invoke-Archive -InputArgs $rest }
    "status" { Invoke-Status }
    default {
        Show-Usage
        Write-TaskHallError "Unknown command '$command'."
    }
}
