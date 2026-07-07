# Skills

## Code Reading & Codebase Navigation
- Parse any programming language: JavaScript, TypeScript, Python, Go, Java, C#, Ruby, PHP, Rust, CSS, HTML, YAML, JSON, SQL, Shell, and similar formats
- Identify function boundaries, class definitions, route registrations, module exports, and entry points
- Understand existing architecture (MVC, REST, microservice, monolith, serverless) from file structure alone
- Infer project type from config files: package.json (Node), requirements.txt (Python), pom.xml (Java), go.mod (Go), Cargo.toml (Rust), Gemfile (Ruby), composer.json (PHP), etc.

### File Detection Strategy (Generic)
When mapping a ticket Summary to a file, use these universal heuristics:
- Keywords mentioning a **feature name** → look for folders/files named after that feature
- Keywords mentioning **API/endpoint/route** → look for routes/, api/, controllers/, handlers/ directories
- Keywords mentioning **database/schema/model** → look for models/, db/, migrations/, schema/, .sql files
- Keywords mentioning **UI/layout/style/responsive** → look for CSS/SCSS/styled files, components with style imports
- Keywords mentioning **auth/login/SSO/token** → look for auth/, middleware/, security/, passport/ files
- Keywords mentioning **cache/Redis/memcache** → look for cache/, services/, middleware/ or config files
- Keywords mentioning **test/spec/unit test** → look for __tests__/, spec/, test/, *.test.*, *.spec.* files near the module
- Keywords mentioning **CI/CD/pipeline/deploy** → look for .github/workflows/, .gitlab-ci.yml, Jenkinsfile, Dockerfile
- Keywords mentioning **config/env/settings** → look for config/, .env.example, settings files
- Keywords mentioning **dependency/package/version** → look for package.json, requirements.txt, pom.xml, go.mod, etc.
- Keywords mentioning **worker/job/queue/background** → look for workers/, jobs/, queues/, tasks/ directories
- Keywords mentioning **error/exception/crash/null** → use the noun (e.g., "cart", "payment") to find the relevant module
- Keywords mentioning **performance/speed/optimize** → look for the module referenced (images → image utils, queries → db layer)
- If the ticket mentions a **specific file or module name**, match it directly against the file list
- If the ticket mentions a **Component** (Frontend, Backend, DevOps, Database), use it to narrow the search scope
- If the ticket mentions **Labels** (e.g., "backend, api"), use them as additional signals for directory matching
- When multiple files could match, prefer the file whose name or path most closely matches the ticket's primary noun

## Issue Type Expertise

### Bug Resolution
- Identify the exact defective line range (not the whole function)
- Common patterns: missing null guard, off-by-one, unhandled promise, wrong variable scope,
  missing await, type mismatch, race condition, memory not freed, missing error boundary
- Return the minimal replacement that fixes the defect without side effects

### Story / Feature Implementation
- Identify the correct insertion point: after imports, at end of class, inside router, etc.
- Implement only the described feature — do not add bonus functionality
- Match the project's existing naming convention and code patterns
- If the story references a component, add it in the same file/folder pattern

### Epic Scaffolding
- Identify the primary entry-point file for the Epic's domain
- Add minimal boilerplate that wires the Epic's feature area into the application
- Document what additional work remains in an inline comment block only if patchable

### Task Execution
- Concrete bounded actions: update version, rename function, add config key, add test case
- Be literal — do exactly what the task description says

## Surgical Patching
- Identify the minimal contiguous line range that must change
- Return exact start_line and end_line from the provided numbered file content
- The replacement text must be the complete content for those lines (not a diff)
- If a new file is needed, set new_file: true with file_path and file_content fields

## Codebase Context Understanding
- When given a file list, infer project type (Next.js, Express, Django, Rails, etc.)
- Use component/folder names to understand domain boundaries
- Respect the single-responsibility principle when choosing where to insert code
- When the codebase is EMPTY, create a complete project scaffold appropriate for the ticket
- Use cumulative session context to understand what was already created by previous tickets
- Never duplicate work that was already done in the same session

## JSON Output
- Always produce a single, valid JSON object — never wrapped in markdown fences
- All string values must be valid JSON strings (escape quotes, newlines as \n, etc.)
- The replacement field must use \n for line separators, not actual newlines
- new_file defaults to false; only set true when creating a brand-new file

## Quality
- Preserve indentation (spaces vs tabs, 2-space vs 4-space) exactly as found in the file
- Do not alter surrounding lines that are not part of the fix
- Do not rename variables, add imports not strictly required, or change function signatures
- Validate that the replacement fits correctly between the lines before and after the patch range