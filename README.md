# Jira Ticket Resolver Agent v10.1 (Principal Engineer AI)

An **autonomous, self-healing AI agent** that connects directly to your Jira board, reads open tickets, infers requirements from vague descriptions, decomposes complex work, generates production-ready code with tests, **automatically fixes security issues through iterative refinement**, verifies builds, and updates Jira — all without human intervention.

---

## What Makes This Different

### 🧠 **Intelligence & Autonomy**
- **Requirement Inference** — Expands vague tickets by reading and understanding your codebase
- **Ticket Decomposition** — Automatically splits complex Epics into ordered sub-tasks
- **Architecture Planning** — Analyzes ALL tickets together to ensure consistent tech stack decisions
- **Self-Learning Memory** — Remembers patterns, fixes, and conventions across runs (per-project)

### 🔒 **Security & Quality**
- **Self-Healing Security Review** — Automatically regenerates code when security issues are detected
- **Dual-Layer Code Review** — Static analysis + AI Principal Engineer-level logic review
- **CVE Package Auditing** — Scans newly installed packages for known vulnerabilities
- **Cross-File Wiring Validation** — Ensures imports resolve before applying changes

### 🚀 **Production-Ready Features**
- **Multi-File Generation** — Creates entire feature scaffolds (frontend + backend + tests)
- **Auto-Test Generation** — Jest/pytest test files generated for all new code
- **Smart Package Management** — Auto-installs npm/pip/cargo/go dependencies
- **Build Verification** — Runs build/test commands after changes
- **Atomic Rollback** — Snapshots entire codebase, reverts all changes on failure

### 🔧 **Developer Experience**
- **Direct Jira Integration** — Real-time status updates and comments
- **Dry-Run Mode** — Preview changes without applying them
- **Multi-LLM Support** — OpenAI, Anthropic, Google Gemini, OpenRouter, Qwen
- **Multi-Language** — JavaScript, TypeScript, Python, Java, Go, Rust, C#, PHP, Ruby
- **Context-Aware** — Loads related files to match existing patterns and conventions

---

## Quick Start

```powershell
# 1. Copy config template
copy .env.local .env

# 2. Edit .env with your Jira URL, API token, LLM key, and codebase path

# 3. Preview what the agent will do (safe, no changes)
.\run.ps1 -DryRun

# 4. Execute live (creates/patches files, updates Jira)
.\run.ps1
```

---

## How It Works (9-Phase Pipeline)

