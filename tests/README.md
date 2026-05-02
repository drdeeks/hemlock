# Hemlock Enterprise Framework - Test Suite

## Overview

This directory contains a comprehensive test suite for the Hemlock Enterprise Framework, covering:
- Agent lifecycle management (create, import, export, delete)
- Hidden files/directories support
- Runtime command validation
- Common library unit tests
- Configuration validation
- Cross-script integration
- Self-healing mechanisms
- Memory injection workflows

## Directory Structure

```
tests/
├── run_all.sh                          # Master test runner (all categories)
│
├── validation/                         # Fast structural validation tests
│   ├── validate_structure.sh           # Project directory/file structure
│   ├── validate_permissions.sh         # File permission standards (auto-fixes 700)
│   └── validate_skills.sh             # Skills library validation (289+ skills)
│
├── unit/                               # Isolated component unit tests
│   ├── test_delete_agent.sh            # Agent deletion (runtime.sh + agent-delete.sh)
│   ├── test_agent_create.sh            # Agent create / import / export (NEW)
│   ├── test_common_lib.sh              # lib/common.sh full function coverage (NEW)
│   └── test_runtime_commands.sh        # runtime.sh command coverage (NEW)
│
├── integration/                        # Component interaction tests
│   ├── test_backup_system.sh           # backup-interactive.sh ↔ runtime.sh
│   ├── test_agent_lifecycle.sh         # Create→list→import→export→delete cycle (NEW)
│   ├── test_config_validation.sh       # Config files (runtime.yaml, gateway.yaml) (NEW)
│   └── test_script_interactions.sh     # Cross-script dependencies (NEW)
│
└── e2e/                                # End-to-end workflow tests
    ├── test_complete_workflow.sh        # Full backup/restore/validation workflow
    ├── test_hidden_files.sh            # Hidden file preservation (import/export/delete)
    ├── test_self_healing.sh            # Self-healing mechanisms (NEW)
    ├── test_memory_injection.sh        # Memory injection workflow (NEW)
    ├── enforce_100_percent.sh          # 100% pass enforcement
    ├── run_tests.sh                    # E2E-specific runner
    ├── test_agent.sh                   # Agent creation setup
    └── TESTING_REPORT.md               # Historical test reports
```

---

## Running Tests

### Run All Tests (all categories)
```bash
./tests/run_all.sh
```

### Run by Category
```bash
./tests/run_all.sh validation       # Fast structural checks (~2s)
./tests/run_all.sh unit             # Unit tests (~10s)
./tests/run_all.sh integration      # Integration tests (~15s)
./tests/run_all.sh e2e              # End-to-end tests (~30s)
```

### Run a Specific Test File
```bash
./tests/run_all.sh unit tests/unit/test_common_lib.sh
bash tests/unit/test_common_lib.sh
bash tests/integration/test_agent_lifecycle.sh
```

---

## Test Categories

### Validation Tests
Fast checks that verify the project structure is intact. Run these first to catch
configuration drift.

| Script | What it tests |
|--------|--------------|
| `validate_structure.sh` | Required dirs, scripts, lib files, agent configs |
| `validate_permissions.sh` | No 700 perms, scripts executable, configs readable |
| `validate_skills.sh` | 289+ skills have SKILL.md with required sections |

### Unit Tests
Isolated tests for individual scripts and libraries.

| Script | What it tests |
|--------|--------------|
| `test_common_lib.sh` | 15 tests: all lib/common.sh functions (log, safe_mkdir, atomic_write, safe_chmod, validate_permission, retry_with_fallback, with_self_healing, detect_environment, etc.) |
| `test_runtime_commands.sh` | 12 tests: runtime.sh --help, list-agents, status, self-check, list-plugins, list-crews, backup-status, unknown commands |
| `test_agent_create.sh` | 12 tests: agent-create.sh, agent-import.sh, agent-export.sh, agent-delete.sh, import/export roundtrip |
| `test_delete_agent.sh` | 7 tests: delete via runtime.sh, --force flag, nonexistent agent handling, runtime.log cleanup |

### Integration Tests
Tests that verify multiple scripts work together correctly.

| Script | What it tests |
|--------|--------------|
| `test_backup_system.sh` | 10 tests: backup-interactive.sh ↔ runtime.sh, --help/--version/--dry-run, required scripts |
| `test_agent_lifecycle.sh` | 14 tests: full create→import→list→export→delete cycle + hidden files + idempotency |
| `test_config_validation.sh` | 14 tests: runtime.yaml, gateway.yaml, .env.template, agent configs, Makefile targets, YAML syntax |
| `test_script_interactions.sh` | 12 tests: runtime.sh↔common.sh, runtime.sh↔backup, runtime.sh↔health, runtime.sh↔inject-memory |

### E2E Tests
End-to-end tests that exercise complete user-facing workflows.

| Script | What it tests |
|--------|--------------|
| `test_complete_workflow.sh` | 11 tests: full backup/validate/health-check workflow |
| `test_hidden_files.sh` | 6 tests: hidden file preservation (.secrets, .archive, .backups, .hermes, .env.enc) |
| `test_self_healing.sh` | 11 tests: health_check.sh, fix_permissions, safe_mkdir, with_self_healing retry, .auto-update.sh.backup removed |
| `test_memory_injection.sh` | 10 tests: SOUL/USER/IDENTITY/MEMORY/AGENTS injection, inject-all-memory, memory.sh |

---

## Test Design Principles

1. **Isolated**: Each test creates its own temp directories (`/tmp/`) and cleans up via `trap … EXIT`
2. **Idempotent**: Tests can be run multiple times without side effects
3. **Self-describing**: Every test prints `[TEST] description` before running
4. **Non-destructive**: Tests use `--dry-run`, `--force`, and temp dirs to avoid modifying production data
5. **RUNTIME_ROOT aware**: All tests auto-detect the framework root by walking up until `runtime.sh` is found
6. **No Docker required**: All tests are designed to pass without a running Docker daemon

---

## Test Results Format

```
[TEST] Description of what is being tested
[PASS] What passed ✓
[FAIL] What failed ✗  (to stderr)
[WARN] Non-fatal warning

========================================
Test Summary
========================================
Total Tests: N
Passed:      N
Failed:      N
Time:        Xs
```

---

## Adding New Tests

1. Create `tests/<category>/test_<name>.sh`
2. Make executable: `chmod +x tests/<category>/test_<name>.sh`
3. Use the standard header:
   ```bash
   #!/bin/bash
   set -uo pipefail
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   RUNTIME_ROOT="$SCRIPT_DIR"
   while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/runtime.sh" ]]; do
       RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
   done
   ```
4. Use `pass()`, `fail()`, `run_test()` helpers
5. Add cleanup via `trap cleanup EXIT`
6. Exit 0 on all pass, exit 1 on any fail

The `run_all.sh` runner auto-discovers all `.sh` files in each category directory.

---

## Troubleshooting

### "runtime.sh not found"
Run tests from the repository root: `cd /path/to/hemlock && ./tests/run_all.sh`

### Permission errors
The validation tests auto-fix 700 permissions. If you see errors, run:
```bash
./tests/validation/validate_permissions.sh
```

### Tests leave artifacts
If a test is interrupted (Ctrl+C), temp dirs under `/tmp/` may remain. Clean with:
```bash
rm -rf /tmp/e2e_* /tmp/lifecycle_* /tmp/mem_* /tmp/self_heal_* /tmp/common_lib_* /tmp/create_* /tmp/script_*
```

### Skills validation warnings
Skills warnings (missing optional sections) do not cause test failures — only errors do.
