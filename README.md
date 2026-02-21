# OpenClaw Client Starter Kit
### By Go Digital | v1.0

This folder contains everything needed to set up a new OpenClaw deployment for a client. Copy the entire folder into the client's workspace directory.

## What's Included

### Core Files (workspace root)

| File | Purpose | When It's Read |
|------|---------|----------------|
| `SOUL.md` | Agent personality, values, boundaries | Every session |
| `AGENTS.md` | Operating instructions, memory protocol, safety rules | Every session |
| `IDENTITY.md` | Agent name, role, emoji | Every session |
| `USER.md` | Human's name, timezone, preferences, projects | Every session |
| `TOOLS.md` | Connected services, API notes, installed skills | As needed |
| `HEARTBEAT.md` | Periodic check-in tasks | On heartbeat polls |
| `BOOTSTRAP.md` | First-run conversation guide (delete after setup) | First session only |
| `MEMORY.md` | Long-term curated memory | Every main session |

### Memory Directory (`memory/`)

| File | Purpose |
|------|---------|
| `KEY-DECISIONS.md` | Decisions that affect future behavior |
| `lessons-learned.md` | What worked, what failed, patterns |
| `content-ideas.md` | Ideas for content creation |
| `archive/` | Older daily notes (auto-searchable) |

## Setup Steps

### 1. Copy Files
```bash
cp -r client-starter-kit/ /path/to/client/workspace/
```

### 2. First Boot
The agent will find `BOOTSTRAP.md` and initiate a getting-to-know-you conversation with the client. They'll decide the agent's name, personality, and preferences together.

### 3. Post-Bootstrap
After the first conversation, the agent will:
- Fill in `IDENTITY.md` with its chosen name and emoji
- Fill in `USER.md` with the client's info
- Customize `SOUL.md` based on the conversation
- Delete `BOOTSTRAP.md`
- Create initial daily notes in `memory/`

### 4. Hardening
Run through the security checklist in `client-onboarding-guide.md` (separate document).

## Customization

### For Business Clients
Add to `AGENTS.md`:
- Industry-specific instructions
- Compliance requirements
- Approved external actions
- Reporting schedules

### For Technical Clients
Add to `TOOLS.md`:
- SSH server details
- GitHub repos
- Database connections
- CI/CD pipelines

### For Creative Clients
Add to `SOUL.md`:
- Brand voice guidelines
- Content pillars
- Tone preferences
- Platform-specific rules

## File Relationships

```
BOOTSTRAP.md (first run only, then deleted)
    ↓ creates
IDENTITY.md ← who the agent is
USER.md     ← who the human is
SOUL.md     ← how the agent behaves
    ↓ governed by
AGENTS.md   ← operating rules + memory protocol
    ↓ uses
MEMORY.md + memory/ ← persistent knowledge
TOOLS.md   ← environment config
HEARTBEAT.md ← periodic tasks
```

## The Memory Protocol

The key differentiator in our setup. Most OpenClaw deployments have no structured memory. Our clients get:

1. **5-file save protocol** - Every significant action saves to 5 files
2. **Auto-triggers** - Agent knows WHEN to save (not just "remember things")
3. **Structured storage** - Agent knows WHERE to save (daily notes vs long-term vs decisions)
4. **Search-first recall** - Uses `memory_search` before answering from memory
5. **Context management** - Auto-saves when context window fills up

This is the protocol that makes the agent actually useful across sessions instead of starting fresh every time.

---

*Maintained by Go Digital. Last updated: February 2026.*
