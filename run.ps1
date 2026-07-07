# Jira Ticket Resolver Agent v9.1
# Fully autonomous: sub-task decomposition, self-learning memory, package auto-install,
# AI logic review with self-fix retry, cross-file wiring check, read-back verification.
param(
    [string]$CodebasePath = '',
    [string]$EnvFile = '.env',
    [switch]$DryRun,
    [switch]$Test,
    [switch]$Restore,
    [string]$RestoreDate = '',
    [switch]$FastMode,
    [switch]$UseJiraPriority
)
$global:FastMode = $FastMode

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# == 1. LOAD CONFIG ==
$envPath = Join-Path $PSScriptRoot $EnvFile
if (Test-Path -LiteralPath $envPath) {
    Write-Host "  Loaded config from: $EnvFile" -ForegroundColor Cyan
    Get-Content -LiteralPath $envPath | ForEach-Object {
        if ($_ -match '^\s*([^#=\s]+)\s*=\s*(.+)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim())
        }
    }
}
$provider  = if ($env:PROVIDER) { $env:PROVIDER.ToLower() } else { 'openrouter' }
$apiKey    = $env:API_KEY
$model     = if ($env:MODEL) { $env:MODEL } else { 'google/gemini-flash-1.5' }
$jiraUrl   = if ($env:JIRA_URL) { ($env:JIRA_URL).TrimEnd('/') } else { '' }
$jiraEmail = $env:JIRA_EMAIL
$jiraToken = $env:JIRA_API_TOKEN
$jiraPat   = $env:JIRA_PAT
$jiraProj  = $env:JIRA_PROJECT
$jiraJql   = $env:JIRA_JQL
$writeBack = $env:JIRA_WRITE_BACK -match '(?i)^(true|1|yes)$'
$cbPath    = if ($CodebasePath) { $CodebasePath } `
             elseif ($env:CODEBASE_PATH) { $env:CODEBASE_PATH } `
             else { Join-Path $PSScriptRoot 'project' }
$cbPath = $cbPath.TrimEnd('\').TrimEnd('/')

# == 2. VALIDATE ==
if (-not $apiKey -or $apiKey -match 'YOUR|your-llm') { Write-Host 'ERROR: API_KEY not set' -ForegroundColor Red; exit 1 }
if (-not $jiraUrl -or $jiraUrl -match 'yourcompany') { Write-Host 'ERROR: JIRA_URL not set' -ForegroundColor Red; exit 1 }
if (-not $jiraToken -and -not $jiraPat) { Write-Host 'ERROR: JIRA_API_TOKEN or JIRA_PAT required' -ForegroundColor Red; exit 1 }
if (-not $jiraProj -and -not $jiraJql) { Write-Host 'ERROR: JIRA_PROJECT or JIRA_JQL required' -ForegroundColor Red; exit 1 }
if (-not (Test-Path $cbPath)) { New-Item -ItemType Directory -Path $cbPath -Force | Out-Null }

$backupDir = Join-Path $PSScriptRoot 'backups'
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

# Jira auth
$jiraHeaders = @{ 'Content-Type' = 'application/json' }
if ($jiraToken -and $jiraEmail) {
    $pair = "${jiraEmail}:${jiraToken}"
    $jiraHeaders['Authorization'] = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair)))"
} elseif ($jiraPat) { $jiraHeaders['Authorization'] = "Bearer $jiraPat" }

# == 3. BANNER ==
Write-Host ''
Write-Host '  ====================================================' -ForegroundColor Cyan
Write-Host '  Jira Ticket Resolver Agent     ' -ForegroundColor Cyan
Write-Host '  ====================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Jira      : $jiraUrl" -ForegroundColor Gray
Write-Host "  Project   : $(if ($jiraJql) { 'Custom JQL' } else { $jiraProj })" -ForegroundColor Gray
Write-Host "  Model     : $provider / $model" -ForegroundColor Gray
Write-Host "  Codebase  : $cbPath" -ForegroundColor Gray
$modeText = if ($Test) { 'TEST' } elseif ($DryRun) { 'DRY RUN' } else { 'LIVE' }
$modeColor = if ($Test) { 'Magenta' } elseif ($DryRun) { 'Yellow' } else { 'Green' }
Write-Host "  Mode      : $modeText" -ForegroundColor $modeColor
Write-Host ''



# == 4. LOAD PROMPTS ==
$agentCtx  = Get-Content (Join-Path $PSScriptRoot 'agent.md')  -Raw -ErrorAction SilentlyContinue
$skillsCtx = Get-Content (Join-Path $PSScriptRoot 'skills.md') -Raw -ErrorAction SilentlyContinue
$taskCtx   = Get-Content (Join-Path $PSScriptRoot 'task.md')   -Raw -ErrorAction SilentlyContinue

# == 5. CORE HELPERS ==
. "$PSScriptRoot\src\llm.ps1"
. "$PSScriptRoot\src\jira.ps1"
. "$PSScriptRoot\src\files.ps1"
. "$PSScriptRoot\src\quality.ps1"
. "$PSScriptRoot\src\memory.ps1"
. "$PSScriptRoot\src\codebase.ps1"
. "$PSScriptRoot\src\executor.ps1"
. "$PSScriptRoot\src\file-validator.ps1"
. "$PSScriptRoot\src\content-normalizer.ps1"
. "$PSScriptRoot\src\file-reader.ps1"
. "$PSScriptRoot\src\improved-fix.ps1"

