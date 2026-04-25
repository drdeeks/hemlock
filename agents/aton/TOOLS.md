# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```


## Environment Paths

**Workspace root:** `$HERMES_HOME` (set by gateway)
- In containers: `/data/agents/aton/`
- On host: `~/.openclaw/agents/aton/`

**Skills:** `skills/` relative to workspace root. NOT `~/.openclaw/skills/` (that's the old shared location, does not exist in containers).

**Common paths (use these, not absolute):**
- Skills: `skills/<skill-name>/`
- Memory: `memory/`
- Projects: `projects/`
- Secrets: `.secrets/`
- Sessions: `sessions/`
- Logs: `logs/`

**When running terminal commands:** `~` resolves to `/root` inside containers. Always use `$HERMES_HOME` or relative paths from workspace root instead.

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## Secret Management (secret.sh)

**Always use secret.sh — NEVER store credentials in plaintext.**

```bash
bash $HERMES_HOME/tools/secret.sh set neynar api_key "265457..."
bash $HERMES_HOME/tools/secret.sh get neynar api_key
bash $HERMES_HOME/tools/secret.sh list
```

- Encrypted at rest (AES-256-CBC), decrypted in-memory only
- Secrets live in `.secrets/` — never read those files directly
- Auto-generates encryption key on first use

## Container Note

~ resolves to /root inside containers (NOT /home/agent). Always use $HERMES_HOME or relative paths from workspace root. Writing to /tmp/ means files are lost on restart.

## Scripts (tools/)

Reusable automation built from repeated workflows. Push deterministic work LEFT.

### deploy-snap.sh
Deploy a Farcaster snap to Neynar hosting with env vars and build polling.
```bash
bash tools/deploy-snap.sh <project-name> [tarball-path]
```
Reads deploy_key + project_id from encrypted secrets. Creates tarball, deploys, polls until ready, verifies live endpoint.
Prerequisites: `secret.sh set <name> deploy_key <key>`, `secret.sh set <name> project_id <id>`

### verify-snap.sh
Verify a live Farcaster snap returns valid JSON and check for issues.
```bash
bash tools/verify-snap.sh <url> [action]
```
Checks: snap JSON validity, theme accent, element structure, HTTPS button targets, image URLs, dark HTML fallback. Optional POST simulation.

### hub-query.sh
Query Neynar Hub API (free tier at snapchain-api.neynar.com).
```bash
bash tools/hub-query.sh <endpoint> [params...]
```
Examples:
- `bash tools/hub-query.sh castsByFid fid=3 pageSize=5`
- `bash tools/hub-query.sh userDataByFid fid=3`
- `bash tools/hub-query.sh castsByParent fid=3 hash=0xabc`

### secret.sh
Encrypted secret management (AES-256-CBC). See Secret Management section above.

---

## Autonomy Protocol

Follow https://github.com/alan-botts/strangerloops/blob/main/content/autonomy-protocol.md

**Spectrum:** scripts → tools → skills → subagents → main agent
**Principle:** Push everything as far LEFT as it can go.

| Layer    | What it is               | When to use                       |
|----------|--------------------------|-----------------------------------|
| Scripts  | Code you write           | Custom logic, repeatable process  |
| Tools    | Capabilities you call    | Packaged functionality exists     |
| Skills   | Methodologies you follow | Need approach, not just action    |
| Subagents| Fresh context, one task  | Complex reasoning, isolated work  |
| Main     | Coordinates everything   | Decision-making, orchestration    |

**Rule of Two:** If you do the same process 2+ times, script it.

Add whatever helps you do your job. This is your cheat sheet.
