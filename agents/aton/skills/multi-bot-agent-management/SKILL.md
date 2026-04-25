---
name: multi-bot-agent-management
description: "Complete multi-bot agent management system with automatic workspace initialization, builder code hardwiring, submission handling, backup system, analyze system with .scope/ generation, archive management with bloat cleanup, secrets directory, file locking, port management, and changelog system. Use when: setting up multiple Telegram bots for different agents, creating agents with standardized workspaces, ensuring all agents have builder codes, implementing automatic content organization, backing up files with ZIP/TAR support, analyzing codebases, or managing agent credentials. Covers four-bot architecture (Hermes/Titan/Avery/Agent Allman), workspace structure, agent creation, submission handling, backup, analyze, and enforcement systems."
version: 1.0.0
metadata:
  hermes:
    tags: [agents, telegram, multi-bot, workspace, builder-code, submissions, backup, analyze, scope, archive, secrets, file-locking, port-manager, changelog, agent-allman, erc-8004]
    related_skills: [autonomous-crew, builder-code, adding-builder-codes]
    category: autonomous-ai-agents
    complexity: advanced
---

# Multi-Bot Agent Management System

## Overview

Complete system for managing multiple Telegram bots (Hermes, Titan, Avery) with automatic workspace initialization, builder code integration, and content organization.

## Architecture

### Four Separate Bots

1. **Hermes Bot** (@hermes_vpss_bot)
   - Purpose: Communication with user
   - Service: `telegram-bot.service`
   - Commands: 58
   - Token: User's Hermes token

2. **Titan Bot** (@Titan_Smokes_Bot)
   - Purpose: Infrastructure and development
   - Service: `telegram-titan.service`
   - Commands: 58
   - Token: User's Titan token

3. **Avery Bot** (@IvankaSlaw_Bot)
   - Purpose: Child-safe agent for Ava
   - Service: `telegram-avery.service`
   - Commands: 18
   - Token: User's Avery token

4. **Agent Allman Bot** (@Agent_Allman_Bot)
   - Purpose: Agent creation with ERC-8004 onchain identity
   - Service: `telegram-agent-allman.service`
   - Commands: 58
   - Token: User's Agent Allman token
   - Creates agents with builder code hardwired

### Key Components

1. **Agent Manager** (`agent_manager.py`)
   - Creates agents with unique identities
   - Auto-initializes workspace structure
   - Hardwires builder code into all agents

2. **Workspace Structure** (`workspace_structure.py`)
   - Standardized directory layout (30+ directories)
   - Automatic file categorization
   - Knowledge base, tools, submissions organization

3. **Submission Handler** (`submission_handler.py`)
   - Auto-detects content type (code, config, script, doc)
   - Saves to correct directory
   - Provides search and retrieval

4. **Builder Code Integration** (`builder_code_integration.py`)
   - Hardcodes builder code into agent creation
   - Ensures all agents inherit builder code
   - Transaction integration for blockchain

## Implementation

### 1. Deploy Three Bots

```bash
# Create service files
sudo tee /etc/systemd/system/telegram-bot.service > /dev/null << 'EOF'
[Unit]
Description=Hermes Telegram Bot (Hermes)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/telegram-webhook/bot_enhanced.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=/opt/telegram-webhook
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
EOF

# Repeat for titan and avery with different tokens and log files
```

### 2. Initialize Workspace Structure

```python
from workspace_structure import WorkspaceStructure

# Initialize for each agent
for agent in ['hermes', 'titan', 'avery']:
    workspace = f'/home/ubuntu/hermes-agent/workspaces/{agent}'
    ws = WorkspaceStructure(workspace)
    print(f'Initialized: {workspace}')
```

### 3. Auto-Initialize on Agent Creation

In `agent_manager.py`, add to `create_agent()` method:

```python
# After creating workspace_dir
import sys
sys.path.insert(0, '/home/ubuntu/hermes-agent')
from workspace_structure import WorkspaceStructure
workspace_structure = WorkspaceStructure(str(workspace_dir))
```

### 4. Hardwire Builder Code

In `agent_manager.py`, add to agent.json creation:

```python
from builder_code_integration import get_builder_code_manager
builder_manager = get_builder_code_manager()

agent_json = {
    'agent_id': identity.agent_id,
    'name': identity.name,
    'builderCode': {
        'code': builder_manager.BUILDER_CODE,
        'hex': builder_manager.BUILDER_CODE_HEX,
        'owner': builder_manager.OWNER_ADDRESS,
        'hardwired': True
    }
}
```

## Standardized Workspace Structure

```
[agent-workspace]/
├── agent/                      # Agent identity (SOUL.md, AGENTS.md)
├── archives/                   # Archived content
├── assets/                     # Static resources
│   ├── data/                   # Data files
│   ├── documents/              # PDFs, docs
│   └── images/                 # Images
├── backups/                    # Workspace backups
├── cache/                      # Cached data
├── knowledge/                  # Knowledge base
│   ├── api/                    # API documentation
│   ├── examples/               # Code examples
│   ├── guides/                 # How-to guides
│   └── research/               # Research notes
├── logs/                       # Agent logs
│   ├── errors/
│   ├── performance/
│   └── submissions/
├── memory/                     # Daily logs
├── projects/                   # Active projects
├── sessions/                   # Session transcripts
├── submissions/                # Received content
│   ├── code/                   # Programming code
│   ├── configs/                # Configuration files
│   ├── data/                   # Data files
│   ├── documents/              # Documentation
│   ├── misc/                   # Other content
│   ├── notes/                  # Notes
│   └── scripts/                # Shell scripts
├── temp/                       # Temporary files
├── tools/                      # Tools and utilities
│   ├── configs/
│   ├── scripts/
│   └── templates/
└── workflows/                  # Workflow definitions
```

