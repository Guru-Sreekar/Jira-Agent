# Task Instructions

You will receive:
1. A Jira ticket with full metadata (Issue Key, Type, Summary, Description, Priority, etc.)
2. The current state of the codebase (list of existing files, or "EMPTY" if greenfield)
3. If patching an existing file: the full numbered file content

---

## CRITICAL: Think Comprehensively

Before producing output, ask yourself:
- "What does this ticket ACTUALLY need to be considered DONE?"
- "If I were reviewing this as a PR, would I approve it as complete?"
- "Are there missing files that this feature depends on?"

### Examples of WRONG (incomplete) thinking:
- Ticket: "Create a React project" -> WRONG: only creating package.json
- Ticket: "Add authentication" -> WRONG: only creating one auth.js placeholder
- Ticket: "Set up CI/CD" -> WRONG: only creating a basic yml with just npm test

### Examples of RIGHT (complete) thinking:
- Ticket: "Create a React project" -> RIGHT: package.json + src/index.js + src/App.js + src/App.css + public/index.html + .gitignore + README.md
- Ticket: "Add authentication" -> RIGHT: auth routes + middleware + user model + login handler + register handler + token utils
- Ticket: "Set up CI/CD" -> RIGHT: full workflow with install, lint, test, build, and deploy steps

---

## Output Format

Return ONLY this JSON object — no markdown fences, no extra text:

{
  "ticket_id": "<Issue Key>",
  "issue_type": "<Bug|Story|Epic|Task>",
  "patchable": true,
  "analysis": "<what needs to be done - be specific>",
  "files": [
    {
      "action": "create",
      "file_path": "relative/path/to/file.ext",
      "file_content": "complete file content with \\n for newlines"
    },
    {
      "action": "create",
      "file_path": "another/file.ext",
      "file_content": "complete content"
    },
    {
      "action": "patch",
      "file_path": "existing/file.ext",
      "start_line": 10,
      "end_line": 15,
      "replacement": "replacement code",
      "search_fallback": "original code",
      "replace_fallback": "fixed code"
    }
  ],
  "explanation": "<comprehensive explanation of everything that was done>",
  "priority": "<Critical|High|Medium|Low>"
}

---

## Rules

- "files" array must contain ALL files needed to fully resolve the ticket.
- For a new project: include package.json, entry points, config files, core modules, README.
- For a new feature: include all routes, handlers, models, views, and tests needed.
- For a bug fix: include the patch for every file that needs to change.
- file_content must be the COMPLETE content of the file (not a snippet).
- Use \\n for newlines within file_content strings.
- file_path is relative to codebase root, forward slashes, no leading slash.
- If the ticket is non-code (e.g., "conduct user testing"), set patchable: false.

---

## If patchable is false

{
  "ticket_id": "<Issue Key>",
  "issue_type": "<Type>",
  "patchable": false,
  "analysis": "<why this cannot be resolved with code>",
  "files": [],
  "explanation": "",
  "priority": "<priority>"
}
