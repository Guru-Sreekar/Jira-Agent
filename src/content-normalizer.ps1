# content-normalizer.ps1 - Fixes escaped content and validates file writes

function Normalize-FileContent {
    param([string]$Content)
    
    if (-not $Content) { return '' }
    
    # Fix escaped newlines - replace literal \n with actual newlines
    if ($Content -match '\\n') {
        $Content = $Content -replace '\\n', "`n"
    }
    
    # Fix escaped quotes
    if ($Content -match '\\"') {
        $Content = $Content -replace '\\"', '"'
    }
    if ($Content -match "\\'") {
        $Content = $Content -replace "\\'", "'"
    }
    
    # Fix escaped tabs
    if ($Content -match '\\t') {
        $Content = $Content -replace '\\t', "`t"
    }
    
    # Fix double-escaped backslashes - skip this as it's causing regex errors
    # The previous replacements already handle the main cases (\\n, \\t, \\", \\')
    # $Content = $Content -replace '\\\\(?![nt"' + "'" + '])', '\\'
    
    # Normalize line endings to Unix style
    $Content = $Content -replace "`r`n", "`n"
    
    return $Content
}

function Write-FileWithValidation {
    param(
        [string]$FilePath,
        [string]$Content,
        [string]$Operation = 'write'
    )
    
    $result = @{ success=$false; message=''; integrity=$null }
    
    try {
        # Normalize content before writing
        $normalizedContent = Normalize-FileContent -Content $Content
        
        # Create directory if needed
        $dir = Split-Path $FilePath -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        
        # Write file
        Set-Content -LiteralPath $FilePath -Value $normalizedContent -Encoding UTF8 -NoNewline -ErrorAction Stop
        
        # Verify what was written
        Start-Sleep -Milliseconds 50  # Give filesystem time to flush
        $writtenContent = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
        
        # Check integrity
        $integrityCheck = Test-FileCompleteness -FilePath $FilePath -ExpectedContent $normalizedContent
        
        if ($integrityCheck.complete) {
            $result.success = $true
            $result.message = "File written successfully"
            $result.integrity = $integrityCheck
        } else {
            # Try to fix common issues
            $fixed = $false
            
            # If file is truncated or has integrity issues, try writing again
            if ($integrityCheck.issues.Count -gt 0) {
                Start-Sleep -Milliseconds 200
                Set-Content -LiteralPath $FilePath -Value $normalizedContent -Encoding UTF8 -NoNewline -ErrorAction Stop
                Start-Sleep -Milliseconds 50
                $retryCheck = Test-FileCompleteness -FilePath $FilePath -ExpectedContent $normalizedContent
                if ($retryCheck.complete) {
                    $fixed = $true
                    $result.success = $true
                    $result.message = "File written successfully (after retry)"
                    $result.integrity = $retryCheck
                }
            }
            
            if (-not $fixed) {
                $result.success = $false
                $result.message = "File integrity check failed: $($integrityCheck.issues -join '; ')"
                $result.integrity = $integrityCheck
            }
        }
        
    } catch {
        $result.success = $false
        $result.message = "Error writing file: $($_.Exception.Message)"
    }
    
    return $result
}