```text
[Phase 1/9] 🔍 Fetch Tickets from Jira
            ├─ REST API v3 with v2 fallback
            ├─ JQL filtering with pagination
            └─ Priority-based ordering

[Phase 2/9] 📂 Scan Codebase & Detect Build Tools
            ├─ File inventory (excludes node_modules, .git, etc.)
            ├─ Build tool detection (npm, pip, maven, cargo, go)
            └─ Test framework detection (jest, pytest, etc.)

[Phase 3/9] 🗺️  Build Codebase Intelligence Map
            ├─ Project type detection (27 types: React, Next.js, Django, etc.)
            ├─ Architecture discovery (backend folder, router, CSS framework)
            ├─ Installed packages inventory
            ├─ Existing routes/components/API endpoints extraction
            └─ Cached for performance (invalidates on file changes)

[Phase 4/9] 📸 Create Pre-Execution Snapshot
            ├─ Full codebase backup in backups/snapshots/TIMESTAMP/
            ├─ Manifest.json with ticket IDs and file count
            └─ Atomic restore on failure

[Phase 5/9] 🏗️  Architecture Planning (Cross-Ticket)
            ├─ Analyzes ALL tickets together (with priorities)
            ├─ Determines unified tech stack
            ├─ Plans folder structure
            ├─ Only reorders if technical dependencies require it
            └─ Cached until ticket list changes

[Phase 6/9] 📊 Smart Ticket Ordering
            ├─ Uses Jira priority by default (priority DESC, created ASC)
            ├─ Architecture plan can override if technical dependencies exist
            ├─ LLM only reorders when necessary (not by issue type)
            └─ Use -UseJiraPriority flag to force Jira order

[Phase 7/9] ⚙️  Process Each Ticket
            │
            ├─ 7.1 Validate Ticket Quality (100-point scoring)
            │       └─ Always passes (inference fills gaps)
            │
            ├─ 7.2 Infer Requirements
            │       ├─ Read related files by keyword
            │       ├─ Load agent memory for patterns
            │       ├─ Generate detailed tech spec
            │       └─ Score complexity (simple/medium/complex)
            │
            ├─ 7.3 Decompose Complex Tickets
            │       ├─ Split into 3-4 file sub-tasks
            │       ├─ Track dependencies
            │       └─ Max 6 sub-tasks per ticket
            │
            ├─ FOR EACH SUB-TASK:
            │   │
            │   ├─ 7.4 Generate Code
            │   │       ├─ Context: ticket + codebase map + memory + session history
            │   │       ├─ Load related files for pattern matching
            │   │       ├─ Apply architecture plan constraints
            │   │       └─ Retry on JSON parse failure
            │   │
            │   ├─ 7.5 Static Code Review
            │   │       ├─ Security: secrets, SQL injection, XSS, command injection, path traversal
            │   │       ├─ Quality: debug logs, unused vars, missing error handling, TODOs
            │   │       ├─ Best Practices: async patterns, null safety, naming conventions
            │   │       └─ BLOCKS on critical issues
            │   │
            │   ├─ 7.6 Auto-Install Packages
            │   │       ├─ Extract imports from code
            │   │       ├─ npm/pip/cargo/go install missing packages
            │   │       └─ Sync package.json if updated
            │   │
            │   ├─ 7.7 CVE Audit
            │   │       ├─ npm audit --json for Node projects
            │   │       └─ BLOCKS on critical CVEs
            │   │
            │   ├─ 7.8 AI Logic Review (Principal Engineer)
            │   │       ├─ Second AI reviews code with fresh eyes
            │   │       ├─ Finds: logic bugs, race conditions, N+1 queries, architecture violations
            │   │       └─ IF BLOCKED: Self-Fix Retry Loop
            │   │           ├─ Build detailed fix prompt from issues
            │   │           ├─ Regenerate complete solution
            │   │           ├─ Re-run AI Logic Review
            │   │           ├─ Repeat up to 2 times
            │   │           └─ BLOCKS only if unresolvable after retries
            │   │
            │   ├─ 7.9 Apply Files to Disk
            │   │       ├─ Backup existing files
            │   │       ├─ Create new files
            │   │       ├─ Patch existing files (line-range or search/replace)
            │   │       └─ Track all changes for sub-task
            │   │
            │   ├─ 7.10 Cross-File Wiring Check
            │   │        ├─ Validate all imports resolve
            │   │        ├─ Check file extensions
            │   │        └─ Report broken imports
            │   │
            │   ├─ 7.11 Build Verification
            │   │        ├─ Run npm run build / pip install / cargo build
            │   │        ├─ Capture errors
            │   │        └─ IF FAILED: Diagnose & retry (up to 2 times)
            │   │
            │   ├─ 7.12 Read-Back Verification
            │   │        ├─ Read actual file contents from disk
            │   │        ├─ Verify against ticket requirements
            │   │        └─ Report missing implementations
            │   │
            │   ├─ 7.13 Auto-Generate Tests
            │   │        ├─ Extract function names from source
            │   │        ├─ Generate Jest/pytest test files
            │   │        ├─ Create tests/ directory structure
            │   │        └─ Skip files already tests
            │   │
            │   └─ 7.14 Update Session Context
            │           └─ Record files created for next sub-task
            │
            ├─ 7.15 Update Agent Memory
            │       ├─ Save learned patterns
            │       ├─ Record error fixes
            │       ├─ Update package registry
            │       └─ Refresh codebase map
            │
            └─ 7.16 Update Jira Status
                    ├─ Success → "Done" + comment with files
                    ├─ Failure → "In Progress" + error details
                    └─ Non-code → Skip silently

[Phase 8/9] 📋 Summary Report
            ├─ Success count
            ├─ Skipped count
            ├─ Failed count
            └─ Per-ticket status

[Phase 9/9] 💾 Save Execution Log
            └─ JSON log in agent-run-TIMESTAMP.log.json
```

---

## Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `JIRA_URL` | Yes | Your Jira instance (e.g., `https://company.atlassian.net`) |
| `JIRA_EMAIL` | Cloud | Email for Jira Cloud auth |
| `JIRA_API_TOKEN` | Cloud | API token from Atlassian |
| `JIRA_PAT` | Server | Personal Access Token for Jira Server/DC |
| `JIRA_PROJECT` | Yes* | Project key (e.g., `ENG`). Not needed if JQL is set. |
| `JIRA_JQL` | No | Custom JQL query (overrides project) |
| `JIRA_WRITE_BACK` | No | `true` to update Jira after patching. Default: `false` |
| `PROVIDER` | Yes | `openrouter`, `openai`, `anthropic`, `google`, `qwen` |
| `API_KEY` | Yes | Your LLM API key |
| `MODEL` | No | Model name (default: `google/gemini-flash-1.5`) |
| `CODEBASE_PATH` | Yes | Absolute path to your project source code |

> [!IMPORTANT]
> **Why Jira Credentials Are Compulsory**
> The agent operates autonomously by reading ticket requirements directly from Jira via its REST API. 
> - **`JIRA_URL`**: Required so the agent knows exactly which server/instance to send its web requests to. Without it, the agent has no destination address.
> - **`JIRA_EMAIL` & `JIRA_API_TOKEN` (or `JIRA_PAT`)**: Required to authenticate past your company's security wall. The agent acts on your behalf to read the private titles, descriptions, and acceptance criteria of your tickets. Without authentication, Jira returns a `401 Unauthorized` error and blocks the agent.

