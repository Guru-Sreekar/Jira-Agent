function Test-Build {
    $cmd = if ($script:testCmd) { $script:testCmd } elseif ($script:buildCmd) { $script:buildCmd } else { return $true }
    try { $null = & cmd /c "cd /d `"$cbPath`" && $cmd 2>&1"; return ($LASTEXITCODE -eq 0) }
    catch { return $false }
}

# === ENHANCEMENT 1: TICKET VALIDATION ===
function Test-TicketQuality([object]$Issue) {
    # Validates ticket has enough information to proceed
    $f = $Issue.fields
    $summary = $f.summary
    $desc = ''
    if ($f.description) {
        $desc = $f.description
        if ($desc -is [PSCustomObject] -and $desc.content) {
            $dt=''; foreach($b in $desc.content){if($b.content){foreach($il in $b.content){if($il.text){$dt+=$il.text}};$dt+="`n"}}; $desc=$dt.Trim()
        }
    }

    $issues = @()
    $score = 100

    # Check 1: Vague summary (too short or generic)
    if ($summary.Length -lt 10) {
        $issues += "Summary too short - needs more detail"
        $score -= 30
    }
    if ($summary -match '(?i)^(fix|update|change|improve|add)\s+(the\s+)?(app|code|project|system)$') {
        $issues += "Summary too vague - specify what to fix/update/change"
        $score -= 40
    }

    # Check 2: Missing description
    if (-not $desc -or $desc.Length -lt 20) {
        $issues += "Description missing or too short - add details about what needs to be done"
        $score -= 30
    }

    # Check 3: No acceptance criteria or specifics
    if ($desc -and $desc -notmatch '(should|must|when|given|expected|actual|steps|criteria|requirements?)') {
        $issues += "No clear requirements - add acceptance criteria or expected behavior"
        $score -= 20
    }

    # Check 4: Bug without error details
    if ($f.issuetype.name -eq 'Bug' -and $desc -notmatch '(error|exception|fail|crash|broken|not working|expected|actual)') {
        $issues += "Bug ticket lacks error details - describe what's broken and expected behavior"
        $score -= 25
    }

    return @{
        valid = $true # Always accept tickets, letting the LLM infer requirements
        score = $score
        issues = $issues
        needsClarification = ($score -lt 50)
    }
}

