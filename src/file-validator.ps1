# file-validator.ps1 - Validates file completeness after writing

function Test-FileCompleteness {
    param(
        [string]$FilePath,
        [string]$ExpectedContent
    )
    
    $result = @{ complete=$true; issues=@() }
    
    if (-not (Test-Path -LiteralPath $FilePath)) {
        $result.complete = $false
        $result.issues += "File does not exist: $FilePath"
        return $result
    }
    
    try {
        $actualContent = Get-Content -LiteralPath $FilePath -Raw -EA Stop
        
        if (-not $actualContent) {
            $result.complete = $false
            $result.issues += "File is empty"
            return $result
        }
        
        $ext = [IO.Path]::GetExtension($FilePath).ToLower()
        
        # Check for truncation indicators
        if ($actualContent -match '(?:^|\n)\s*[a-zA-Z_$][\w$]*\s*$' -and $ext -match '\.(js|ts|tsx|jsx|py|cs|java|go|rs)$') {
            $result.issues += "File may be truncated - ends with incomplete identifier"
        }
        
        # Check for incomplete function/class definitions
        if ($ext -match '\.(js|ts|tsx|jsx)$') {
            # Brace counting is disabled because it's too unreliable:
            # - Braces in strings: "hello {world}"
            # - Braces in template literals: `${var}`
            # - Braces in comments: // { comment }
            # - Braces in regex: /\{/g
            # A proper parser would be needed for accurate detection.
            # The build/compile check is more reliable for catching syntax errors.
            
            # Only check for obviously incomplete code (function without closing)
            if ($actualContent -match 'function\s+\w+\s*\([^)]*\)\s*\{\s*$') {
                $result.complete = $false
                $result.issues += "Function appears incomplete - ends with opening brace only"
            }
            
            # Check for incomplete function
            if ($actualContent -match '(?:function|const\s+\w+\s*=\s*(?:async\s*)?\([^)]*\)\s*=>)\s*\{[^}]*$') {
                $result.complete = $false
                $result.issues += "Incomplete function definition detected"
            }
        }
        
        if ($ext -eq '.py') {
            # Check for incomplete Python functions
            if ($actualContent -match '(?m)^\s*def\s+\w+\s*\([^)]*\):\s*$') {
                $result.issues += "Function definition without body detected"
            }
        }
        
        # Check for incomplete CSS/comments
        if ($ext -match '\.(css|scss|less)$' -or $actualContent -match '/\*') {
            $openComments = ([regex]::Matches($actualContent, '/\*')).Count
            $closeComments = ([regex]::Matches($actualContent, '\*/')).Count
            if ($openComments -ne $closeComments) {
                $result.complete = $false
                $result.issues += "Incomplete comment block: $openComments open, $closeComments close"
            }
        }
        
        # Check if file is significantly shorter than expected
        if ($ExpectedContent -and $ExpectedContent.Length -gt 500) {
            $ratio = $actualContent.Length / $ExpectedContent.Length
            if ($ratio -lt 0.8) {
                $result.issues += "File is significantly shorter than expected (${ratio}% of expected length)"
            }
        }
        
        # Check for common truncation patterns
        $truncationPatterns = @(
            '\.\.\.$',                          # Ends with ...
            '(?:^|\n)[a-z]+$',                  # Ends mid-word
            '(?:^|\n)\s*\w+\s*\($',             # Ends with function call opening
            '(?:^|\n)\s*\{$',                   # Ends with lone opening brace
            '(?:^|\n)\s*\[$',                   # Ends with lone opening bracket
            '(?:^|\n)\s*["\x27][\w\s]*$'        # Ends with unclosed string
        )
        
        foreach ($pattern in $truncationPatterns) {
            if ($actualContent -match $pattern) {
                $result.issues += "Possible truncation: content matches pattern '$pattern'"
                break
            }
        }
        
    } catch {
        $result.complete = $false
        $result.issues += "Error reading file: $($_.Exception.Message)"
    }
    
    if ($result.issues.Count -gt 0) {
        $result.complete = $false
    }
    
    return $result
}

function Invoke-FileIntegrityCheck {
    param([array]$Files, [string]$CodebasePath)
    
    $results = @()
    
    foreach ($file in $Files) {
        $fp = $file.file_path -replace '\\','/'
        $abs = Join-Path $CodebasePath ($fp -replace '/','\')
        
        if (Test-Path -LiteralPath $abs) {
            $check = Test-FileCompleteness -FilePath $abs -ExpectedContent $file.file_content
            
            if (-not $check.complete) {
                $results += @{
                    file = $fp
                    issues = $check.issues
                }
            }
        }
    }
    
    return $results
}