## Automatic File Organization

### File Type Mapping

```python
FILE_TYPE_MAPPING = {
    # Code
    '.py': 'submissions/code',
    '.js': 'submissions/code',
    '.ts': 'submissions/code',
    '.html': 'submissions/code',
    '.css': 'submissions/code',
    
    # Scripts
    '.sh': 'submissions/scripts',
    '.bash': 'submissions/scripts',
    
    # Config
    '.json': 'submissions/configs',
    '.yaml': 'submissions/configs',
    '.yml': 'submissions/configs',
    '.env': 'submissions/configs',
    
    # Documents
    '.md': 'submissions/documents',
    '.txt': 'submissions/documents',
    
    # Data
    '.csv': 'submissions/data',
    '.xml': 'submissions/data',
    
    # Images
    '.png': 'assets/images',
    '.jpg': 'assets/images',
}
```

### Submission Handler Integration

In `bot_enhanced.py`, add submission detection:

```python
def _is_submission(self, text: str) -> bool:
    """Check if text is a submission."""
    if '```' in text:
        return True
    
    code_patterns = [
        r'^\s*def\s+\w+\s*\(',
        r'^\s*class\s+\w+',
        r'^\s*import\s+\w+',
        # ... more patterns
    ]
    
    for pattern in code_patterns:
        if re.search(pattern, text, re.MULTILINE):
            return True
    
    return False

def _handle_submission(self, chat_id: int, text: str, msg_id: int = None) -> str:
    """Handle submission content."""
    from handlers.submission_handlers import SubmissionHandlers
    
    if not hasattr(self, 'submission_handlers'):
        self.submission_handlers = SubmissionHandlers(self)
    
    return self.submission_handlers.handle_submission_content(
        chat_id=chat_id,
        content=text,
        content_type='text'
    )
```

## Telegram Commands

### Agent Management
```
/agent list [type]          - List all agents
/agent create <type> [name] - Create new agent
/agent setup <id> [token]   - Set up Telegram bot
/agent show <id>            - Show agent details
/agent types                - Show available types
```

### Submission Management
```
/submit help                - Show commands
/submit list [category]     - List submissions
/submit stats               - Show statistics
/submit view <id>           - View submission
/submit search <query>      - Search content
```

### Crew Management
```
/crew create <name> <agents> - Create crew
/crew start <name>           - Start workflow
/crew status <name>          - Show status
```

### Backup System
```
/backup create <path> [options] - Create backup (ZIP/TAR/TAR.GZ)
/backup list [filter]           - List all backups
/backup restore <backup> [path] - Restore backup
/backup delete <backup>         - Delete backup
/backup cleanup [days]          - Clean old backups

Options:
  -z, --zip        - Create ZIP archive (default)
  -t, --tar        - Create TAR archive
  -g, --gzip       - Create TAR.GZ archive
  -n, --name NAME  - Custom backup name
  -e, --exclude PATTERN - Exclude pattern (repeatable)
```

### Analyze System
```
/analyze run [path]         - Analyze codebase and generate .scope/
/analyze scope [path]       - View .scope/ contents
/analyze components [path]  - Show key components
/analyze functions [path]   - Show key functions
/analyze structure [path]   - Show project structure
/analyze cleanup [path]     - Suggest file cleanup

Options:
  -s, --scope      - Generate .scope/ directory
  -d, --deep       - Deep analysis (more thorough)
```

## Builder Code Integration

### Hardwired Values
```python
BUILDER_CODE = "bc_26ulyc23"
BUILDER_CODE_HEX = "0x62635f3236756c79633233"
OWNER_ADDRESS = "0x12F1B38DC35AA65B50E5849d02559078953aE24b"
```

### Agent Creation Integration
```python
# In agent_manager.py create_agent()
builder_manager = get_builder_code_manager()

# Register agent with builder code
builder_manager.register_agent(
    agent_id=identity.agent_id,
    agent_name=identity.name,
    agent_type=agent_type,
    parent_agent="system"
)
```

### Transaction Integration
```python
def append_builder_code_to_transaction(tx_data: str) -> str:
    """Append builder code to transaction."""
    builder_code_hex = "62635f3236756c79633233"
    if tx_data.startswith("0x"):
        tx_data = tx_data[2:]
    return "0x" + tx_data + builder_code_hex
```

## Service Management

### Check All Services
```bash
sudo systemctl status telegram-bot.service telegram-titan.service telegram-avery.service
```

### Restart Services
```bash
sudo systemctl restart telegram-bot.service
sudo systemctl restart telegram-titan.service
sudo systemctl restart telegram-avery.service
```

### View Logs
```bash
sudo tail -f /opt/telegram-webhook/logs/bot.log      # Hermes
sudo tail -f /opt/telegram-webhook/logs/titan.log    # Titan
sudo tail -f /opt/telegram-webhook/logs/avery-bot.log # Avery
```

## Testing

### Test Agent Creation with Workspace
```python
from agent_manager import get_agent_manager

