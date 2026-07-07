# files.ps1 - File operations: listing, backup, snapshot, package install, safe build

function Refresh-FileList {
    $script:relFiles = @()
    $files = Get-ChildItem -Path $cbPath -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.bak|__pycache__|venv|dist|build|target|bin\\|obj\\' }
    if ($files) { $script:relFiles = $files | ForEach-Object { $_.FullName.Substring($cbPath.Length+1).Replace('\','/') } }
    $script:fileListText = $script:relFiles -join "`n"
}

function Backup-File([string]$FilePath, [string]$TicketId) {
    if (Test-Path $FilePath) {
        $rel = $FilePath.Substring($cbPath.Length+1).Replace('\','__').Replace('/','__')
        $bp  = Join-Path $backupDir "${TicketId}__${rel}"
        Copy-Item $FilePath $bp -Force
        return $bp
    }
    return $null
}

# ?? Snapshot System ?????????????????????????????????????????????????????????????

function New-Snapshot {
    param([string[]]$TicketIds = @())

    $stamp       = Get-Date -Format 'yyyy-MM-dd-HH-mm-ss'
    $snapshotDir = Join-Path $backupDir "snapshots\$stamp"
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

    $allFiles = Get-ChildItem -Path $cbPath -Recurse -File -EA SilentlyContinue |
                Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.next|dist|build|\.turbo|__pycache__' }
    $count = 0; $skipped = 0
    foreach ($f in $allFiles) {
        $rel     = $f.FullName.Substring($cbPath.Length+1)
        $dest    = Join-Path $snapshotDir $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        try { Copy-Item $f.FullName $dest -Force -EA Stop; $count++ }
        catch { $skipped++ }
    }

    @{ timestamp=$stamp; ticket_ids=$TicketIds; file_count=$count; codebase=$cbPath } |
        ConvertTo-Json | Set-Content (Join-Path $snapshotDir 'manifest.json') -Encoding UTF8

    $skipMsg = if ($skipped -gt 0) { " ($skipped skipped - locked)" } else { '' }
    Write-Host "  [BACKUP] Snapshot saved ($count files$skipMsg) ? snapshots\$stamp" -ForegroundColor DarkGray
    return $snapshotDir
}

function Restore-Snapshot {
    param([string]$Date = '')

    $snapshotBase = Join-Path $backupDir 'snapshots'
    if (-not (Test-Path $snapshotBase)) { Write-Host '  No snapshots found.' -ForegroundColor Red; return }

    $snapshots = Get-ChildItem $snapshotBase -Directory | Sort-Object Name -Descending
    if ($snapshots.Count -eq 0) { Write-Host '  No snapshots found.' -ForegroundColor Red; return }

    $target = if ($Date) { $snapshots | Where-Object { $_.Name -match [regex]::Escape($Date) } | Select-Object -First 1 }
              else       { $snapshots[0] }

    if (-not $target) { Write-Host "  No snapshot matching '$Date'." -ForegroundColor Red; return }

    Write-Host "  [RESTORE] Restoring from: $($target.Name)" -ForegroundColor Cyan
    
    # Get all files from snapshot (excluding manifest.json)
    $snapshotFiles = Get-ChildItem $target.FullName -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' }
    $snapshotRelPaths = @()
    
    # Restore files from snapshot
    $restored = 0; $skipped = 0
    foreach ($f in $snapshotFiles) {
        $rel     = $f.FullName.Substring($target.FullName.Length+1)
        $snapshotRelPaths += $rel
        $dest    = Join-Path $cbPath $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        try { Copy-Item $f.FullName $dest -Force -EA Stop; $restored++ }
        catch { $skipped++ }
    }
    
    # Delete files that exist in codebase but not in snapshot
    $currentFiles = Get-ChildItem -Path $cbPath -Recurse -File -EA SilentlyContinue |
                    Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.next|dist|build|\.turbo|__pycache__|backups' }
    $deleted = 0
    foreach ($cf in $currentFiles) {
        $rel = $cf.FullName.Substring($cbPath.Length+1)
        if ($snapshotRelPaths -notcontains $rel) {
            try {
                Remove-Item $cf.FullName -Force -EA Stop
                $deleted++
                Write-Host "    [DELETED] $rel" -ForegroundColor DarkYellow
            }
            catch { }
        }
    }
    
    # Remove empty directories
    $dirs = Get-ChildItem -Path $cbPath -Recurse -Directory -EA SilentlyContinue |
            Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.next|dist|build|\.turbo|__pycache__|backups' } |
            Sort-Object { $_.FullName.Length } -Descending
    $removedDirs = 0
    foreach ($d in $dirs) {
        $items = Get-ChildItem $d.FullName -EA SilentlyContinue
        if ($items.Count -eq 0) {
            try {
                Remove-Item $d.FullName -Force -EA Stop
                $removedDirs++
            }
            catch { }
        }
    }
    
    $skipMsg = if ($skipped -gt 0) { " ($skipped skipped - locked)" } else { '' }
    $deleteMsg = if ($deleted -gt 0) { ", $deleted deleted" } else { '' }
    $dirMsg = if ($removedDirs -gt 0) { ", $removedDirs empty dirs removed" } else { '' }
    Write-Host "  [RESTORE] $restored files restored$deleteMsg$dirMsg$skipMsg" -ForegroundColor Green
}

function Remove-OldSnapshots {
    param([int]$KeepLast = 10)
    $snapshotBase = Join-Path $backupDir 'snapshots'
    if (-not (Test-Path $snapshotBase)) { return }
    $old = Get-ChildItem $snapshotBase -Directory | Sort-Object Name -Descending | Select-Object -Skip $KeepLast
    foreach ($s in $old) { Remove-Item $s.FullName -Recurse -Force -EA SilentlyContinue }
    if ($old.Count -gt 0) { Write-Host "  [BACKUP] Removed $($old.Count) old snapshot(s)" -ForegroundColor DarkGray }
}

# # ?? Package Installation ?????????????????????????????????????????????????????????
# NOTE: Normalize-FileContent and Write-FileWithValidation are defined in content-normalizer.ps1

function Install-RequiredPackages {
    param([array]$Files, $CodebaseMap)

    $installed = @()
    $pt        = $CodebaseMap.project_type

    # ?? Node.js ??
    if ($pt -match 'vite|react|vue|angular|nextjs|nodejs|express|fullstack|svelte') {
        $requiredPkgs = @()
        foreach ($f in $Files) {
            # Normalize content before parsing
            $content = if ($f.file_content) { Normalize-FileContent -Content $f.file_content } else { '' }
            if (-not $content) { continue }
            # CommonJS require('pkg')
            [regex]::Matches($content, "require\s*\(\s*['""]([^./'\""@][^'""]*)['""]") |
                ForEach-Object { $requiredPkgs += ($_.Groups[1].Value -split '/')[0] }
            # ES import ... from 'pkg'
            [regex]::Matches($content, "(?m)^import\s+.*?from\s+['""]([^./'\""@][^'""]*)['""]") |
                ForEach-Object { $requiredPkgs += ($_.Groups[1].Value -split '/')[0] }
            # Dynamic import('pkg')
            [regex]::Matches($content, "import\s*\(\s*['""]([^./'\""@][^'""]*)['""]") |
                ForEach-Object { $requiredPkgs += ($_.Groups[1].Value -split '/')[0] }
        }

        # Check if any file is a new/updated package.json
        $hasNewPkgJson = $Files | Where-Object { $_.file_path -match 'package\.json$' }

        $nodeModules = Join-Path $cbPath 'node_modules'
        $alreadyInstalled = @($CodebaseMap.installed_packages)
        # Built-ins / always-present
        $builtins = @('react','react-dom','next','vite','@vitejs','@types','typescript','node','path','fs','crypto','http','https','url','os','events','stream','util','buffer','process','querystring','child_process','cluster','dgram','dns','domain','net','readline','repl','string_decoder','tls','tty','vm','zlib','assert','constants','module','sys')

        $missing = $requiredPkgs | Select-Object -Unique | Where-Object {
            $_ -and
            ($builtins | Where-Object { $_ -eq $requiredPkgs -or $_ -eq $_ }) -notcontains $_ -and
            $alreadyInstalled -notcontains $_ -and
            -not (Test-Path (Join-Path $nodeModules $_))
        }

        if ($missing.Count -gt 0) {
            Write-Host "  |  [PACKAGES] Installing: $($missing -join ', ')" -ForegroundColor Cyan
            $r = & cmd /c "cd /d `"$cbPath`" && npm install $($missing -join ' ') --save 2>&1"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  |  [PACKAGES] Installed OK" -ForegroundColor Green
                $installed += $missing
            } else {
                Write-Host "  |  [PACKAGES] Warn: $($r | Select-Object -Last 2 | Out-String)" -ForegroundColor Yellow
            }
        }

        if ($hasNewPkgJson) {
            Write-Host "  |  [PACKAGES] Syncing package.json (npm install)..." -ForegroundColor DarkGray
            $null = & cmd /c "cd /d `"$cbPath`" && npm install 2>&1"
            Write-Host "  |  [PACKAGES] Sync complete" -ForegroundColor Green
        }

        # Backend sub-folder (separate package.json)
        if ($CodebaseMap.backend_folder) {
            $bfPkg = Join-Path $cbPath "$($CodebaseMap.backend_folder)\package.json"
            if (Test-Path $bfPkg) {
                $null = & cmd /c "cd /d `"$cbPath\$($CodebaseMap.backend_folder)`" && npm install 2>&1"
            }
        }
    }

    # ?? Python ??
    elseif ($pt -match 'django|flask|fastapi|python') {
        $requiredPkgs = @()
        foreach ($f in $Files) {
            # Normalize content before parsing
            $content = if ($f.file_content) { Normalize-FileContent -Content $f.file_content } else { '' }
            if (-not $content) { continue }
            [regex]::Matches($content, '(?m)^(?:import|from)\s+(\w+)') |
                ForEach-Object { $requiredPkgs += $_.Groups[1].Value }
        }
        $stdlib   = @('os','sys','json','re','datetime','time','math','random','collections','functools','itertools','pathlib','typing','abc','io','logging','unittest','hashlib','hmac','base64','urllib','http','email','csv','copy','glob','shutil','tempfile','threading','multiprocessing','subprocess','socket','ssl','asyncio','contextlib','dataclasses','enum','struct','pprint','string','traceback','warnings','builtins','__future__')
        $reqFile  = Join-Path $cbPath 'requirements.txt'
        $existing = if (Test-Path $reqFile) { Get-Content $reqFile } else { @() }
        $missing  = $requiredPkgs | Select-Object -Unique | Where-Object { $_ -and $stdlib -notcontains $_ -and ($existing -join '') -notmatch [regex]::Escape($_) }
        if ($missing.Count -gt 0) {
            Write-Host "  |  [PACKAGES] pip install $($missing -join ' ')" -ForegroundColor Cyan
            $null = & cmd /c "cd /d `"$cbPath`" && pip install $($missing -join ' ') 2>&1"
            $installed += $missing
        }
    }

    # ?? Go ??
    elseif ($pt -eq 'golang') {
        foreach ($f in $Files) {
            # Normalize content before parsing
            $content = if ($f.file_content) { Normalize-FileContent -Content $f.file_content } else { '' }
            if (-not $content) { continue }
            [regex]::Matches($content, '"([a-z][a-z0-9\-\.]+/[^"]+)"') | ForEach-Object {
                $pkg = $_.Groups[1].Value
                if ($pkg -notmatch '^(fmt|os|net|io|log|sync|time|math|sort|errors|strconv|strings|bytes|bufio|context|encoding|crypto|path|regexp|unicode|runtime|reflect)') {
                    $null = & cmd /c "cd /d `"$cbPath`" && go get $pkg 2>&1"
                    $installed += $pkg
                }
            }
        }
    }

    # ?? Rust ??
    elseif ($pt -eq 'rust') {
        foreach ($f in $Files) {
            # Normalize content before parsing
            $content = if ($f.file_content) { Normalize-FileContent -Content $f.file_content } else { '' }
            if (-not $content) { continue }
            [regex]::Matches($content, 'extern crate (\w+)') | ForEach-Object {
                $null = & cmd /c "cd /d `"$cbPath`" && cargo add $($_.Groups[1].Value) 2>&1"
                $installed += $_.Groups[1].Value
            }
        }
    }

    return $installed
}

# ?? Package Security Audit ???????????????????????????????????????????????????????

function Invoke-PackageAudit {
    param($CodebaseMap)
    $result = @{ pass=$true; critical=@(); warnings=@() }
    if ($CodebaseMap.project_type -notmatch 'vite|react|vue|angular|nextjs|nodejs|express|fullstack') { return $result }
    try {
        $out  = & cmd /c "cd /d `"$cbPath`" && npm audit --json 2>&1"
        $json = $out | ConvertFrom-Json -EA SilentlyContinue
        if ($json -and $json.vulnerabilities) {
            foreach ($v in $json.vulnerabilities.PSObject.Properties) {
                $sev = $v.Value.severity; $name = $v.Name
                if ($sev -eq 'critical') { $result.critical += "CRITICAL CVE in '$name': $($v.Value.title)"; $result.pass = $false }
                elseif ($sev -eq 'high') { $result.warnings += "HIGH severity in '$name'" }
            }
        }
    } catch { }
    return $result
}

# ?? Safe Build ???????????????????????????????????????????????????????????????????

function Invoke-SafeBuild {
    param($CodebaseMap)
    $result = @{ success=$false; output=''; errors='' }
    if (-not $script:buildCmd) { return @{ success=$true; output='No build command'; errors='' } }

    # Ensure node_modules exist before building
    if ($CodebaseMap.project_type -match 'vite|react|vue|angular|nextjs|nodejs|express|fullstack') {
        $nm = Join-Path $cbPath 'node_modules'
        if (-not (Test-Path $nm)) {
            Write-Host "  |  [BUILD] npm install (first time)..." -ForegroundColor DarkGray
            $null = & cmd /c "cd /d `"$cbPath`" && npm install 2>&1"
        }
    }

    try {
        $out = & cmd /c "cd /d `"$cbPath`" && $($script:buildCmd) 2>&1"
        $result.output  = $out | Out-String
        $result.success = ($LASTEXITCODE -eq 0)
        if (-not $result.success) { $result.errors = $result.output }
    } catch {
        $result.errors = $_.Exception.Message
    }
    return $result
}