---

## 📚 Documentation

For detailed documentation on setup and features:
- **[docs/SETUP-GUIDE.md](docs/SETUP-GUIDE.md)** — Step-by-step credential setup
- **[docs/CHANGELOG.md](docs/CHANGELOG.md)** — Release notes and comprehensive feature explanations

---

## Jira Status Behavior

| Outcome | Jira Status | Comment Added |
|---------|-------------|---------------|
| Success (all files applied, build passes, code review passed) | **Done** | "AI Agent completed (N files): explanation" |
| Success after auto-fix (security issues resolved via retry) | **Done** | "AI Agent completed (N files, fixed after N retries): explanation" |
| Invalid ticket (quality score < 50) | **In Progress** | "AI Agent: Ticket needs more information (Quality Score: XX/100). Please add: [specific feedback]" |
| Review blocked after retries (critical issues persist after 2 attempts) | **In Progress** | "AI Agent: Code review FAILED after auto-fix attempts. Critical issues: [list]" |
| Failure (patch failed, build failed, LLM error) | **In Progress** | "AI Agent failed: reason. Changes reverted." |
| Non-code ticket (e.g., "conduct testing") | No change | Skipped silently |

---

## Backup & Revert

- Backups stored in `backups/` folder (e.g., `backups/IN-4__src__auth__auth.js`)
- On failure: ALL changes for that ticket are atomically reverted
- New files are deleted, patched files are restored from backup
- Manual revert: copy backup file back or use `git restore`

---

## Multi-Project Usage

```powershell
# Different projects with different configs
.\run.ps1 -EnvFile backend.env
.\run.ps1 -EnvFile frontend.env
.\run.ps1 -EnvFile mobile.env
```

---

## Files

| File | Purpose |
|------|---------|
| `run.ps1` | Main agent script — imports modules and executes the main loop |
| `src/llm.ps1` | LLM integration (5 providers), error diagnosis |
| `src/jira.ps1` | Jira REST API (v2/v3), ticket context, status updates |
| `src/files.ps1` | File operations, backups, snapshots, package install |
| `src/quality.ps1` | Code review, test generation, AI logic review |
| `src/memory.ps1` | Persistent learning, pattern storage |
| `src/codebase.ps1` | Project detection, intelligence mapping |
| `agent.md` | AI role, behavior rules, quality standards |
| `task.md` | Output format, completeness examples |
| `skills.md` | File detection heuristics, patching rules |
| `.env.local` | Configuration template |
| `SETUP-GUIDE.md` | Step-by-step credential setup |
| `backups/` | Automatic file backups before patching |
| `docs/` | Comprehensive documentation |

---

## Best Practices

### Writing Good Tickets

**✅ GOOD Examples:**
```text
Summary: Add user authentication to login endpoint
Description: 
- Add JWT token generation on successful login
- Validate email/password against database
- Return 401 on invalid credentials
- Token should expire in 24 hours
Acceptance Criteria:
- POST /auth/login returns JWT on valid credentials
- Invalid credentials return 401 with error message
```

**❌ BAD Examples (Will Be Rejected):**
```text
Summary: Fix app
Description: Not working
```

**💡 Tips:**
- Write summaries > 10 characters with specific details
- Add descriptions > 20 characters explaining what needs to be done
- Include acceptance criteria or expected behavior
- For bugs: describe the error, expected behavior, and actual behavior

---

## Example Output

```text
  [5/7] Processing tickets...

  +-- [1/3] PROJ-123
  |  Type    : Story
  |  Summary : Add user authentication to login endpoint
  |  [VALIDATE] Score: 100/100 | Sub-tasks: 1
  |  [INFER] Complexity: medium
  |  [SUB-TASK 1/1] Implementation
  |  [AI] Generating...
  |  [AI] 3 file(s) planned
  |  [CODE REVIEW] Passed - no issues detected!
  |  [AI REVIEW] Senior logic review...
  |  [AI REVIEW] BLOCKED - attempting auto-fix (retry 1/2)...
  |  [REGEN] Regenerating code with security fixes...
  |  [REGEN] 3 file(s) regenerated
  |  [AI REVIEW] PASSED after fix!
  |  [OK] Created: src/auth/login.js
  |  [OK] Created: src/middleware/auth.js
  |  [OK] Created: src/routes/auth.routes.js
  |  [WIRING] All imports verified
  |  [VERIFY] Running build/test...
  |  [VERIFY] Passed!
  |  [READ-BACK] Verification complete
  |  [TESTS] Created: tests/auth/login.test.js
  |  [TESTS] Generated 1 test file(s)
  |  [JIRA] Status: Done
  |  [DONE] Implemented JWT authentication with password hashing and secure middleware
  +--------------------------------------------------
```