manager = get_agent_manager()
result = manager.create_agent('ui', 'Test-Agent')

assert result['success']
assert os.path.exists(result['workspace'] + '/.workspace_structure.json')
assert os.path.exists(result['workspace'] + '/submissions/code')
```

### Test Submission Handling
```python
from submission_handler import SubmissionHandler

handler = SubmissionHandler('/path/to/workspace')
result = handler.process_submission(
    content='def hello(): print("Hello")',
    content_type='text',
    filename='hello.py'
)

assert result['success']
assert result['category'] == 'code'
```

## Troubleshooting

### Service Won't Start
```bash
# Check logs
sudo journalctl -u telegram-bot.service -n 50

# Check token
grep "TOKEN=" /opt/telegram-webhook/bot_enhanced.py

# Test token
python3 -c "import requests; r = requests.get('https://api.telegram.org/botTOKEN/getMe'); print(r.json())"
```

### Workspace Not Initialized
```python
# Manually initialize
from workspace_structure import WorkspaceStructure
ws = WorkspaceStructure('/path/to/workspace')
```

### Submission Not Categorized
```python
# Check file extension mapping
from workspace_structure import WorkspaceStructure
ws = WorkspaceStructure('/path/to/workspace')
target = ws.get_target_directory('file.py', 'code')
print(target)
```

## Secrets Management

### Hidden .secrets/ Directory

Every agent gets a hidden `.secrets/` directory with secure permissions:

```
.secrets/                        # HIDDEN (700 permissions)
├── .api_key_telegram.secret     # Telegram bot token (600 permissions)
├── .api_key_openai.secret       # OpenAI API key
├── .wallet_ethereum.secret      # ETH wallet recovery phrase
├── .private_key_signing.secret  # Transaction signing key
└── ...
```

### Security Features

- **Directory permissions:** `700` (owner only)
- **File permissions:** `600` (owner read/write only)
- **All files hidden:** Start with `.`
- **Individual files:** One secret per file
- **Metadata included:** Type, name, description, timestamp

### Create Secret

```python
ws.create_secret('api_key', 'telegram', 'BOT_TOKEN_HERE', 'Telegram bot token')
# Creates: .secrets/.api_key_telegram.secret
```

### List Secrets (metadata only)

```python
secrets = ws.list_secrets()
# Returns: [{'type': 'api_key', 'name': 'telegram', 'description': '...'}]
```

### Get Secret Value

```python
token = ws.get_secret('telegram')
# Returns: 'BOT_TOKEN_HERE'
```

## Archive Management

### Archive Completed Work

Archive projects without bloat (node_modules, __pycache__, .git, etc.):

```python
# Archive with bloat cleanup
ws.archive_completed_work('/path/to/project', description='Completed feature')

# Cleanup (archive + delete to save space)
ws.cleanup_project('/path/to/project', description='Finished project')
```

### Bloat Exclusion Patterns

```python
ARCHIVE_EXCLUDE_PATTERNS = [
    'node_modules',
    '__pycache__',
    '.git',
    '.next',
    '.nuxt',
    'dist',
    'build',
    '.cache',
    '.tmp',
    'tmp',
    '*.pyc',
    '*.pyo',
    '*.egg-info',
    '.venv',
    'venv',
    'env',
]
```

### List Archives

```python
archives = ws.list_archives()
# Returns: [{'name': '...', 'size': '...', 'archived_at': '...'}]
```

### Restore Archive

```python
ws.restore_archive('project_name_20260410')
# Restores to projects/ directory
```

## Agent Enforcement System

### Self-Healing Identity Verification

Before every significant action, agents verify their identity:

```python
from agent_enforcement import AgentEnforcement

enforcement = AgentEnforcement('/path/to/workspace')
identity = enforcement.verify_identity_before_action()

# Output:
╔════════════════════════════════════════════════════════════╗
║  IDENTITY VERIFICATION                                     ║
╠════════════════════════════════════════════════════════════╣
║  Agent: Design-Master                                     ║
║  ID: ui-a1b2c3d4                                          ║
║  Type: ui                                                 ║
║  Builder Code: bc_26ulyc23                                ║
╚════════════════════════════════════════════════════════════╝
```

### Credential Checking (NO BULLSHIT Policy)

Before credential-requiring actions, agents check what they have:

```python
result = enforcement.check_credentials_before_action(
    'Send Telegram message',
    ['api_key', 'token']
)

if not result['can_proceed']:
    # Show clear message about what's missing
    message = enforcement.generate_missing_credentials_message(
        'Send Telegram message',
        result['missing_credentials']
    )
    print(message)
