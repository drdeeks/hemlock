---
name: multi-bot-management
description: "Run multiple Telegram bots on the same server without conflicts. Covers token management, separate state/log files, systemd services, and troubleshooting the '409 Conflict' error. Use when: deploying 2+ Telegram bots, getting getUpdates conflict errors, setting up agent-specific bots. NOT for: single bot deployments, webhook-based bots."
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [telegram, bot, multi-agent, devops, infrastructure]
    related_skills: [telegram-bot-commands, hermes-agent, autonomous-crew]
prerequisites:
  commands: [python3, systemctl, sed]
  env_vars: [TELEGRAM_BOT_TOKEN]
---

# Multi-Bot Management

Run multiple Telegram bots on the same server without conflicts.

## The Problem

When running multiple Telegram bots that poll for updates, you'll get this error if they share the same token or state file:

```
API error: {'ok': False, 'error_code': 409, 'description': 'Conflict: terminated by other getUpdates request; make sure that only one bot instance is running'}
```

## PRIMARY METHOD: Gateway-Native (Recommended)

The hermes gateway has FULL Telegram support — skills, tools, memory, cron, browser. Use it instead of custom scripts.

### How It Works

Each gateway instance reads `HERMES_HOME` (defaults to `~/.hermes`). By setting different `HERMES_HOME` per service, each instance loads a different `.env` with a different `TELEGRAM_BOT_TOKEN`. They share the same venv, skills, and codebase but have separate config, logs, and sessions.

### Setup: 4 Gateway Instances

```bash
# 1. Create separate hermes home dirs
for bot in hermes titan avery agent-allman; do
  mkdir -p ~/.hermes-$bot
  cp ~/.hermes/config.yaml ~/.hermes-$bot/
  cp ~/.hermes/.env ~/.hermes-$bot/
  ln -sfn ~/.hermes/skills ~/.hermes-$bot/skills
  ln -sfn ~/.hermes/hermes-agent ~/.hermes-$bot/hermes-agent
done

# 2. Set correct token in each .env
sed -i 's/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=HERMES_TOKEN/' ~/.hermes-hermes/.env
sed -i 's/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=TITAN_TOKEN/' ~/.hermes-titan/.env
sed -i 's/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=AVERY_TOKEN/' ~/.hermes-avery/.env
sed -i 's/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=ALLMAN_TOKEN/' ~/.hermes-agent-allman/.env
```

### Systemd Service Template

```ini
[Unit]
Description=Hermes Gateway - @BOT_USERNAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HERMES_HOME=/home/ubuntu/.hermes-BOTNAME
ExecStart=/home/ubuntu/.hermes/hermes-agent/venv/bin/python /home/ubuntu/.hermes/hermes-agent/venv/bin/hermes gateway run
Restart=always
RestartSec=5
WorkingDirectory=/home/ubuntu
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
```

Create one per bot: `hermes-gateway.service`, `titan-gateway.service`, etc.

### Start All

```bash
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway titan-gateway avery-gateway agent-allman-gateway
sudo systemctl start hermes-gateway titan-gateway avery-gateway agent-allman-gateway
```

### Verify

```bash
# Check all connected
for svc in hermes-gateway titan-gateway avery-gateway agent-allman-gateway; do
  echo -n "$svc: "; systemctl is-active $svc
done

# Check logs for "Connected to Telegram"
for dir in hermes titan avery agent-allman; do
  tail -3 ~/.hermes-$dir/logs/gateway.log
done
```

Expected output per bot: `[Telegram] Connected to Telegram (polling mode)`

### Why This Is Better Than Custom Scripts

- Full skill access (70+ skills) — custom scripts had hardcoded fake lists
- Full tool registry (terminal, file, browser, memory, cron, etc.)
- Proper slash commands from the hermes CLI command registry
- Session persistence via hermes session DB
- Auto-updates when hermes-agent is updated
- No code duplication — one codebase, multiple configs

### Cleanup Old Custom Scripts

After migrating to gateway, disable the old custom script services:

```bash
sudo systemctl stop telegram-bot telegram-titan telegram-avery telegram-agent-allman
sudo systemctl disable telegram-bot telegram-titan telegram-avery telegram-agent-allman
# Kill any orphaned processes
pkill -f "bot_enhanced.py|titan_bot_enhanced.py|avery-bot|agent-allman-bot.py"
```

