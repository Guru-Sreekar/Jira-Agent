# memory.ps1 - Persistent agent self-learning memory system
# Remembers patterns, errors, fixes, and codebase knowledge across runs

function Get-AgentMemoryDir {
    if ($cbPath) {
        return Join-Path $cbPath '.agent-memory'
    } else {
        return Join-Path $PSScriptRoot '..\agent-memory'
    }
}

function Load-AgentMemory {
    $mem = @{
        codebase_map     = @{}
        learned_patterns = @()
        error_history    = @()
        package_registry = @{}
    }
    $memDir = Get-AgentMemoryDir
    if (-not (Test-Path $memDir)) {
        New-Item -ItemType Directory -Path $memDir -Force | Out-Null
    }
    $mapFile      = Join-Path $memDir 'codebase-map.json'
    $patternsFile = Join-Path $memDir 'learned-patterns.json'
    $errorsFile   = Join-Path $memDir 'error-history.json'
    $pkgsFile     = Join-Path $memDir 'package-registry.json'

    if (Test-Path $mapFile)      { try { $mem.codebase_map     = Get-Content $mapFile      -Raw | ConvertFrom-Json } catch {} }
    if (Test-Path $patternsFile) { try { $mem.learned_patterns = @(Get-Content $patternsFile -Raw | ConvertFrom-Json) } catch {} }
    if (Test-Path $errorsFile)   { try { $mem.error_history    = @(Get-Content $errorsFile   -Raw | ConvertFrom-Json) } catch {} }
    if (Test-Path $pkgsFile)     { try { $mem.package_registry = Get-Content $pkgsFile      -Raw | ConvertFrom-Json } catch {} }

    return $mem
}

function Save-AgentMemory {
    param($Memory)
    $memDir = Get-AgentMemoryDir
    if (-not (Test-Path $memDir)) { New-Item -ItemType Directory -Path $memDir -Force | Out-Null }
    try { $Memory.codebase_map     | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $memDir 'codebase-map.json')      -Encoding UTF8 } catch {}
    try { $Memory.learned_patterns | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $memDir 'learned-patterns.json')  -Encoding UTF8 } catch {}
    try { $Memory.error_history    | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $memDir 'error-history.json')     -Encoding UTF8 } catch {}
    try { $Memory.package_registry | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $memDir 'package-registry.json') -Encoding UTF8 } catch {}
}

function Get-MemoryContext {
    param($Memory, [string]$Keywords = '')
    $ctx = ''
    if ($Memory.codebase_map -and $Memory.codebase_map.project_type) {
        $m = $Memory.codebase_map
        $ctx += "AGENT MEMORY (learned from previous runs):`n"
        $ctx += "  Project Type   : $($m.project_type)`n"
        if ($m.css_framework)      { $ctx += "  CSS Framework  : $($m.css_framework)`n" }
        if ($m.router)             { $ctx += "  Router         : $($m.router)`n" }
        if ($m.test_framework)     { $ctx += "  Test Framework : $($m.test_framework)`n" }
        if ($m.backend_folder)     { $ctx += "  Backend Folder : $($m.backend_folder) - ALL server-side files go here`n" }
        if ($m.existing_routes -and $m.existing_routes.Count -gt 0) {
            $ctx += "  Existing Routes: $($m.existing_routes -join ', ')`n"
        }
        if ($m.installed_packages -and $m.installed_packages.Count -gt 0) {
            $ctx += "  Installed Pkgs : $($m.installed_packages -join ', ')`n"
        }
        $ctx += "`n"
    }
    
    $patterns = $Memory.learned_patterns
    $errors   = $Memory.error_history

    if ($Keywords -and $Keywords.Length -gt 3) {
        $words = $Keywords.ToLower() -split '\s+|[_\-]' | Where-Object { $_.Length -ge 4 -and $_ -notmatch '^(this|that|with|from|have|will|should|could|would)$' } | Select-Object -Unique
        if ($words.Count -gt 0) {
            $regex = ($words | ForEach-Object { [regex]::Escape($_) }) -join '|'
            if ($patterns) { $patterns = @($patterns | Where-Object { $_.observation -match $regex }) }
            if ($errors)   { $errors   = @($errors   | Where-Object { $_.error_pattern -match $regex -or $_.fix -match $regex }) }
        }
    }

    if ($patterns -and $patterns.Count -gt 0) {
        $ctx += "LEARNED PATTERNS:`n"
        foreach ($p in $patterns | Select-Object -Last 10) {
            $ctx += "  - $($p.observation)`n"
        }
        $ctx += "`n"
    }
    if ($errors -and $errors.Count -gt 0) {
        $ctx += "KNOWN ERROR FIXES:`n"
        foreach ($e in $errors | Select-Object -Last 5) {
            $ctx += "  - If you see '$($e.error_pattern)': $($e.fix)`n"
        }
        $ctx += "`n"
    }
    return $ctx
}

function Update-AgentMemory {
    param(
        $Memory,
        [string]$TicketId,
        [string]$Summary,
        [array]$CreatedFiles   = @(),
        [array]$PkgsInstalled  = @(),
        [array]$BuildErrors    = @(),
        [array]$BuildFixes     = @(),
        $CodebaseMap = @{}
    )
    # Update package registry
    foreach ($pkg in $PkgsInstalled) {
        if ($pkg -and -not $Memory.package_registry.$pkg) {
            $Memory.package_registry | Add-Member -NotePropertyName $pkg -NotePropertyValue $pkg -Force -EA SilentlyContinue
        }
    }
    # Learn from build errors
    for ($i = 0; $i -lt [Math]::Min($BuildErrors.Count, $BuildFixes.Count); $i++) {
        $err = $BuildErrors[$i]; $fix = $BuildFixes[$i]
        if ($err -and $fix) {
            $exists = $Memory.error_history | Where-Object { $_.error_pattern -eq $err }
            if (-not $exists) {
                $Memory.error_history += @{ error_pattern=$err; fix=$fix; learned_from=$TicketId; date=(Get-Date -Format 'yyyy-MM-dd') }
            }
        }
    }
    # Learn from created files
    if ($CreatedFiles.Count -gt 0) {
        $Memory.learned_patterns += @{
            observation  = "Ticket '$Summary' required files: $($CreatedFiles -join ', ')"
            learned_from = $TicketId
            date         = (Get-Date -Format 'yyyy-MM-dd')
        }
    }
    # Update codebase map from new scan
    if ($CodebaseMap.Count -gt 0) {
        foreach ($key in $CodebaseMap.Keys) {
            $Memory.codebase_map | Add-Member -NotePropertyName $key -NotePropertyValue $CodebaseMap[$key] -Force -EA SilentlyContinue
        }
    }
    # Keep lists manageable
    if ($Memory.learned_patterns.Count -gt 50) { $Memory.learned_patterns = @($Memory.learned_patterns | Select-Object -Last 50) }
    if ($Memory.error_history.Count -gt 30)    { $Memory.error_history    = @($Memory.error_history    | Select-Object -Last 30) }

    Save-AgentMemory -Memory $Memory
}