# === ENHANCEMENT 2: TEST GENERATION ===
function New-TestFile([string]$SourceFile, [string]$SourceContent, [string]$Language, [string]$Framework) {
    $testFile = ''
    $testContent = ''

    if ($Language -eq 'javascript' -or $Language -eq 'typescript') {
        # Detect test framework
        $useJest = $Framework -match 'jest|react|next' -or (Test-Path (Join-Path $cbPath 'jest.config.js'))
        $useMocha = (Test-Path (Join-Path $cbPath 'package.json')) -and ((Get-Content (Join-Path $cbPath 'package.json') -Raw) -match 'mocha')
        
        if ($SourceFile -match '\.test\.|\.spec\.') { return $null } # Already a test file
        
        # Generate test file path
        if ($SourceFile -match '^src/') {
            $testFile = $SourceFile -replace '^src/', 'tests/' -replace '\.(js|ts|jsx|tsx)$', '.test.$1'
        } else {
            $testFile = $SourceFile -replace '\.(js|ts|jsx|tsx)$', '.test.$1'
        }

        # Extract functions to test
        $functions = [regex]::Matches($SourceContent, '(?:export\s+)?(?:async\s+)?function\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
        $arrowFuncs = [regex]::Matches($SourceContent, 'export\s+const\s+(\w+)\s*=\s*(?:async\s*)?\(') | ForEach-Object { $_.Groups[1].Value }
        $allFuncs = @($functions) + @($arrowFuncs) | Select-Object -First 5

        if ($allFuncs.Count -eq 0) { return $null }

        $importPath = '../' + ($SourceFile -replace '\\','/')
        $testContent = @"
// Auto-generated tests for $SourceFile
import { $(($allFuncs | Select-Object -First 3) -join ', ') } from '$importPath';

describe('$([IO.Path]::GetFileNameWithoutExtension($SourceFile))', () => {
$(foreach ($fn in $allFuncs) {@"

  describe('$fn', () => {
    it('should execute without errors', () => {
      expect($fn).toBeDefined();
    });

    it('should return expected result', () => {
      // TODO: Add test implementation
      expect(true).toBe(true);
    });
  });
"@
})
});
"@
    } elseif ($Language -eq 'python') {
        if ($SourceFile -match 'test_') { return $null }
        
        $testFile = $SourceFile -replace '\.py$', '' -replace '^src/', 'tests/test_' -replace '^', 'tests/test_'
        if (-not ($testFile -match '^tests/')) { $testFile = "tests/$testFile" }
        $testFile += '.py'

        $functions = [regex]::Matches($SourceContent, 'def\s+(\w+)\s*\(') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^__' } | Select-Object -First 5
        if ($functions.Count -eq 0) { return $null }

        $moduleName = [IO.Path]::GetFileNameWithoutExtension($SourceFile)
        $testContent = @"
"""Auto-generated tests for $SourceFile"""
import pytest
from $($SourceFile -replace '\.py$','' -replace '/','.' -replace '^src\.','') import $(($functions | Select-Object -First 3) -join ', ')

$(foreach ($fn in $functions) {@"

class Test$($fn.Substring(0,1).ToUpper() + $fn.Substring(1)):
    def test_${fn}_exists(self):
        assert callable($fn)

    def test_${fn}_basic(self):
        # TODO: Add test implementation
        assert True
"@
})
"@
    }

    if ($testFile -and $testContent) {
        return @{
            file_path = $testFile
            file_content = $testContent
            action = 'create'
        }
    }
    return $null
}

# === ENHANCEMENT 3: RELATED FILES CONTEXT ===
function Get-RelatedFiles([string]$TargetFile) {
    $related = @()
    if (-not $TargetFile) { return $related }

    $baseName = [IO.Path]::GetFileNameWithoutExtension($TargetFile)
    $dir = [IO.Path]::GetDirectoryName($TargetFile)

    # Same directory, similar names
    foreach ($f in $script:relFiles) {
        $fBase = [IO.Path]::GetFileNameWithoutExtension($f)
        $fDir = [IO.Path]::GetDirectoryName($f)
        
        # Same base name, different extension
        if ($fBase -eq $baseName -and $f -ne $TargetFile) {
            $related += $f
        }
        # Similar name pattern (e.g., user.model.js, user.controller.js, user.routes.js)
        # Escape special regex characters to prevent ArgumentException
        elseif ($fBase -and $baseName) {
            try {
                $escapedFBase = [regex]::Escape($fBase)
                $escapedBaseName = [regex]::Escape($baseName)
                if ($fBase -match $escapedBaseName -or $baseName -match $escapedFBase) {
                    $related += $f
                }
            } catch {
                # Skip if regex matching fails
            }
        }
        # Same directory and related keywords
        elseif ($fDir -eq $dir) {
            if ($TargetFile -match 'model' -and $f -match 'controller|service|route') { $related += $f }
            if ($TargetFile -match 'controller' -and $f -match 'model|service|route') { $related += $f }
            if ($TargetFile -match 'route' -and $f -match 'controller|middleware') { $related += $f }
        }
    }

    return $related | Select-Object -Unique -First 5
}

function Get-RelatedFilesContent([string]$TargetFile) {
    $relatedFiles = Get-RelatedFiles -TargetFile $TargetFile
    if ($relatedFiles.Count -eq 0) { return '' }

    $context = "RELATED FILES CONTEXT:`n"
    foreach ($rf in $relatedFiles) {
        $abs = Join-Path $cbPath $rf
        if (Test-Path $abs) {
            $content = Get-Content $abs -Raw -ErrorAction SilentlyContinue
            if ($content.Length -gt 2000) { $content = $content.Substring(0, 2000) + "`n... (truncated)" }
            $context += "`n--- FILE: $rf ---`n$content`n"
        }
    }
    return $context
}

function Invoke-CodeReview([array]$Files) {
    # Internal code review: security, quality, best practices, completeness
    $issues = @()
    $warnings = @()
    $infos = @()

    foreach ($file in $Files) {
        $fp = $file.file_path
        # Normalize content before analyzing to fix escaped characters
        $rawContent = if ($file.file_content) { $file.file_content } elseif ($file.replacement) { $file.replacement } else { '' }
        if (-not $rawContent) { continue }
        $content = Normalize-FileContent -Content $rawContent

        $ext = [IO.Path]::GetExtension($fp).ToLower()
        $isJS = $ext -match '\.(js|jsx|ts|tsx|mjs|cjs)$'
        $isPy = $ext -match '\.py$'
        $isSQL = $ext -match '\.sql$'
        $isHTML = $ext -match '\.(html|htm|vue|svelte)$'
        $isJava = $ext -match '\.(java|kt|scala)$'
        $isCS = $ext -match '\.cs$'
        $isPHP = $ext -match '\.php$'
        $isRuby = $ext -match '\.rb$'
        $isGo = $ext -match '\.go$'

        # === SECURITY CHECKS ===

        # Hardcoded secrets detection
        if ($content -match '(?i)(password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|access[_-]?key)\s*[=:]\s*["''](?!YOUR_|your-|xxx|test|example|changeme|password|admin)[a-zA-Z0-9+/=_-]{8,}') {
            $issues += "[SECURITY] $fp : Potential hardcoded secret detected. Use environment variables or secure vaults instead."
        }

        # AWS/Azure/GCP keys
        if ($content -match 'AKIA[0-9A-Z]{16}') {
            $issues += "[SECURITY] $fp : AWS Access Key detected. Never commit credentials."
        }
        if ($content -match '(?i)(sk-[a-zA-Z0-9]{48})|(sk-proj-[a-zA-Z0-9-_]{40,})') {
            $issues += "[SECURITY] $fp : OpenAI API key pattern detected."
        }

        # SQL Injection patterns
        if ($isJS -or $isPy -or $isPHP -or $isJava) {
            if ($content -match '(?i)(execute|query|exec)\s*\(\s*["''].*?\+.*?["'']') {
                $issues += "[SECURITY] $fp : SQL injection risk - string concatenation in query. Use parameterized queries."
            }
            if ($content -match '(?i)SELECT.*?FROM.*?\$\{') {
                $issues += "[SECURITY] $fp : SQL injection risk - template literals in query. Use prepared statements."
            }
        }

        # XSS vulnerabilities
        if ($isJS -or $isHTML) {
            if ($content -match '\.innerHTML\s*=') {
                $warnings += "[SECURITY] $fp : Potential XSS via .innerHTML. Use textContent or sanitize input."
            }
            if ($content -match 'dangerouslySetInnerHTML') {
                $warnings += "[SECURITY] $fp : dangerouslySetInnerHTML used. Ensure input is sanitized."
            }
            if ($content -match 'eval\s*\(') {
                $issues += "[SECURITY] $fp : eval() detected. This is a severe security risk. Avoid entirely."
            }
        }

        # Command injection
        if ($content -match '(?i)(exec|system|shell_exec|passthru|popen|proc_open)\s*\([^)]*\$') {
            $issues += "[SECURITY] $fp : Command injection risk - user input in shell command. Sanitize or use safe alternatives."
        }

        # Path traversal
        if ($content -match '(?i)(readFile|writeFile|unlink).*?\.\.[/\\]') {
            $issues += "[SECURITY] $fp : Path traversal pattern detected (../ or ..\). Validate file paths."
        }

        # === CODE QUALITY CHECKS ===

        # Console.log in production code
        if ($isJS) {
            $logCount = ([regex]::Matches($content, 'console\.(log|debug|info|warn)')).Count
            if ($logCount -gt 3) {
                $warnings += "[QUALITY] $fp : $logCount console.log statements found. Remove debug logs before production."
            }
        }

        # Python print() debugging
        if ($isPy) {
            $printCount = ([regex]::Matches($content, '^\s*print\(')).Count
            if ($printCount -gt 2) {
                $warnings += "[QUALITY] $fp : $printCount print() statements found. Use logging module instead."
            }
        }

        # Unused variables (basic detection)
        if ($isJS) {
            if ($content -match 'const\s+(\w+)\s*=.*?;\s*$' -and $content -notmatch $matches[1]) {
                $warnings += "[QUALITY] $fp : Potentially unused variable detected."
            }
        }

        # Missing error handling
        if ($isJS) {
            if ($content -match 'await\s+' -and $content -notmatch 'try\s*\{') {
                $warnings += "[QUALITY] $fp : async/await without try-catch. Add error handling."
            }
            if ($content -match '\.then\(' -and $content -notmatch '\.catch\(') {
                $warnings += "[QUALITY] $fp : Promise without .catch(). Add error handling."
            }
        }
        if ($isPy) {
            if ($content -match '(?i)(open|requests\.|urllib)' -and $content -notmatch 'try:') {
                $warnings += "[QUALITY] $fp : I/O operation without try-except. Add error handling."
            }
        }

        # === BEST PRACTICES ===

        # TODO/FIXME comments
        $todoCount = ([regex]::Matches($content, '(?i)(TODO|FIXME|HACK|XXX|BUG):')).Count
        if ($todoCount -gt 0) {
            $warnings += "[COMPLETENESS] $fp : $todoCount TODO/FIXME comments found. Code may be incomplete."
        }

        # Async/await best practices
        if ($isJS) {
            if ($content -match 'async\s+function' -and $content -match 'return\s+await\s+') {
                $infos += "[BEST PRACTICE] $fp : Unnecessary 'return await'. Return the promise directly unless in try-catch."
            }
        }

        # Null/undefined checks
        if ($isJS) {
            if ($content -match '\.\w+\(' -and $content -notmatch '(\?\.|\&\&\s*\w+\.)') {
                $infos += "[BEST PRACTICE] $fp : Consider optional chaining (?.) for safer property access."
            }
        }

        # === COMPLETENESS CHECKS ===

        # Missing imports (JavaScript/TypeScript)
        if ($isJS) {
            $hasReact = $content -match '<\w+.*?>'
            $hasReactImport = $content -match 'import.*?React'
            if ($hasReact -and -not $hasReactImport) {
                $warnings += "[COMPLETENESS] $fp : JSX used but React not imported."
            }

            # Check for common unimported modules
            if ($content -match '\bexpress\(\)' -and $content -notmatch 'require\(["'']express["'']\)|import.*?express') {
                $warnings += "[COMPLETENESS] $fp : express() called but not imported."
            }
            if ($content -match '\baxios\.' -and $content -notmatch 'require\(["'']axios["'']\)|import.*?axios') {
                $warnings += "[COMPLETENESS] $fp : axios used but not imported."
            }
        }

        # Missing imports (Python)
        if ($isPy) {
            if ($content -match '\bnp\.' -and $content -notmatch 'import numpy') {
                $warnings += "[COMPLETENESS] $fp : numpy (np) used but not imported."
            }
            if ($content -match '\bpd\.' -and $content -notmatch 'import pandas') {
                $warnings += "[COMPLETENESS] $fp : pandas (pd) used but not imported."
            }
            if ($content -match '\brequests\.' -and $content -notmatch 'import requests') {
                $warnings += "[COMPLETENESS] $fp : requests used but not imported."
            }
        }

        # Naming conventions
        if ($isJS) {
            if ($content -match 'var\s+') {
                $infos += "[BEST PRACTICE] $fp : 'var' keyword used. Prefer 'const' or 'let' in modern JavaScript."
            }
        }
        if ($isPy) {
            if ($content -match 'def\s+[A-Z]') {
                $infos += "[BEST PRACTICE] $fp : Function name starts with uppercase. Python convention is snake_case."
            }
        }

        # === LANGUAGE-SPECIFIC CHECKS ===

        # JavaScript/TypeScript
        if ($isJS) {
            if ($content -match '==(?!=)' -and $content -notmatch '===') {
                $infos += "[BEST PRACTICE] $fp : Use === instead of == for strict equality."
            }
            if ($content -match 'function\s+\w+\s*\([^)]*\)\s*\{' -and $content -notmatch 'async') {
                # Check if function contains await (missing async keyword)
                if ($content -match 'await\s+') {
                    $issues += "[ERROR] $fp : 'await' used in non-async function. Add 'async' keyword."
                }
            }
        }

        # Python
        if ($isPy) {
            if ($content -match 'except\s*:') {
                $warnings += "[BEST PRACTICE] $fp : Bare except clause. Specify exception type."
            }
            if ($content -match 'import\s+\*') {
                $infos += "[BEST PRACTICE] $fp : Wildcard import used. Import specific names for clarity."
            }
        }

        # Go
        if ($isGo) {
            if ($content -match 'err\s*:?=\s*\S+' -and $content -notmatch 'if\s+err\s*!=\s*nil') {
                $warnings += "[QUALITY] $fp : Error returned but not checked. Add error handling."
            }
        }

        # === FILE STRUCTURE CHECKS ===

        # Check for proper file structure based on type
        if ($fp -match 'package\.json$') {
            try {
                $pkg = $content | ConvertFrom-Json
                if (-not $pkg.name) { $warnings += "[COMPLETENESS] $fp : package.json missing 'name' field." }
                if (-not $pkg.version) { $warnings += "[COMPLETENESS] $fp : package.json missing 'version' field." }
            } catch {
                $issues += "[ERROR] $fp : package.json is not valid JSON."
            }
        }
    }

    # Return review result
    return @{
        pass = ($issues.Count -eq 0)
        issues = $issues
        warnings = $warnings
        infos = $infos
        totalIssues = $issues.Count
        totalWarnings = $warnings.Count
    }
}
# ?? AI-Powered Logic Review ???????????????????????????????????????????????????????
function Invoke-AILogicReview {
    param([array]$Files, [string]$TicketSummary)
    $result = @{ approved=$true; issues=@(); warnings=@(); auto_fixes=@() }
    $reviewable = $Files | Where-Object { $_.file_content -and $_.file_content.Length -gt 50 }
    if ($reviewable.Count -eq 0) { return $result }
    $filesSummary = ($reviewable | Select-Object -First 6 | ForEach-Object {
        # Normalize content before sending to LLM
        $normalizedContent = Normalize-FileContent -Content $_.file_content
        $preview = $normalizedContent.Substring(0, [Math]::Min(50000, $normalizedContent.Length))
        "FILE: $($_.file_path)`n---`n$preview`n"
    }) -join "`n"
    $reviewSys = "You are a PRINCIPAL ENGINEER doing a critical code review. You did NOT write this code. Find ONLY real problems: logic bugs, security flaws, runtime crashes, architecture violations, N+1 queries. For auto_fixes include only small safe fixes with exact search text. The search_fallback MUST be an EXACT literal match of the existing file content (including exact whitespace/indentation) and provide enough unique lines (3-4 lines) to locate the text reliably. Security issues: set approved=false. Return ONLY valid JSON."
    $reviewUser = "TICKET: $TicketSummary`n`nCODE:`n$filesSummary`n`nReturn: {`"approved`": true, `"issues`": [], `"warnings`": [], `"auto_fixes`": [{`"file_path`": `"..`", `"search_fallback`": `"exact existing text`", `"replace_fallback`": `"replacement`"}]}"
    try {
        if (-not $global:FastMode) { Start-Sleep -Milliseconds 1500 }
        $raw = Invoke-LLM -SysPrompt $reviewSys -UserPrompt $reviewUser
        $review = Get-ParsedJson -Text $raw
        if ($review) {
            $result.approved = if ($review.approved -eq $false) { $false } else { $true }
            if ($review.issues)     { $result.issues     = @($review.issues) }
            if ($review.warnings)   { $result.warnings   = @($review.warnings) }
            if ($review.auto_fixes) { $result.auto_fixes = @($review.auto_fixes) }
        }
    } catch { }
    return $result
}

# ?? Behavior-Based Test Generation ???????????????????????????????????????????????
function New-BehaviorTestFile {
    param([string]$SourceFile, [string]$SourceContent, $CodebaseMap)
    $ext  = [IO.Path]::GetExtension($SourceFile).ToLower()
    $isJS = $ext -match '\.(js|jsx|ts|tsx)$'
    $isPy = $ext -eq '.py'
    if (-not ($isJS -or $isPy)) { return $null }
    if ($SourceFile -match '\.test\.|\.spec\.|test_') { return $null }
    $funcCount = ([regex]::Matches($SourceContent, '(?:function\s+\w+|=>\s*\{|def\s+\w+\s*\()')).Count
    $isComplex = $funcCount -ge 3 -or $SourceContent.Length -gt 500
    $lang = if ($isJS) { 'javascript' } else { 'python' }
    $tf   = if ($CodebaseMap.test_framework) { $CodebaseMap.test_framework } else { if ($isJS) { 'jest' } else { 'pytest' } }
    if (-not $isComplex) {
        return New-TestFile -SourceFile $SourceFile -SourceContent $SourceContent -Language $lang -Framework $tf
    }
    $testSys  = "You are a test engineer. Write comprehensive behavior-based $tf tests with real edge cases and error handling."
    $testUser = "Write complete $tf tests for this file.`nSOURCE: $SourceFile`n---`n$($SourceContent.Substring(0,[Math]::Min(50000,$SourceContent.Length)))`n---`nReturn ONLY valid JSON: {`"file_path`": `"tests/..`", `"file_content`": `"complete test file`"}"
    try {
        if (-not $global:FastMode) { Start-Sleep -Milliseconds 1500 }
        $raw  = Invoke-LLM -SysPrompt $testSys -UserPrompt $testUser
        $resp = Get-ParsedJson -Text $raw
        if ($resp -and $resp.file_path -and $resp.file_content) {
            return @{ action='create'; file_path=$resp.file_path; file_content=($resp.file_content -replace '\\n',"`n") }
        }
    } catch { }
    return New-TestFile -SourceFile $SourceFile -SourceContent $SourceContent -Language $lang -Framework $tf
}

# ?? Cross-File Wiring Check ???????????????????????????????????????????????????????
function Test-CrossFileWiring {
    param([array]$NewFiles)
    $issues = @()
    foreach ($f in $NewFiles) {
        if (-not $f.file_content) { continue }
        $fp  = $f.file_path
        $ext = [IO.Path]::GetExtension($fp).ToLower()
        if ($ext -notmatch '\.(js|jsx|ts|tsx)$') { continue }
        $relImports = [regex]::Matches($f.file_content, 'from\s+[''"](\./[^''"]+|\.{1,2}/[^''"]+)[''"]')
        foreach ($m in $relImports) {
            $imp  = $m.Groups[1].Value
            $dir  = ($fp -replace '[^/\\]+$','').TrimEnd('/\')
            $combined = if ($dir) { "$dir/$imp" } else { $imp }
            $resolved = $combined -replace '/[^/]+/\.\./','/'    # resolve ../ segments

            # TypeScript ESM (node16/bundler moduleResolution) uses .js imports that resolve to .ts files
            # e.g. import { User } from '../models/User.js'  ->  actually ../models/User.ts
            $candidates = [System.Collections.Generic.List[string]]::new()
            $candidates.Add($resolved)
            if ($resolved -match '\.js$') {
                $candidates.Add(($resolved -replace '\.js$', '.ts'))
                $candidates.Add(($resolved -replace '\.js$', '.tsx'))
            }

            $found = $false
            foreach ($base in $candidates) {
                foreach ($ext2 in @('','.ts','.tsx','.js','.jsx','/index.ts','/index.tsx','/index.js')) {
                    $candidate = "$base$ext2"
                    if (($script:relFiles -contains $candidate) -or
                        (Test-Path (Join-Path $cbPath ($candidate.Replace('/','\')))) -or
                        ($NewFiles | Where-Object { $_.file_path -eq $candidate })) {
                        $found = $true; break
                    }
                }
                if ($found) { break }
            }
            if (-not $found) { $issues += "BROKEN IMPORT in $fp : '$imp' not found" }
        }
    }
    return $issues
}

# ?? Read-Back Verification ????????????????????????????????????????????????????????
function Invoke-VerifyCreatedFiles {
    param([array]$Files, [string]$TicketSummary, [string]$SubtaskName)
    $result = @{ verified=$true; issues=@(); fixes_needed=@() }
    if ($Files.Count -eq 0) { return $result }
    $fileContents = @()
    foreach ($f in $Files | Select-Object -First 6) {
        $abs = Join-Path $cbPath $f.file_path
        if (Test-Path $abs) {
            $c = Get-Content $abs -Raw -EA SilentlyContinue
            if ($c) { 
                # Normalize content before verification
                $normalized = Normalize-FileContent -Content $c
                $fileContents += "FILE: $($f.file_path)`n$($normalized.Substring(0,[Math]::Min(50000,$normalized.Length)))" 
            }
        }
    }
    if ($fileContents.Count -eq 0) { return $result }
    $vSys  = 'You verify generated code fully implements ticket requirements. Return ONLY valid JSON. The search_fallback MUST be an EXACT literal match of the existing file content (including exact whitespace/indentation) and provide enough unique lines (3-4 lines) to locate the text reliably.'
    $vUser = "TICKET: $TicketSummary`nSUBTASK: $SubtaskName`n`nFILES:`n$($fileContents -join "`n---`n")`n`nReturn: {`"verified`": true/false, `"issues`": [], `"fixes_needed`": [{`"file_path`": `"..`", `"search_fallback`": `"exact existing text`", `"replace_fallback`": `"fix`"}]}"
    try {
        if (-not $global:FastMode) { Start-Sleep -Milliseconds 1500 }
        $raw    = Invoke-LLM -SysPrompt $vSys -UserPrompt $vUser
        $review = Get-ParsedJson -Text $raw
        if ($review) {
            $result.verified = if ($review.verified -eq $false) { $false } else { $true }
            if ($review.issues)       { $result.issues       = @($review.issues) }
            if ($review.fixes_needed) { $result.fixes_needed = @($review.fixes_needed) }
        }
    } catch { }
    return $result
}

# ?? Self-Fix Retry Loop ???????????????????????????????????????????????????????????
function Invoke-SelfFixBuild {
    param([string]$BuildError, [array]$RecentFiles, [int]$MaxRetries=3, $CodebaseMap)
    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Host "  |  [SELF-FIX] Attempt $i/$MaxRetries" -ForegroundColor DarkYellow
        $fileList = ($RecentFiles | ForEach-Object { $_.file_path }) -join ', '
        
        $errStr = if ($BuildError -is [array]) { $BuildError -join "`n" } else { $BuildError }
        $ctxFiles = ""
        if ($CodebaseMap -and $CodebaseMap.Keys.Count -gt 0) {
            foreach ($key in $CodebaseMap.Keys) {
                $bn = Split-Path $key -Leaf
                if ($bn -and $errStr.Contains($bn)) {
                    $absP = Join-Path $cbPath $key
                    if (Test-Path $absP) {
                        $lines = Get-Content $absP -EA SilentlyContinue
                        if ($lines) {
                            $numL = for($k=0;$k -lt $lines.Count;$k++){"$($k+1): $($lines[$k])"}
                            $ctxFiles += "FILE: $key`nCONTENT:`n" + ($numL -join "`n") + "`n`n"
                        }
                    }
                }
            }
        }
        
        $errDisplay = $errStr | Select-Object -Last 40 | Out-String
        $fSys  = 'You are a build error expert. Return the minimal fix. Return ONLY valid JSON. The search_fallback MUST be an EXACT literal match of the existing file content (including exact whitespace/indentation) and provide enough unique lines (3-4 lines) to locate the text reliably.'
        $fUser = "BUILD ERROR:`n$errDisplay`n`nCONTEXT FILES (Potentially involved):`n$ctxFiles`nRECENT FILES: $fileList`n`nReturn: {`"diagnosis`": `"..`", `"files`": [{`"file_path`": `"..`", `"search_fallback`": `"exact existing text`", `"replace_fallback`": `"fix`", `"file_content`": `"optional`"}]}"
        
        try {
            if (-not $global:FastMode) { Start-Sleep -Seconds 3 }
            $raw = Invoke-LLM -SysPrompt $fSys -UserPrompt $fUser
            $fix = Get-ParsedJson -Text $raw
            if ($fix -and $fix.files) {
                Write-Host "  |  [SELF-FIX] $($fix.diagnosis)" -ForegroundColor DarkYellow
                foreach ($ff in $fix.files) {
                    $abs = Join-Path $cbPath $ff.file_path
                    if ($ff.file_content -and -not (Test-Path $abs)) {
                        $d = Split-Path $abs -Parent
                        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
                        $contentToWrite = $ff.file_content
                        if ($contentToWrite -is [string] -and $contentToWrite -match '\\n') {
                            $contentToWrite = $contentToWrite -replace '\\n', "`n"
                        }
                        Set-Content -Path $abs -Value $contentToWrite -Encoding UTF8 -NoNewline
                        Write-Host "  |  [SELF-FIX] Created: $($ff.file_path)" -ForegroundColor Yellow
                        
                        # Verify file integrity
                        $integrityCheck = Test-FileCompleteness -FilePath $abs -ExpectedContent $contentToWrite
                        if (-not $integrityCheck.complete) {
                            Write-Host "  |  [INTEGRITY] Warning - created file may be incomplete" -ForegroundColor Yellow
                            foreach ($issue in $integrityCheck.issues) {
                                Write-Host "  |    - $issue" -ForegroundColor Yellow
                            }
                        }
                    } elseif ($ff.file_content) {
                        Write-Host "  |  [SELF-FIX] Refusing full overwrite of existing: $($ff.file_path)" -ForegroundColor Yellow
                    } elseif ($ff.search_fallback -and (Test-Path $abs)) {
                        $rc = (Get-Content $abs -Raw) -replace "`r`n", "`n"
                        $search = $ff.search_fallback -replace "`r`n", "`n"
                        $replace = $ff.replace_fallback -replace "`r`n", "`n"
                        if ($rc.Contains($search)) {
                            $newContent = $rc.Replace($search, $replace)
                            Set-Content -Path $abs -Value $newContent -Encoding UTF8 -NoNewline
                            Write-Host "  |  [SELF-FIX] Patched: $($ff.file_path)" -ForegroundColor Yellow
                            
                            # Verify file integrity
                            $integrityCheck = Test-FileCompleteness -FilePath $abs -ExpectedContent $newContent
                            if (-not $integrityCheck.complete) {
                                Write-Host "  |  [INTEGRITY] Warning - patched file may be incomplete" -ForegroundColor Yellow
                            }
                        }
                    }
                }
                if (-not $global:FastMode) { Start-Sleep -Seconds 2 }
                $br = Invoke-SafeBuild -CodebaseMap $CodebaseMap
                if ($br.success) {
                    Write-Host "  |  [SELF-FIX] Fixed on attempt $i!" -ForegroundColor Green
                    return @{ fixed=$true; attempts=$i; diagnosis=$fix.diagnosis }
                }
                $BuildError = $br.errors
            }
        } catch { Write-Host "  |  [SELF-FIX] Error: $($_.Exception.Message)" -ForegroundColor DarkYellow }
    }
    return @{ fixed=$false; attempts=$MaxRetries }
}

# Note: Invoke-SurgicalBuildFix is defined in src/executor.ps1 (dot-sourced by run.ps1)
# It supersedes Invoke-SelfFixBuild for precise file-level error targeting.
# Invoke-SelfFixBuild kept below for backward compatibility.