```

### Missing Credentials Message

```
╔════════════════════════════════════════════════════════════╗
║  ⚠️  CREDENTIAL CHECK FAILED                               ║
╠════════════════════════════════════════════════════════════╣
║  Agent: Design-Master                                     ║
║  Action: Send Telegram message                            ║
╠════════════════════════════════════════════════════════════╣
║  ❌ MISSING CREDENTIALS:                                   ║
║  • api_key                                                ║
║  • token                                                  ║
╠════════════════════════════════════════════════════════════╣
║  🔐 WHAT I NEED:                                           ║
║  I cannot proceed without the above credentials.          ║
║  Please provide them specifically for me (not shared).    ║
║                                                           ║
║  ⚠️  I will NOT guess or assume credentials.              ║
║  ⚠️  I will NOT use your credentials.                     ║
║  ⚠️  I will clearly state what I'm missing.               ║
╚════════════════════════════════════════════════════════════╝
```

### Enforcement Rules

**Agents WILL NOT:**
- ❌ Guess credentials
- ❌ Assume they have credentials
- ❌ Use your credentials
- ❌ Make up credentials
- ❌ Proceed without required credentials

**Agents WILL:**
- ✅ Check what credentials they have
- ✅ Clearly state what's missing
- ✅ Ask for specific credentials
- ✅ Store credentials individually
- ✅ Verify before each action

## Best Practices

1. **Always initialize workspace** when creating agents
2. **Always hardwire builder code** in agent creation
3. **Use consistent naming** across all bots
4. **Test submissions** with various file types
5. **Monitor logs** for errors
6. **Backup workspaces** regularly
7. **Use .secrets/ for all credentials** (individual per agent)
8. **Archive completed work** without bloat
9. **Verify identity before actions**
10. **Check credentials before using them**

## Analyze System - .scope/ Generation

### Generate Project Analysis

The `/analyze` command generates a `.scope/` directory with comprehensive project understanding:

```
.scope/
├── README.md                    - Project overview (ONE comprehensive file)
├── components.md                - Key components identified
├── functions.md                 - Key functions identified
├── workflows.md                 - Development workflows
├── architecture.md              - Architecture overview
└── cleanup-suggestions.md       - Cleanup recommendations
```

### Key Principles

- **ONE comprehensive README** instead of many markdown files
- **Streamlined structure** without unnecessary nesting
- **Auto-generated** but human-readable
- **Focus on necessities** - only what's needed for development

### Example Analysis Output

```python
from handlers.analyze_handlers import AnalyzeHandlers

analyzer = AnalyzeHandlers(bot_instance)

# Run analysis
analysis = analyzer._analyze_codebase(Path('/path/to/project'), deep=False)

# Generate .scope/
result = analyzer._generate_scope_directory(Path('/path/to/project'), analysis)

print(f"Files: {analysis['total_files']}")
print(f"Functions: {len(analysis['functions'])}")
print(f"Classes: {len(analysis['classes'])}")
print(f".scope/ files: {len(result['files_created'])}")
```

## Backup System Implementation

### Handler Implementation

```python
# handlers/backup_handlers.py

class BackupHandlers:
    def __init__(self, bot_instance):
        self.bot = bot_instance
        self.backup_dir = Path(self.config.get('backup_dir', '/tmp/backups'))
        self.backup_dir.mkdir(parents=True, exist_ok=True)
    
    def handle_backup(self, chat_id: int, args: List[str], msg_id: int = None) -> str:
        """Handle /backup command."""
        if not args:
            return self._show_backup_help()
        
        command = args[0].lower()
        
        if command == "create":
            return self._create_backup(args[1:])
        elif command == "list":
            return self._list_backups(args[1:])
        # ... other commands
    
    def _create_zip(self, source: Path, destination: Path, 
                   exclude_patterns: List[str]) -> bool:
        """Create ZIP archive excluding bloat."""
        with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(source):
                # Filter out bloat directories
                dirs[:] = [d for d in dirs if not self._should_exclude(d, exclude_patterns)]
                
                for file in files:
                    if not self._should_exclude(file, exclude_patterns):
                        file_path = Path(root) / file
                        arcname = file_path.relative_to(source)
                        zipf.write(file_path, arcname)
        
        return True
    
    def _should_exclude(self, name: str, patterns: List[str]) -> bool:
        """Check if name should be excluded."""
        default_excludes = [
            '__pycache__', '.git', 'node_modules', '.next', '.nuxt',
            'dist', 'build', '.cache', '.tmp', 'tmp', '.venv', 'venv', 'env'
        ]
        
        all_excludes = default_excludes + patterns
        
        for pattern in all_excludes:
            if pattern in name:
                return True
        
        return False
```

## Bug Fixes and Lessons Learned

### Submission Handler Bug Fix

**Issue:** `category` variable not defined in `process_submission()` method.

**Fix:** Use `analysis['category']` instead of undefined `category` variable:

```python
# BEFORE (broken)
submission_log = {
    'category': category,  # NameError: name 'category' is not defined
}

# AFTER (fixed)
submission_log = {
    'category': analysis['category'],  # Use analysis dict
}

# Also fix logger statement:
# BEFORE: logger.info(f"Processed submission {submission_id}: {filename} -> {category}")
# AFTER:  logger.info(f"Processed submission {submission_id}: {filename} -> {analysis['category']}")
```

### Command Count Verification

**Issue:** Test script using `subprocess.run(['tail', ...])` doesn't reliably find initialization messages.

**Fix:** Read log files directly with Python:

```python
# BEFORE (unreliable)
result = subprocess.run(['tail', '-10', log_file], capture_output=True, text=True)
match = re.search(r'initialized with (\d+) commands', result.stdout)

# AFTER (reliable)
with open(log_file, 'r') as f:
    content = f.read()
matches = re.findall(r'initialized with (\d+) commands', content)
actual = max(int(m) for m in matches)  # Get latest/highest count
```

### Agent Creation Test Conflicts

**Issue:** Using hardcoded agent names causes "Agent already exists" errors on repeated test runs.

**Fix:** Use timestamp-based unique names:

```python
# BEFORE (fails on second run)
result = manager.create_agent('debugger', 'Final-Test-Debug')

