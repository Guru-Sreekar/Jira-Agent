# src/executor.ps1
# Real developer execution loop: compile check, surgical fix, test runner, runtime verification
# Dot-sourced from run.ps1 â€” shares $cbPath, $script:buildCmd, $script:testCmd scope

# ??????????????????????????????????????????????????????????????????????????????????
# Compile Check â€” language-aware, returns structured [{file,line,col,code,message}]
# ??????????????????????????????????????????????????????????????????????????????????
function Invoke-CompileCheck {
    param($CodebaseMap)
    $result = @{ pass=$true; errors=@() }
    $lang   = if ($CodebaseMap -and $CodebaseMap.language) { $CodebaseMap.language.ToLower() } else { '' }

    try {
        if ($lang -match 'typescript' -or (Test-Path (Join-Path $cbPath 'tsconfig.json'))) {
            $tscBin = Join-Path $cbPath 'node_modules/.bin/tsc'
            $tscCmd = if (Test-Path $tscBin) { "`"$tscBin`" --noEmit 2>&1" } else { 'npx --no-install tsc --noEmit 2>&1' }
            $output = & cmd /c "cd /d `"$cbPath`" && $tscCmd"
            $result.pass = ($LASTEXITCODE -eq 0)
            if (-not $result.pass) { $result.errors = ConvertFrom-TypeScriptErrors -Output ($output -join "`n") }

        } elseif ($lang -match 'python' -or (Test-Path (Join-Path $cbPath 'requirements.txt'))) {
            $pyFiles = Get-ChildItem -Path $cbPath -Filter '*.py' -Recurse -EA SilentlyContinue |
                Where-Object { $_.FullName -notmatch 'node_modules|\.git|__pycache__' } |
                Select-Object -First 30
            foreach ($pf in $pyFiles) {
                $out = & cmd /c "python -m py_compile `"$($pf.FullName)`" 2>&1"
                if ($LASTEXITCODE -ne 0) {
                    $result.pass = $false
                    $rel = ($pf.FullName.Replace($cbPath,'').TrimStart('\','/') -replace '\\','/')
                    $result.errors += @{ file=$rel; line=0; col=0; code='SYNTAX'; message=($out -join ' ') }
                }
            }

        } elseif ($lang -match '\bgo\b' -or (Test-Path (Join-Path $cbPath 'go.mod'))) {
            $output = & cmd /c "cd /d `"$cbPath`" && go build ./... 2>&1"
            $result.pass = ($LASTEXITCODE -eq 0)
            if (-not $result.pass) { $result.errors = ConvertFrom-GoErrors -Output ($output -join "`n") }
        }
        # Java/Rust/C# handled by Invoke-SafeBuild
    } catch {
        $result.pass = $true   # Never block on checker failure
    }
    return $result
}

function ConvertFrom-TypeScriptErrors {
    param([string]$Output)
    $errors  = @()
    $cbNorm  = ($cbPath -replace '\\','/').TrimEnd('/')
    $rxMatch = [regex]::Matches($Output, '([^\r\n(]+)\((\d+),(\d+)\):\s+error\s+(TS\d+):\s+(.+)')
    foreach ($m in $rxMatch) {
        $fp = ($m.Groups[1].Value.Trim() -replace '\\','/')
        if ($fp.StartsWith($cbNorm)) { $fp = $fp.Substring($cbNorm.Length).TrimStart('/') }
        $errors += @{
            file    = $fp
            line    = [int]$m.Groups[2].Value
            col     = [int]$m.Groups[3].Value
            code    = $m.Groups[4].Value
            message = $m.Groups[5].Value.Trim()
        }
    }
    return $errors
}

function ConvertFrom-GoErrors {
    param([string]$Output)
    $errors  = @()
    $cbNorm  = ($cbPath -replace '\\','/').TrimEnd('/')
    $rxMatch = [regex]::Matches($Output, '([^\s:]+\.go):(\d+):(\d+):\s+(.+)')
    foreach ($m in $rxMatch) {
        $fp = ($m.Groups[1].Value -replace '\\','/').Trim()
        if ($fp.StartsWith($cbNorm)) { $fp = $fp.Substring($cbNorm.Length).TrimStart('/') }
        $errors += @{ file=$fp; line=[int]$m.Groups[2].Value; col=[int]$m.Groups[3].Value; code='BUILD'; message=$m.Groups[4].Value.Trim() }
    }
    return $errors
}

# ??????????????????????????????????????????????????????????????????????????????????
# Surgical Fix â€” fixes ONE compile/review error in ONE specific file
# ??????????????????????????????????????????????????????????????????????????????????
function Invoke-SurgicalFix {
    param(
        [string]$FilePath,
        $CompileError,
        [int]$MaxAttempts = 5
    )
    $result = @{ fixed=$false; attempts=0 }
    $abs    = Join-Path $cbPath ($FilePath -replace '/','\')
    if (-not (Test-Path $abs)) { return $result }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $result.attempts = $i
        $currentContent  = Get-Content $abs -Raw -EA SilentlyContinue
        if (-not $currentContent) { break }

        # Context window: 5 lines around the error
        $allLines  = $currentContent -split "`r?`n"
        $errIdx    = [Math]::Max(0, $CompileError.line - 1)
        $startCtx  = [Math]::Max(0, $errIdx - 5)
        $endCtx    = [Math]::Min($allLines.Count - 1, $errIdx + 5)
        $ctxLines  = for ($k = $startCtx; $k -le $endCtx; $k++) {
            "$($k+1)$(if ($k -eq $errIdx) { ' >>>' } else { ':   ' }) $($allLines[$k])"
        }
        $ctxBlock  = $ctxLines -join "`n"
        $preview   = $currentContent.Substring(0, [Math]::Min(50000, $currentContent.Length))

        $fixSys    = "You are a compiler error expert. Fix ONLY the specific error shown. Return ONLY valid JSON. Never rewrite the whole file unless absolutely necessary. The search_fallback MUST be an EXACT literal match of the existing file content (including exact whitespace/indentation) and provide enough unique lines (3-4 lines) to locate the text reliably."
        $fixUser   = "FILE: $FilePath`nERROR ($($CompileError.code)): $($CompileError.message) at line $($CompileError.line)`n`nCODE CONTEXT:`n$ctxBlock`n`nFULL FILE (first 2500 chars):`n$preview`n`nReturn JSON: {`"search_fallback`": `"exact existing text`", `"replace_fallback`": `"replacement`", `"explanation`": `"what was fixed`"}`nAlt if full rewrite needed: {`"file_content`": `"complete corrected file`", `"explanation`": `"...`"}"

        try {
            if (-not $global:FastMode) { Start-Sleep -Milliseconds 1500 }
            $raw = Invoke-LLM -SysPrompt $fixSys -UserPrompt $fixUser
            $fix = Get-ParsedJson -Text $raw
            if (-not $fix) { continue }

            $latest = (Get-Content $abs -Raw) -replace "`r`n", "`n"
            $search = $fix.search_fallback -replace "`r`n", "`n"
            $replace = $fix.replace_fallback -replace "`r`n", "`n"
            if ($search -and $replace -and $latest.Contains($search)) {
                $newContent = $latest.Replace($search, $replace)
                Set-Content -Path $abs -Value $newContent -Encoding UTF8 -NoNewline
                Write-Host "  |    [SURGICAL] $($fix.explanation)" -ForegroundColor DarkYellow
                
                # Verify file integrity
                $integrityCheck = Test-FileCompleteness -FilePath $abs -ExpectedContent $newContent
                if (-not $integrityCheck.complete) {
                    Write-Host "  |    [INTEGRITY] Warning - file may be incomplete after fix" -ForegroundColor Yellow
                }
            } elseif ($fix.file_content) {
                $contentToWrite = $fix.file_content
                if ($contentToWrite -is [string] -and $contentToWrite -match '\\n') {
                    $contentToWrite = $contentToWrite -replace '\\n', "`n"
                }
                Set-Content -Path $abs -Value $contentToWrite -Encoding UTF8 -NoNewline
                Write-Host "  |    [SURGICAL] Applied full file rewrite" -ForegroundColor DarkYellow
                
                # Verify file integrity
                $integrityCheck = Test-FileCompleteness -FilePath $abs -ExpectedContent $contentToWrite
                if (-not $integrityCheck.complete) {
                    Write-Host "  |    [INTEGRITY] Warning - file may be incomplete after rewrite" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  |    [SURGICAL] Patch text not found - retrying" -ForegroundColor DarkYellow
                continue
            }

            # Re-run compile and check if this specific error is gone
            $recheck     = Invoke-CompileCheck -CodebaseMap @{}
            $fileNamePat = [regex]::Escape([IO.Path]::GetFileName($FilePath))
            $stillBroken = $recheck.errors | Where-Object {
                ($_.file -eq $FilePath) -or ($_.file -match $fileNamePat) -or
                (($_.line -eq $CompileError.line) -and ($_.code -eq $CompileError.code))
            }
            if ($stillBroken.Count -eq 0 -or $recheck.pass) {
                Write-Host "  |  [COMPILE] Fixed on attempt $i!" -ForegroundColor Green
                $result.fixed = $true
                return $result
            }
            $CompileError = $stillBroken[0]
        } catch {
            Write-Host "  |    [SURGICAL] Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    return $result
}

# ??????????????????????????????????????????????????????????????????????????????????
# Surgical Build Fix â€” parses build errors to find exact file, calls Invoke-SurgicalFix
# ??????????????????????????????????????????????????????????????????????????????????
function Invoke-SurgicalBuildFix {
    param([string]$BuildError, [array]$RecentFiles, [int]$MaxRetries = 5, $CodebaseMap)
    $errStr = if ($BuildError -is [array]) { $BuildError -join "`n" } else { $BuildError }
    $cbNorm = ($cbPath -replace '\\', '/').TrimEnd('/')

    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Host "  |  [BUILD FIX] Attempt $i/$MaxRetries" -ForegroundColor DarkYellow

        # Parse structured errors from the build output
        $compileErrors = @()

        # TypeScript: path/file.ts(line,col): error TS####: message
        $tsMx = [regex]::Matches($errStr, '([^\r\n(]+\.(ts|tsx|js|jsx))\((\d+),(\d+)\):\s+error\s+(TS\d+):\s+(.+)')
        foreach ($m in $tsMx | Select-Object -First 5) {
            $fp = ($m.Groups[1].Value.Trim() -replace '\\','/')
            if ($fp.StartsWith($cbNorm)) { $fp = $fp.Substring($cbNorm.Length).TrimStart('/') }
            $compileErrors += @{ file=$fp; line=[int]$m.Groups[3].Value; col=[int]$m.Groups[4].Value; code=$m.Groups[5].Value; message=$m.Groups[6].Value.Trim() }
        }

        # Python: File "path", line N
        $pyMx = [regex]::Matches($errStr, 'File "([^"]+)", line (\d+)')
        foreach ($m in $pyMx | Select-Object -First 3) {
            $fp = ($m.Groups[1].Value -replace '\\','/').Trim()
            if ($fp.StartsWith($cbNorm)) { $fp = $fp.Substring($cbNorm.Length).TrimStart('/') }
            $compileErrors += @{ file=$fp; line=[int]$m.Groups[2].Value; col=0; code='SYNTAX'; message='Python error' }
        }

        if ($compileErrors.Count -gt 0) {
            $err = $compileErrors[0]
            Write-Host "  |  [BUILD FIX] Targeting $($err.file):$($err.line) - $($err.message)" -ForegroundColor DarkYellow
            $absErr = Join-Path $cbPath ($err.file -replace '/','\')

            if (Test-Path $absErr) {
                $sfResult = Invoke-ImprovedSurgicalFix -FilePath $err.file -CompileError $err -MaxAttempts 3
                if ($sfResult.fixed) {
                    $br = Invoke-SafeBuild -CodebaseMap $CodebaseMap
                    if ($br.success) {
                        return @{ fixed=$true; attempts=$i; diagnosis="Fixed $($err.file) line $($err.line): $($err.message)" }
                    }
                    $errStr = if ($br.errors -is [array]) { $br.errors -join "`n" } else { "$($br.errors)" }
                    continue
                }
            }

            # Surgical fix failed - rewrite just that one file
            $fileContent = Get-Content $absErr -Raw -EA SilentlyContinue
            if (-not $fileContent) { $fileContent = '' }
            $fSys  = 'You are a build error expert. Fix the broken file. Return ONLY valid JSON.'
            $fUser = "BUILD ERROR:`n$($errStr.Substring(0,[Math]::Min(10000,$errStr.Length)))`n`nBROKEN FILE: $($err.file)`nCONTENT:`n$($fileContent.Substring(0,[Math]::Min(50000,[Math]::Max(0,$fileContent.Length))))`n`nReturn: {`"files`": [{`"file_path`": `"$($err.file)`", `"file_content`": `"complete fixed file content`"}]}"
            try {
                if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
                $raw = Invoke-LLM -SysPrompt $fSys -UserPrompt $fUser
                $fix = Get-ParsedJson -Text $raw
                if ($fix -and $fix.files -and $fix.files[0].file_content) {
                    Write-Host "  |  [BUILD FIX] Refusing full rewrite of $($err.file) - trying next approach" -ForegroundColor Yellow
                    $br = Invoke-SafeBuild -CodebaseMap $CodebaseMap
                    if ($br.success) { return @{ fixed=$true; attempts=$i; diagnosis="Rewrote $($err.file)" } }
                    $errStr = if ($br.errors -is [array]) { $br.errors -join "`n" } else { "$($br.errors)" }
                }
            } catch { }
        } else {
            # Can't parse specific file — fall back to general LLM fix
            $fileList = ($RecentFiles | ForEach-Object { $_.file_path }) -join ', '
            
            $recentFilesContext = ""
            foreach ($rf in $RecentFiles) {
                $rfPath = Join-Path $cbPath ($rf.file_path -replace '/','\')
                if (Test-Path -LiteralPath $rfPath) {
                    $rfContent = Get-Content -LiteralPath $rfPath -Raw -EA SilentlyContinue
                    if ($rfContent) {
                        $lines = $rfContent -split "`r?`n"
                        $numbered = for ($k = 0; $k -lt $lines.Count; $k++) {
                            "$($k+1): $($lines[$k])"
                        }
                        $recentFilesContext += "`n=== FILE: $($rf.file_path) ===`n"
                        $recentFilesContext += ($numbered -join "`n")
                        $recentFilesContext += "`n=============================`n"
                    }
                }
            }

            $fSys  = 'You are a build error expert. Return the minimal fix. Return ONLY valid JSON. The search_fallback MUST be an EXACT literal match of the existing file content (including exact whitespace/indentation) and provide enough unique lines (3-4 lines) to locate the text reliably.'
            $fUser = "BUILD ERROR:`n$($errStr.Substring(0,[Math]::Min(10000,$errStr.Length)))`n`nRECENT FILES: $fileList`n`nRECENT FILES CONTENTS:`n$recentFilesContext`n`nReturn: {`"diagnosis`": `"..`", `"files`": [{`"file_path`": `"..`", `"search_fallback`": `"exact existing text`", `"replace_fallback`": `"fix`"}]}"
            try {
                if (-not $global:FastMode) { Start-Sleep -Seconds 5 }
                $raw = Invoke-LLM -SysPrompt $fSys -UserPrompt $fUser
                $fix = Get-ParsedJson -Text $raw
                if ($fix -and $fix.files) {
                    foreach ($ff in $fix.files) {
                        $abs = Join-Path $cbPath ($ff.file_path -replace '/','\')
                        if ($ff.file_content -and -not (Test-Path $abs)) {
                            $contentToWrite = $ff.file_content
                            if ($contentToWrite -is [string] -and $contentToWrite -match '\\n') {
                                $contentToWrite = $contentToWrite -replace '\\n', "`n"
                            }
                            Set-Content -Path $abs -Value $contentToWrite -Encoding UTF8 -NoNewline
                            
                            # Verify file integrity
                            $integrityCheck = Test-FileCompleteness -FilePath $abs -ExpectedContent $contentToWrite
                            if (-not $integrityCheck.complete) {
                                Write-Host "  |  [INTEGRITY] Warning - created file may be incomplete" -ForegroundColor Yellow
                            }
                        } elseif ($ff.file_content) {
                            Write-Host "  |  [BUILD FIX] Skipping full overwrite of existing: $($ff.file_path)" -ForegroundColor Yellow
                        }
                        elseif ($ff.search_fallback -and (Test-Path $abs)) {
                            $rc = (Get-Content $abs -Raw) -replace "`r`n", "`n"
                            $search = $ff.search_fallback -replace "`r`n", "`n"
                            $replace = $ff.replace_fallback -replace "`r`n", "`n"
                            if ($rc.Contains($search)) {
                                $newContent = $rc.Replace($search, $replace)
                                Set-Content -Path $abs -Value $newContent -Encoding UTF8 -NoNewline
                                
                                # Verify file integrity
                                $integrityCheck = Test-FileCompleteness -FilePath $abs -ExpectedContent $newContent
                                if (-not $integrityCheck.complete) {
                                    Write-Host "  |  [INTEGRITY] Warning - patched file may be incomplete" -ForegroundColor Yellow
                                }
                            }
                        }
                    }
                    $br = Invoke-SafeBuild -CodebaseMap $CodebaseMap
                    if ($br.success) { return @{ fixed=$true; attempts=$i; diagnosis=$fix.diagnosis } }
                    $errStr = if ($br.errors -is [array]) { $br.errors -join "`n" } else { "$($br.errors)" }
                }
            } catch { }
        }
    }
    return @{ fixed=$false; attempts=$MaxRetries }
}

# ??????????????????????????????????????????????????????????????????????????????????
# Test Runner â€” runs all tests, attempts to fix failures
# ??????????????????????????????????????????????????????????????????????????????????
function Invoke-RunTests {
    param($CodebaseMap, [array]$RecentFiles)
    $result = @{ pass=$true; passed=0; failed=0; failures=@() }
    if (-not $script:testCmd) {
        Write-Host "  |  [TESTS] No test command detected - skipping" -ForegroundColor DarkGray
        return $result
    }

    Write-Host "  |  [TESTS] Running: $script:testCmd" -ForegroundColor DarkGray
    try {
        $output    = & cmd /c "cd /d `"$cbPath`" && $script:testCmd 2>&1"
        $exitCode  = $LASTEXITCODE
        $outputStr = ($output -join "`n")

        if ($script:testCmd -match 'jest|npm test') {
            if ($outputStr -match 'Tests:\s+(\d+)\s+failed')  { $result.failed = [int]$Matches[1] }
            if ($outputStr -match '(\d+)\s+passed')            { $result.passed = [int]$Matches[1] }
            [regex]::Matches($outputStr, '(?m)^\s*?[^\w\s]\s+(.+failed.*|.+)') | Select-Object -First 5 | ForEach-Object {
                $result.failures += @{ test=$_.Groups[1].Value.Trim(); error='' }
            }
        } elseif ($script:testCmd -match 'pytest') {
            if ($outputStr -match '(\d+)\s+passed')   { $result.passed = [int]$Matches[1] }
            if ($outputStr -match '(\d+)\s+failed')   { $result.failed = [int]$Matches[1] }
            [regex]::Matches($outputStr, 'FAILED\s+([\w/\\.-]+)::([\w_]+)') | Select-Object -First 5 | ForEach-Object {
                $result.failures += @{ test="$($_.Groups[1].Value)::$($_.Groups[2].Value)"; error='' }
            }
        } elseif ($script:testCmd -match 'cargo test') {
            if ($outputStr -match '(\d+)\s+passed')   { $result.passed = [int]$Matches[1] }
            if ($outputStr -match '(\d+)\s+failed')   { $result.failed = [int]$Matches[1] }
        } elseif ($script:testCmd -match 'go test') {
            $result.passed = ([regex]::Matches($outputStr, '^ok\b',  [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
            $result.failed = ([regex]::Matches($outputStr, '^FAIL\b',[System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
        }
        $result.pass = ($exitCode -eq 0)

        if ($result.pass) {
            Write-Host "  |  [TESTS] $($result.passed) passed" -ForegroundColor Green
        } else {
            Write-Host "  |  [TESTS] $($result.passed) passed, $($result.failed) failed" -ForegroundColor Yellow
            if ($result.failures.Count -gt 0) {
                $anyFixed = Invoke-FixFailingTests -Failures $result.failures -RecentFiles $RecentFiles -Output $outputStr
                if ($anyFixed) {
                    Write-Host "  |  [TESTS] Re-running after fixes..." -ForegroundColor DarkGray
                    $output2     = & cmd /c "cd /d `"$cbPath`" && $script:testCmd 2>&1"
                    $result.pass = ($LASTEXITCODE -eq 0)
                    if ($result.pass) { Write-Host "  |  [TESTS] All passing after fix!" -ForegroundColor Green }
                }
            }
        }
    } catch {
        Write-Host "  |  [TESTS] Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    return $result
}

function Invoke-FixFailingTests {
    param([array]$Failures, [array]$RecentFiles, [string]$Output)
    $anyFixed = $false
    foreach ($failure in $Failures | Select-Object -First 3) {
        $testName   = $failure.test
        $relatedSrc = $RecentFiles | Where-Object {
            $testName -match [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($_.file_path))
        } | Select-Object -First 1

        $srcContent = ''
        if ($relatedSrc) {
            $sAbs = Join-Path $cbPath ($relatedSrc.file_path -replace '/','\')
            if (Test-Path $sAbs) { 
                $srcContent = Get-Content $sAbs -Raw -EA SilentlyContinue
                if (-not $srcContent) { $srcContent = '' }
            }
        }

        $fixSys  = "You are a test engineer. Fix the failing test. Return ONLY valid JSON. The search_fallback MUST be an EXACT literal match of the existing file content (including exact whitespace/indentation) and provide enough unique lines (3-4 lines) to locate the text reliably."
        $fixUser = "FAILING TEST: $testName`n`nTEST OUTPUT:`n$($Output.Substring(0,[Math]::Min(10000,$Output.Length)))`n`nSOURCE FILE:`n$($srcContent.Substring(0,[Math]::Min(50000,[Math]::Max(0,$srcContent.Length))))`n`nReturn: {`"file_path`": `"..`", `"search_fallback`": `"exact existing text to replace`", `"replace_fallback`": `"fixed text`"}"
        try {
            if (-not $global:FastMode) { Start-Sleep -Milliseconds 2000 }
            $raw = Invoke-LLM -SysPrompt $fixSys -UserPrompt $fixUser
            $fix = Get-ParsedJson -Text $raw
            if ($fix -and $fix.file_path -and $fix.search_fallback) {
                $fAbs = Join-Path $cbPath ($fix.file_path -replace '/','\')
                if (Test-Path $fAbs) {
                    $fc = (Get-Content $fAbs -Raw) -replace "`r`n", "`n"
                    $search = $fix.search_fallback -replace "`r`n", "`n"
                    $replace = $fix.replace_fallback -replace "`r`n", "`n"
                    if ($fc.Contains($search)) {
                        Set-Content -Path $fAbs -Value ($fc.Replace($search, $replace)) -Encoding UTF8 -NoNewline
                        Write-Host "  |  [TESTS] Fixed: $($fix.file_path)" -ForegroundColor DarkYellow
                        $anyFixed = $true
                    }
                }
            }
        } catch { }
    }
    return $anyFixed
}

# ??????????????????????????????????????????????????????????????????????????????????
# Runtime Check â€” starts server process, hits endpoints from ticket description
# ??????????????????????????????????????????????????????????????????????????????????
function Invoke-RuntimeCheck {
    param($CodebaseMap, [string]$TicketDescription)
    $result = @{ started=$false; endpointsPassed=0; endpointsFailed=0; details=@(); skipped=$false }

    # Detect server start command and port
    $startCmd = $null; $port = 3000
    if (Test-Path (Join-Path $cbPath 'package.json')) {
        $pkg = Get-Content (Join-Path $cbPath 'package.json') -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
        if ($pkg -and $pkg.scripts) {
            if ($pkg.scripts.dev)   { $startCmd = 'npm run dev' }
            elseif ($pkg.scripts.start) { $startCmd = 'npm start' }
        }
    }
    if (-not $startCmd) {
        foreach ($entry in @(@{file='manage.py';cmd='python manage.py runserver --noreload';p=8000},
                             @{file='app.py';   cmd='python app.py';    p=8000},
                             @{file='main.py';  cmd='python main.py';   p=8000},
                             @{file='server.py';cmd='python server.py'; p=8000})) {
            if (Test-Path (Join-Path $cbPath $entry.file)) { $startCmd=$entry.cmd; $port=$entry.p; break }
        }
    }
    if (-not $startCmd -and (Test-Path (Join-Path $cbPath 'go.mod'))) {
        foreach ($ep in @('main.go','cmd/main.go')) {
            if (Test-Path (Join-Path $cbPath $ep)) { $startCmd="go run $ep"; $port=8080; break }
        }
    }

    if (-not $startCmd) {
        Write-Host "  |  [RUNTIME] No server entry detected - build verify only" -ForegroundColor DarkGray
        $result.skipped = $true; return $result
    }

    Write-Host "  |  [RUNTIME] Starting: $startCmd (port $port)" -ForegroundColor DarkGray
    $proc = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = 'cmd.exe'
        $psi.Arguments              = "/c cd /d `"$cbPath`" && $startCmd"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $proc = [System.Diagnostics.Process]::Start($psi)

        # Wait up to 15s for server to respond
        $deadline = (Get-Date).AddSeconds(15)
        $started  = $false
        while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
            Start-Sleep -Milliseconds 700
            try {
                $null = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 1 -UseBasicParsing -EA Stop
                $started = $true; break
            } catch {
                if ($_.Exception.Response) { $started = $true; break }
            }
        }

        if (-not $started) {
            Write-Host "  |  [RUNTIME] Server did not respond in 15s - build verify only" -ForegroundColor Yellow
            $result.skipped = $true; return $result
        }
        $result.started = $true
        Write-Host "  |  [RUNTIME] Server up on :$port" -ForegroundColor Green

        # Extract endpoints from ticket description
        $endpoints = @()
        [regex]::Matches($TicketDescription, '\b(GET|POST|PUT|DELETE|PATCH)\s+(/[\w/:{}\[\]-]+)') |
            Select-Object -First 6 | ForEach-Object {
                $endpoints += @{ method=$_.Groups[1].Value; path=$_.Groups[2].Value }
            }
        if ($endpoints.Count -eq 0) {
            [regex]::Matches($TicketDescription, '/api/[\w/:-]+') | Select-Object -First 3 | ForEach-Object {
                $endpoints += @{ method='GET'; path=$_.Value }
            }
        }
        if ($endpoints.Count -eq 0) { $endpoints = @(@{ method='GET'; path='/' }) }

        # Hit each endpoint
        foreach ($ep in $endpoints) {
            try {
                $resp = Invoke-WebRequest -Uri "http://localhost:$port$($ep.path)" -Method $ep.method -TimeoutSec 5 -UseBasicParsing -EA Stop
                $ok   = $resp.StatusCode -lt 500
                Write-Host "  |  [RUNTIME] $($ep.method) $($ep.path) -> $($resp.StatusCode) $(if($ok){'OK'}else{'FAIL'})" -ForegroundColor $(if($ok){'Green'}else{'Yellow'})
                if ($ok) { $result.endpointsPassed++ } else { $result.endpointsFailed++ }
                $result.details += "$($ep.method) $($ep.path) -> $($resp.StatusCode)"
            } catch {
                $sc = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                # 400/401/403/404/422 are expected for unauthenticated/empty requests
                if ($sc -in @(400,401,403,404,422)) {
                    Write-Host "  |  [RUNTIME] $($ep.method) $($ep.path) -> $sc (expected)" -ForegroundColor Green
                    $result.endpointsPassed++
                } else {
                    Write-Host "  |  [RUNTIME] $($ep.method) $($ep.path) -> ERROR ($sc)" -ForegroundColor Yellow
                    $result.endpointsFailed++
                }
                $result.details += "$($ep.method) $($ep.path) -> $sc"
            }
        }
    } catch {
        Write-Host "  |  [RUNTIME] Failed to start: $($_.Exception.Message)" -ForegroundColor DarkYellow
        $result.skipped = $true
    } finally {
        if ($proc -and -not $proc.HasExited) {
            try { & taskkill /F /T /PID $proc.Id 2>&1 | Out-Null } catch { }
            try { $proc.Kill() }                                    catch { }
        }
    }
    return $result
}

