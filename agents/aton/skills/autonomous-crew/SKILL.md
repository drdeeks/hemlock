---
name: autonomous-crew
description: "Enterprise-grade multi-agent system with 4 Telegram bots (192+ commands), builder code enforcement, standardized workspaces, backup/analyze commands, secrets management, and Agent Allman for ERC-8004 onchain identity creation. Includes complete deployment package with 44 files."
version: 3.0.0
metadata:
  hermes:
    tags: [crew, autonomous, multi-agent, workflow, telegram, agent-management, builder-code, erc-8004, backup, analyze]
    related_skills: [coding-agent, subagent-driven-development, plan, telegram-admin-portal, builder-code]
    category: autonomous-ai-agents
    complexity: advanced
    requires:
      - git
      - python3
      - psutil
      - requests
      - systemd
      - telegram_bot_token (for each agent)
---

# Enterprise Multi-Agent System

## Overview

Production-ready multi-agent system with 4 Telegram bots, 192+ commands, builder code enforcement, and complete deployment package.

## System Components

### 4 Telegram Bots

| Bot | Username | Commands | Purpose |
|-----|----------|----------|---------|
| Hermes | @hermes_vpss_bot | 58 | Communication agent |
| Titan | @Titan_Smokes_Bot | 58 | Infrastructure agent |
| Avery | @IvankaSlaw_Bot | 18 | Child-safe agent |
| Agent Allman | @Agent_Allman_Bot | 58 | Agent creator (ERC-8004) |

### Builder Code (Hardwired)

Every agent includes builder code `bc_26ulyc23`:
```json
{
  "builderCode": {
    "code": "bc_26ulyc23",
    "hex": "0x62635f3236756c79633233",
    "owner": "0x12F1B38DC35AA65B50E5849d02559078953aE24b",
    "hardwired": true,
    "enforced": true
  }
}
```

## Workspace Structure (30+ directories)

Every agent gets standardized workspace:
```
[agent-workspace]/
├── agent/                      # Identity files (SOUL.md, etc.)
├── .secrets/                   # Hidden, 700 perms, individual credentials
├── submissions/                # Auto-categorized content
│   ├── code/                   # Programming code
│   ├── configs/                # Configuration files
│   ├── documents/              # Documentation
│   └── scripts/                # Shell scripts
├── knowledge/                  # Knowledge base
├── tools/                      # Tools and utilities
├── archives/                   # Completed projects (bloat cleaned)
├── backups/                    # Workspace backups
├── memory/                     # Session memory
├── projects/                   # Active projects
└── .scope/                     # Analysis results (auto-generated)
```

## Key Commands

### Agent Management
```
/agent list [type]          - List all agents
/agent create <type> [name] - Create agent with unique identity
/agent setup <id> [token]   - Configure Telegram bot
/agent issues               - Detect configuration problems
```

### Backup System
```
/backup create <path> -z    - Create ZIP backup
/backup create <path> -t    - Create TAR backup
/backup create <path> -g    - Create TAR.GZ backup
/backup list                - List all backups
/backup restore <name>      - Restore backup
```

### Analyze System
```
/analyze run . --scope      - Analyze and generate .scope/
/analyze components .       - Show key components
/analyze functions .        - Show key functions
/analyze cleanup .          - Suggest cleanup
```

### Submission System
```
/submit list [category]     - List submissions
/submit view <id>           - View submission
```

## Bug Fixes Applied

### submission_handler.py
```python
# FIXED: category variable not defined
# Line 164: Changed 'category': category to 'category': analysis['category']
# Line 176: Changed {category} to {analysis["category"]}
```

### Test Command Counts
```python
# FIXED: Read log files directly instead of subprocess
with open(log_file, 'r') as f:
    content = f.read()
matches = re.findall(r'initialized with (\d+) commands', content)
actual = max(int(m) for m in matches) if matches else 0
```

## Core Python Modules (14 files)

| Module | Purpose |
|--------|---------|
| `workspace_structure.py` | 30+ directories, .secrets/, archives |
| `agent_manager.py` | Agent creation, builder code enforcement |
| `submission_handler.py` | Auto-categorize content |
| `builder_code_integration.py` | bc_26ulyc23 enforcement |
| `agent_enforcement.py` | Self-healing, credential checks |
| `command_handler.py` | Command registration |
| `enhanced_telegram_commands.py` | /agent and /crew commands |
| `lead_agent.py` | Lead agent manager |
| `file_locking.py` | Cross-agent protection |
| `agent_port_manager.py` | Auto-expanding ports |
| `autonomous_crew.py` | Crew workflow engine |
| `changelog_manager.py` | Append-only changelog |

## Deployment

### One-Command Deploy
```bash
cd ~/hermes-agent/enterprise-deployment
bash scripts/deploy-all.sh
```

### Manual Deploy
```bash
# Copy bot files
sudo cp hermes/bot.py /opt/telegram-webhook/bot_enhanced.py
sudo cp titan/bot.py /opt/telegram-webhook/titan_bot_enhanced.py

# Copy core modules
sudo cp core/*.py /opt/telegram-webhook/
sudo cp core/handlers/*.py /opt/telegram-webhook/handlers/

# Start services
sudo systemctl daemon-reload
sudo systemctl start telegram-bot.service
```

## Enterprise Package (44 files)

Location: `~/hermes-agent/enterprise-deployment/`
- 25 Python scripts (~350KB)
- 4 bot implementations
- 4 systemd services
- 6 documentation files
- 1 deployment script

## Agent Allman (ERC-8004)

Creates agents with onchain identities:
1. Section-by-section process (7 sections)
2. ERC-8004 registration
3. NFT minting and transfer
4. Platform listings (AgentScan, Reputation, Scoring)
5. Builder code enforced on every agent

## Key Learnings

1. **Category Bug**: Always define variables before use in submission_handler.py
2. **Command Counts**: Read log files directly, not via subprocess
3. **psutil**: Install via apt (`python3-psutil`) not pip
4. **requests**: Install in venv with pip
5. **Bot Tokens**: Each bot needs separate log and state files
6. **Workspace**: Auto-initialize .secrets/ with 700 permissions
7. **Builder Code**: Must be in agent.json at creation time
8. **Archives**: Clean bloat (node_modules, __pycache__, .git)

## Troubleshooting

### Conflict Errors
```bash
sudo systemctl stop telegram-bot.service
sudo pkill -f bot_enhanced.py
sleep 5
sudo systemctl start telegram-bot.service
```

### Missing psutil
```bash
sudo apt install python3-psutil
# OR in venv:
source ~/venv/bin/activate
pip install psutil requests
```

### Permission Errors
```bash
chmod 700 ~/workspace/.secrets
chmod 600 ~/workspace/.secrets/*.secret
```

## Test Results

100% pass rate (53/53 tests):
- ✅ 4 bots running
- ✅ 58 commands each (except Avery: 18)
- ✅ Workspace structure auto-initializes
- ✅ .secrets/ with 700/600 permissions
- ✅ Backup system (ZIP/TAR/TAR.GZ)
- ✅ Analyze system with .scope/
- ✅ Agent creation with builder code
- ✅ Archive system with bloat cleanup
- ✅ File locking with cross-agent prevention
- ✅ Port manager with auto-expansion

## License

Proprietary — DrDeeks  
Builder Code: `bc_26ulyc23`