# AFTER (always unique)
import time
unique_name = f"Final-Test-{int(time.time())}"
result = manager.create_agent('debugger', unique_name)
```

### Python Dependencies

**Issue:** Test script fails with `ModuleNotFoundError: No module named 'psutil'` or `requests`.

**Fix:** Install dependencies in the venv:

```bash
source /home/ubuntu/venv/bin/activate
pip install psutil requests
```

## Testing and Verification

### 100% Test Coverage

Create comprehensive tests that verify ALL functionality:

```python
# final_100_percent_test.py

class Final100PercentTest:
    def run_all_tests(self):
        """Run ALL tests - 100% required."""
        self.test_all_bots_running()           # 4 bots active
        self.test_all_command_counts()         # 58/58/58/18 commands
        self.test_workspace_structure()        # 30+ directories
        self.test_secrets_directory()          # 700/600 permissions
        self.test_backup_zip()                 # ZIP creation
        self.test_backup_tar()                 # TAR creation
        self.test_analyze_system()             # .scope/ generation
        self.test_submission_system()          # Auto-categorization
        self.test_agent_creation()             # Builder code enforced
        self.test_builder_code()               # Hardwired values
        self.test_archive_system()             # Bloat removal
        self.test_file_locking()               # Cross-agent prevention
        self.test_port_manager()               # Auto-expansion
        self.test_changelog()                  # Append-only tracking
        self.test_agent_allman()               # ERC-8004 ready
        
        return self.results['failed'] == 0
```

### Expected Output (100% Success)

```
======================================================================
FINAL VERIFICATION SUMMARY
======================================================================
Total Tests: 53
Passed: 53 ✅
Failed: 0 ❌
Success Rate: 100.0%

🎉🎉🎉 100% SUCCESS - ALL SYSTEMS VERIFIED! 🎉🎉🎉

✅ 4 Bots Running (Hermes, Titan, Avery, Agent Allman)
✅ 192+ Commands Across All Bots
✅ Workspace Structure Auto-Initializes
✅ Secrets Directory (700/600 permissions)
✅ Backup System (ZIP, TAR, TAR.GZ)
✅ Analyze System with .scope/ Generation
✅ Submission System with Auto-Categorization
✅ Agent Creation with Builder Code
✅ Builder Code bc_26ulyc23 Hardwired
✅ Archive System with Bloat Cleanup
✅ File Locking with Cross-Agent Prevention
✅ Port Manager with Auto-Expansion
✅ Changelog System (Append-Only)
✅ Agent Allman Ready for ERC-8004 Registration

🚀 EVERYTHING IS PRODUCTION READY!
```

## Best Practices

1. **Always initialize workspace** when creating agents
2. **Always hardwire builder code** in agent creation
3. **Use consistent naming** across all bots
4. **Test submissions** with various file types
5. **Monitor logs** for errors
6. **Backup workspaces** regularly
7. **Use .secrets/ for all credentials** (individual per agent)
8. **Archive completed work** without bloat
9. **Verify identity before actions**
10. **Check credentials before using them**
11. **Generate .scope/ for project analysis**
12. **Use unique names in tests** to avoid conflicts
13. **Read log files directly** for reliable parsing
14. **Install dependencies in venv** for test scripts

## Enterprise Deployment Package

### Package Structure

```
enterprise-deployment/
├── README.md                    # Master documentation
├── hermes/
│   ├── README.md               # Hermes identity & SOUL.md
│   ├── agent.json              # Configuration with builder code
│   ├── bot.py                  # Telegram bot script
│   └── service.service         # Systemd service file
├── titan/
│   ├── README.md               # Titan identity & SOUL.md
│   ├── agent.json              # Configuration with builder code
│   ├── bot.py                  # Telegram bot script
│   └── service.service         # Systemd service file
├── avery/
│   ├── README.md               # Avery identity & SOUL.md
│   ├── agent.json              # Configuration with builder code
│   ├── bot.py                  # Telegram bot script
│   └── service.service         # Systemd service file
├── agent-allman/
│   ├── README.md               # Agent Allman identity & SOUL.md
│   ├── agent.json              # Configuration with builder code
│   ├── bot.py                  # Telegram bot script
│   └── service.service         # Systemd service file
└── scripts/
    └── deploy-all.sh           # One-command deployment
```

### Deploy All Agents

```bash
cd ~/hermes-agent/enterprise-deployment
bash scripts/deploy-all.sh
```

### Each Agent README.md Includes

1. **Identity** — Name, bot, token, purpose, commands, personality
2. **SOUL.md** — Who you are, purpose, principles, personality, capabilities
3. **Builder Code** — Hardwired bc_26ulyc23
4. **Boundaries** — What agents will/won't do

## Bug Fixes and Lessons Learned

### 1. Submission Handler Category Variable

**Issue:** `NameError: name 'category' is not defined` in `process_submission()`.

**Root Cause:** Variable `category` referenced but never defined.

**Fix in `/opt/telegram-webhook/submission_handler.py`:**

```python
# Line ~164: Change 'category' to 'analysis['category']'
submission_log = {
    'category': analysis['category'],  # NOT just 'category'
}

# Line ~176: Fix logger statement
logger.info(f"Processed submission {submission_id}: {filename} -> {analysis['category']}")
```

### 2. Command Count Verification in Tests

**Issue:** Using `subprocess.run(['tail', ...])` doesn't reliably find initialization messages.

**Root Cause:** Subprocess output capture can miss lines or have timing issues.

**Fix — Read log files directly with Python:**

```python
# BEFORE (unreliable)
result = subprocess.run(['tail', '-10', log_file], capture_output=True, text=True)
match = re.search(r'initialized with (\d+) commands', result.stdout)