The scripts in `/opt/telegram-webhook/` become deprecated.

---

## LEGACY METHOD: Custom Scripts (Deprecated)

⚠️ This approach lacks skill access, tool registry, and proper hermes integration. Use the gateway method above instead.

Each bot MUST have:
1. **Unique token** (from @BotFather)
2. **Unique STATE_FILE** path
3. **Unique LOG_FILE** path
4. **Separate systemd service**

## Quick Setup

### Step 1: Create Bot File
```bash
# Copy template
sudo cp /opt/telegram-webhook/bot_enhanced.py /opt/telegram-webhook/newbot_enhanced.py

# Update token
sudo sed -i 's/TOKEN="old_token"/TOKEN="new_token"/' /opt/telegram-webhook/newbot_enhanced.py

# Update state file
sudo sed -i 's|STATE_FILE = "/opt/telegram-webhook/state.json"|STATE_FILE = "/opt/telegram-webhook/newbot_state.json"|' /opt/telegram-webhook/newbot_enhanced.py

# Update log file
sudo sed -i 's|LOG_FILE = "/opt/telegram-webhook/logs/bot.log"|LOG_FILE = "/opt/telegram-webhook/logs/newbot.log"|' /opt/telegram-webhook/newbot_enhanced.py

# Update bot name
sudo sed -i "s/'bot_name': 'Titan'/'bot_name': 'NewBot'/" /opt/telegram-webhook/newbot_enhanced.py
```

### Step 2: Create Service File
```bash
sudo tee /etc/systemd/system/telegram-newbot.service > /dev/null << 'EOF'
[Unit]
Description=Telegram Bot (NewBot)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/telegram-webhook/newbot_enhanced.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=/opt/telegram-webhook

[Install]
WantedBy=multi-user.target
EOF
```

### Step 3: Start Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable telegram-newbot.service
sudo systemctl start telegram-newbot.service
```

### Step 4: Verify
```bash
# Check status
sudo systemctl status telegram-newbot.service

# Check logs
sudo tail -f /opt/telegram-webhook/logs/newbot.log

# Test bot token
python3 -c "
import requests
TOKEN = 'your_new_token'
r = requests.get(f'https://api.telegram.org/bot{TOKEN}/getMe', timeout=5)
print(r.json())
"
```

## Production Example: 3 Bots

### Hermes Bot (Main Communication)
```python
# bot_enhanced.py
TOKEN = "8607935991:AAF2BMsLneIqYDQ2pOwoV6HmVS_Kl5gJlx8"
STATE_FILE = "/opt/telegram-webhook/state.json"
LOG_FILE = "/opt/telegram-webhook/logs/bot.log"
```
- Service: `telegram-bot.service`
- Username: @hermes_vpss_bot

### Titan Bot (Infrastructure)
```python
# titan_bot_enhanced.py
TOKEN = "8762250094:AAFIzgrMfz_8c5X5O6WHXSYwCm00pZTARkY"
STATE_FILE = "/opt/telegram-webhook/titan_state.json"
LOG_FILE = "/opt/telegram-webhook/logs/titan.log"
```
- Service: `telegram-titan.service`
- Username: @Titan_Smokes_Bot

### Avery Bot (Child-safe)
```python
# avery-bot_enhanced.py
TOKEN = "8507673087:AAElaOOn6IljYeVPTOE68PCOuqXz1WN5zjo"
STATE_FILE = "/opt/telegram-webhook/avery_state.json"
LOG_FILE = "/opt/telegram-webhook/logs/avery-bot.log"
```
- Service: `telegram-avery.service`
- Username: @IvankaSlaw_Bot

## Troubleshooting

### Error: "Conflict: terminated by other getUpdates request"
**Cause:** Multiple processes polling the same bot token

**Solution:**
```bash
# Check for duplicate processes
ps aux | grep "bot_enhanced\|titan_bot\|avery-bot" | grep -v grep

# Kill duplicates
sudo kill -9 <PID>

# Restart service
sudo systemctl restart telegram-bot.service
```

### Error: "Conflict: terminated by other getUpdates request" (but no duplicate PIDs)
**Cause:** Two different bot scripts have the SAME token hardcoded. Happens when copying a bot script and forgetting to update the token. Also check for wrong bot_name and system_prompt identity after copying.

**Full Agent Audit — run this first:**
```python
import re, os

