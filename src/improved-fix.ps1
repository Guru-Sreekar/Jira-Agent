# improved-fix.ps1 - Enhanced surgical fix with better error recovery
# NOTE: content-normalizer.ps1 and file-validator.ps1 are already dot-sourced by run.ps1

function Invoke-ImprovedSurgicalFix {
    param(
        [string]$FilePath,
        $CompileError,
        [int]$MaxAttempts = 5
    )
    
    $result = @{ fixed=$false; attempts=0; method='' }
    $abs = Join-Path $cbPath ($FilePath -replace '/','\')
    
    if (-not (Test-Path -LiteralPath $abs)) {
        $result.method = 'file_not_found'
        return $result
    }

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $result.attempts = $i
        
        # CRITICAL: Re-read the file content EVERY attempt (file may have changed)
        Write-Host "  |    [READ] Re-reading $FilePath for attempt $i..." -ForegroundColor DarkGray
        $currentContent = Get-Content -LiteralPath $abs -Raw -EA SilentlyContinue
        if (-not $currentContent) { break }

        # Context window: 5 lines around the error
        $allLines = $currentContent -split "`r?`n"
        $errIdx = [Math]::Max(0, $CompileError.line - 1)
        $startCtx = [Math]::Max(0, $errIdx - 5)
        $endCtx = [Math]::Min($allLines.Count - 1, $errIdx + 5)
        $ctxLines = for ($k = $startCtx; $k -le $endCtx; $k++) {
            "$($k+1)$(if ($k -eq $errIdx) { ' >>>' } else { ':   ' }) $($allLines[$k])"
        }
        $ctxBlock = $ctxLines -join "`n"
        
        # Show numbered lines for entire context (no truncation for large models)
        $numberedLines = for ($k = 0; $k -lt $allLines.Count; $k++) {
            "$($k+1): $($allLines[$k])"
        }
        $numberedContent = $numberedLines -join "`n"

        $fixSys = "You are a compiler error expert. Fix ONLY the specific error shown. Return ONLY valid JSON with NO markdown formatting, NO code blocks, NO backticks. For search_fallback, you MUST copy 4-6 lines of EXACT existing code from the numbered content provided (including exact whitespace and indentation). The lines must UNIQUELY identify the location and include the error line plus context. Security issues: never remove security checks. Never output code blocks with ```json."
        
        $fixUser = "FILE: $FilePath`nERROR ($($CompileError.code)): $($CompileError.message) at line $($CompileError.line)`n`nCODE CONTEXT (lines $($startCtx+1)-$($endCtx+1)):`n$ctxBlock`n`n=== FULL FILE WITH LINE NUMBERS (for search_fallback) ===`n$numberedContent`n`n=== INSTRUCTIONS ===`nFor search_fallback: Copy 4-6 consecutive lines EXACTLY from the numbered content above. Include the error line ($($CompileError.line)) plus 2-3 lines before and after. Use EXACT whitespace and indentation.`n`nReturn JSON in this exact format:`n{`n  `"search_fallback`": `"exact 4-6 lines copied from numbered content above`",`n  `"replace_fallback`": `"corrected version of those same lines`",`n  `"explanation`": `"what was fixed in one sentence`"`n}`n`nOR if full file rewrite is absolutely necessary:`n{`n  `"file_content`": `"complete corrected file`",`n  `"explanation`": `"why full rewrite was needed`"`n}"

        try {
            if (-not $global:FastMode) { Start-Sleep -Milliseconds 1500 }
            
            $raw = Invoke-LLM -SysPrompt $fixSys -UserPrompt $fixUser
            
            # Clean up the response - remove markdown code blocks if present
            $raw = $raw -replace '(?s)^\s*```json\s*', '' -replace '(?s)\s*```\s*$', ''
            $raw = $raw.Trim()
            
            $fix = Get-ParsedJson -Text $raw
            if (-not $fix) {
                Write-Host "  |    [SURGICAL] Attempt ${i}: JSON parse failed" -ForegroundColor DarkYellow
                continue
            }

            # Try patch approach first
            if ($fix.search_fallback -and $fix.replace_fallback) {
                $patchResult = Apply-SmartPatch -FilePath $abs -SearchText $fix.search_fallback -ReplaceText $fix.replace_fallback -MinSimilarity 0.80
                
                if ($patchResult.success) {
                    Write-Host "  |    [SURGICAL] $($fix.explanation)" -ForegroundColor DarkYellow
                    $result.method = 'smart_patch'
                    
                    # Verify the fix worked
                    $recheck = Invoke-CompileCheck -CodebaseMap @{}
                    $fileNamePat = [regex]::Escape([IO.Path]::GetFileName($FilePath))
                    $stillBroken = $recheck.errors | Where-Object {
                        ($_.file -eq $FilePath) -or ($_.file -match $fileNamePat) -or
                        (($_.line -eq $CompileError.line) -and ($_.code -eq $CompileError.code))
                    }
                    
                    if ($stillBroken.Count -eq 0 -or $recheck.pass) {
                        Write-Host "  |  [COMPILE] Fixed on attempt $i! ($($result.method))" -ForegroundColor Green
                        $result.fixed = $true
                        return $result
                    } else {
                        # Patch applied but error still exists - update error for next iteration
                        $CompileError = $stillBroken[0]
                        Write-Host "  |    [SURGICAL] Patch applied but error persists, retrying with fresh read..." -ForegroundColor DarkYellow
                    }
                } else {
                    Write-Host "  |    [SURGICAL] Patch failed: $($patchResult.message)" -ForegroundColor DarkYellow
                }
            }
            
            # If patch didn't work or wasn't provided, try full rewrite as last resort
            if ($fix.file_content -and $i -ge 3) {
                Write-Host "  |    [SURGICAL] Attempting full file rewrite (attempt $i/$MaxAttempts)..." -ForegroundColor DarkYellow
                
                $writeResult = Write-FileWithValidation -FilePath $abs -Content $fix.file_content
                
                if ($writeResult.success) {
                    $result.method = 'full_rewrite'
                    Write-Host "  |    [SURGICAL] $($fix.explanation)" -ForegroundColor DarkYellow
                    
                    # Verify the fix
                    $recheck = Invoke-CompileCheck -CodebaseMap @{}
                    $fileNamePat = [regex]::Escape([IO.Path]::GetFileName($FilePath))
                    $stillBroken = $recheck.errors | Where-Object {
                        ($_.file -eq $FilePath) -or ($_.file -match $fileNamePat)
                    }
                    
                    if ($stillBroken.Count -eq 0 -or $recheck.pass) {
                        Write-Host "  |  [COMPILE] Fixed on attempt $i! ($($result.method))" -ForegroundColor Green
                        $result.fixed = $true
                        return $result
                    }
                } else {
                    Write-Host "  |    [SURGICAL] File write failed: $($writeResult.message)" -ForegroundColor DarkYellow
                }
            }
            
        } catch {
            Write-Host "  |    [SURGICAL] Attempt $i error: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    
    return $result
}

function Invoke-ImprovedBuildFix {
    param(
        [string]$BuildError,
        [array]$RecentFiles,
        [int]$MaxRetries = 5,
        $CodebaseMap
    )
    
    $errStr = if ($BuildError -is [array]) { $BuildError -join "`n" } else { $BuildError }
    $cbNorm = ($cbPath -replace '\\', '/').TrimEnd('/')

    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Host "  |  [BUILD FIX] Attempt $i/$MaxRetries" -ForegroundColor DarkYellow

        # Parse structured errors from build output
        $compileErrors = @()

        # TypeScript: path/file.ts(line,col): error TS####: message
        $tsMx = [regex]::Matches($errStr, '([^\r\n(]+\.(ts|tsx|js|jsx))\((\d+),(\d+)\):\s+error\s+(TS\d+):\s+(.+)')
        foreach ($m in $tsMx | Select-Object -First 5) {
            $fp = ($m.Groups[1].Value.Trim() -replace '\\','/')
            if ($fp.StartsWith($cbNorm)) { $fp = $fp.Substring($cbNorm.Length).TrimStart('/') }
            $compileErrors += @{
                file=$fp
                line=[int]$m.Groups[3].Value
                col=[int]$m.Groups[4].Value
                code=$m.Groups[5].Value
                message=$m.Groups[6].Value.Trim()
            }
        }

        # Python errors
        $pyMx = [regex]::Matches($errStr, 'File "([^"]+)", line (\d+)')
        foreach ($m in $pyMx | Select-Object -First 3) {
            $fp = ($m.Groups[1].Value -replace '\\','/').Trim()
            if ($fp.StartsWith($cbNorm)) { $fp = $fp.Substring($cbNorm.Length).TrimStart('/') }
            $compileErrors += @{
                file=$fp
                line=[int]$m.Groups[2].Value
                col=0
                code='SYNTAX'
                message='Python syntax error'
            }
        }

        if ($compileErrors.Count -gt 0) {
            # Try to fix the first error
            $err = $compileErrors[0]
            Write-Host "  |  [BUILD FIX] Targeting $($err.file):$($err.line) - $($err.message)" -ForegroundColor DarkYellow
            
            $sfResult = Invoke-ImprovedSurgicalFix -FilePath $err.file -CompileError $err -MaxAttempts 3
            
            if ($sfResult.fixed) {
                # Verify build now passes
                $br = Invoke-SafeBuild -CodebaseMap $CodebaseMap
                if ($br.success) {
                    return @{
                        fixed=$true
                        attempts=$i
                        diagnosis="Fixed $($err.file) line $($err.line): $($err.message) using $($sfResult.method)"
                    }
                }
                # Build still failing - update error string and continue
                $errStr = if ($br.errors -is [array]) { $br.errors -join "`n" } else { "$($br.errors)" }
                continue
            }
        }
        
        # If no structured errors or surgical fix failed, try LLM-based general fix
        $fileList = ($RecentFiles | ForEach-Object { $_.file_path }) -join ', '
        $errDisplay = $errStr | Select-Object -Last 40 | Out-String
        
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
        
        $fSys = 'You are a build error expert. Return ONLY valid JSON with NO markdown formatting, NO code blocks, NO backticks. For search_fallback, provide 4-6 lines of EXACT existing code. Never output ```json.'
        $fUser = "BUILD ERROR:`n$errDisplay`n`nRECENT FILES: $fileList`n`nRECENT FILES CONTENTS:`n$recentFilesContext`n`nReturn JSON:`n{`n  `"diagnosis`": `"what is wrong`",`n  `"files`": [{`n    `"file_path`": `"path`",`n    `"search_fallback`": `"exact 4-6 lines`",`n    `"replace_fallback`": `"fixed version`"`n  }]`n}`n`nNever use file_content unless absolutely necessary."
        
        try {
            if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
            
            $raw = Invoke-LLM -SysPrompt $fSys -UserPrompt $fUser
            $raw = $raw -replace '(?s)^\s*```json\s*', '' -replace '(?s)\s*```\s*$', ''
            $raw = $raw.Trim()
            
            $fix = Get-ParsedJson -Text $raw
            
            if ($fix -and $fix.files) {
                Write-Host "  |  [BUILD FIX] $($fix.diagnosis)" -ForegroundColor DarkYellow
                
                foreach ($ff in $fix.files) {
                    $abs = Join-Path $cbPath ($ff.file_path -replace '/','\')
                    
                    if ($ff.search_fallback -and $ff.replace_fallback) {
                        $patchResult = Apply-SmartPatch -FilePath $abs -SearchText $ff.search_fallback -ReplaceText $ff.replace_fallback
                        
                        if ($patchResult.success) {
                            Write-Host "  |    [PATCHED] $($ff.file_path)" -ForegroundColor Green
                        } else {
                            Write-Host "  |    [FAILED] $($ff.file_path): $($patchResult.message)" -ForegroundColor Yellow
                        }
                    } elseif ($ff.file_content -and -not (Test-Path -LiteralPath $abs)) {
                        # Only create new files, never overwrite existing ones with full content
                        $writeResult = Write-FileWithValidation -FilePath $abs -Content $ff.file_content
                        if ($writeResult.success) {
                            Write-Host "  |    [CREATED] $($ff.file_path)" -ForegroundColor Green
                        }
                    }
                }
                
                # Check if build passes now
                $br = Invoke-SafeBuild -CodebaseMap $CodebaseMap
                if ($br.success) {
                    return @{ fixed=$true; attempts=$i; diagnosis=$fix.diagnosis }
                }
                $errStr = if ($br.errors -is [array]) { $br.errors -join "`n" } else { "$($br.errors)" }
            }
        } catch {
            Write-Host "  |    [ERROR] $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    return @{ fixed=$false; attempts=$MaxRetries; diagnosis="Could not resolve build errors after $MaxRetries attempts" }
}
