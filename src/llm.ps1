function Escape-JsonString([string]$Text) {
    if (-not $Text) { return '' }
    $Text = $Text -replace '\\', '\\\\' -replace '"', '\"'
    $Text = $Text -replace "`r`n", '\n' -replace "`n", '\n' -replace "`r", '\n' -replace "`t", '\t'
    return [regex]::Replace($Text, '[\x00-\x1f]', '')
}

function Test-ModelSuitability {
    param([string]$Model, [string]$Provider)
    
    $warnings = @()
    $recommendations = @()
    $severity = 'info'  # info, warning, error
    
    # Models known to be problematic for code generation
    $problematicModels = @{
        'deepseek/deepseek-v4-flash' = @{
            issue = 'Too fast/low-quality for accurate code patches'
            reason = 'This model prioritizes speed over accuracy and frequently generates patches that do not match actual file content'
            recommendation = 'Switch to google/gemini-2.0-flash-exp, openai/gpt-4o-mini, or anthropic/claude-3-5-sonnet'
            severity = 'error'
        }
        'deepseek/deepseek-chat' = @{
            issue = 'Inconsistent patch generation'
            reason = 'Base DeepSeek models struggle with exact string matching required for patches'
            recommendation = 'Use google/gemini-2.0-flash-exp or openai/gpt-4o-mini for better reliability'
            severity = 'warning'
        }
        'openai/gpt-3.5-turbo' = @{
            issue = 'Limited context window and outdated training'
            reason = 'GPT-3.5 has a smaller context window and older training data'
            recommendation = 'Upgrade to openai/gpt-4o-mini or openai/gpt-4o for better results'
            severity = 'warning'
        }
    }
    
    # Free/limited models that often fail
    if ($Model -match 'free|lite|mini' -and $Model -notmatch 'gpt-4o-mini|gemini.*flash') {
        $warnings += 'Free-tier models often have low token limits (4K output) which causes truncation and parse failures'
        $recommendations += 'Consider paid tiers: google/gemini-2.0-flash-exp (1M context), openai/gpt-4o-mini, or anthropic/claude-3-5-sonnet'
        $severity = 'warning'
    }
    
    # Check against known problematic models
    if ($problematicModels.ContainsKey($Model)) {
        $problem = $problematicModels[$Model]
        $warnings += $problem.issue
        $warnings += "Reason: $($problem.reason)"
        $recommendations += $problem.recommendation
        $severity = $problem.severity
    }
    
    # Recommended models
    $recommended = @(
        'google/gemini-2.0-flash-exp (Best: Free, 1M context, fast, accurate)',
        'openai/gpt-4o-mini (Good: Cheap, reliable, 128K context)',
        'openai/gpt-4o (Premium: Most capable, 128K context)',
        'anthropic/claude-3-5-sonnet (Premium: Excellent for code, 200K context)'
    )
    
    return @{
        model = $Model
        provider = $Provider
        warnings = $warnings
        recommendations = $recommendations
        recommended_models = $recommended
        severity = $severity
        is_problematic = ($warnings.Count -gt 0)
    }
}