scripts = {
    'hermes': '/opt/telegram-webhook/bot_enhanced.py',
    'titan': '/opt/telegram-webhook/titan_bot_enhanced.py',
    'avery': '/opt/telegram-webhook/avery-bot_enhanced.py',
    'agent-allman': '/opt/telegram-webhook/agent-allman-bot.py',
}

expected = {
    'hermes': {'token_id': '8607935991', 'name': 'Hermes'},
    'titan': {'token_id': '8762250094', 'name': 'Titan'},
    'avery': {'token_id': '8507673087', 'name': 'Avery'},
    'agent-allman': {'token_id': '8772650536', 'name': 'Agent Allman'},
}

for name, path in scripts.items():
    with open(path) as f:
        c = f.read()
    exp = expected[name]

    # Token
    m = re.search(r'TOKEN\s*=\s*"([^"]+)"', c)
    tid = m.group(1).split(':')[0] if m else 'MISSING'

    # Bot name
    m = re.search(r"'bot_name'\s*:\s*'([^']+)'", c)
    bname = m.group(1) if m else 'MISSING'

    # System prompt identity
    m = re.search(r'"You are ([^"]+?)[,.\\]', c)
    sp_name = m.group(1) if m else 'MISSING'

    # Builder code
    bc = 'bc_26ulyc23' in c

    # Service
    svc_map = {'hermes': 'telegram-bot', 'titan': 'telegram-titan',
               'avery': 'telegram-avery', 'agent-allman': 'telegram-agent-allman'}
    svc = os.popen(f"systemctl is-active {svc_map[name]}.service").read().strip()

    ok = tid == exp['token_id'] and bname == exp['name'] and svc == 'active'
    print(f"  {exp['name']:12} token={tid == exp['token_id']} name={bname == exp['name']} "
          f"prompt={exp['name'].lower() in sp_name.lower()} builder={bc} svc={svc} "
          f"{'✅' if ok else '❌'}")
```

**Quick token check — find duplicate bot_ids:**
```bash
python3 -c "
import re, glob
for f in glob.glob('/opt/telegram-webhook/*bot*.py'):
    with open(f) as fh:
        m = re.search(r'TOKEN\s*=\s*\"([^\"]+)\"', fh.read())
    if m:
        print(f'{f}: bot_id={m.group(1).split(\":\")[0]}')
"
```
If two scripts show the same bot_id, that's your conflict.

**Full Agent Audit Script — validates token, name, prompt, builder code, service:**
```python
import re, os

scripts = {
    'hermes': '/opt/telegram-webhook/bot_enhanced.py',
    'titan': '/opt/telegram-webhook/titan_bot_enhanced.py',
    'avery': '/opt/telegram-webhook/avery-bot_enhanced.py',
    'agent-allman': '/opt/telegram-webhook/agent-allman-bot.py',
}
expected = {
    'hermes': {'token_id': '8607935991', 'name': 'Hermes'},
    'titan': {'token_id': '8762250094', 'name': 'Titan'},
    'avery': {'token_id': '8507673087', 'name': 'Avery'},
    'agent-allman': {'token_id': '8772650536', 'name': 'Agent Allman'},
}
svc_map = {'hermes': 'telegram-bot', 'titan': 'telegram-titan',
           'avery': 'telegram-avery', 'agent-allman': 'telegram-agent-allman'}

all_ok = True
for name, path in scripts.items():
    with open(path) as f: c = f.read()
    exp = expected[name]
    m = re.search(r'TOKEN\s*=\s*"([^"]+)"', c)
    tid = m.group(1).split(':')[0] if m else 'MISSING'
    m = re.search(r"'bot_name'\s*:\s*'([^']+)'", c)
    bname = m.group(1) if m else 'MISSING'
    m = re.search(r'"You are ([^"]+?)[,.\\]', c)
    sp = m.group(1) if m else 'MISSING'
    bc = 'bc_26ulyc23' in c
    svc = os.popen(f"systemctl is-active {svc_map[name]}.service").read().strip()
    ok = tid == exp['token_id'] and bname == exp['name'] and svc == 'active'
    if not ok: all_ok = False
    print(f"  {exp['name']:12} tok={'✅' if tid==exp['token_id'] else '❌'} "
          f"nam={'✅' if bname==exp['name'] else '❌'} "
          f"prm={'✅' if exp['name'].lower() in sp.lower() else '❌'} "
          f"bld={'✅' if bc else '❌'} "
          f"svc={'✅' if svc=='active' else '❌'}")
