# Agent Testing Guide

## Pre-Test Checklist

Before running the agent with the improvements, verify:

- [ ] All files are saved and no editors have unsaved changes
- [ ] `src/content-normalizer.ps1` exists and contains normalization functions
- [ ] `src/improved-fix.ps1` exists and contains improved fix functions
- [ ] `run.ps1` sources both new modules (check lines 96-97)
- [ ] DeepSeek API key is configured in `.env` or `.env.local`

## Quick Verification Test

Run this command to verify the new functions are loaded:

```powershell
cd d:\agents
.\run.ps1 -Verify
```

Expected output should show:
```
[OK] content-normalizer.ps1 loaded
[OK] improved-fix.ps1 loaded
[OK] Normalize-FileContent available
[OK] Write-FileWithValidation available
[OK] Apply-SmartPatch available
[OK] Invoke-ImprovedSurgicalFix available
[OK] Invoke-ImprovedBuildFix available
```

## Test Scenarios

### Test 1: Basic Ticket Resolution (Bug)

**Objective**: Verify escaped newline fixes and file integrity

1. Create a simple Bug ticket in Jira with:
   - Summary: "Fix undefined variable error in user profile"
   - Description: "When viewing user profile, console shows 'userEmail is not defined'"

2. Run the agent:
```powershell
.\run.ps1
```

3. Monitor logs for these success indicators:
   - ✅ `[OK] Content normalized` messages
   - ✅ `[OK] File written successfully` with integrity checks
   - ✅ No "Invalid character" errors
   - ✅ No "Mismatched braces" warnings
   - ✅ Ticket marked as "Done" (not "In Progress")

### Test 2: Patch Matching (Build Error Fix)

**Objective**: Verify fuzzy patch matching works

1. Create a Bug ticket with a compile error that requires patching
2. Run agent and watch for:
   - ✅ `[COMPILE] Fixed on attempt X! (smart_patch)` messages
   - ✅ Similarity percentages (e.g., "similarity: 95%")
   - ✅ No "Patch text not found" failures after multiple retries

### Test 3: Build Recovery (Multiple Errors)

**Objective**: Verify structured error parsing and targeted fixes

1. Create a ticket that generates multiple compile errors
2. Run agent and verify:
   - ✅ `[BUILD FIX] Targeting file.ts:line - error message`
   - ✅ Errors fixed one by one (not full file rewrites)
   - ✅ `[BUILD] Fixed! Fixed src/... using smart_patch`

## Success Metrics

### Before Improvements (Baseline)
- Success Rate: 1/3 tickets (33%)
- "Patch text not found" failures: Common
- "Could not fix after 5 attempts": Frequent
- Tickets marked "In Progress": 2/3

### After Improvements (Target)
- Success Rate: >80% tickets
- Patch success: >90% (exact or fuzzy)
- Build recovery: Structured diagnosis with targeted fixes
- Tickets marked "Done": >80%

## Log Analysis

### Success Indicators

Look for these patterns in the logs:

```
[OK] Patched: file.ts (Patch applied successfully - similarity: 95%)
[COMPILE] Fixed on attempt 1! (smart_patch)
[BUILD] Fixed! Fixed src/app/actions/invoice.ts line 14 using smart_patch
[OK] File written successfully
[OK] File integrity check passed
```

### Warning Signs

These indicate potential issues:

```
[INTEGRITY] Warning - file may be incomplete after fix
[SURGICAL] Patch text not found - retrying
[BUILD FIX] Refusing full rewrite of existing file
Could not fix after 5 attempts
```

### Error Patterns (Should NOT Appear)

```
Invalid character in identifier
SyntaxError: Unexpected token
Mismatched braces (72 open, 75 close)
File appears truncated
```

## Debugging Failed Tests

### If escaped newlines still appear:

1. Check if `Normalize-FileContent` is being called before writing
2. Verify the LLM response isn't wrapped in triple backticks (````json)
3. Check if the content is a string (not an object)

### If patches fail to match:

1. Check the similarity threshold (default: 85%)
2. Review the search text - should be 3-4 unique lines
3. Verify whitespace normalization is working
4. Check logs for "Fuzzy match attempt" messages

### If build errors repeat:

1. Verify `Invoke-ImprovedBuildFix` is being called (not old function)
2. Check if error parsing is working (TypeScript/Python/Go)
3. Review the targeted file path and line number
4. Ensure surgical fix is attempting before full rewrite

## Performance Monitoring

Track these timing metrics:

- **Ticket Resolution Time**: Should be <5 minutes per Bug
- **Patch Match Time**: Should find match within 3 attempts
- **Build Fix Time**: Should fix errors within 3 retry loops

## Rollback Procedure

If the improvements cause issues:

### Option 1: Restore from snapshot
```powershell
.\run.ps1 -Restore
# Or restore specific date:
.\run.ps1 -Restore -Date "2026-06-28"
```

### Option 2: Remove new modules
```powershell
# Temporarily disable by renaming
Rename-Item src\content-normalizer.ps1 src\content-normalizer.ps1.bak
Rename-Item src\improved-fix.ps1 src\improved-fix.ps1.bak
```

### Option 3: Restore from backup
```powershell
Copy-Item backups\snapshots\2026-06-28-22-17-27\* . -Recurse -Force
```

## Next Steps After Testing

### If tests pass (>80% success rate):
1. Document successful test cases
2. Update README with new features
3. Create release notes
4. Archive old backup snapshots
5. Monitor production runs for 1 week

### If tests fail (<80% success rate):
1. Collect failure logs from `agent-run-*.log.json`
2. Analyze root causes
3. Create focused improvement PRs
4. Re-test with fixes
5. Consider gradual rollout (A/B testing)

## Advanced Testing

### Stress Test (Multiple Tickets)
```powershell
# Process 5+ tickets in one run
.\run.ps1 -MaxTickets 5
```

### Specific Error Types
Test with tickets that trigger:
- SQL injection fixes (security)
- Missing import statements (completeness)
- TypeScript type errors (compile)
- React hook dependency warnings (quality)

### Edge Cases
- Very large files (>5000 lines)
- Files with mixed line endings
- Files with Unicode/emoji characters
- Concurrent file modifications

## Support Resources

- **Full Documentation**: See `IMPROVEMENTS.md`
- **Architecture**: See `src/content-normalizer.ps1` header comments
- **Logs**: Check `agent-run-YYYY-MM-DD-HH-mm.log.json`
- **Backups**: In `backups/snapshots/` directory

## Contact

For issues or questions:
1. Check logs in `agent-run-*.log.json`
2. Review `IMPROVEMENTS.md` for architecture
3. Test with `-Verbose` flag for detailed output
4. Create snapshot before major changes
