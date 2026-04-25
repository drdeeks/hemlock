# Enforcement Rules Reference

Detailed rules for workspace enforcement. Referenced by SKILL.md — load when enforcement details are needed.

## Required Directory Layout

```
$HERMES_HOME/
├── SOUL.md                 Agent identity (REQUIRED)
├── USER.md                 User profile (REQUIRED)
├── AGENTS.md               Rules and protocols (REQUIRED)
├── MEMORY.md               Long-term curated memories
├── HEARTBEAT.md            Heartbeat tasks
├── TOOLS.md                Tool notes + environment paths
├── agent.json              Builder code (REQUIRED)
├── config.yaml             Model + provider config
├── .env                    API keys, tokens (SENSITIVE)
├── auth.json               Provider OAuth tokens
│
├── memory/                 Daily notes (YYYY-MM-DD.md)
├── sessions/               Conversation transcripts
├── skills/                 Agent skills
├── projects/               Active work
├── .archive/               Completed/old work (compressed)
├── media/                  Received media from user (NEVER delete)
│   ├── images/
│   │   ├── agents/         Agent profile/prompt images
│   │   └── misc/           Other received images
│   └── files/              Other received files
├── tools/                  Agent-specific scripts
├── logs/                   Runtime logs
├── .secrets/               Credential storage
└── .backups/               Auto-backups
```

## Forbidden Directories

NEVER allowed. Bloat from Hermes framework misconfiguration. Archive contents before removing.

```
memories/       → Use memory/ (singular)
archives/       → Use .archive/ (hidden, singular)
cache/          → Rename to media/, organize contents by type
cron/           Runtime artifact — archive
docs/           Not needed — archive
platforms/      Runtime artifact — archive
state/          Runtime artifact — archive
sandboxes/      Runtime artifact — archive
hooks/          Runtime artifact — archive
audio_cache/    Runtime artifact — archive
image_cache/    Runtime artifact — archive
pairing/        Runtime artifact — archive
profiles/       Runtime artifact — archive
whatsapp/       Runtime artifact — archive
checkpoints/    14GB+ transient — archive
```

### Handling Rules

| Directory | Action |
|-----------|--------|
| `cache/` | Move images to `media/images/misc/`, rest to `media/files/`, remove dir |
| `memories/` | Copy contents to `memory/`, remove dir |
| `archives/` | Copy contents to `.archive/`, remove dir |
| Empty runtime dirs | `rmdir` (safe) |
| Non-empty runtime dirs | `tar czf .archive/<name>-<date>.tar.gz`, then remove |

**media/ is sacred** — contains files the user sent to agents. Never archive or delete.

## Forbidden Files

Safe to remove WITHOUT investigation:

```
.skills_prompt_snapshot.json
.hermes_history
.update_check
interrupt_debug.log
auth.lock
SOUL.md.old
__pycache__/        (recursive)
*.pyc
.DS_Store
```

## Permission Rules

```
WRONG: chmod 700 (anywhere)
WRONG: chmod 000 (anywhere)
RIGHT: chmod 755 (directories)
RIGHT: chmod 644 (files)
EXCEPTION: .secrets/.secret-key may be 600 (encryption key)
```

`chmod 700` locks the user out of their own files. Has caused catastrophic data loss. Detection and auto-fix is part of enforcement.

## Container Awareness

- Containers run as non-root user `agent` (uid 1000, gid 1000)
- `HOME=/home/agent` inside containers
- Plugin mount: `/home/agent/.hermes/plugins/` (NOT `/root/.hermes/plugins/`)
- `$HERMES_HOME` = `/data/agents/<name>/` inside containers
- Host path: `~/.openclaw/agents/<name>/` (bind-mounted)
- Canonical skills location: `~/.openclaw/agents/.skills/` (NOT `~/.hermes/skills/`)

### Entrypoint Permission Normalization (REQUIRED)

The hermes gateway runtime recreates chmod 700 directories on startup. The entrypoint MUST normalize permissions BEFORE launching the gateway. Without this, the workspace root gets 700, blocking enforcement from traversing the directory.

**Fix in entrypoint.sh (after mkdir -p, before gateway start):**
```bash
# Normalize permissions — chmod 700 LOCKS USER OUT
while IFS= read -r d; do
    [ -z "$d" ] && continue
    chmod 755 "$d" 2>/dev/null
done < <(find "${HERMES_HOME}" -type d -perm 700 2>/dev/null)
while IFS= read -r f; do
    [ -z "$f" ] && continue
    chmod 644 "$f" 2>/dev/null
done < <(find "${HERMES_HOME}" -type f -perm 700 \
    -not -path '*/.secrets/*' -not -name '.env' -not -name 'auth.json' 2>/dev/null)
```

Also apply in `agent-bootstrap.sh` embedded entrypoint template so regenerated containers include the fix.

**Why:** chmod 700 on workspace root blocks `find`, `enforce.sh`, and all directory traversal from the agent user. The gateway sets 700 on `memory/`, `logs/`, `sessions/`, and the workspace root itself during startup.

### Agent Path Confusion

Weak models sometimes create `agent-<name>/` in `/app/` (CWD) instead of `$HERMES_HOME`. Files there vanish on container restart.

**Prevention layers:**
1. SOUL.md TOOL CALLS section
2. Plugin pre_llm_call: PATH_ENFORCEMENT
3. Plugin pre_tool_call: warning log
4. Skill: explicit "NEVER create agent-<name> directories"
5. TOOLS.md: Environment Paths section

**Recovery:**
```bash
docker cp <container>:/app/agent-<name>/ ~/recovered-files/
```

## Runtime Behavior

The hermes gateway recreates certain forbidden directories at runtime:
- `cron/` — cron scheduler
- `memories/` — honcho memory service
- `channel_directory.json` — gateway

This is expected. Enforcement handles them on each run. The fix is at the container level (entrypoint ownership fix + non-root USER).

## Autonomy Protocol

From [The Autonomy Protocol](https://github.com/alan-botts/strangerloops/blob/main/content/autonomy-protocol.md):

1. **Deterministic tasks → scripts.** Enforcement is code, not English description.
2. **State in files, not head.** Forbidden dir lists live in this file, not in memory.
3. **Third repetition → build the tool.** If manually cleaning 3x, add to the script.
4. **Fail loudly.** Report what was found and what was done. Silent cleanup loses data.
5. **Fresh context for complex tasks.** Spawn a subagent for multi-agent enforcement.
