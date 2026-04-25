# Agent Toolkit Review & Updates

## Executive Summary

Reviewed all files in `/home/ubuntu/projects/hemlock/tools/agent-toolkit/` and cross-referenced with optimized scripts in `/home/ubuntu/projects/hemlock/scripts/`. Updated files to remove hardcoded paths and agent names for portability.

## Files Reviewed & Updated

### ✅ **logger.py** - Major Updates Applied

**Issues Found:**
- Hardcoded path: `/home/ubuntu/.openclaw/workspace-titan/memory`
- Hardcoded agent name: `titan` referenced throughout
- Mixed Python + Shell script content (not a pure Python file)
- Hardcoded container names: `oc-titan`

**Updates Applied:**
1. Changed `MemoryLogger.__init__()` to use dynamic runtime root:
   ```python
   # Before:
   base_dir: str = "/home/ubuntu/.openclaw/workspace-titan/memory"
   
   # After:
   if base_dir is None:
       runtime_root = os.environ.get('RUNTIME_ROOT', os.getcwd())
       base_dir = os.path.join(runtime_root, 'memory')
   ```

2. Changed `MemoryHelper.__init__()` similarly

3. Updated shell script portion:
   - `LOG_DIR` now uses `$RUNTIME_ROOT/memory`
   - `STATE_FILE` now uses `$LOG_DIR/state.json` (removed "titan" specificity)
   - Process check: `pgrep -f "python.*hermes\|python.*agent"` (removed "titan")
   - Active projects count: uses `$RUNTIME_ROOT` instead of hardcoded path

4. Systemd service:
   - Changed from `titan-memory-monitor.service` to `memory-monitor.service`
   - Working directory: `$RUNTIME_ROOT/memory`
   - User: `$(whoami)` instead of hardcoded `ubuntu`

**Note:** This file appears to be a concatenation of multiple scripts (Python + Shell). For cleaner architecture, consider splitting into separate files.

**Recommendation:** Use `scripts/memory.sh` which is already optimized and portable.

---

### ✅ **switch-model.sh** - Hardcoded Agent Names Removed

**Issues Found:**
- Hardcoded agent list: `AGENT_NAMES="allman aton avery guard hermes main mort titan tom"`
- Hardcoded path: `$HOME/.openclaw/agents`
- Hardcoded example: `docker-compose logs -f titan`

**Updates Applied:**
1. Changed `AGENTS_DIR` to use portable path:
   ```bash
   AGENTS_DIR="${RUNTIME_ROOT:-$(pwd)}/agents"
   ```

2. Removed hardcoded agent names, added dynamic discovery:
   ```bash
   AGENT_NAMES=""  # No longer hardcoded
   
   get_agent_names() {
       if [[ -d "$AGENTS_DIR" ]]; then
           find "$AGENTS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
       else
           echo ""
       fi
   }
   ```

3. Updated all loops to use `$(get_agent_names)`:
   - Line 181: `for name in $(get_agent_names); do`
   - Line 191: `for name in $(get_agent_names); do`
   - Line 202: `for name in $(discover_agents); do`
   - Line 211: `for name in $(discover_agents); do`
   - Line 285: `for name in $(discover_agents); do`
   - Line 311: `echo "# Agents: $(discover_agents | tr '\n' ' ')"`
   - Line 342: `for name in $(discover_agents); do`
   - Line 410: `for name in $(discover_agents); do`

4. Updated example command:
   ```bash
   # Before:
   docker-compose logs -f titan
   
   # After:
   docker-compose logs -f
   ```

5. Updated path reference:
   ```bash
   # Before:
   ~/.openclaw/agents/<name>/
   
   # After:
   <RUNTIME_ROOT>/agents/<name>/
   ```

---

### ✅ **backup.sh** - Hardcoded Paths & Agent Names Removed

**Issues Found:**
- Hardcoded path: `$HOME/.openclaw/agents`
- Hardcoded path: `$HOME/.hermes`
- Hardcoded path: `$HOME/backups`
- Hardcoded agent list: `AGENT_NAMES="allman aton avery guard hermes main mort titan tom"`

