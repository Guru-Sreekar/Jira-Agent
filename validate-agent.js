/**
 * Agent Configuration Validator
 * Validates that agent.md has all required sections and keywords
 */

const fs = require('fs');
const path = require('path');

const AGENT_FILE = path.join(__dirname, 'agent.md');

// Required keywords and sections
const REQUIRED_CHECKS = {
  'Continuation Protocol': [
    'CONTINUATION PROTOCOL',
    'EXECUTE FIRST',
    'Check Previous Execution State',
    'agent-run-*.log.json',
    'PARTIAL',
    'filesCreated',
  ],
  'State Awareness': [
    'List all files in backend/',
    'List all files in src/',
    'CONTINUATION',
    'FRESH START',
    'mode:',
  ],
  'Anti-Duplication': [
    'NEVER recreate files',
    'use "patch"',
    'If file exists',
    'action = "patch"',
  ],
  'Output Format': [
    'continuation_info',
    'files_already_exist',
    'subtasks_completed',
    'next_phase',
  ],
  'Epic Handling': [
    'INCREMENTAL EXECUTION',
    '5+ subtasks',
    'Break into logical phases',
    'Resume from next incomplete subtask',
  ],
  'Validation': [
    'Validate Before Execution',
    'Cross-check file paths',
    'Verify all imports',
    'PRE-EXECUTION CHECKLIST',
  ],
};

function validateAgent() {
  console.log('🔍 Validating agent.md configuration...\n');

  if (!fs.existsSync(AGENT_FILE)) {
    console.error('❌ ERROR: agent.md not found!');
    process.exit(1);
  }

  const content = fs.readFileSync(AGENT_FILE, 'utf8');
  let totalChecks = 0;
  let passedChecks = 0;
  const failures = [];

  for (const [section, keywords] of Object.entries(REQUIRED_CHECKS)) {
    console.log(`📦 Checking section: ${section}`);
    
    for (const keyword of keywords) {
      totalChecks++;
      const found = content.includes(keyword);
      
      if (found) {
        passedChecks++;
        console.log(`  ✅ Found: "${keyword}"`);
      } else {
        console.log(`  ❌ Missing: "${keyword}"`);
        failures.push({ section, keyword });
      }
    }
    console.log('');
  }

  // Summary
  console.log('═'.repeat(60));
  console.log(`📊 VALIDATION SUMMARY`);
  console.log('═'.repeat(60));
  console.log(`Total Checks: ${totalChecks}`);
  console.log(`Passed: ${passedChecks} (${Math.round((passedChecks/totalChecks)*100)}%)`);
  console.log(`Failed: ${totalChecks - passedChecks}`);
  console.log('');

  if (failures.length > 0) {
    console.log('⚠️  MISSING ELEMENTS:');
    failures.forEach(f => console.log(`  - [${f.section}] ${f.keyword}`));
    console.log('');
  }

  // Structure checks
  console.log('🏗️  STRUCTURE VALIDATION:');
  const hasVersion = content.match(/v\d+\.\d+/);
  console.log(hasVersion ? '  ✅ Version number found' : '  ⚠️  No version number');
  
  const hasPriority = content.indexOf('CONTINUATION PROTOCOL') < content.indexOf('# Goal');
  console.log(hasPriority ? '  ✅ Continuation Protocol appears before Goal' : '  ❌ Continuation Protocol must come first!');
  
  const hasChecklist = content.includes('PRE-EXECUTION CHECKLIST');
  console.log(hasChecklist ? '  ✅ Pre-execution checklist present' : '  ⚠️  No pre-execution checklist');
  
  console.log('');

  // Final result
  if (passedChecks === totalChecks && hasPriority) {
    console.log('✅ VALIDATION PASSED - Agent configuration is complete and correct!');
    return true;
  } else {
    console.log('❌ VALIDATION FAILED - Agent configuration has issues that need fixing.');
    return false;
  }
}

// Run validation
const isValid = validateAgent();
process.exit(isValid ? 0 : 1);
