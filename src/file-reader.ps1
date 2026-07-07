# file-reader.ps1 - Reads and prepares files for patching
# This ensures the LLM sees ACTUAL file content before generating patches

function Get-FileWithLineNumbers {
    param(
        [string]$FilePath,
        [int]$MaxLines = 500
    )
    
    $abs = Join-Path $cbPath ($FilePath -replace '/','\')
    if (-not (Test-Path -LiteralPath $abs)) {
        return @{ exists=$false; content=''; numbered=''; lineCount=0 }
    }
    
    try {
        $lines = Get-Content -LiteralPath $abs -ErrorAction Stop
        $total = $lines.Count
        
        # If file is too long, include first/last sections + middle sample
        if ($total -gt $MaxLines) {
            $firstSection = 200
            $lastSection = 200
            $middleStart = [Math]::Floor($total / 2) - 50
            $middleEnd = $middleStart + 100
            
            $numbered = @()
            for ($i = 0; $i -lt $firstSection; $i++) {
                $numbered += "$($i+1): $($lines[$i])"
            }
            $numbered += "`n... [lines $($firstSection+1)-$middleStart omitted] ...`n"
            for ($i = $middleStart; $i -lt $middleEnd; $i++) {
                $numbered += "$($i+1): $($lines[$i])"
            }
            $numbered += "`n... [lines $($middleEnd+1)-$($total-$lastSection) omitted] ...`n"
            for ($i = $total - $lastSection; $i -lt $total; $i++) {
                $numbered += "$($i+1): $($lines[$i])"
            }
            $numberedText = $numbered -join "`n"
        } else {
            $numbered = for ($i = 0; $i -lt $total; $i++) {
                "$($i+1): $($lines[$i])"
            }
            $numberedText = $numbered -join "`n"
        }
        
        return @{
            exists = $true
            content = ($lines -join "`n")
            numbered = $numberedText
            lineCount = $total
        }
    } catch {
        return @{ exists=$false; content=''; numbered=''; lineCount=0; error=$_.Exception.Message }
    }
}

function Get-FilesForPatching {
    param([array]$PlannedFiles)
    
    $filesContext = @()
    
    foreach ($pf in $PlannedFiles) {
        $fp = $pf.file_path
        $action = if ($pf.action) { $pf.action } else { 'create' }
        
        # For patches, ALWAYS read the current file
        if ($action -eq 'patch') {
            $fileData = Get-FileWithLineNumbers -FilePath $fp -MaxLines 500
            if ($fileData.exists) {
                Write-Host "  |  [READ] $fp ($($fileData.lineCount) lines)" -ForegroundColor DarkGray
                $filesContext += @{
                    file_path = $fp
                    action = 'patch'
                    current_content = $fileData.numbered
                    line_count = $fileData.lineCount
                }
            } else {
                Write-Host "  |  [WARN] Cannot patch non-existent file: $fp (will create instead)" -ForegroundColor Yellow
                $filesContext += @{
                    file_path = $fp
                    action = 'create'
                    current_content = ''
                    line_count = 0
                }
            }
        } else {
            # For create, just mark it
            $filesContext += @{
                file_path = $fp
                action = 'create'
                current_content = ''
                line_count = 0
            }
        }
    }
    
    return $filesContext
}

function Build-FileContextString {
    param([array]$FilesContext)
    
    $contextStr = ""
    
    foreach ($fctx in $FilesContext) {
        if ($fctx.action -eq 'patch' -and $fctx.current_content) {
            $contextStr += "`n================================================================`n"
            $contextStr += "CURRENT FILE TO PATCH: $($fctx.file_path) ($($fctx.line_count) lines)`n"
            $contextStr += "================================================================`n"
            $contextStr += "$($fctx.current_content)`n"
            $contextStr += "================================================================`n`n"
        } else {
            $contextStr += "`n=== FILE TO CREATE: $($fctx.file_path) ===`n(New file - no current content)`n`n"
        }
    }
    
    return $contextStr
}
