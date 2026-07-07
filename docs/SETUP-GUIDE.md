# Setup Guide — Jira Ticket Resolver Agent v10.1

Step-by-step instructions to get every credential needed to run the agent.

---

## 1. Jira Credentials

### Jira Cloud (yourcompany.atlassian.net)

1. Go to **https://id.atlassian.com/manage-profile/security/api-tokens**
2. Click **Create API token**, name it (e.g., `jira-agent`)
3. Copy the token immediately
4. Add to `.env`:
```ini
JIRA_URL=https://yourcompany.atlassian.net
JIRA_EMAIL=you@company.com
JIRA_API_TOKEN=ATATT3xFfGF0...your-token
```

### Jira Server / Data Center (self-hosted)

1. Go to your Jira profile → **Personal Access Tokens**
2. Create a token, copy it
3. Add to `.env`:
```ini
JIRA_URL=https://jira.yourcompany.com
JIRA_PAT=your-personal-access-token
```

### Importance of Jira Credentials
The agent operates by connecting to the Jira REST API to fetch ticket details and optionally update ticket statuses.
- **`JIRA_URL` (Compulsory)**: Required so the agent knows the exact server address to pull tickets from. Without this, the web requests fail instantly.
- **Authentication (Email+Token or PAT) (Compulsory)**: Required to pass your company's security verification. The agent acts on your behalf to read private ticket descriptions and acceptance criteria. Without authentication, Jira rejects the agent's requests with a `401 Unauthorized` error.

### Permissions Required
- **Read**: Browse Project permission (required)
- **Write-back**: Transition Issues + Add Comments (optional, for status updates)

---

## 2. LLM API Key

Choose one provider:

### OpenRouter (recommended — access to many models)
1. Sign up at **https://openrouter.ai/**
2. Go to **https://openrouter.ai/keys** → Create Key
3. Add to `.env`:
```ini
PROVIDER=openrouter
API_KEY=sk-or-v1-your-key
MODEL=google/gemini-2.5-flash
```
Note: Free models have 50 req/day limit. Add $5 credit for 1000/day.

### OpenAI
1. Go to **https://platform.openai.com/api-keys** → Create key
2. Add billing at **https://platform.openai.com/account/billing**
```ini
PROVIDER=openai
API_KEY=sk-proj-your-key
MODEL=gpt-4o
```

### Anthropic (Claude)
1. Go to **https://console.anthropic.com/settings/keys** → Create Key
```ini
PROVIDER=anthropic
API_KEY=sk-ant-api03-your-key
MODEL=claude-sonnet-4-20250514
```

### Google Gemini
1. Go to **https://aistudio.google.com/apikey** → Create API Key
```ini
PROVIDER=google
API_KEY=AIzaSy-your-key
MODEL=gemini-2.0-flash
```
Free tier: 15 req/min, 1500/day for gemini-2.0-flash.

### Qwen (DashScope)
1. Go to **https://dashscope.console.aliyun.com/** → API Keys
```ini
PROVIDER=qwen
API_KEY=your-dashscope-key
MODEL=qwen-plus
```

---

## 3. Codebase Path

Point to the root of your project:
```ini
CODEBASE_PATH=C:\Users\you\projects\my-app
```

Requirements:
- Path must exist (agent creates it if missing)
- Agent needs read + write access
- Should point to project root (where package.json, pom.xml, etc. lives)
- Agent excludes: node_modules, .git, dist, build, __pycache__, venv

---

## 4. Project Filtering

### Simple: all open tickets in a project
```ini
JIRA_PROJECT=ENG
```

### Advanced: custom JQL
```ini
JIRA_JQL=project = ENG AND sprint in openSprints()
JIRA_JQL=project = ENG AND assignee = currentUser() AND status = "To Do"
JIRA_JQL=project = ENG AND priority IN (High, Highest)
```

---

## 5. Complete Example

```ini
JIRA_URL=https://mycompany.atlassian.net
JIRA_EMAIL=dev@mycompany.com
JIRA_API_TOKEN=ATATT3xFfGF0abc123
JIRA_PROJECT=ENG
JIRA_WRITE_BACK=true
PROVIDER=google
API_KEY=AIzaSyAbc123
MODEL=gemini-2.0-flash
CODEBASE_PATH=C:\projects\my-app
```

---

## 6. Verify Setup

To verify your credentials, run the built-in test command:
```powershell
.\run.ps1 -Test
```
This will securely test both your Jira connection and your LLM API key, providing clear error diagnosis if anything fails.

---

## 7. Troubleshooting

| Error | Fix |
|-------|-----|
| `401 Unauthorized` | Regenerate API token, check email is correct |
| `403 Forbidden` | Ask Jira admin for project access |
| `410 Gone` | Agent handles this automatically (v3 API) |
| `429 Too Many Requests` | Agent retries 3x automatically. Switch model or add credits. |
| `400 Bad Request` from LLM | Agent handles JSON escaping. If persists, try a different model. |
| `No open tickets found` | Check JIRA_PROJECT matches your board. Verify tickets aren't all Done. |
| `Codebase path not found` | Use absolute path. Agent creates the folder if missing. |

---

## 8. Security Notes

- Never commit `.env` to git (`.gitignore` handles this)
- API tokens can be revoked anytime in Atlassian settings
- The agent sends ticket data + file content to the LLM provider
- For confidential code, use a self-hosted LLM or private API endpoint
- Set `API_ENDPOINT` in `.env` to use a custom/private LLM endpoint