# == 5.5 MODEL VALIDATION (After loading llm.ps1) ==
$modelCheck = Test-ModelSuitability -Model $model -Provider $provider
if ($modelCheck.is_problematic) {
    Write-Host ''
    if ($modelCheck.severity -eq 'error') {
        Write-Host '  ╔═══════════════════════════════════════════════════════════╗' -ForegroundColor Red
        Write-Host '  ║  ⚠️  CRITICAL MODEL ISSUE DETECTED                       ║' -ForegroundColor Red
        Write-Host '  ╚═══════════════════════════════════════════════════════════╝' -ForegroundColor Red
    } else {
        Write-Host '  ┌───────────────────────────────────────────────────────────┐' -ForegroundColor Yellow
        Write-Host '  │  ⚠️  Model Warning                                        │' -ForegroundColor Yellow
        Write-Host '  └───────────────────────────────────────────────────────────┘' -ForegroundColor Yellow
    }
    
    foreach ($w in $modelCheck.warnings) {
        Write-Host "  │  $w" -ForegroundColor $(if ($modelCheck.severity -eq 'error') { 'Red' } else { 'Yellow' })
    }
    Write-Host '  │' -ForegroundColor DarkGray
    Write-Host '  │  Recommended models:' -ForegroundColor Cyan
    foreach ($r in $modelCheck.recommended_models) {
        Write-Host "  │    • $r" -ForegroundColor Green
    }
    
    if ($modelCheck.severity -eq 'error') {
        Write-Host '  │' -ForegroundColor Red
        Write-Host '  │  This model is known to cause frequent patch failures.' -ForegroundColor Red
        Write-Host '  │  Update MODEL in .env to one of the recommended models above.' -ForegroundColor Red
        Write-Host '  ╚═══════════════════════════════════════════════════════════╝' -ForegroundColor Red
    } else {
        Write-Host '  └───────────────────────────────────────────────────────────┘' -ForegroundColor Yellow
    }
    Write-Host ''
    
    if ($modelCheck.severity -eq 'error' -and -not $DryRun) {
        Write-Host '  Press Ctrl+C to abort and change model, or wait 10 seconds to continue anyway...' -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
}
# == 5a. RESTORE MODE ==
if ($Restore) {
    Write-Host '  [RESTORE] Restoring from snapshot...' -ForegroundColor Cyan
    Restore-Snapshot -Date $RestoreDate
    exit 0
}
# == 3.5 TEST CREDENTIALS MODE (MOVED AFTER HELPERS) ==
if ($Test) {
    Write-Host '  ====================================================' -ForegroundColor Cyan
    Write-Host '  [!] Validating credentials ' -ForegroundColor DarkGray
    Write-Host ''
    
    $jiraFailed = $false
    Write-Host '  Testing Jira Connection... ' -NoNewline
    try {
        $null = Invoke-RestMethod -Uri "$jiraUrl/rest/api/2/myself" -Headers $jiraHeaders -Method Get -TimeoutSec 15
        Write-Host '[SUCCESS]' -ForegroundColor Green
    } catch {
        Write-Host '[FAILED]' -ForegroundColor Red
        $errMsg = $_.Exception.Message
        if ($errMsg -match '401|unauthorized') {
            Write-Host "  |  [DIAGNOSIS] AUTHENTICATION FAILED: Your Jira API token or email is incorrect." -ForegroundColor Red
            Write-Host "  |  [FIX] Check JIRA_EMAIL and JIRA_TOKEN in .env. Create a new token from Atlassian settings if needed." -ForegroundColor DarkYellow
        } elseif ($errMsg -match '404|not found') {
            Write-Host "  |  [DIAGNOSIS] NOT FOUND: The Jira URL might be incorrect." -ForegroundColor Red
            Write-Host "  |  [FIX] Check JIRA_URL in .env. Format should be: https://yourdomain.atlassian.net" -ForegroundColor DarkYellow
        } else {
            Write-Host "  |  [ERROR] $errMsg" -ForegroundColor Red
        }
        $jiraFailed = $true
    }
    
    $llmFailed = $false
    Write-Host '  Testing LLM Configuration... ' -NoNewline
    if ($apiKey -and $apiKey -notmatch 'YOUR|your-llm') {
        try {
            # Send a tiny prompt to validate the key actually works
            $null = Invoke-LLM -SysPrompt "You are a test bot." -UserPrompt "Respond with the single word: OK"
            Write-Host '[SUCCESS]' -ForegroundColor Green
            Write-Host "  Provider: $provider" -ForegroundColor DarkGray
            Write-Host "  Model:    $model" -ForegroundColor DarkGray
        } catch {
            Write-Host '[FAILED]' -ForegroundColor Red
            $null = Get-ErrorDiagnosis -ErrorMsg $_.Exception.Message -Context "TEST"
            $llmFailed = $true
        }
    } else {
        Write-Host '[FAILED]' -ForegroundColor Red
        Write-Host "  |  [DIAGNOSIS] KEY MISSING: API key format is invalid or missing in .env" -ForegroundColor Red
        Write-Host "  |  [FIX] Set API_KEY to a valid string in your .env file." -ForegroundColor DarkYellow
        $llmFailed = $true
    }
    
    Write-Host ''
    if ($jiraFailed -or $llmFailed) { 
        Write-Host '  Test finished with errors.' -ForegroundColor Red
        exit 1 
    } else { 
        Write-Host '  All credentials validated successfully!' -ForegroundColor Green
        exit 0 
    }
}

# == 6. FETCH JIRA TICKETS ==
Write-Host '  [1/7] Fetching tickets from Jira...' -ForegroundColor Cyan
$jql = if ($jiraJql) { $jiraJql } else { "project = `"$jiraProj`" AND status NOT IN (Done, Closed, Resolved) ORDER BY priority DESC, created ASC" }
Write-Host "  JQL: $jql" -ForegroundColor DarkGray

$allIssues = @(); $nextPageToken = $null
while ($true) {
    $url = "$jiraUrl/rest/api/3/search/jql?jql=$([uri]::EscapeDataString($jql))&maxResults=50&fields=*all"
    if ($nextPageToken) { $url += "&nextPageToken=$([uri]::EscapeDataString($nextPageToken))" }
    try {
        $r = $null
        try { $r = Invoke-RestMethod -Uri $url -Headers $jiraHeaders -Method Get -TimeoutSec 30 }
        catch { $r = Invoke-RestMethod -Uri "$jiraUrl/rest/api/2/search?jql=$([uri]::EscapeDataString($jql))&startAt=$($allIssues.Count)&maxResults=50" -Headers $jiraHeaders -Method Get -TimeoutSec 30 }
        if ($r.issues) { $allIssues += $r.issues }
        if ($r.isLast -eq $true -or -not $r.nextPageToken) { break }
        $nextPageToken = $r.nextPageToken
    } catch {
        $em = $_.Exception.Message; try{$s=$_.Exception.Response.GetResponseStream();$rd=New-Object IO.StreamReader($s);$eb=$rd.ReadToEnd();if($eb){$em+=" | $eb"}}catch{}
        Write-Host "  FAILED: $em" -ForegroundColor Red; exit 1
    }
}
if ($allIssues.Count -eq 0) { Write-Host '  No open tickets found.' -ForegroundColor Yellow; exit 0 }
Write-Host "  Found $($allIssues.Count) ticket(s)." -ForegroundColor Green
Write-Host ''

# == 7. SCAN CODEBASE & DETECT BUILD TOOLS ==
Write-Host '  [2/7] Scanning codebase...' -ForegroundColor Cyan
Refresh-FileList
Write-Host "  Files: $($relFiles.Count)" -ForegroundColor DarkGray

$script:buildCmd = $null; $script:testCmd = $null
if (Test-Path (Join-Path $cbPath 'package.json')) {
    $pkg = Get-Content (Join-Path $cbPath 'package.json') -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
    if ($pkg -and $pkg.scripts) { if($pkg.scripts.build){$script:buildCmd='npm run build'}; if($pkg.scripts.test){$script:testCmd='npm test'} }
    if (-not $script:buildCmd) { $script:buildCmd = 'npm install' }
} elseif (Test-Path (Join-Path $cbPath 'requirements.txt')) { $script:buildCmd='pip install -r requirements.txt'; $script:testCmd='python -m pytest --tb=short -q 2>nul' }
elseif (Test-Path (Join-Path $cbPath 'pom.xml')) { $script:buildCmd='mvn compile -q'; $script:testCmd='mvn test -q' }
elseif (Test-Path (Join-Path $cbPath 'Cargo.toml')) { $script:buildCmd='cargo build'; $script:testCmd='cargo test' }
elseif (Test-Path (Join-Path $cbPath 'go.mod')) { $script:buildCmd='go build ./...'; $script:testCmd='go test ./...' }

if ($script:buildCmd) { Write-Host "  Build: $($script:buildCmd)" -ForegroundColor DarkGray }

# Load agent memory (self-learning across runs)
$agentMemory = Load-AgentMemory

# == 7a. DEEP CODEBASE MAP ==
Write-Host '  [2b/7] Building codebase intelligence map...' -ForegroundColor Cyan
$codebaseMap = Build-CodebaseMap
Write-Host "  Project Type : $($codebaseMap.project_type)" -ForegroundColor Magenta
if ($codebaseMap.backend_folder) { Write-Host "  Backend Dir  : $($codebaseMap.backend_folder)/" -ForegroundColor Magenta }
if ($codebaseMap.router)         { Write-Host "  Router       : $($codebaseMap.router)" -ForegroundColor DarkGray }
if ($codebaseMap.css_framework)  { Write-Host "  CSS          : $($codebaseMap.css_framework)" -ForegroundColor DarkGray }

# Save updated codebase map to memory
$agentMemory.codebase_map = $codebaseMap
# == 7b. SNAPSHOT BEFORE ANY CHANGES ==
if (-not $DryRun) {
    $snapshotPath = New-Snapshot -TicketIds ($allIssues | ForEach-Object { $_.key })
}

Write-Host ''

# == 8. ARCHITECTURE PLANNING PASS (NEW: Capability 2 - Full Picture) ==
Write-Host '  [3/7] Planning architecture across all tickets...' -ForegroundColor Cyan
$archCacheDir = Get-AgentMemoryDir
if (-not (Test-Path -LiteralPath $archCacheDir)) { New-Item -ItemType Directory -Path $archCacheDir -Force | Out-Null }
$archCacheFile = Join-Path $archCacheDir 'arch-plan.json'
$currentKeys = ($allIssues | ForEach-Object { $_.key }) | Sort-Object
$archPlan = $null

if (Test-Path -LiteralPath $archCacheFile) {
    try {
        $cached = Get-Content -LiteralPath $archCacheFile -Raw | ConvertFrom-Json
        if ($cached -and $cached.ticket_keys) {
            $cachedKeys = @($cached.ticket_keys) | Sort-Object
            if (($currentKeys -join ',') -eq ($cachedKeys -join ',')) {
                $archPlan = $cached.plan
                Write-Host '  [CACHE HIT] Loaded existing architecture plan for these tickets' -ForegroundColor Green
            }
        }
    } catch {}
}

if (-not $archPlan) {
    # Include priority in ticket summaries for the LLM
    $ticketSummaries = ($allIssues | ForEach-Object { 
        $priority = if ($_.fields.priority) { $_.fields.priority.name } else { "None" }
        "$($_.key) [Priority: $priority] [$($_.fields.issuetype.name)] $($_.fields.summary)" 
    }) -join "`n"
    $planSysPrompt = 'You are a senior software architect. You look at ALL tickets together and produce a unified technology plan. Return ONLY valid JSON, no markdown.'
    $planUserPrompt = "ALL OPEN TICKETS:`n$ticketSummaries`n`nEXISTING CODEBASE FILES:`n$(if($relFiles.Count -gt 0){$fileListText}else{'EMPTY - greenfield project'})`n`nProduce a unified architecture plan as JSON:`n{`n  `"tech_stack`": `"e.g. React + Express + PostgreSQL`",`n  `"language`": `"e.g. javascript`",`n  `"framework`": `"e.g. express`",`n  `"folder_structure`": [`"src/`", `"src/routes/`", `"src/models/`", ...],`n  `"ticket_order`": [`"TICKET-1`", `"TICKET-2`", ...] (optional - only specify if dependencies require different order than priority),`n  `"notes`": `"any architectural decisions`"`n}`n`nIMPORTANT: Only specify ticket_order if there are technical dependencies that require a different order than the existing priorities. Otherwise, omit ticket_order to use Jira priority order."

    try {
        $planRaw = Invoke-LLM -SysPrompt $planSysPrompt -UserPrompt $planUserPrompt
        $archPlan = Get-ParsedJson -Text $planRaw
        if ($archPlan) {
            # Save to cache
            $cacheObj = @{
                ticket_keys = $currentKeys
                plan = $archPlan
            }
            $cacheObj | ConvertTo-Json -Depth 10 | Set-Content $archCacheFile -Encoding UTF8
        }
    } catch {
        Write-Host "  [WARN] Planning failed (will proceed without plan): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
}

if ($archPlan) {
    Write-Host "  Tech Stack : $($archPlan.tech_stack)" -ForegroundColor Magenta
    Write-Host "  Language   : $($archPlan.language)" -ForegroundColor Magenta
    Write-Host "  Framework  : $($archPlan.framework)" -ForegroundColor Magenta
    if ($archPlan.notes) { Write-Host "  Notes      : $($archPlan.notes)" -ForegroundColor DarkGray }
}
Write-Host ''
if (-not $global:FastMode) { Start-Sleep -Seconds 2 }

# == 9. SMART TICKET ORDERING (Respects Jira order or arch plan) ==
Write-Host '  [4/7] Ordering tickets...' -ForegroundColor Cyan

# If arch plan specified an order, use it (unless UseJiraPriority is set)
$orderedIssues = @()
if ($UseJiraPriority) {
    # Force use of Jira priority order (ignore arch plan)
    $orderedIssues = @() + $allIssues
    Write-Host "  Using Jira priority order (forced via -UseJiraPriority)" -ForegroundColor Cyan
} elseif ($archPlan -and $archPlan.ticket_order) {
    foreach ($key in $archPlan.ticket_order) {
        $match = $allIssues | Where-Object { $_.key -eq $key }
        if ($match) { $orderedIssues += $match }
    }
    # Add any tickets not in the plan
    $remaining = $allIssues | Where-Object { $_.key -notin $archPlan.ticket_order }
    $orderedIssues += $remaining
    Write-Host "  Using architecture plan order: $($archPlan.ticket_order -join ', ')" -ForegroundColor DarkGray
} else {
    # Preserve original Jira order (already sorted by JQL: priority DESC, created ASC)
    $orderedIssues = @() + $allIssues
    Write-Host "  Using Jira priority order (priority DESC, created ASC)" -ForegroundColor DarkGray
}

Write-Host "  Processing $($orderedIssues.Count) ticket(s) in order: $($orderedIssues.key -join ', ')" -ForegroundColor DarkGray
Write-Host ''

# Session memory: what has been done so far (shared across sub-tasks)
$sessionContext = New-Object System.Collections.Generic.List[string]
$log = New-Object System.Collections.Generic.List[hashtable]

$codebaseContext = Get-CodebaseContext -CodebaseMap $codebaseMap

# == 10. MAIN PROCESSING LOOP ==
Write-Host '  [5/7] Processing tickets...' -ForegroundColor Cyan
Write-Host ''

$counter = 0
foreach ($issue in $orderedIssues) {
    $counter++
    $ticketId  = $issue.key
    $issueType = $issue.fields.issuetype.name
    $summary   = $issue.fields.summary
    $ticketText = Get-TicketContext -Issue $issue

    Write-Host "  +-- [$counter/$($orderedIssues.Count)] $ticketId" -ForegroundColor Cyan
    Write-Host "  |  Type    : $issueType" -ForegroundColor Gray
    Write-Host "  |  Summary : $summary" -ForegroundColor Gray

    # === TICKET QUALITY (always passes - inference fills gaps) ===
    $qualityCheck = Test-TicketQuality -Issue $issue
    if ($qualityCheck.score -lt 50) {
        Write-Host "  |  [INFER] Low quality score ($($qualityCheck.score)/100) - will infer from codebase" -ForegroundColor DarkYellow
    }

    # === PHASE: INFER (expand vague tickets by reading codebase) ===
    Write-Host '  |  [INFER] Expanding ticket requirements from codebase...' -ForegroundColor DarkGray
    $inferSys  = 'You are a senior engineer auditing requirements from a Jira ticket. Check the provided RELEVANT CODE and codebase context to see if any parts of the ticket are already implemented. Explicitly filter out completed work and infer exactly what STILL needs to be done (the missing/remaining work). Return ONLY valid JSON.'
    $ticketCtxForInfer = Get-TicketContext -Issue $issue

    # Read a few files related to the ticket keywords
    $sumWords2  = $summary.ToLower() -split '\s+' | Where-Object { $_.Length -gt 3 }
    $relFiles2  = @()
    foreach ($w in $sumWords2) {
        $relFiles2 += $script:relFiles | Where-Object { $_.ToLower() -match [regex]::Escape($w) } | Select-Object -First 2
    }
    $relFiles2 = @($relFiles2 | Select-Object -Unique -First 5)
    $relFileContents2 = ''
    foreach ($rf2 in $relFiles2) {
        $abs2 = Join-Path $cbPath $rf2
        if (Test-Path -LiteralPath $abs2) {
            $c2 = Get-Content -LiteralPath $abs2 -Raw -EA SilentlyContinue
            if ($c2) { $relFileContents2 += "--- $rf2 ---`n$($c2.Substring(0,[Math]::Min(50000,$c2.Length)))`n" }
        }
    }

    # === PHASE: INFER (expand requirements) ===
    # Skip inference for simple Bug tickets - they're already specific
    $skipInference = ($issueType -eq 'Bug' -and $complexity -notmatch 'complex')
    
    $inferUser = "$ticketCtxForInfer`n`n$codebaseContext`n$memoryContext`n`nRELEVANT CODE:`n$relFileContents2`n`nReturn JSON: {`"is_completely_implemented`": true|false, `"expanded_description`": `"detailed tech spec of ONLY the REMAINING missing work`", `"estimated_complexity`": `"simple|medium|complex`", `"key_files_affected`": []}"
    $inferResult = @{ expanded_description=$ticketCtxForInfer; estimated_complexity='medium'; key_files_affected=@() }
    
    if ($skipInference) {
        Write-Host '  |  [INFER] Skipped for simple Bug - using original description' -ForegroundColor DarkGray
        $inferResult.estimated_complexity = 'simple'
    } else {
        try {
            $inferRaw  = Invoke-LLM -SysPrompt $inferSys -UserPrompt $inferUser
            $inferParsed = Get-ParsedJson -Text $inferRaw
            if ($inferParsed) {
                if ($inferParsed.is_completely_implemented -eq $true) {
                    Write-Host "  |  [INFER] Ticket is already completely implemented! Skipping." -ForegroundColor Green
                    $log += @{ ticketId=$ticketId; status='COMPLETED' }
                    $ticketSuccess = $true
                    continue
                }
                if ($inferParsed.expanded_description) {
                    $inferResult = $inferParsed
                    Write-Host "  |  [INFER] Complexity: $($inferResult.estimated_complexity)" -ForegroundColor DarkGray
                }
            }
        } catch { Write-Host '  |  [INFER] Skipped (using original description)' -ForegroundColor DarkGray }
    }
    
    # Shorter delay for simple tickets
    if (-not $global:FastMode) { 
        if ($inferResult.estimated_complexity -eq 'simple') { Start-Sleep -Seconds 1 }
        else { Start-Sleep -Seconds 3 }
    }

    # === PHASE: DECOMPOSE (split complex tickets into sub-tasks) ===
    $subtasks = @()
    # Skip decomposition for Bug tickets and simple complexity
    $shouldDecompose = ($issueType -ne 'Bug' -and $inferResult.estimated_complexity -eq 'complex')
    if ($shouldDecompose) {
        Write-Host '  |  [DECOMPOSE] Complex ticket - splitting into sub-tasks...' -ForegroundColor DarkGray
        $decomposeSys  = "You decompose software tickets into ordered sub-tasks. Each sub-task max 3-4 files (~3000 tokens output). Backend files go in: $($codebaseMap.backend_folder)/. Return ONLY valid JSON."
        $decomposeUser = "$ticketCtxForInfer`n`nEXPANDED: $($inferResult.expanded_description)`n`n$codebaseContext`n`nReturn: {`"decompose`": true/false, `"subtasks`": [{`"id`": 1, `"name`": `"..`", `"description`": `"..`", `"files_hint`": [], `"depends_on`": [], `"is_build_affecting`": true}]}"
        try {
            if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
            $decompRaw    = Invoke-LLM -SysPrompt $decomposeSys -UserPrompt $decomposeUser
            $decompParsed = Get-ParsedJson -Text $decompRaw
            if ($decompParsed -and $decompParsed.decompose -eq $true -and $decompParsed.subtasks) {
                $subtasks = @($decompParsed.subtasks)
                Write-Host "  |  [DECOMPOSE] $($subtasks.Count) sub-task(s) identified" -ForegroundColor Green
                foreach ($st in $subtasks) { Write-Host "  |    - Sub-task $($st.id): $($st.name)" -ForegroundColor DarkGray }
            }
        } catch { Write-Host '  |  [DECOMPOSE] Skipped - will process as single task' -ForegroundColor DarkGray }
        if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
    } else {
        if ($issueType -eq 'Bug') {
            Write-Host '  |  [DECOMPOSE] Skipped for Bug ticket' -ForegroundColor DarkGray
        }
    }

    # If no sub-tasks, treat as single sub-task
    if ($subtasks.Count -eq 0) {
        $subtasks = @(@{ id=1; name='Implementation'; description=$inferResult.expanded_description; files_hint=@(); depends_on=@(); is_build_affecting=$true })
    }

    Write-Host "  |  [VALIDATE] Score: $($qualityCheck.score)/100 | Sub-tasks: $($subtasks.Count)" -ForegroundColor Green

    Refresh-FileList

    # Context shared across all sub-tasks
    $archContext  = if ($archPlan) { "ARCHITECTURE PLAN: Tech=$($archPlan.tech_stack), Lang=$($archPlan.language), Framework=$($archPlan.framework)`n" } else { '' }
    $sessionCtx   = if ($sessionContext.Count -gt 0) { "ALREADY COMPLETED THIS SESSION:`n" + ($sessionContext -join "`n") + "`n" } else { '' }
    $cbContext     = if ($script:relFiles.Count -gt 0) { "EXISTING FILES:`n$script:fileListText" } else { 'CODEBASE IS EMPTY' }
    $genSysBase    = $agentCtx + "`n`n" + $skillsCtx + "`n`n" + $archContext + $codebaseContext

    # Track sub-task session context (what each sub-task created, for the next sub-task)
    $subtaskContext   = ''
    $ticketAllCreated = @()
    $ticketPkgsInstalled = @()
    $ticketBuildErrors   = @()
    $ticketBuildFixes    = @()
    $ticketSuccess       = $true
    $ticketExplanation   = ''

    # ============================================================
    # SUB-TASK EXECUTION LOOP  —  Developer Loop (per-file)
    # ============================================================
    $stCounter = 0
    foreach ($subtask in $subtasks) {
        $stCounter++
        $stName    = $subtask.name
        $stDesc    = $subtask.description
        $filesHint = if ($subtask.files_hint) { "FILES TO CREATE/MODIFY: $($subtask.files_hint -join ', ')`n" } else { '' }

        Write-Host "  |" -ForegroundColor DarkGray
        Write-Host "  |  [SUB-TASK $stCounter/$($subtasks.Count)] $stName" -ForegroundColor Cyan

        # Keyword match to find most relevant existing file
        $targetFile = $null
        $sumWords   = ($stName + ' ' + $stDesc).ToLower() -split '\s+' | Where-Object { $_.Length -gt 3 }
        foreach ($f in $script:relFiles) {
            foreach ($w in $sumWords) { if ($f.ToLower() -match [regex]::Escape($w)) { $targetFile = $f; break } }
            if ($targetFile) { break }
        }
        $fileSection    = ''
        $relatedContext = ''
        if ($targetFile) {
            $absT = Join-Path $cbPath $targetFile
            $rawT = Get-Content -LiteralPath $absT
            $numT = for ($i=0; $i -lt $rawT.Count; $i++) { "$($i+1): $($rawT[$i])" }
            $fileSection    = "TARGET FILE: $targetFile`nCONTENT:`n" + ($numT -join "`n")
            $relatedContext = Get-RelatedFilesContent -TargetFile $targetFile
        }

        $memoryContext = Get-MemoryContext -Memory $agentMemory -Keywords "$summary $stName $stDesc"
        
        # ===  READ CRITICAL SCHEMA FILES (NEW) ===
        $schemaContext = ''
        $criticalFiles = @()
        
        # Prisma schema
        $prismaSchema = Join-Path $cbPath 'prisma\schema.prisma'
        if (Test-Path -LiteralPath $prismaSchema) {
            try {
                $prismaContent = Get-Content -LiteralPath $prismaSchema -Raw -EA SilentlyContinue
                if ($prismaContent) {
                    $schemaContext += "`n=== PRISMA SCHEMA (CRITICAL - USE EXACT FIELD NAMES FROM THIS SCHEMA) ===`nFile: prisma/schema.prisma`n`n$prismaContent`n`nIMPORTANT: All database operations MUST use the exact model names, field names, and relations defined above. Do NOT guess field names.`n"
                    $criticalFiles += 'prisma/schema.prisma'
                    Write-Host "  |  [SCHEMA] Loaded Prisma schema ($($prismaContent.Length) chars)" -ForegroundColor DarkCyan
                }
            } catch { }
        }
        
        # GraphQL schema
        $graphqlSchema = Join-Path $cbPath 'schema.graphql'
        if (Test-Path -LiteralPath $graphqlSchema) {
            try {
                $graphqlContent = Get-Content -LiteralPath $graphqlSchema -Raw -EA SilentlyContinue
                if ($graphqlContent -and $graphqlContent.Length -lt 5000) {
                    $schemaContext += "`n=== GRAPHQL SCHEMA ===`n$graphqlContent`n"
                    $criticalFiles += 'schema.graphql'
                }
            } catch { }
        }
        
        # TypeScript types/interfaces
        $typesFile = Join-Path $cbPath 'src\types.ts'
        if (Test-Path -LiteralPath $typesFile) {
            try {
                $typesContent = Get-Content -LiteralPath $typesFile -Raw -EA SilentlyContinue
                if ($typesContent -and $typesContent.Length -lt 3000) {
                    $schemaContext += "`n=== TYPESCRIPT TYPES ===`n$typesContent`n"
                    $criticalFiles += 'src/types.ts'
                }
            } catch { }
        }
        
        # Database migration files (latest only)
        $migrationsDir = Join-Path $cbPath 'prisma\migrations'
        if (Test-Path -LiteralPath $migrationsDir) {
            $latestMigration = Get-ChildItem -LiteralPath $migrationsDir -Directory -EA SilentlyContinue |
                               Sort-Object Name -Descending | Select-Object -First 1
            if ($latestMigration) {
                $migrationSql = Join-Path $latestMigration.FullName 'migration.sql'
                if (Test-Path -LiteralPath $migrationSql) {
                    try {
                        $sqlContent = Get-Content -LiteralPath $migrationSql -Raw -EA SilentlyContinue
                        if ($sqlContent -and $sqlContent.Length -lt 3000) {
                            $schemaContext += "`n=== LATEST DB MIGRATION ===`n$sqlContent`n"
                        }
                    } catch { }
                }
            }
        }
        
        $genSys        = $genSysBase + $memoryContext + $schemaContext

        # ----------------------------------------------------------------
        # STEP 1: PLAN - ask LLM for file list (no code yet)
        # ----------------------------------------------------------------
        Write-Host "  |  [PLAN] Identifying files for this sub-task..." -ForegroundColor DarkGray
        $planSys  = 'You are a senior developer planning a sub-task. List the exact files to create or patch. Return ONLY valid JSON - no code content.'
        $planUser = "TICKET: $ticketId [$issueType] $summary`nSUBTASK: $stName`nDESCRIPTION: $stDesc`n$filesHint`n$cbContext`n`n$subtaskContext`n`nReturn: {`"files`": [{`"file_path`": `"src/..`", `"action`": `"create|patch`", `"description`": `"what this file does`"}]}"

        $filePlan = @()
        try {
            if (-not $global:FastMode) { Start-Sleep -Seconds 1 }
            $planRaw    = Invoke-LLM -SysPrompt $planSys -UserPrompt $planUser
            $planParsed = Get-ParsedJson -Text $planRaw
            if ($planParsed -and $planParsed.files -and $planParsed.files.Count -gt 0) {
                $filePlan = @($planParsed.files)
                Write-Host "  |  [PLAN] $($filePlan.Count) file(s) planned" -ForegroundColor DarkGray
                foreach ($pf in $filePlan) { Write-Host "  |    $($pf.action.ToUpper()): $($pf.file_path)" -ForegroundColor DarkGray }
            }
        } catch { Write-Host "  |  [PLAN] Plan step skipped" -ForegroundColor DarkGray }

        # Fallback: if plan fails, use a single synthetic entry (generates all at once)
        if ($filePlan.Count -eq 0) {
            Write-Host "  |  [PLAN] Fallback - single-pass generation" -ForegroundColor DarkYellow
            $filePlan = @(@{ file_path='_ALL_'; action='create'; description=$stDesc })
        }

        # ----------------------------------------------------------------
        # STEP 2: GENERATE + COMPILE + REVIEW per file
        # ----------------------------------------------------------------
        $allFiles  = [System.Collections.Generic.List[psobject]]::new()
        $stCreated = @(); $stBackups = @{}; $stPatched = @()
        $stSuccess = $true

        # -------- READ FILES BEFORE GENERATING (CRITICAL FIX) --------
        Write-Host "  |  [READ] Reading current file content for patches..." -ForegroundColor DarkGray
        $filesForGen = Get-FilesForPatching -PlannedFiles $filePlan
        $fileContextStr = Build-FileContextString -FilesContext $filesForGen
        
        # -------- Generate code (Hybrid Batch) --------
        Write-Host "  |  [AI] Generating hybrid batch for sub-task..." -ForegroundColor DarkGray
        
        $alreadyDone = ($allFiles | ForEach-Object { $_.file_path }) -join ', '
        $planStr = ($filePlan | ConvertTo-Json -Compress)
        $genUser = "$taskCtx`n`nTICKET: $ticketId [$issueType] $summary`n`nSUBTASK $stCounter/$($subtasks.Count): $stName`nDESCRIPTION: $stDesc`n`n$cbContext`n`n$subtaskContext`n`n$relatedContext`n`n$fileSection`n`n$schemaContext`n`n$fileContextStr`n`nOTHER FILES ALREADY WRITTEN THIS SUB-TASK: $alreadyDone`n`nPLANNED FILES TO GENERATE:`n$planStr`n`n=== CRITICAL PATCHING INSTRUCTIONS ===`nFor files marked 'patch' above, you have been shown the COMPLETE CURRENT CONTENT with line numbers.`n`nWhen creating search_fallback:`n1. Copy 4-6 consecutive lines EXACTLY from the numbered content shown above`n2. Include the EXACT whitespace, indentation, and punctuation`n3. Choose lines that are UNIQUE enough to find (avoid generic code like closing braces)`n4. Include the line(s) you want to change PLUS 2-3 lines of context before/after`n5. DO NOT modify or normalize the search text - use it EXACTLY as shown`n`nFor replace_fallback:`n1. Take the same lines from search_fallback`n2. Apply ONLY the necessary changes for this ticket`n3. Preserve all other formatting exactly`n`nIf this ticket involves database operations, you MUST use the exact field names and model names from the schema provided above. Return ONLY valid JSON: { 'files': [ { 'action': 'create|patch', 'file_path': '...', 'search_fallback': '...', 'replace_fallback': '...', 'file_content': '...' } ] }"

        $parsed = $null
        try {
            $rawGen = Invoke-LLM -SysPrompt $genSys -UserPrompt $genUser
            $parsed = Get-ParsedJson -Text $rawGen
        } catch {
            Write-Host "  |  [ERROR] LLM: $($_.Exception.Message)" -ForegroundColor Red
            $ticketSuccess = $false; continue
        }
        if (-not $parsed) {
            Write-Host "  |  [WARN] Parse failed. Retrying..." -ForegroundColor DarkYellow
            if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
            try {
                $rawGen2 = Invoke-LLM -SysPrompt $genSys -UserPrompt ($genUser + "`n`nWARNING: Previous response was not valid JSON. Return ONLY valid JSON.")
                $parsed  = Get-ParsedJson -Text $rawGen2
            } catch { }
        }
        if (-not $parsed) { Write-Host "  |  [ERROR] Parse failed" -ForegroundColor Red; $ticketSuccess = $false; continue }
        if ($parsed.patchable -eq $false) { Write-Host "  |  [SKIP] Non-code sub-task" -ForegroundColor Yellow; continue }
        if ($ticketExplanation -eq '') { $ticketExplanation = if ($parsed.explanation) { $parsed.explanation } else { $parsed.analysis } }

        # Normalize files list
        $batchFiles = @()
        if ($parsed -is [array])                                               { $batchFiles = $parsed }
        elseif ($parsed.files -and $parsed.files.Count -gt 0)                  { $batchFiles = $parsed.files }
        elseif ($parsed.file_path -and $parsed.file_content)                   { $batchFiles = @($parsed) }
        if ($batchFiles.Count -eq 0) { Write-Host "  |  [SKIP] No files" -ForegroundColor Yellow; continue }

        # Correct destinations
        $batchFiles = @($batchFiles | ForEach-Object {
            $corrected = Resolve-FileDestination -FilePath $_.file_path -CodebaseMap $codebaseMap
            if ($corrected -ne $_.file_path) { $_ | Add-Member -NotePropertyName 'file_path' -NotePropertyValue $corrected -Force }
            $_
        })

        # Static code review on this batch
        $codeReview = Invoke-CodeReview -Files $batchFiles
        if ($codeReview.issues.Count -gt 0) {
            Write-Host "  |  [CODE REVIEW] $($codeReview.issues.Count) critical issue(s) - skipping this batch" -ForegroundColor Red
            foreach ($cri in $codeReview.issues) { Write-Host "  |    - $cri" -ForegroundColor Red }
            $ticketSuccess = $false; continue
        }
        if ($codeReview.warnings.Count -gt 0) {
            Write-Host "  |  [CODE REVIEW] $($codeReview.warnings.Count) warning(s)" -ForegroundColor Yellow
        }

        # DRY RUN
        if ($DryRun) {
            foreach ($bf in $batchFiles) { Write-Host "  |  [DRY] $($bf.action.ToUpper()): $($bf.file_path)" -ForegroundColor Yellow }
            foreach ($bf in $batchFiles) { $allFiles.Add($bf) }
            continue
        }

        # -------- Write to disk --------
        foreach ($fileObj in $batchFiles) {
                $fp  = $fileObj.file_path -replace '\\','/'
                $abs = Join-Path $cbPath ($fp -replace '/','\')
                $writeOk = $false
                $fileExists = Test-Path -LiteralPath $abs

                if ($fileObj.action -eq 'patch' -and $fileExists) {
                    # PATCH: prefer search/replace to preserve existing file content
                    $stBackups[$abs] = Backup-File -FilePath $abs -TicketId $ticketId
                    
                    if ($fileObj.search_fallback -and $fileObj.replace_fallback) {
                        # Use improved smart patch
                        $patchResult = Apply-SmartPatch -FilePath $abs -SearchText $fileObj.search_fallback -ReplaceText $fileObj.replace_fallback
                        
                        if ($patchResult.success) {
                            Write-Host "  |  [OK] Patched: $fp ($($patchResult.message))" -ForegroundColor Green
                            $stPatched += $abs; $writeOk = $true
                        } else {
                            Write-Host "  |  [WARN] Patch failed: $($patchResult.message)" -ForegroundColor Yellow
                            
                            # Fallback to full rewrite if LLM provided file_content
                            if ($fileObj.file_content) {
                                Write-Host "  |  [WARN] Falling back to full rewrite for: $fp" -ForegroundColor Yellow
                                $writeResult = Write-FileWithValidation -FilePath $abs -Content $fileObj.file_content
                                if ($writeResult.success) {
                                    Write-Host "  |  [OK] Rewrote: $fp" -ForegroundColor Green
                                    $stPatched += $abs; $writeOk = $true
                                } else {
                                    Write-Host "  |  [ERROR] Rewrite failed: $($writeResult.message)" -ForegroundColor Red
                                }
                            }
                        }
                    } elseif ($fileObj.file_content) {
                        # LLM gave full file_content for a patch - warn but apply
                        Write-Host "  |  [WARN] Patch has full file_content for existing file: $fp - applying full rewrite" -ForegroundColor Yellow
                        $writeResult = Write-FileWithValidation -FilePath $abs -Content $fileObj.file_content
                        if ($writeResult.success) {
                            Write-Host "  |  [OK] Rewrote: $fp" -ForegroundColor Green
                            $stPatched += $abs; $writeOk = $true
                        } else {
                            Write-Host "  |  [ERROR] Rewrite failed: $($writeResult.message)" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "  |  [WARN] No valid patch data for: $fp" -ForegroundColor Yellow
                    }
                } elseif ($fileObj.action -eq 'create' -or (-not $fileExists -and $fileObj.file_content)) {
                    # CREATE: new file or file doesn't exist yet
                    $dir2 = Split-Path $abs -Parent
                    if (-not (Test-Path $dir2)) { New-Item -ItemType Directory -Path $dir2 -Force | Out-Null }
                    if ($fileExists) { $stBackups[$abs] = Backup-File -FilePath $abs -TicketId $ticketId }
                    
                    $writeResult = Write-FileWithValidation -FilePath $abs -Content $fileObj.file_content
                    if ($writeResult.success) {
                        Write-Host "  |  [OK] Created: $fp" -ForegroundColor Green
                        $stCreated += $abs; $ticketAllCreated += $fp; $writeOk = $true
                    } else {
                        Write-Host "  |  [ERROR] Create failed: $($writeResult.message)" -ForegroundColor Red
                        if (-not $writeResult.integrity.complete) {
                            foreach ($issue in $writeResult.integrity.issues) {
                                Write-Host "  |    - $issue" -ForegroundColor Red
                            }
                        }
                    }
                } elseif ($fileObj.search_fallback -and $fileObj.replace_fallback) {
                    # Fallback for unspecified action with search/replace
                    if ($fileExists) {
                        $stBackups[$abs] = Backup-File -FilePath $abs -TicketId $ticketId
                        $patchResult = Apply-SmartPatch -FilePath $abs -SearchText $fileObj.search_fallback -ReplaceText $fileObj.replace_fallback
                        
                        if ($patchResult.success) {
                            Write-Host "  |  [OK] Patched: $fp" -ForegroundColor Green
                            $stPatched += $abs; $writeOk = $true
                        } else {
                            Write-Host "  |  [WARN] Patch failed: $($patchResult.message)" -ForegroundColor Yellow
                        }
                    } else { 
                        Write-Host "  |  [WARN] File not found for patch: $fp" -ForegroundColor Yellow 
                    }
                } else {
                    Write-Host "  |  [WARN] No valid write method for: $fp" -ForegroundColor Yellow
                } 

                if ($writeOk) {
                    $allFiles.Add($fileObj)
                    
                    # File integrity is already checked by Write-FileWithValidation
                    # Just verify compilation for code files

                    # -------- Per-file compile check + surgical fix --------
                    $fileExt = [IO.Path]::GetExtension($fp).ToLower()
                    if ($fileExt -match '\.(ts|tsx|py|go)$') {
                        Write-Host "  |  [COMPILE] Checking $fp..." -ForegroundColor DarkGray
                        $compResult = Invoke-CompileCheck -CodebaseMap $codebaseMap
                        if (-not $compResult.pass) {
                            $fileNamePat = [regex]::Escape([IO.Path]::GetFileName($fp))
                            $fileErrors  = $compResult.errors | Where-Object {
                                ($_.file -eq $fp) -or ($_.file -match $fileNamePat)
                            }
                            if ($fileErrors.Count -gt 0) {
                                $firstErr = $fileErrors[0]
                                Write-Host "  |  [COMPILE] Error line $($firstErr.line): $($firstErr.message)" -ForegroundColor Yellow
                                $sfResult = Invoke-ImprovedSurgicalFix -FilePath $fp -CompileError $firstErr -MaxAttempts 5
                                if (-not $sfResult.fixed) {
                                    Write-Host "  |  [COMPILE] Could not fix after $($sfResult.attempts) attempts - keeping file" -ForegroundColor DarkYellow
                                }
                            } else {
                                Write-Host "  |  [COMPILE] Error in other files (not blocking $fp)" -ForegroundColor DarkGray
                            }
                        } else {
                            Write-Host "  |  [COMPILE] Passed!" -ForegroundColor Green
                        }
                    }
                } # end writeOk
            } # end foreach fileObj in batchFiles
        
        # -------- Batch AI Review (after all files written) --------
        if ($allFiles.Count -gt 0 -and -not $DryRun) {
            Write-Host "  |  [AI REVIEW] Batch reviewing $($allFiles.Count) file(s)..." -ForegroundColor DarkGray
            
            # Collect all written files for batch review
            $reviewBatch = @()
            foreach ($f in $allFiles) {
                $fp = $f.file_path -replace '\\','/'
                $abs = Join-Path $cbPath ($fp -replace '/','\')
                if (Test-Path -LiteralPath $abs) {
                    try {
                        $content = Get-Content -LiteralPath $abs -Raw -EA SilentlyContinue
                        if ($content -and $content.Length -gt 50) {
                            $reviewBatch += @{ file_path=$fp; file_content=$content }
                        }
                    } catch {
                        Write-Host "  |  [WARN] Could not read $fp for review" -ForegroundColor DarkYellow
                    }
                }
            }
            
            if ($reviewBatch.Count -gt 0) {
                try {
                    $batchReview = Invoke-AILogicReview -Files $reviewBatch -TicketSummary "$summary - $stName"
                    
                    if (-not $batchReview.approved) {
                        Write-Host "  |  [AI REVIEW] Found $($batchReview.issues.Count) issue(s) across batch" -ForegroundColor Yellow
                        
                        # Group issues by file for organized fixing
                        $issuesByFile = @{}
                        foreach ($iss in $batchReview.issues) {
                            $issFile = if ($iss -is [psobject] -and $iss.file_path) { $iss.file_path } else { $reviewBatch[0].file_path }
                            if (-not $issuesByFile.ContainsKey($issFile)) {
                                $issuesByFile[$issFile] = @()
                            }
                            $issuesByFile[$issFile] += $iss
                        }
                        
                        # Fix issues per file (limit to first 3 issues per file)
                        foreach ($fileKey in $issuesByFile.Keys) {
                            $fileIssues = $issuesByFile[$fileKey] | Select-Object -First 3
                            Write-Host "  |    [$fileKey] $($fileIssues.Count) issue(s)" -ForegroundColor Yellow
                            
                            foreach ($iss in $fileIssues) {
                                $issMsg  = if ($iss -is [psobject] -and $iss.description) { $iss.description } else { "$iss" }
                                $issLine = if ($iss -is [psobject] -and $iss.line) { 
                                    $lineVal = "$($iss.line)"
                                    if ($lineVal -match '^(\d+)') { [int]$Matches[1] } else { 0 }
                                } else { 0 }
                                
                                $surgErr = @{ file=$fileKey; line=$issLine; col=0; code='REVIEW'; message=$issMsg }
                                try {
                                    $sfResult = Invoke-ImprovedSurgicalFix -FilePath $fileKey -CompileError $surgErr -MaxAttempts 3
                                    if (-not $sfResult.fixed) { 
                                        $shortMsg = if ($issMsg.Length -gt 60) { $issMsg.Substring(0, 60) + "..." } else { $issMsg }
                                        Write-Host "  |      [SKIP] Could not fix: $shortMsg" -ForegroundColor DarkYellow 
                                    }
                                } catch {
                                    Write-Host "  |      [ERROR] Fix failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
                                }
                            }
                        }
                        
                        # Apply safe auto-fixes
                        if ($batchReview.auto_fixes -and $batchReview.auto_fixes.Count -gt 0) {
                            Write-Host "  |  [AI REVIEW] Applying $($batchReview.auto_fixes.Count) auto-fix(es)..." -ForegroundColor DarkGray
                            foreach ($fix in $batchReview.auto_fixes) {
                                try {
                                    $fixAbs = Join-Path $cbPath ($fix.file_path -replace '/','\')
                                    if (Test-Path -LiteralPath $fixAbs) {
                                        $patchResult = Apply-SmartPatch -FilePath $fixAbs -SearchText $fix.search_fallback -ReplaceText $fix.replace_fallback
                                        if ($patchResult.success) {
                                            Write-Host "  |    [AUTO-FIX] $($fix.file_path)" -ForegroundColor DarkYellow
                                        } else {
                                            Write-Host "  |    [SKIP] Auto-fix failed for $($fix.file_path): $($patchResult.message)" -ForegroundColor Yellow
                                        }
                                    }
                                } catch {
                                    Write-Host "  |    [ERROR] Auto-fix error for $($fix.file_path): $($_.Exception.Message)" -ForegroundColor DarkYellow
                                }
                            }
                        }
                    } else {
                        Write-Host "  |  [AI REVIEW] All files OK" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  |  [WARN] Batch review failed: $($_.Exception.Message) - continuing..." -ForegroundColor Yellow
                }
            }
        }
        
        # Skip sub-task if nothing was written
        if ($DryRun) {
            $log.Add(@{ticket=$ticketId;status='DRY_RUN';subtask=$stName;file=($allFiles|%{$_.file_path})-join','})
            continue
        }
        if ($stCreated.Count -eq 0 -and $stPatched.Count -eq 0) {
            Write-Host "  |  [SUB-TASK $stCounter] No files written - skipping" -ForegroundColor Yellow
            $ticketSuccess = $false; continue
        }

        # ----------------------------------------------------------------
        # STEP 3: Install packages + CVE audit
        # ----------------------------------------------------------------
        $pkgsInstalled = Install-RequiredPackages -Files $allFiles -CodebaseMap $codebaseMap
        $ticketPkgsInstalled += $pkgsInstalled
        if ($pkgsInstalled.Count -gt 0) {
            $audit = Invoke-PackageAudit -CodebaseMap $codebaseMap
            if (-not $audit.pass) {
                Write-Host "  |  [SECURITY] Critical CVE found - skipping sub-task" -ForegroundColor Red
                foreach ($cve in $audit.critical) { Write-Host "  |    - $cve" -ForegroundColor Red }
                $ticketSuccess = $false; continue
            }
            if ($audit.warnings.Count -gt 0) { foreach ($w in $audit.warnings) { Write-Host "  |  [AUDIT] $w" -ForegroundColor Yellow } }
        }

        # ----------------------------------------------------------------
        # STEP 4: Full integration build + surgical build fix
        # ----------------------------------------------------------------
        $isBuildAffecting = if ($subtask.PSObject.Properties['is_build_affecting']) { $subtask.is_build_affecting } else { $true }
        if ($isBuildAffecting -and $script:buildCmd) {
            Write-Host "  |  [BUILD] Running full build..." -ForegroundColor DarkGray
            Refresh-FileList
            $buildResult = Invoke-SafeBuild -CodebaseMap $codebaseMap
            if (-not $buildResult.success) {
                Write-Host "  |  [BUILD] Failed - surgical fix..." -ForegroundColor Red
                $ticketBuildErrors += $buildResult.errors
                $fixResult = Invoke-ImprovedBuildFix -BuildError $buildResult.errors -RecentFiles $allFiles -MaxRetries 5 -CodebaseMap $codebaseMap
                if ($fixResult.fixed) {
                    Write-Host "  |  [BUILD] Fixed! $($fixResult.diagnosis)" -ForegroundColor Green
                    $ticketBuildFixes += $fixResult.diagnosis
                } else {
                    Write-Host "  |  [BUILD] Could not fix - keeping files, marking partial" -ForegroundColor DarkYellow
                    Write-Host "  |  [BUILD] $($fixResult.diagnosis)" -ForegroundColor DarkYellow
                    foreach ($e in $stBackups.GetEnumerator()) {
                        $isCreated = $stCreated -contains $e.Key
                        if (-not $isCreated -and (Test-Path $e.Value)) { Copy-Item $e.Value $e.Key -Force }
                    }
                    $ticketSuccess = $false
                }
            } else {
                Write-Host "  |  [BUILD] Passed!" -ForegroundColor Green
            }
        }

        # ----------------------------------------------------------------
        # STEP 5: Run all tests
        # ----------------------------------------------------------------
        if ($script:testCmd) {
            Refresh-FileList
            $testResult = Invoke-RunTests -CodebaseMap $codebaseMap -RecentFiles $allFiles
            if (-not $testResult.pass) {
                Write-Host "  |  [TESTS] Some tests still failing - continuing" -ForegroundColor DarkYellow
            }
        }

        # ----------------------------------------------------------------
        # STEP 6: Runtime check (start server + hit endpoints)
        # ----------------------------------------------------------------
        $runtimeResult = Invoke-RuntimeCheck -CodebaseMap $codebaseMap -TicketDescription $ticketText
        if ($runtimeResult.started) {
            $rColor = if ($runtimeResult.endpointsFailed -eq 0) { 'Green' } else { 'Yellow' }
            Write-Host "  |  [RUNTIME] $($runtimeResult.endpointsPassed) passed, $($runtimeResult.endpointsFailed) failed" -ForegroundColor $rColor
        }

        # ----------------------------------------------------------------
        # STEP 7: Cross-file wiring check
        # ----------------------------------------------------------------
        $wiringIssues = Test-CrossFileWiring -NewFiles ($allFiles | Where-Object { $_.file_content })
        foreach ($wi in $wiringIssues) { Write-Host "  |  [WIRING] $wi" -ForegroundColor DarkYellow }

        # ----------------------------------------------------------------
        # STEP 8: Read-back verification
        # ----------------------------------------------------------------
        Write-Host "  |  [VERIFY] Reading back created files..." -ForegroundColor DarkGray
        $stFiles      = $allFiles | Where-Object { $_.file_content }
        $verifyResult = Invoke-VerifyCreatedFiles -Files $stFiles -TicketSummary $summary -SubtaskName $stName
        if (-not $verifyResult.verified) {
            Write-Host "  |  [VERIFY] Issues: $($verifyResult.issues -join '; ')" -ForegroundColor DarkYellow
            foreach ($fx in $verifyResult.fixes_needed | Select-Object -First 3) {
                $fxAbs = Join-Path $cbPath ($fx.file_path -replace '/','\')
                if ((Test-Path -LiteralPath $fxAbs) -and $fx.search_fallback -and $fx.replace_fallback) {
                    $fxRaw = (Get-Content -LiteralPath $fxAbs -Raw) -replace "`r`n", "`n"
                    $search = $fx.search_fallback -replace "`r`n", "`n"
                    $replace = $fx.replace_fallback -replace "`r`n", "`n"
                    if ($fxRaw.Contains($search)) {
                        Set-Content -LiteralPath $fxAbs -Value ($fxRaw.Replace($search, $replace)) -Encoding UTF8 -NoNewline
                        Write-Host "  |  [VERIFY FIX] $($fx.file_path)" -ForegroundColor DarkYellow
                    }
                }
            }
        } else {
            Write-Host "  |  [VERIFY] Passed!" -ForegroundColor Green
        }

        # ----------------------------------------------------------------
        # STEP 9: Generate test files
        # ----------------------------------------------------------------
        $testsGenerated = 0
        foreach ($tf2 in ($allFiles | Where-Object { $_.action -eq 'create' -and $_.file_content })) {
            $tFile = New-BehaviorTestFile -SourceFile $tf2.file_path -SourceContent $tf2.file_content -CodebaseMap $codebaseMap
            if ($tFile) {
                $tAbs = Join-Path $cbPath ($tFile.file_path -replace '/','\')
                if (-not (Test-Path $tAbs)) {
                    $tDir = Split-Path $tAbs -Parent
                    if (-not (Test-Path $tDir)) { New-Item -ItemType Directory -Path $tDir -Force | Out-Null }
                    Set-Content -Path $tAbs -Value $tFile.file_content -Encoding UTF8
                    Write-Host "  |  [TESTS] Generated: $($tFile.file_path)" -ForegroundColor Green
                    $testsGenerated++
                }
            }
        }

        # ----------------------------------------------------------------
        # Update session context for the next sub-task
        # ----------------------------------------------------------------
        $createdNames = ($allFiles | Where-Object { $_.file_content } | ForEach-Object { $_.file_path }) -join ', '
        $subtaskContext += "Sub-task $stCounter ($stName) created/patched: $createdNames`n"
        $sessionContext.Add("[$ticketId/$stCounter] $stName - $createdNames")

        Write-Host "  |  [SUB-TASK $stCounter] Complete" -ForegroundColor Green
        Refresh-FileList
        if (-not $global:FastMode) { Start-Sleep -Seconds 5 }
    }
    # ============================================================
    # END SUB-TASK LOOP
    # ============================================================

    # (sub-task loop above replaced the old single-pass block)

    # -- TICKET RESULT + MEMORY SAVE --
    $ticketStatus = if ($ticketSuccess -and -not $DryRun) { 'COMPLETED' } elseif ($DryRun) { 'DRY_RUN' } else { 'PARTIAL' }
    Write-Host "  |  [TICKET] $ticketStatus - $($ticketAllCreated.Count) file(s) total" -ForegroundColor $(if($ticketSuccess){'Green'}else{'DarkYellow'})
    if ($ticketExplanation) { Write-Host "  |  $ticketExplanation" -ForegroundColor White }

    # Save to memory (self-learning)
    if (-not $DryRun) {
        Update-AgentMemory -Memory $agentMemory -TicketId $ticketId -Summary $summary `
            -CreatedFiles $ticketAllCreated -PkgsInstalled $ticketPkgsInstalled `
            -BuildErrors $ticketBuildErrors -BuildFixes $ticketBuildFixes `
            -CodebaseMap $codebaseMap
        # Update context for next ticket's prompts
        $memoryContext   = Get-MemoryContext   -Memory $agentMemory
        $codebaseContext = Get-CodebaseContext -CodebaseMap $codebaseMap
    }

    $log.Add(@{
        ticket      = $ticketId
        status      = $ticketStatus
        ticketType  = $issueType
        summary     = $summary
        subtasks    = $subtasks.Count
        filesCreated = $ticketAllCreated
        pkgsInstalled = $ticketPkgsInstalled
        explanation  = $ticketExplanation
        timestamp    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    })

    if (-not $DryRun) {
        $comment = if ($ticketSuccess) {
            "AI Agent v9.0 completed ($($ticketAllCreated.Count) files, $($subtasks.Count) sub-tasks): $ticketExplanation"
        } else {
            "AI Agent v9.0 partial completion ($($ticketAllCreated.Count) files created, build issues encountered). Check agent log for details."
        }
        if ($writeBack) { Write-JiraUpdate -IssueKey $ticketId -TargetStatus $(if($ticketSuccess){'Done'}else{'In Progress'}) -Comment $comment }
    }
    Refresh-FileList

    Write-Host '  +--------------------------------------------------' -ForegroundColor DarkGray
    if ($counter -lt $orderedIssues.Count) { if (-not $global:FastMode) { Start-Sleep -Seconds 10 } }
}

# == 11. SUMMARY ==
Write-Host ''
Write-Host '  [6/7] Summary' -ForegroundColor Cyan
Write-Host '  +--------------------------------------------------' -ForegroundColor DarkGray

$success=0; $skipped=0; $failed=0
foreach ($e in $log) {
    $st = $e['status']
    $icon = switch($st) { 'COMPLETED'{'[DONE]'} 'DRY_RUN'{'[DRY] '} 'NOT_PATCHABLE'{'[SKIP]'} default{'[FAIL]'} }
    $color = switch($st) { 'COMPLETED'{'Green'} 'DRY_RUN'{'Yellow'} 'NOT_PATCHABLE'{'DarkYellow'} default{'Red'} }
    $txt = "  |  $icon $($e['ticket'])"
    if ($e['file']) { $txt += " | $($e['file'])" }
    if ($e['fix']) { $txt += " | $($e['fix'])" }
    if ($e['reason']) { $txt += " | $($e['reason'])" }
    Write-Host $txt -ForegroundColor $color
    if ($st -match 'COMPLETED|DRY_RUN') { $success++ } elseif ($st -eq 'NOT_PATCHABLE') { $skipped++ } else { $failed++ }
}
Write-Host '  +--------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  Success: $success | Skipped: $skipped | Failed: $failed" -ForegroundColor Cyan

# == 12. SAVE LOG (fixed filename - no illegal chars) ==
Write-Host ''
Write-Host '  [7/7] Saving log...' -ForegroundColor Cyan
$stamp   = Get-Date -Format 'yyyy-MM-dd - hh-mm'
$logPath = Join-Path $PSScriptRoot "agent-run-$stamp.log.json"
$log | ConvertTo-Json -Depth 5 | Set-Content $logPath -Encoding UTF8
Write-Host "  Saved: $logPath" -ForegroundColor Gray

# == 13. CLEANUP OLD SNAPSHOTS ==
Remove-OldSnapshots -KeepLast 10

Write-Host ''
Write-Host '  Done! (v9.0)' -ForegroundColor Cyan
Write-Host ''