function Invoke-LLM([string]$SysPrompt, [string]$UserPrompt) {
    $safeSys = Escape-JsonString $SysPrompt
    $safeUser = Escape-JsonString $UserPrompt
    for ($retry = 0; $retry -le 3; $retry++) {
        try {
            Write-Host -NoNewline "  |  Working...  " -ForegroundColor DarkGray
            
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $runspace
            [void]$ps.AddScript({
                param($provider, $model, $apiKey, $apiEndpoint, $safeSys, $safeUser)
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                try {
                    $body = $null; $result = $null; $finalText = $null
                    if ($provider -eq 'anthropic') {
                        $body = '{"model":"'+$model+'","max_tokens":8000,"system":"'+$safeSys+'","messages":[{"role":"user","content":"'+$safeUser+'"}]}'
                        $result = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers @{"x-api-key"=$apiKey;"anthropic-version"="2023-06-01";"content-type"="application/json"} -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
                        $finalText = $result.content[0].text
                    } elseif ($provider -eq 'google') {
                        $body = '{"system_instruction":{"parts":[{"text":"'+$safeSys+'"}]},"contents":[{"parts":[{"text":"'+$safeUser+'"}]}],"generationConfig":{"temperature":0.05,"maxOutputTokens":8192}}'
                        $url = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$apiKey"
                        $result = Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
                        $finalText = $result.candidates[0].content.parts[0].text
                    } else {
                        $ep = if ($apiEndpoint) { $apiEndpoint } elseif ($provider -eq 'openai') { 'https://api.openai.com/v1/chat/completions' } elseif ($provider -eq 'qwen') { 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions' } else { 'https://openrouter.ai/api/v1/chat/completions' }
                        $body = '{"model":"'+$model+'","temperature":0.05,"max_tokens":8000,"messages":[{"role":"system","content":"'+$safeSys+'"},{"role":"user","content":"'+$safeUser+'"}]}'
                        $result = Invoke-RestMethod -Uri $ep -Method Post -Headers @{Authorization="Bearer $apiKey";'Content-Type'='application/json'} -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
                        if ($result.error) {
                            throw "API Error: $($result.error.message)"
                        }
                        $finalText = $result.choices[0].message.content
                    }
                    return @{ success = $true; data = $finalText }
                } catch {
                    $errBody = ''; try { $s=$_.Exception.Response.GetResponseStream(); $r=New-Object IO.StreamReader($s); $errBody=$r.ReadToEnd() } catch {}
                    $msg = $_.Exception.Message + $(if($errBody){" | $errBody"}else{''})
                    return @{ success = $false; error = $msg }
                }
            }).AddArgument($provider).AddArgument($model).AddArgument($apiKey).AddArgument($env:API_ENDPOINT).AddArgument($safeSys).AddArgument($safeUser)
            
            $handle = $ps.BeginInvoke()

            $spinChars = @('|', '/', '-', '\')
            $spinIndex = 0
            while (-not $handle.IsCompleted) {
                Write-Host -NoNewline "`b$($spinChars[$spinIndex % 4])" -ForegroundColor Cyan
                $spinIndex++
                if ($global:FastMode) { Start-Sleep -Milliseconds 50 } else { Start-Sleep -Milliseconds 150 }
            }

            $jobResult = $ps.EndInvoke($handle)
            $ps.Dispose()
            $runspace.Close()
            $runspace.Dispose()

            # Clear the spinner output cleanly
            Write-Host -NoNewline "`b`b`b`b`b`b`b`b`b`b`b`b`b`b`b`b`b                 `b`b`b`b`b`b`b`b`b`b`b`b`b`b`b`b`b"

            if ($jobResult -and $jobResult.success) {
                return $jobResult.data
            } elseif ($jobResult -and $jobResult.error) {
                throw $jobResult.error
            } else {
                throw "Runspace failed unexpectedly"
            }

        } catch {
            $msg = $_.Exception.Message
            if ($msg -match '429|503|rate.?limit|overload|high demand|unavailable|quota' -and $retry -lt 3) {
                $wait = ($retry+1)*15; Write-Host "    [RETRY $($retry+1)/3] Waiting ${wait}s..." -ForegroundColor DarkYellow; Start-Sleep -Seconds $wait; continue
            }
            throw $msg
        }
    }
}

function Get-ParsedJson([string]$Text) {
    $c = $Text -replace '(?s)```json', '' -replace '(?s)```', ''
    $c = $c.Trim()
    if ($c -match '(?s)(\{.*\})') { try { return $matches[1] | ConvertFrom-Json } catch {} }
    # If JSON is truncated (missing closing brace), try to fix it
    if ($c -match '(?s)(\{.+)') {
        $partial = $matches[1]
        # Count braces to find how many are missing
        $open = ($partial.ToCharArray() | Where-Object { $_ -eq '{' }).Count
        $close = ($partial.ToCharArray() | Where-Object { $_ -eq '}' }).Count
        $missing = $open - $close
        if ($missing -gt 0 -and $missing -le 5) {
            # Try closing with empty arrays/strings for truncated fields
            $arrMissing = [Math]::Max(0, $partial.Split('[').Count - $partial.Split(']').Count)
            $fixed = $partial.TrimEnd(',', ' ', "`n") + (']' * $arrMissing) + ('}' * $missing)
            try { return $fixed | ConvertFrom-Json } catch {}
        }
    }
    return $null
}

function Get-ErrorDiagnosis([string]$ErrorMsg, [string]$Context) {
    $diagnosis = ''
    $suggestion = ''

    if ($ErrorMsg -match '429|rate.?limit|too many|quota') {
        $diagnosis = 'RATE LIMITED: The LLM provider rejected the request because you have exceeded the allowed number of requests per minute/day.'
        $suggestion = 'Wait a few minutes and retry, add credits to your account, or switch to a different model/provider in .env.'
    } elseif ($ErrorMsg -match '503|unavailable|high demand|overload') {
        $diagnosis = 'SERVER OVERLOADED: The LLM provider is temporarily unable to handle requests due to high traffic.'
        $suggestion = 'Wait 1-2 minutes and retry. This is temporary. If persistent, switch to a different model.'
    } elseif ($ErrorMsg -match '401|unauthorized|invalid.*key|authentication') {
        $diagnosis = 'AUTHENTICATION FAILED: Your API key is invalid, expired, or not authorized for this model.'
        $suggestion = 'Check API_KEY in .env. Regenerate the key from your provider dashboard. Ensure the key has access to the specified MODEL.'
    } elseif ($ErrorMsg -match '400|bad request|invalid.*json|payload') {
        $diagnosis = 'BAD REQUEST: The request sent to the LLM was malformed. This usually means special characters in the prompt broke the JSON.'
        $suggestion = 'This is an agent bug. Try a different model. If persistent, report the issue.'
    } elseif ($ErrorMsg -match 'connection.*closed|transport|timeout|timed out') {
        $diagnosis = 'CONNECTION LOST: The LLM response was too large and the connection was terminated before it completed, OR the server timed out.'
        $suggestion = 'The model output limit is too low for this ticket. Switch to a model with higher output tokens (8K+). Avoid openrouter/free for complex tickets.'
    } elseif ($ErrorMsg -match '404|not found|model.*not') {
        $diagnosis = 'MODEL NOT FOUND: The specified model name does not exist or has been deprecated.'
        $suggestion = 'Check MODEL in .env. Verify the model name is correct for your provider. Try: gemini-2.0-flash (Google), gpt-4o (OpenAI), claude-sonnet-4-20250514 (Anthropic).'
    } elseif ($ErrorMsg -match 'parse|json|could not parse') {
        $diagnosis = 'PARSE FAILURE: The LLM returned a response but it was not valid JSON. This happens when the model output is truncated (hit token limit) or the model returned markdown/prose instead of JSON.'
        $suggestion = 'Switch to a model with higher output token limits. Free models often cap at 4K tokens which is too small for multi-file responses. Try gemini-2.0-flash or gpt-4o-mini.'
    } elseif ($ErrorMsg -match 'patch failed|not found|line range') {
        $diagnosis = 'PATCH FAILED: The AI suggested changes to a file but the line numbers or search strings did not match the actual file content.'
        $suggestion = 'The file may have been modified by a previous ticket. The agent will retry on next run. No action needed.'
    } elseif ($ErrorMsg -match 'build.*fail|test.*fail|verify') {
        $diagnosis = 'BUILD/TEST FAILED: The code changes were applied but the project build or tests failed afterward. All changes have been reverted.'
        $suggestion = 'The AI-generated code has issues. Check the ticket description for clarity. More detailed ticket descriptions produce better code.'
    } else {
        $diagnosis = "UNKNOWN ERROR: $ErrorMsg"
        $suggestion = 'Check your .env configuration. Try running with -DryRun first. If persistent, try a different LLM provider/model.'
    }

    Write-Host "  |  [DIAGNOSIS] $diagnosis" -ForegroundColor Red
    Write-Host "  |  [FIX] $suggestion" -ForegroundColor DarkYellow
    return @{ diagnosis = $diagnosis; suggestion = $suggestion }
}