# AFTER (reliable)
with open(log_file, 'r') as f:
    content = f.read()
matches = re.findall(r'initialized with (\d+) commands', content)
if matches:
    actual = max(int(m) for m in matches)  # Get latest/highest count
```

### 3. Agent Creation Test Name Conflicts

**Issue:** Using hardcoded agent names causes "Agent already exists" errors on repeated test runs.

**Fix — Use timestamp-based unique names:**

```python
# BEFORE (fails on second run)
result = manager.create_agent('debugger', 'Final-Test-Debug')

# AFTER (always unique)
import time
unique_name = f"Final-Test-{int(time.time())}"
result = manager.create_agent('debugger', unique_name)
```

### 4. Python Dependencies in Tests

**Issue:** `ModuleNotFoundError: No module named 'psutil'` or `'requests'`.

**Root Cause:** Test script uses system Python without dependencies installed.

**Fix — Install in venv:**

```bash
source /home/ubuntu/venv/bin/activate
pip install psutil requests
```

**Or run tests with venv Python:**

```bash
/home/ubuntu/venv/bin/python3 final_100_percent_test.py
```

### 5. Telegram Bot Token Conflicts

**Issue:** Error `409 Conflict: terminated by other getUpdates request`.

**Root Cause:** Multiple bot instances polling the same token.

**Fix:**

```bash
# Stop all instances
sudo systemctl stop telegram-bot.service
sudo pkill -f bot_enhanced.py

# Wait 5 seconds for cleanup
sleep 5

# Start fresh
sudo systemctl start telegram-bot.service
```

### 6. Service File Deployment

**Issue:** Cannot write to `/etc/systemd/system/` without sudo.

**Fix — Use terminal tool with sudo:**

```python
# Don't use write_file for system paths
# Use terminal instead:
terminal(command="sudo tee /etc/systemd/system/telegram-bot.service > /dev/null << 'EOF'\n...\nEOF")
```

### 7. Secrets Directory Renaming (secrets/ → .secrets/)

**Issue:** User created `secrets/` directory without period prefix.

**Fix — Extract and rename:**

```bash
# If you have a secrets.zip or secrets/ directory
cd ~/hermes-agent/workspaces/titan

# Extract if zipped
unzip -o secrets.zip -d temp_extract

# Move and rename
mv temp_extract/secrets .secrets
rm -rf temp_extract

# Rename all files with period prefix
cd .secrets
for f in *; do
    if [[ ! "$f" == .* ]]; then
        mv "$f" ".$f"
    fi
done

# Set proper permissions
chmod 700 ~/hermes-agent/workspaces/titan/.secrets
cd ~/hermes-agent/workspaces/titan/.secrets
for f in .[^.]*; do
    chmod 600 "$f"
done
```

### 8. Workspace Self-Organization

**Issue:** Agent's own workspace needs to match standardized structure.

**Fix — Initialize missing components:**

```bash
# Create .secrets/ directory if missing
mkdir -p ~/hermes-agent/workspaces/hermes/.secrets
chmod 700 ~/hermes-agent/workspaces/hermes/.secrets

# Create agent identity files
cat > ~/hermes-agent/workspaces/hermes/agent/SOUL.md << 'EOF'
# SOUL.md — Hermes
[Agent identity content]
EOF

# Create agent.json with builder code
cat > ~/hermes-agent/workspaces/hermes/agent.json << 'EOF'
{
  "agent_id": "hermes",
  "name": "Hermes",
  "builderCode": {
    "code": "bc_26ulyc23",
    "hex": "0x62635f3236756c79633233",
    "owner": "0x12F1B38DC35AA65B50E5849d02559078953aE24b",
    "hardwired": true,
    "enforced": true
  }
}
EOF
```

### 9. Enterprise Deployment Package Structure

**Issue:** Need complete deployment package with all scripts.

**Fix — Create organized package:**

```bash
# Create deployment directory
mkdir -p ~/hermes-agent/agents_and_telegramconfig/{core/handlers,hermes,titan,avery,agent-allman,workspace-template,scripts}

# Copy core Python scripts
cp /opt/telegram-webhook/workspace_structure.py ~/hermes-agent/agents_and_telegramconfig/core/
cp /opt/telegram-webhook/agent_manager.py ~/hermes-agent/agents_and_telegramconfig/core/
cp /opt/telegram-webhook/submission_handler.py ~/hermes-agent/agents_and_telegramconfig/core/
# ... copy all core scripts

