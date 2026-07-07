# Ticket Ordering Guide

## Overview
The agent now properly respects Jira priorities when processing tickets instead of artificially reordering by type (Epics first, bugs last).

## How It Works

### Three Ordering Modes:

1. **Jira Priority Order** (Default when no arch plan exists)
   - Uses the order from Jira's JQL: `priority DESC, created ASC`
   - Higher priority tickets are processed first
   - Among same priority, older tickets come first
   - No artificial reordering by issue type

2. **Architecture Plan Order** (When LLM determines dependencies)
   - The architecture planning LLM can specify `ticket_order` if there are technical dependencies
   - The LLM is instructed to ONLY specify order if dependencies require it
   - If no dependencies exist, the LLM omits `ticket_order` and Jira priority is used
   - Priority information is included in the prompt to help the LLM make better decisions

3. **Force Jira Priority** (Manual override)
   - Use `-UseJiraPriority` flag to force Jira priority order
   - Ignores any architecture plan ordering
   - Example: `.\run.ps1 -UseJiraPriority`

## Usage

### Default behavior (respects priorities):
```powershell
.\run.ps1
```

### Force Jira priority (ignore arch plan):
```powershell
.\run.ps1 -UseJiraPriority
```

### Clear cached architecture plan:
If you want to regenerate the architecture plan with the new priority-aware prompt, delete the cache:
```powershell
# Find your codebase's .agent-memory folder
Remove-Item "D:\GL\invoice app\.agent-memory\arch-plan.json" -Force
```

## Changes Made

### Architecture Planning Prompt
- Now includes priority information in ticket summaries: `IA-5 [Priority: High] [Epic] need login page`
- Instructs LLM to only specify `ticket_order` if technical dependencies require it
- Makes `ticket_order` optional in the architecture plan

### Ticket Ordering Logic
- Added `-UseJiraPriority` parameter to force Jira order
- Default behavior now respects Jira priorities
- Clear logging shows which ordering mode is being used

## Expected Behavior

**Before:**
```
[4/7] Ordering tickets by dependency...
Order: 1 Epics -> 2 standalone -> 0 child
```
- Always processed Epics first regardless of priority
- Bugs always came last

**After:**
```
[4/7] Ordering tickets...
Using Jira priority order (priority DESC, created ASC)
Processing 3 ticket(s) in order: IA-3, IA-4, IA-5
```
OR
```
[4/7] Ordering tickets...
Using architecture plan order: IA-5, IA-3, IA-4
(only if LLM detected technical dependencies)
```

## Troubleshooting

### Agent still using wrong order?
1. Check if there's a cached architecture plan with old logic
2. Delete `<codebase>/.agent-memory/arch-plan.json`
3. Run again to regenerate with new priority-aware prompt

### Want to always use Jira priorities?
Use the `-UseJiraPriority` flag:
```powershell
.\run.ps1 -UseJiraPriority
```

### Architecture plan order seems wrong?
The LLM might have detected technical dependencies. Check the plan:
```powershell
Get-Content "D:\GL\invoice app\.agent-memory\arch-plan.json" | ConvertFrom-Json | Select-Object -ExpandProperty plan | Select-Object -ExpandProperty ticket_order
```

If you disagree with the LLM's assessment:
1. Delete the cache file
2. Use `-UseJiraPriority` flag
3. Or manually edit Jira priorities