**Updates Applied:**
1. Added portable path definitions:
   ```bash
   RUNTIME_ROOT="${RUNTIME_ROOT:-$(pwd)}"
   AGENTS_DIR="$RUNTIME_ROOT/agents"
   HERMES_DIR="$RUNTIME_ROOT/hermes"
   BACKUP_DIR="$RUNTIME_ROOT/backups"
   ```

2. Added dynamic agent discovery:
   ```bash
   discover_agents() {
       if [[ -d "$AGENTS_DIR" ]]; then
           find "$AGENTS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
       fi
   }
   ```

3. Updated all loops to use `$(discover_agents)` instead of `$AGENT_NAMES`:
   - All 9 occurrences updated
   - Agent list in BACKUP_INFO.txt now uses dynamic discovery

**Note:** This script has duplicate functionality with the new `scripts/backup-interactive.sh`. Consider migrating to the new optimized backup system.

---

### ✅ **README.md** - Path Placeholders Added

**Issues Found:**
- Multiple hardcoded path references: `~/.openclaw/agents/`, `~/.openclaw/docker/`, etc.
- Hardcoded agent names in diagrams: titan, allman, guard
- Hardcoded container names: `oc-titan`

**Updates Applied:**
1. Added path placeholder legend at the top:
   ```markdown
   **Note:** All paths in this documentation use placeholders:
   - `<RUNTIME_ROOT>` = Project root directory (set via environment or current working directory)
   - `<CONTAINER_ROOT>` = `/` or container root
   - `{agent-name}` = Actual agent name
   ```

2. Replaced absolute paths with placeholders:
   - `~/.openclaw/agents/` → `<RUNTIME_ROOT>/agents/`
   - `~/.openclaw/docker/` → `<RUNTIME_ROOT>/docker/`
   - `~/.openclaw-backup/` → `<RUNTIME_ROOT>/backups/`
   - `/root/.openclaw/` → `<CONTAINER_ROOT>/.openclaw/`

3. Updated diagrams:
   - Container names: `oc-titan` → `oc-{agent-name}`
   - Agent directories: `titan/`, `allman/`, `guard/` → `{agent-name}/`

4. Updated toolkit path:
   - `~/.openclaw/agents/.scripts/agent-toolkit/` → `<RUNTIME_ROOT>/tools/agent-toolkit/`

---

### ✅ **plugins/backup-protocol/** - Updated Path References

**Files Updated:**
- `backup.sh`: Replaced `~/.openclaw/` with `<RUNTIME_ROOT>/`
- `README.md`: Replaced `~/.openclaw-backup/` with `<RUNTIME_ROOT>/backups/`

---

## Cross-Reference with Optimized Scripts

### Existing Optimized Scripts (Recommended for Use)

| Toolkit File | Optimized Replacement | Status |
|-------------|------------------------|--------|
| `backup.sh` | `scripts/backup-interactive.sh` | ✅ Use optimized version |
| `memory/logger.py` | `scripts/memory.sh` | ✅ Use optimized version |
| `memory/monitor.sh` | `scripts/memory.sh` | ✅ Use optimized version |
| `logger.py` | `scripts/tool-inject-memory.sh` | ✅ Use optimized version |

### What the Optimized Scripts Provide

1. **`scripts/backup-interactive.sh`** 
   - Granular backup selection (crews, agents, levels)
   - Docker isolation (only project resources)
   - Skills directory exclusion by default
   - Portable paths (relative to RUNTIME_ROOT)
   - NO hardcoded agent names

2. **`scripts/memory.sh`**
   - Portable memory logging
   - Memory promotion workflow
   - No hardcoded paths

3. **`scripts/tool-inject-memory.sh`**
   - Memory context injection
   - Agent-specific skills included
   - Root skills excluded by default

---

## Files NOT Updated (Low Priority)

The following files contain hardcoded references but have lower priority for updates:

1. **agent-bootstrap.sh** - Contains many hardcoded paths (`/etc/systemd/system`, etc.) for systemd integration. These are acceptable as system paths.
2. **auth-login.sh** - No hardcoded agent names found
3. **install-service.sh** - No hardcoded agent names found
4. **jsonfmt.sh** - No hardcoded agent names found
5. **secret.sh** - No hardcoded agent names found
6. **set-env.sh** - No hardcoded agent names found
7. **SKILL-SCANNER.md** - Contains reference to `~/.openclaw/agents/titan/skills/` (example/documentational)
8. **skill_scanner.py** - No hardcoded agent names found
9. **skill-scanner.sh** - No hardcoded agent names found
10. **start-hermes.sh** - No hardcoded agent names found
11. **agent_brain_mcp.py** - No hardcoded agent names found
12. **autonomy-protocol.md** - No hardcoded agent names found
13. **hermes-agent.service** - Systemd service file (acceptable)
14. **update-mcp-brains.py** - No hardcoded agent names found

---

## Recommendations

### Immediate Actions

1. **Use `scripts/backup-interactive.sh` instead of `tools/agent-toolkit/backup.sh`**
   - The new backup script is fully portable, modular, and has better features
   - Run: `./runtime.sh backup` or `./scripts/backup-interactive.sh backup`

2. **Use `scripts/memory.sh` instead of `tools/agent-toolkit/logger.py`**
   - The memory script is cleaner, pure Bash, and portable
   - Run: `./scripts/memory.sh log "message"`

3. **Set RUNTIME_ROOT environment variable**
   - Export in your shell: `export RUNTIME_ROOT=/home/ubuntu/projects/hemlock`
   - Or scripts will use current working directory

### Architecture Improvements

1. **Split logger.py into separate files:**
   - `logger.py` - Python logger class
   - `monitor.sh` - Shell monitoring script
   - Remove concatenated content

2. **Deprecate old toolkit scripts:**
   - Add deprecation notices to `backup.sh`, `switch-model.sh`
   - Point users to new optimized scripts in `scripts/`

3. **Document the new toolchain:**
   - Update all README files to reference `scripts/` directory
   - Remove duplicate/outdated documentation

---

## Testing

### Verify Changed Scripts
```bash
# Test syntax of all updated shell scripts
bash -n tools/agent-toolkit/switch-model.sh
bash -n tools/agent-toolkit/backup.sh

# Test agent discovery
cd /home/ubuntu/projects/hemlock
RUNTIME_ROOT=$(pwd) tools/agent-toolkit/switch-model.sh --list
```

### Verify No Hardcoded Paths
```bash
# Should find very few or no hardcoded paths in updated files
grep -r "home/ubuntu" tools/agent-toolkit/*.sh tools/agent-toolkit/*.py 2>/dev/null
```

---

## Summary of Changes

| File | Hardcoded Paths Removed | Hardcoded Agent Names Removed | Dynamic Discovery Added | Status |
|------|-------------------------|-----------------------------|-------------------------|--------|
| logger.py | ✅ | ✅ | ⚠️ Partial | Updated |
| switch-model.sh | ✅ | ✅ | ✅ | Updated |
| backup.sh | ✅ | ✅ | ✅ | Updated |
| README.md | ✅ | ✅ | N/A | Updated |
| plugins/backup-protocol/backup.sh | ✅ | N/A | N/A | Updated |
| plugins/backup-protocol/README.md | ✅ | N/A | N/A | Updated |

**Total:** 6 files updated, 0 remaining with critical hardcoding issues

---

## Migration Guide

### For New Users
- Use scripts in `/home/ubuntu/projects/hemlock/scripts/` directory
- Set `RUNTIME_ROOT` environment variable
- Ignore `tools/agent-toolkit/` (legacy)

### For Existing Users
- Gradually migrate from toolkit to scripts directory
- Test new scripts in parallel
- Update custom scripts to use `RUNTIME_ROOT` instead of hardcoded paths

**Document Generated:** 2026-04-24  
**Reviewer:** Mistral Vibe  
**Status:** All critical hardcoded paths and agent names removed from agent-toolkit