# Copy handler scripts
cp /opt/telegram-webhook/handlers/*.py ~/hermes-agent/agents_and_telegramconfig/core/handlers/

# Copy bot scripts to each agent directory
cp /opt/telegram-webhook/bot_enhanced.py ~/hermes-agent/agents_and_telegramconfig/hermes/bot.py
cp /opt/telegram-webhook/titan_bot_enhanced.py ~/hermes-agent/agents_and_telegramconfig/titan/bot.py
cp /opt/telegram-webhook/avery-bot_enhanced.py ~/hermes-agent/agents_and_telegramconfig/avery/bot.py
cp /opt/telegram-webhook/agent-allman-bot.py ~/hermes-agent/agents_and_telegramconfig/agent-allman/bot.py

# Copy service files
sudo cp /etc/systemd/system/telegram-bot.service ~/hermes-agent/agents_and_telegramconfig/hermes/service.service
# ... copy all service files
```

### 10. Test Script Import Paths

**Issue:** Test script fails with `ModuleNotFoundError` for handlers.

**Fix — Add proper sys.path entries:**

```python
# In test script, add ALL necessary paths
import sys
sys.path.insert(0, '/home/ubuntu/hermes-agent')
sys.path.insert(0, '/home/ubuntu/hermes-agent/telegram-bot')
sys.path.insert(0, '/home/ubuntu/.hermes/skills/autonomous-crew')
sys.path.insert(0, '/opt/telegram-webhook')
sys.path.insert(0, '/opt/telegram-webhook/handlers')
```

## Quick Reference: Critical File Locations

| Component | Location |
|-----------|----------|
| Bot Scripts | `/opt/telegram-webhook/bot_enhanced.py` |
| Titan Bot | `/opt/telegram-webhook/titan_bot_enhanced.py` |
| Avery Bot | `/opt/telegram-webhook/avery-bot_enhanced.py` |
| Agent Allman | `/opt/telegram-webhook/agent-allman-bot.py` |
| Hermes Service | `/etc/systemd/system/telegram-bot.service` |
| Titan Service | `/etc/systemd/system/telegram-titan.service` |
| Avery Service | `/etc/systemd/system/telegram-avery.service` |
| Allman Service | `/etc/systemd/system/telegram-agent-allman.service` |
| Bot Logs | `/opt/telegram-webhook/logs/bot.log` |
| Submission Handler | `/opt/telegram-webhook/submission_handler.py` |
| Backup Handlers | `/opt/telegram-webhook/handlers/backup_handlers.py` |
| Analyze Handlers | `/opt/telegram-webhook/handlers/analyze_handlers.py` |
| Agent Manager | `~/.hermes/skills/autonomous-crew/agent_manager.py` |
| Workspace Structure | `~/hermes-agent/workspace_structure.py` |
| Builder Code Manager | `~/.hermes/skills/autonomous-crew/builder_code_integration.py` |

## Testing Checklist

Before declaring "100% complete":

- [ ] All 4 bots show `active` status
- [ ] All bots show 58 commands (18 for Avery)
- [ ] Workspace structure auto-initializes on agent creation
- [ ] `.secrets/` directory has 700 permissions
- [ ] Secret files have 600 permissions
- [ ] ZIP backup creates and extracts correctly
- [ ] TAR backup creates and extracts correctly
- [ ] `.scope/` generation creates all 6 files
- [ ] Submission auto-categorizes to correct directory
- [ ] Agent creation includes builder code `bc_26ulyc23`
- [ ] Archive removes bloat (node_modules, __pycache__, .git)
- [ ] File locking prevents cross-agent modifications
- [ ] Port manager allocates 4 ports per agent
- [ ] Changelog entries are append-only
- [ ] Agent Allman workspace has all required files

## Plug-and-Play Deployment Package

The `agents_and_telegramconfig/` directory serves as a standalone, portable backup of the entire multi-agent system. Everything needed to reconstruct any agent lives here.

### Package Structure

```
agents_and_telegramconfig/
├── README.md                    # Master documentation
├── skills/                      # Shared skills directory (all 70)
│   ├── adaptive-reasoning/
│   ├── coding-agent/
│   ├── devops/
│   ├── github/
│   └── ... (70 total)
├── hermes/                      # Orchestrator
│   ├── agent.json               # Config + skills list
│   ├── config.yaml              # Runtime configuration
│   ├── bot.py                   # Telegram bot
│   ├── service.service          # Systemd unit
│   ├── SOUL.md, USER.md, AGENTS.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md
│   ├── .secrets/                # Credentials (700 perms)
│   └── memory/                  # MEMORY.md + recent daily logs
├── titan/                       # Builder
│   ├── agent.json, config.yaml, bot.py, service.service
│   ├── SOUL.md, USER.md, AGENTS.md, HEARTBEAT.md, SECURITY.md
│   ├── .secrets/                # Farcaster, Neyar, Moltbook, X, ERC-8004 creds
│   ├── scripts/                 # run-heartbeat.sh, check-*.sh, restart, watchdog
│   ├── config/builder-code/     # Builder code config
│   ├── tools/                   # Tool configs
│   └── memory/                  # Recent daily logs
├── avery/                       # Child-safe (Ava, age 6)
│   ├── agent.json, config.yaml, bot.py, service.service
│   ├── SOUL.md, USER.md, AGENTS.md
│   └── memory/
├── agent-allman/                # Agent creator
│   ├── agent.json, config.yaml, bot.py, service.service
│   ├── SOUL.md, USER.md, AGENTS.md, TOOLS.md, MEMORY.md
│   ├── .secrets/, memory/, tools/
└── workspace-template/          # Template for new agents
```

### Key Design Patterns

#### 1. Shared Skills Directory (NOT per-agent copies)

One `skills/` at the package root. Each agent's `agent.json` declares which skills they access:

```json
"skills": {
  "shared_path": "../skills",
  "primary": ["software-development", "github", "devops"],
  "secondary": ["research", "weather", "note-taking"]
}
```

**Why:** Single source of truth. Update a skill once, all agents see it. Agent.json controls access scope.

#### 2. Path Agnosticism (NO hardcoded paths)

All config files use environment-variable-style references that resolve at runtime:

| Variable | Resolves To | Usage |
|----------|-------------|-------|
| `$WORKSPACE` | Agent's workspace root | All relative paths |
| `$HOME` | User home directory | Default working dir |
| `$HERMES_ROOT` | hermes-agent install dir | Cross-agent references |
| `~/.openclaw/` | OpenClaw data dir | Security, state |

**In config.yaml:**
```yaml
workspace:
  path: $WORKSPACE          # NOT /home/ubuntu/hermes-agent/workspaces/titan
heartbeat:
  state_file: $WORKSPACE/memory/heartbeat-state.json
```

**In agent.json:**
```json
"workspace": {
  "path": "$WORKSPACE",
  "canonical_state": "$WORKSPACE/memory/heartbeat-state.json"
}
```

**In SOUL.md / HEARTBEAT.md:**
```markdown
Always write heartbeat state to exactly this path:
`$WORKSPACE/memory/heartbeat-state.json`
```

**Why:** Portable across any server, user, or deployment. Copy the package anywhere and it works.

#### 3. Per-Agent config.yaml

Each agent gets a customized `config.yaml` with role-specific settings:

**Titan (builder):**
```yaml
heartbeat:
  enabled: true
  checks_per_cycle: 3
farcaster:
  monitoring: true
  username: @titan_192
research:
  daily_schedule: "10:00 MST"
  topics: [hackathons, airdrops, grants, bounties]
```

**Avery (child-safe):**
```yaml
child_safety:
  enabled: true
  user: Ava
  age: 6
  content_filter: strict
skills:
  blocked: [trading-agents, red-teaming, bankr-skills, ...]
```

**Agent Allman (creator):**
```yaml
agent_creation:
  enabled: true
  builder_code_enforcement: true
  auto_soul_generation: true
onchain:
  erc8004_registry: true
```

#### 4. Skill Assignment by Agent Role

| Agent | Type | Skills Count | Categories |
|-------|------|-------------|------------|
| Titan | builder | 22 | dev, infra, trading research, farcaster, web3 |
| Hermes | orchestrator | 20 | agent management, crew, dev, all skills |
| Avery | child-safe | 10 safe + 13 blocked | creative, weather, gaming, education |
| Agent Allman | creator | 22 | agent creation, onchain identity, dev |

**Blocked skills for Avery:** trading-agents, trading-brain, prediction-market-trader, polymarket-arbitrage, argus-edge, red-teaming, bankr-skills, social-media, x-twitter, farcaster-agent, deploying-contracts-on-base, self-xyz, hackathon-manager

#### 5. Agent Identity Merge (NOT Replace)

When refining SOUL.md or HEARTBEAT.md, **merge** the user's original content with improvements. Never wholesale replace with a new version.

**Pattern:**
1. Read user's original (the one they wrote/curated)
2. Read current/definitive version (with improvements)
3. Integrate: keep user's specific tasks, paths, principles
4. Add: better structure, assertive tone, new capabilities
5. Write merged result — user's intent preserved, presentation improved

**What NOT to do:** Replace user's heartbeat tasks (Moltbook, Farcaster monitoring, daily research) with generic "check disk space" tasks. Merge both.

#### 6. Core Files Per Agent (What to Include)

**Always include:**
- `SOUL.md` — identity, personality, principles
- `USER.md` — who they serve
- `AGENTS.md` — session startup protocol
- `agent.json` — config with skills list
- `config.yaml` — runtime configuration
- `bot.py` — Telegram bot script
- `service.service` — systemd unit

**Include if agent uses it:**
- `HEARTBEAT.md` — background tasks (Titan, Hermes)
- `SECURITY.md` — security directives
- `TOOLS.md` — tool-specific notes
- `MEMORY.md` — long-term curated memory
- `.secrets/` — actual credentials (700 perms)
- `scripts/` — automation scripts (heartbeat checks, restart, watchdog)
- `memory/` — MEMORY.md + 2-3 most recent daily logs (NOT all logs)
- `config/` — builder-code, flows, etc.

**Do NOT include:**
- Full session transcripts
- All historical daily logs
- Project source code (that's in git)
- Temporary/cache files
- Skills (those are in shared `skills/`)

#### 7. Verification Checklist

After building the deployment package:

```
✅ Shared skills/ directory with all skills
✅ Each agent.json has skills list with categories
✅ Each agent has config.yaml with role-specific settings
✅ All paths use $WORKSPACE, $HOME, $HERMES_ROOT (no hardcoded)
✅ SOUL.md + USER.md + AGENTS.md for each agent
✅ .secrets/ with actual credentials (700 perms, dotfiles)
✅ scripts/ with automation scripts (Titan)
✅ memory/ with MEMORY.md + recent logs
✅ README.md explains skills directory and structure
```

## Future Enhancements

1. **Auto-tagging** - ML-based content tagging
2. **Version control** - Git integration for submissions
3. **Shared workspaces** - Collaboration between agents
4. **Analytics** - Usage patterns and statistics
5. **Scheduled organization** - Automatic cleanup and organization
6. **Credential rotation** - Automatic secret rotation
7. **Audit logging** - Track all credential access
8. **Agent Allman integration** - Full ERC-8004 registration flow
9. **Auto-sync** - Keep deployment package in sync with live workspaces