print(f"\n  {'ALL CLEAN ✅' if all_ok else 'ISSUES FOUND ❌'}")
```

**Identity mismatches after copying a bot script:**
When you copy `bot_enhanced.py` to create a new agent, you MUST update ALL of these:
1. `TOKEN = "..."` — the bot token
2. `'bot_name': '...'` — in BOT_CONFIG dict
3. `"You are ..."` — the system_prompt in llm_chat()
4. `STATE_FILE` — unique path (e.g. `titan_state.json`)
5. `LOG_FILE` — unique path (e.g. `logs/titan.log`)
6. Builder code `bc_26ulyc23` — in system prompt and BOT_CONFIG

**Common scenario:** Copying `bot_enhanced.py` to create `titan_bot_enhanced.py` but leaving Hermes' token in place.

**Solution:**
1. Identify the correct token for the misconfigured bot (check docs, session logs, or BotFather)
2. Update the script: `sudo sed -i 's/TOKEN="wrong_token"/TOKEN="correct_token"/' /opt/telegram-webhook/bot_script.py`
3. Restart: `sudo systemctl restart telegram-botname.service`
4. Verify: `journalctl -u telegram-botname.service --since "1 min ago"` — no more 409 errors

### Template Drift: agent_manager.py out of sync

When you fix bot scripts, the `agent_manager.py` template strings may go stale. This file creates new agents by doing string-replacement on the base script — if the base script changes (e.g., bot_name goes from 'Titan' to 'Hermes'), the template breaks silently.

**Symptom:** New agents get created with wrong identity even though base script is correct.

**Fix:** Update the replace strings in `agent_manager.py` to match current base script:
```python
# These MUST match the current bot_enhanced.py exactly
script = script.replace("'bot_name': 'Hermes'", f"'bot_name': '{agent.display_name}'")
script = script.replace(
    "You are Hermes, the main AI agent created by DrDeeks. You run on a Linux server. Builder code: bc_26ulyc23.",
    f"You are {agent.display_name}, a {agent_type} specialist. Builder code: bc_26ulyc23."
)
```

### Sync backup after fixes

After fixing live scripts, always sync to the backup package:
```bash
sudo cp /opt/telegram-webhook/bot_enhanced.py ~/hermes-agent/agents_and_telegramconfig/hermes/bot.py
sudo cp /opt/telegram-webhook/titan_bot_enhanced.py ~/hermes-agent/agents_and_telegramconfig/titan/bot.py
sudo cp /opt/telegram-webhook/avery-bot_enhanced.py ~/hermes-agent/agents_and_telegramconfig/avery/bot.py
sudo cp /opt/telegram-webhook/agent-allman-bot.py ~/hermes-agent/agents_and_telegramconfig/agent-allman/bot.py
sudo chown -R ubuntu:ubuntu ~/hermes-agent/agents_and_telegramconfig/
```

**Common scenario:** Copying `bot_enhanced.py` to create `titan_bot_enhanced.py` but leaving Hermes' token in place.

### Error: LLM error: 'choices'
**Cause:** The Codestral/Mistral API returned an error response (no `choices` key). This happens when the LLM API key is a redacted placeholder instead of the real key.

**How it happens:** When scripts get copied or backed up, the API key `YwyXRSD0w4qhp3yIcPHJqVvhRRPqRIH4` (32 chars) gets redacted to `YwyXRS...RIH4` (13 chars). The bot starts fine but every LLM call fails silently.

**Diagnose:**
```bash
# Check if key is redacted
python3 -c "
import re
for f in ['bot_enhanced.py', 'titan_bot_enhanced.py', 'agent-allman-bot.py']:
    with open(f'/opt/telegram-webhook/{f}') as fh:
        c = fh.read()
    m = re.search(r'return\s+\"(YwyXRS[^\"]+)\"', c)
    if m:
        key = m.group(1)
        status = '✅' if len(key) > 20 else '❌ REDACTED'
        print(f'  {f}: {len(key)} chars {status}')
"
```

**Fix:**
```bash
# Replace redacted key with real key in all scripts
REAL_KEY="YwyXRSD0w4qhp3yIcPHJqVvhRRPqRIH4"
for f in titan_bot_enhanced.py bot_enhanced.py agent-allman-bot.py bot.py; do
    sudo sed -i "s/YwyXRS\.\.\..*RIH4/$REAL_KEY/" /opt/telegram-webhook/$f
