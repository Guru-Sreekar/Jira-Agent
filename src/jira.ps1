function Get-TicketContext([object]$Issue) {
    $f = $Issue.fields; $lines = @()
    $lines += "Issue Key: $($Issue.key)"
    $lines += "Issue Type: $($f.issuetype.name)"
    $lines += "Summary: $($f.summary)"
    $lines += "Status: $($f.status.name)"
    $lines += "Priority: $(if($f.priority){$f.priority.name}else{'None'})"
    $lines += "Labels: $(if($f.labels -and $f.labels.Count -gt 0){$f.labels -join ', '}else{'None'})"
    $lines += "Components: $(if($f.components -and $f.components.Count -gt 0){($f.components|ForEach-Object{$_.name}) -join ', '}else{'None'})"
    if ($f.description) {
        $desc = $f.description
        if ($desc -is [PSCustomObject] -and $desc.content) {
            $dt=''; foreach($b in $desc.content){if($b.content){foreach($il in $b.content){if($il.text){$dt+=$il.text}};$dt+="`n"}}; $desc=$dt.Trim()
        }
        if ($desc.Length -gt 800) { $desc = $desc.Substring(0,800)+'...' }
        $lines += "Description: $desc"
    }
    if ($f.parent) { $lines += "Parent: $($f.parent.key) - $($f.parent.fields.summary)" }
    return $lines -join "`n"
}

function Write-JiraUpdate([string]$IssueKey, [string]$TargetStatus, [string]$Comment) {
    if (-not $writeBack) { return }
    try {
        if ($Comment) {
            $v3 = @{body=@{type="doc";version=1;content=@(@{type="paragraph";content=@(@{type="text";text=$Comment})})}} | ConvertTo-Json -Compress -Depth 10
            try { Invoke-RestMethod -Uri "$jiraUrl/rest/api/3/issue/$IssueKey/comment" -Headers $jiraHeaders -Method Post -Body $v3 -TimeoutSec 15 | Out-Null }
            catch { $v2=@{body=$Comment}|ConvertTo-Json -Compress; Invoke-RestMethod -Uri "$jiraUrl/rest/api/2/issue/$IssueKey/comment" -Headers $jiraHeaders -Method Post -Body $v2 -TimeoutSec 15 | Out-Null }
            Write-Host "    [JIRA] Comment added to $IssueKey" -ForegroundColor DarkCyan
        }
        $tr = $null
        try { $tr = Invoke-RestMethod -Uri "$jiraUrl/rest/api/3/issue/$IssueKey/transitions" -Headers $jiraHeaders -Method Get -TimeoutSec 15 }
        catch { $tr = Invoke-RestMethod -Uri "$jiraUrl/rest/api/2/issue/$IssueKey/transitions" -Headers $jiraHeaders -Method Get -TimeoutSec 15 }
        $t = $tr.transitions | Where-Object { $_.name -match "(?i)$([regex]::Escape($TargetStatus))" -or $_.to.name -match "(?i)$([regex]::Escape($TargetStatus))" } | Select-Object -First 1
        if ($t) {
            $tb = @{transition=@{id=$t.id}} | ConvertTo-Json -Compress -Depth 4
            try { Invoke-RestMethod -Uri "$jiraUrl/rest/api/3/issue/$IssueKey/transitions" -Headers $jiraHeaders -Method Post -Body $tb -TimeoutSec 15 | Out-Null }
            catch { Invoke-RestMethod -Uri "$jiraUrl/rest/api/2/issue/$IssueKey/transitions" -Headers $jiraHeaders -Method Post -Body $tb -TimeoutSec 15 | Out-Null }
            Write-Host "    [JIRA] $IssueKey -> $TargetStatus" -ForegroundColor DarkCyan
        }
    } catch { Write-Host "    [JIRA WARN] $($_.Exception.Message)" -ForegroundColor DarkYellow }
}