function Find-BestPatchMatch {
    param(
        [string]$FileContent,
        [string]$SearchText,
        [double]$MinSimilarity = 0.80  # Lower threshold for better flexibility
    )
    
    $result = @{ found=$false; position=-1; matchedText=''; similarity=0.0; method='' }
    
    # Normalize both texts
    $fileNorm = $FileContent -replace "`r`n", "`n"
    $searchNorm = $SearchText -replace "`r`n", "`n"
    
    # Strategy 1: Exact match
    if ($fileNorm.Contains($searchNorm)) {
        $result.found = $true
        $result.position = $fileNorm.IndexOf($searchNorm)
        $result.matchedText = $searchNorm
        $result.similarity = 1.0
        $result.method = 'exact'
        return $result
    }
    
    # Strategy 2: Whitespace normalization
    $fileWhitespaceNorm = $fileNorm -replace '\s+', ' '
    $searchWhitespaceNorm = $searchNorm -replace '\s+', ' '
    
    if ($fileWhitespaceNorm.Contains($searchWhitespaceNorm)) {
        # Find the original text with proper whitespace
        $searchWords = $searchNorm -split '\s+' | Where-Object { $_.Length -gt 0 }
        $pattern = ($searchWords | ForEach-Object { [regex]::Escape($_) }) -join '\s+'
        if ($fileNorm -match $pattern) {
            $result.found = $true
            $result.position = $Matches[0].Index
            $result.matchedText = $Matches[0]
            $result.similarity = 0.95
            $result.method = 'whitespace_norm'
            return $result
        }
    }
    
    # Strategy 3: Line-by-line fuzzy matching with token comparison
    $searchLines = ($searchNorm -split "`n") | Where-Object { $_.Trim().Length -gt 3 }
    $fileLines = $fileNorm -split "`n"
    
    if ($searchLines.Count -ge 3) {
        for ($i = 0; $i -lt $fileLines.Count - $searchLines.Count + 1; $i++) {
            $matchScore = 0
            $totalPossible = $searchLines.Count
            
            for ($j = 0; $j -lt $searchLines.Count; $j++) {
                $searchLine = $searchLines[$j].Trim()
                $fileLine = $fileLines[$i + $j].Trim()
                
                # Exact line match
                if ($fileLine -eq $searchLine) {
                    $matchScore += 1.0
                } elseif ($searchLine.Length -gt 0) {
                    # Token-based matching (ignoring whitespace differences)
                    $searchTokens = $searchLine -split '\s+' | Where-Object { $_.Length -gt 2 }
                    $fileTokens = $fileLine -split '\s+' | Where-Object { $_.Length -gt 2 }
                    
                    $tokenMatchCount = 0
                    foreach ($st in $searchTokens) {
                        if ($fileTokens -contains $st) {
                            $tokenMatchCount++
                        }
                    }
                    
                    if ($searchTokens.Count -gt 0) {
                        $tokenRatio = $tokenMatchCount / $searchTokens.Count
                        $matchScore += $tokenRatio
                    }
                }
            }
            
            $similarity = $matchScore / $totalPossible
            
            if ($similarity -ge $MinSimilarity) {
                $startLine = $i
                $endLine = $i + $searchLines.Count - 1
                $matchedText = ($fileLines[$startLine..$endLine] -join "`n")
                
                $result.found = $true
                $result.matchedText = $matchedText
                $result.similarity = $similarity
                $result.method = 'fuzzy_lines'
                return $result
            }
        }
    }
    
    # Strategy 4: Find by unique identifier (function/variable/class name)
    $identifiers = [regex]::Matches($searchNorm, '\b(function|const|let|var|class|interface|type|def|async function)\s+(\w+)') | 
                   ForEach-Object { $_.Groups[2].Value } |
                   Select-Object -Unique -First 3
    
    if ($identifiers.Count -gt 0) {
        foreach ($id in $identifiers) {
            $pattern = [regex]::Escape($id)
            $matches = [regex]::Matches($fileNorm, "(?m)^.*\b$pattern\b.*$")
            
            if ($matches.Count -eq 1) {
                # Found unique identifier - expand context around it
                $matchLine = $matches[0].Value
                $matchIndex = $fileNorm.IndexOf($matchLine)
                
                # Get surrounding lines (4 before, 4 after)
                $beforeIndex = [Math]::Max(0, $matchIndex - 250)
                $afterIndex = [Math]::Min($fileNorm.Length, $matchIndex + $matchLine.Length + 250)
                $contextText = $fileNorm.Substring($beforeIndex, $afterIndex - $beforeIndex)
                
                $result.found = $true
                $result.matchedText = $contextText
                $result.similarity = 0.75
                $result.method = 'identifier_match'
                Write-Host "  |    [MATCH] Found by unique identifier: $id" -ForegroundColor DarkGray
                return $result
            }
        }
    }
    
    $result.method = 'no_match'
    return $result
}

function Apply-SmartPatch {
    param(
        [string]$FilePath,
        [string]$SearchText,
        [string]$ReplaceText,
        [double]$MinSimilarity = 0.85
    )
    
    $result = @{ success=$false; message=''; appliedMatch=$null }
    
    try {
        if (-not (Test-Path -LiteralPath $FilePath)) {
            $result.message = "File does not exist"
            return $result
        }
        
        $fileContent = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
        if (-not $fileContent) {
            $result.message = "File is empty"
            return $result
        }
        
        # Normalize search and replace
        $searchNorm = Normalize-FileContent -Content $SearchText
        $replaceNorm = Normalize-FileContent -Content $ReplaceText
        
        # Try to find the best match
        $match = Find-BestPatchMatch -FileContent $fileContent -SearchText $searchNorm -MinSimilarity $MinSimilarity
        
        if ($match.found) {
            # Apply the replacement
            $newContent = $fileContent.Replace($match.matchedText, $replaceNorm)
            
            # Write with validation
            $writeResult = Write-FileWithValidation -FilePath $FilePath -Content $newContent
            
            if ($writeResult.success) {
                $result.success = $true
                $result.message = "Patch applied successfully (similarity: $([Math]::Round($match.similarity * 100, 1))%)"
                $result.appliedMatch = $match
            } else {
                $result.message = "Patch matched but write failed: $($writeResult.message)"
            }
        } else {
            $result.message = "Could not find matching text in file (tried exact, whitespace-normalized, and fuzzy matching)"
        }
        
    } catch {
        $result.message = "Error applying patch: $($_.Exception.Message)"
    }
    
    return $result
}