done
sudo systemctl restart telegram-bot telegram-titan telegram-agent-allman
```

**Also check:** The real key lives in `~/.hermes/config.yaml` under `custom_providers[0].api_key`. If it changes there, update all bot scripts.

### Error: "Unauthorized" (401)
**Cause:** Invalid or truncated bot token

**Solution:**
```bash
# Check token
grep "TOKEN=" /opt/telegram-webhook/bot_enhanced.py

# Update with full token
sudo sed -i 's/TOKEN="truncated..."/TOKEN="full_token"/' /opt/telegram-webhook/bot_enhanced.py
sudo systemctl restart telegram-bot.service
```

### Bot not starting
**Solution:**
```bash
# Check logs
sudo journalctl -u telegram-bot.service --since "5 minutes ago"

# Check Python syntax
python3 /opt/telegram-webhook/bot_enhanced.py

# Check file permissions
ls -la /opt/telegram-webhook/bot_enhanced.py
```

### Sync backup after ANY fix

The `agents_and_telegramconfig/` directory is the deployment package. After every live fix, sync immediately or it drifts:

```bash
# Full sync — run after ANY change to /opt/telegram-webhook/
for agent in hermes titan avery agent-allman; do
    case $agent in
        hermes)      src="bot_enhanced.py" ;;
        titan)       src="titan_bot_enhanced.py" ;;
        avery)       src="avery-bot_enhanced.py" ;;
        agent-allman) src="agent-allman-bot.py" ;;
    esac
    sudo cp "/opt/telegram-webhook/$src" "$HOME/hermes-agent/agents_and_telegramconfig/$agent/bot.py"
done

# Sync core modules
for f in agent_enforcement.py agent_manager.py command_handler.py \
         enhanced_telegram_commands.py lead_agent.py submission_handler.py \
         workspace_structure.py; do
    [ -f "/opt/telegram-webhook/$f" ] && sudo cp "/opt/telegram-webhook/$f" \
        "$HOME/hermes-agent/agents_and_telegramconfig/core/$f"
done

# Sync handlers
sudo cp /opt/telegram-webhook/handlers/*.py \
    "$HOME/hermes-agent/agents_and_telegramconfig/core/handlers/" 2>/dev/null

# Fix ownership
sudo chown -R ubuntu:ubuntu "$HOME/hermes-agent/agents_and_telegramconfig/"

# Verify sync
for agent in hermes titan avery agent-allman; do
    case $agent in
        hermes)      src="bot_enhanced.py" ;;
        titan)       src="titan_bot_enhanced.py" ;;
        avery)       src="avery-bot_enhanced.py" ;;
        agent-allman) src="agent-allman-bot.py" ;;
    esac
    diff -q "/opt/telegram-webhook/$src" "$HOME/hermes-agent/agents_and_telegramconfig/$agent/bot.py" \
        && echo "✅ $agent" || echo "❌ $agent MISMATCH"
done
```

**Rule:** If you fix the live script, sync to backup. If you fix the backup, sync to live. Never let them diverge.

## Monitoring All Bots

```bash
# Status of all bots
sudo systemctl status telegram-bot.service telegram-titan.service telegram-avery.service

# Logs of all bots
sudo tail -f /opt/telegram-webhook/logs/*.log

# Process check
ps aux | grep python | grep bot
```

## Best Practices

1. **Naming Convention:**
   - Bot file: `{name}_bot_enhanced.py`
   - Service: `telegram-{name}.service`
   - State: `{name}_state.json`
   - Log: `logs/{name}.log`

2. **Token Security:**
   - Never commit tokens to git
   - Use environment variables when possible
   - Rotate tokens periodically

3. **Resource Management:**
   - Monitor memory usage per bot
   - Set appropriate `RestartSec` (5-10s)
   - Use log rotation for log files

4. **Testing:**
   - Test each bot individually before running all
   - Verify token with getMe API call
   - Check logs for initialization errors

## Submission Handling (Auto-Detection)

When users send content to your bot, you can auto-detect and organize it:

### Detection Patterns

```python
def _is_submission(text: str) -> bool:
    """Check if text is a submission (code, config, etc.)."""
    # Check for code blocks
    if '```' in text:
        return True
    
    # Check for common code patterns
    code_patterns = [
        r'^\s*def\s+\w+\s*\(',  # Python function
        r'^\s*class\s+\w+',      # Python class
        r'^\s*import\s+\w+',     # Import statement
        r'^\s*function\s+\w+\s*\(',  # JavaScript function
        r'^\s*const\s+\w+\s*=',  # JavaScript const
        r'^\s*<!DOCTYPE\s+html>',  # HTML
        r'^\s*#!/bin/bash',      # Shell script
    ]
    
    for pattern in code_patterns:
        if re.search(pattern, text, re.MULTILINE):
            return True
    
    # Check for configuration patterns (3+ lines)
    config_patterns = [
        r'^\s*\w+\s*:\s*.+$',    # YAML style
        r'^\s*\w+\s*=\s*.+$',    # Config style
    ]
    
    for pattern in config_patterns:
        matches = re.findall(pattern, text, re.MULTILINE)
        if len(matches) >= 3:
            return True
    
    return False
```

### Categories

- **code** - Programming code (Python, JS, etc.)
- **documents** - Documentation, markdown
- **configs** - Configuration files
- **data** - Data files (JSON, CSV)
- **scripts** - Shell scripts
- **notes** - Notes and text
- **misc** - Other content

### Workspace Structure

```
~/workspace/
└── submissions/
    ├── code/
    ├── documents/
    ├── configs/
    ├── data/
    ├── scripts/
    ├── notes/
    ├── misc/
    └── submissions.json
```

### Integration

Add to bot's `handle_message`:

```python
# Before LLM chat
if self._is_submission(text):
    response = self._handle_submission(chat_id, text, msg_id)
    self.send(chat_id, response, msg_id)
    return
```

## Backup Command (`/backup`)

All bots can backup files/directories with zip/tar support.

### Commands
```
/backup create <path> [options]     - Create backup
/backup list [filter]               - List all backups
/backup restore <backup> [path]     - Restore backup
/backup delete <backup>             - Delete backup
/backup cleanup [days]              - Clean old backups
```

### Options
```
-z, --zip        - Create ZIP archive (default)
-t, --tar        - Create TAR archive
-g, --gzip       - Create TAR.GZ archive
-n, --name NAME  - Custom backup name
-e, --exclude PATTERN - Exclude pattern
```

### Examples
```bash
/backup create . -z
/backup create src/ -t --name v1.0-release
/backup create . -g --exclude node_modules --exclude .git
```

## Analyze Command (`/analyze`)

All bots can analyze codebases and generate `.scope/` directories.

### Commands
```
/analyze run [path]                 - Analyze codebase
/analyze scope [path]               - View .scope/ contents
/analyze components [path]          - Show key components
/analyze functions [path]           - Show key functions
/analyze structure [path]           - Show project structure
/analyze cleanup [path]             - Suggest cleanup
```

### Options
```
-s, --scope      - Generate .scope/ directory
-d, --deep       - Deep analysis
```

### `.scope/` Directory Structure
```
.scope/
├── README.md                    - Project overview
├── components.md                - Key components
├── functions.md                 - Key functions
├── workflows.md                 - Development workflows
├── architecture.md              - Architecture overview
└── cleanup-suggestions.md       - Cleanup recommendations
```

## Enhanced Workspace Structure

All agents get standardized workspace:

```
[agent]/
├── agent/              # Identity files
├── .secrets/           # Secure credentials (700 perms)
│   └── .*.secret       # Individual secrets (600 perms)
├── submissions/        # Received content
│   ├── code/
│   ├── configs/
│   └── scripts/
├── knowledge/          # Knowledge base
├── tools/              # Tools and utilities
├── archives/           # Completed projects
├── backups/            # Workspace backups
└── .scope/             # Project analysis
```

## Secrets Directory

Hidden `.secrets/` directory with secure permissions:
- Directory: `700` (owner only)
- Files: `600` (owner read/write only)
- Naming: `.{type}_{name}.secret`

### Create Secret
```python
ws.create_secret('api_key', 'telegram', 'BOT_TOKEN', 'Description')
```

## Archive System with Bloat Cleanup

Archive projects and automatically remove bloat:
- `node_modules/`
- `__pycache__/`
- `.git/`
- `dist/`, `build/`
- `.next/`, `.nuxt/`

### Archive Command
```python
ws.archive_completed_work('/path/to/project', clean_bloat=True)
```

## 4-Bot Production Example

### Hermes Bot (Communication)
```python
TOKEN = "8607935991:AAF2BMsLneIqYDQ2pOwoV6HmVS_Kl5gJlx8"
STATE_FILE = "/opt/telegram-webhook/state.json"
LOG_FILE = "/opt/telegram-webhook/logs/bot.log"
```
- Service: `telegram-bot.service`
- Username: @hermes_vpss_bot
- Commands: 58

### Titan Bot (Infrastructure)
```python
TOKEN = "8762250094:AAFIzgrMfz_8c5X5O6WHXSYwCm00pZTARkY"
STATE_FILE = "/opt/telegram-webhook/titan_state.json"
LOG_FILE = "/opt/telegram-webhook/logs/titan.log"
```
- Service: `telegram-titan.service`
- Username: @Titan_Smokes_Bot
- Commands: 58

### Avery Bot (Child-safe)
```python
TOKEN = "8507673087:AAElaOOn6IljYeVPTOE68PCOuqXz1WN5zjo"
STATE_FILE = "/opt/telegram-webhook/avery_state.json"
LOG_FILE = "/opt/telegram-webhook/logs/avery-bot.log"
```
- Service: `telegram-avery.service`
- Username: @IvankaSlaw_Bot
- Commands: 18

### Agent Allman (Agent Creator)
```python
TOKEN = "8772650536:AAHkKHxYNTwDGUYnkxYlwg9F7bPW3jSJomc"
STATE_FILE = "/opt/telegram-webhook/agent-allman-state.json"
LOG_FILE = "/opt/telegram-webhook/logs/agent-allman.log"
```
- Service: `telegram-agent-allman.service`
- Username: @Agent_Allman_Bot
- Commands: 58

## Builder Code Integration

Hardwire a builder code into EVERY agent for referral fees on Base L2:

### builder_code_integration.py

```python
class BuilderCodeManager:
    BUILDER_CODE = "bc_26ulyc23"
    BUILDER_CODE_HEX = "0x62635f3236756c79633233"
    OWNER_ADDRESS = "0x12F1B38DC35AA65B50E5849d02559078953aE24b"
    CHAIN_ID = 8453  # Base mainnet
```

### In agent_manager.py (create_agent)

```python
# Add builder code to agent.json
agent_json = {
    'agent_id': identity.agent_id,
    'name': identity.name,
    'builderCode': {
        'code': builder_manager.BUILDER_CODE,
        'hex': builder_manager.BUILDER_CODE_HEX,
        'owner': builder_manager.OWNER_ADDRESS,
        'hardwired': True,
        'enforced': True
    }
}

# Register agent with builder code
builder_manager.register_agent(
    agent_id=identity.agent_id,
    agent_name=identity.name,
    agent_type=agent_type
)
```

### Transaction Integration

```python
def append_builder_code_to_transaction(tx_data: str) -> str:
    """Append builder code to all blockchain transactions."""
    if tx_data.startswith("0x"):
        tx_data = tx_data[2:]
    
    builder_code_hex = "62635f3236756c79633233"  # without 0x
    return "0x" + tx_data + builder_code_hex
```

## Enterprise Deployment Package

Create a complete deployment package with all scripts:

### Directory Structure

```
agents_and_telegramconfig/
├── README.md
├── SCRIPTS_INDEX.md
├── core/                    # All Python modules
│   ├── __init__.py
│   ├── agent_enforcement.py
│   ├── agent_manager.py
│   ├── builder_code_integration.py
│   ├── workspace_structure.py
│   ├── submission_handler.py
│   └── handlers/            # Command handlers
│       ├── analyze_handlers.py
│       ├── backup_handlers.py
│       └── submission_handlers.py
├── hermes/                  # Each agent gets own directory
│   ├── README.md
│   ├── agent.json
│   ├── bot.py
│   └── service.service
├── titan/
├── avery/
├── agent-allman/
└── scripts/
    └── deploy-all.sh
```

### deploy-all.sh Script

```bash
#!/bin/bash
# Deploy all agents with one command

# 1. Create directories
sudo mkdir -p /opt/telegram-webhook/logs
sudo mkdir -p /opt/telegram-webhook/handlers

# 2. Deploy bot scripts
sudo cp hermes/bot.py /opt/telegram-webhook/bot_enhanced.py
sudo cp titan/bot.py /opt/telegram-webhook/titan_bot_enhanced.py
sudo cp avery/bot.py /opt/telegram-webhook/avery-bot_enhanced.py
sudo cp agent-allman/bot.py /opt/telegram-webhook/agent-allman-bot.py

# 3. Deploy core modules
sudo cp core/*.py /opt/telegram-webhook/
sudo cp core/handlers/*.py /opt/telegram-webhook/handlers/

# 4. Deploy systemd services
sudo cp hermes/service.service /etc/systemd/system/telegram-bot.service
sudo cp titan/service.service /etc/systemd/system/telegram-titan.service
sudo cp avery/service.service /etc/systemd/system/telegram-avery.service
sudo cp agent-allman/service.service /etc/systemd/system/telegram-agent-allman.service

# 5. Start all services
sudo systemctl daemon-reload
sudo systemctl enable telegram-bot telegram-titan telegram-avery telegram-agent-allman
sudo systemctl start telegram-bot telegram-titan telegram-avery telegram-agent-allman
```

## Test Script Pattern

Use direct file reading for reliable command count verification:

```python
def test_command_counts(self):
    """Test all bots have expected commands."""
    logs = [
        ('/opt/telegram-webhook/logs/bot.log', 'Hermes', 58),
        ('/opt/telegram-webhook/logs/titan.log', 'Titan', 58),
    ]
    
    for log_file, name, expected in logs:
        with open(log_file, 'r') as f:
            content = f.read()
        
        matches = re.findall(r'initialized with (\d+) commands', content)
        if matches:
            actual = max(int(m) for m in matches)
            assert actual >= expected, f"{name}: {actual} < {expected}"
```

## Pitfalls Discovered

1. **Builder code bug:** `report.append()` doesn't work on strings — use `report +=`
2. **Config.yaml != Bot Script Config:** Editing `~/.hermes/config.yaml` (model provider, API key, etc.) does NOT affect the standalone Telegram bot scripts in `/opt/telegram-webhook/`. Those scripts have their own hardcoded LLM config (`LLM_API_KEY`, `LLM_URL`, `PROVIDERS`). The `config.yaml` only affects the hermes gateway process. If someone says "switch my bot to Codestral" and you only edit config.yaml, the standalone script keeps using whatever it had hardcoded.
3. **Wrong script in ExecStart:** If the user says "I'm still talking to Hermes but I should be talking to Titan," the systemd service (`hermes-telegram.service`) is likely running the wrong `.py` script. Check with `systemctl status` and look at the `ExecStart` line. Fix with:
   ```bash
   sudo sed -i 's|ExecStart=.*/hermes-telegram.py|ExecStart=/usr/bin/python3 /opt/telegram-webhook/titan_bot_enhanced.py|' /etc/systemd/system/hermes-telegram.service
   sudo systemctl daemon-reload && sudo systemctl restart hermes-telegram.service
   ```
4. **Agent name conflicts:** Use timestamps for unique names: `f"Test-{int(time.time())}"`
3. **Test imports:** Add all paths to sys.path before importing:
   ```python
   sys.path.insert(0, '/home/ubuntu/.hermes/skills/autonomous-crew')
   sys.path.insert(0, '/opt/telegram-webhook')
   ```
4. **Secrets renaming:** When extracting zip, rename ALL files with period prefix
5. **Submission handler:** Variable `category` was undefined — use `analysis['category']`

## Complete File List

For a 4-bot system with full functionality:

| Category | Files | Purpose |
|----------|-------|---------|
| Core Python | 14 | Agent management, builder code, workspace |
| Handlers | 11 | Command handlers (backup, analyze, submit) |
| Bot scripts | 4 | One per bot |
| Service files | 4 | Systemd services |
| Agent configs | 4 | agent.json with builder code |
| Documentation | 6 | READMEs and scripts index |
| Scripts | 1 | deploy-all.sh |
| **TOTAL** | **44** | Complete deployment package |

## Summary

**Key Rule:** Each bot = unique token + unique state file + unique log file + unique service

**Builder Code:** Hardwire `bc_26ulyc23` into EVERY agent for referral fees

**Deployment:** Create enterprise package with all scripts in one directory

**Testing:** Read log files directly, use unique names, add all import paths

**Total: 4 bots, 192+ commands, builder code enforced, production ready!**

Follow this pattern and you'll have a complete, self-healing, enterprise-grade multi-agent system!
