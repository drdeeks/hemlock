# Hemlock Enterprise Framework - Test Suite

## Overview

This directory contains comprehensive tests for the Hemlock Enterprise Framework, covering:
- Agent lifecycle management (create, import, export, delete)
- Hidden files/directories support
- Docker build and deployment validation
- Runtime functionality
- Self-healing and health checks

## Directory Structure

```
tests/
├── e2e/                           # End-to-end workflow tests
│   ├── run_tests.sh               # E2E test runner
│   ├── test_agent.sh              # Agent creation and management tests
│   ├── test_complete_workflow.sh  # Complete backup/restore/validation workflow
│   ├── test_hidden_files.sh       # Hidden files preservation tests (NEW)
│   └── TESTING_REPORT.md          # Test reports and results
│
├── integration/                   # Component interaction tests
│   └── test_backup_system.sh      # Backup system integration tests
│
├── unit/                          # Isolated component tests
│   ├── tmp_test_write.txt
│   ├── tmp_writable/
│   └── test_delete_agent.sh       # Agent delete functionality tests (NEW)
│
├── validation/                    # Structure and compliance tests
│   ├── validate_permissions.sh    # File permission validation
│   ├── validate_skills.sh          # Skills directory validation
│   └── validate_structure.sh      # Directory structure validation
│
├── run_all.sh                    # Master test runner
└── README.md                      # This file
```

## New Tests Added

### 1. Hidden Files Support Tests (`tests/e2e/test_hidden_files.sh`)
Tests that hidden files and directories (`.secrets/`, `.hermes/`, `.archive/`, `.backups/`, `.env.enc`) are:
- Preserved during agent import
- Preserved during agent export
- Deleted during agent deletion
- Listed correctly in agent listings

**Test Cases:**
- Test source directory has hidden files
- Import agent preserves hidden files
- Hidden file contents preserved
- Delete agent with hidden files
- Export agent preserves hidden files
- List agents shows imported agent

### 2. Delete Agent Functionality (`tests/unit/test_delete_agent.sh`)
Tests the complete agent deletion workflow:
- Delete via `runtime.sh delete-agent` with `--force` flag
- Error handling for nonexistent agents
- Interactive confirmation skipping with `--force`
- Non-interactive mode behavior
- Runtime.log cleanup

**Test Cases:**
- Create test agent with standard structure
- delete-agent.sh script exists and is executable
- Delete agent via runtime.sh with --force flag
- Delete nonexistent agent returns error
- --force flag skips confirmation prompt
- Delete agent without --force shows confirmation prompt
- Delete removes entries from runtime.log

## Running Tests

### Run All Tests

```bash
# From project root
./tests/run_all.sh

# With specific category
./tests/run_all.sh validation
./tests/run_all.sh unit
./tests/run_all.sh e2e
./tests/run_all.sh integration

# With specific test file
./tests/run_all.sh e2e test_hidden_files.sh
```

### Run Individual Test Suites

```bash
# Hidden Files E2E Tests
./tests/e2e/test_hidden_files.sh

# Delete Agent Unit Tests
./tests/unit/test_delete_agent.sh

# Complete Workflow E2E Tests
./tests/e2e/test_complete_workflow.sh

# Validation Tests
./tests/validation/validate_structure.sh
./tests/validation/validate_permissions.sh
./tests/validation/validate_skills.sh

# Integration Tests
./tests/integration/test_backup_system.sh
```

### Run with Verbose Output

```bash
# Most test scripts support verbose output
bash -x ./tests/e2e/test_hidden_files.sh
```

## Docker Build Tests

### Verify Docker Build Context

```bash
# Test that docker-compose.yml is accessible in build context
docker build -f /tmp/test_dockerfile - . 2>&1 | grep docker-compose

# Quick validation without full build
cat > /tmp/quick_test.dockerfile << 'EOF'
FROM scratch
COPY docker-compose.yml /tmp/
COPY agents/ /tmp/agents/
EOF
docker build -f /tmp/quick_test.dockerfile . 2>&1
```

### Full Framework Build

```bash
# This will take several minutes
make build-framework

# Or with docker build directly
cd /home/ubuntu/projects/hemlock
docker build -t openclaw/enterprise-framework:test -f Dockerfile .
```

## Test Environment Setup

### Prerequisites

- Bash 4.0+
- Docker 20.10+
- Python 3.6+
- Standard Unix utilities (grep, sed, awk, find, etc.)

### Test Data

Tests use temporary directories that are automatically cleaned up:
- `/tmp/test_hidden_source_*` - Source for hidden files tests
- `/tmp/test_hidden_export_*` - Export destination for hidden files tests
- `/tmp/e2e_workflow_test_*` - Workflow test directories

## Expected Results

All tests should pass with:
- ✅ Green `[PASS]`output for successful tests
- ❌ Red `[FAIL]` output for failed tests
- Summary showing total/passed/failed counts

### Sample Output

```
==========================================
E2E Test: Hidden Files Support
==========================================
Test Agent: test-hidden-agent-12345
Source Dir: /tmp/test_hidden_source_12345

[TEST] Test source directory has hidden files
[PASS] Test source has all hidden files/directories
[TEST] Import agent preserves hidden files
[PASS] Agent import preserved all hidden files/directories
[TEST] Hidden file contents preserved
[PASS] All hidden file contents preserved correctly
[TEST] Delete agent with hidden files
[PASS] Agent with hidden files deleted successfully
[TEST] Export agent preserves hidden files
[PASS] Agent export preserved all hidden files/directories
[TEST] List agents shows imported agent
[PASS] List agents shows agent with hidden files

==========================================
Hidden Files Test Summary
==========================================
Total Tests: 6
Passed: 6
Failed: 0
Time: 12s

All Hidden Files tests passed in 12s!
```

## Continuous Integration

For CI/CD pipelines, run:

```bash
#!/bin/bash
set -e

# Clone the repository
cd /home/ubuntu/projects/hemlock

# Run all validation tests (fastest)
./tests/validation/validate_structure.sh
./tests/validation/validate_permissions.sh

# Run unit tests
./tests/unit/test_delete_agent.sh

# Run E2E tests
./tests/e2e/test_hidden_files.sh
# ./tests/e2e/test_complete_workflow.sh  # Longer running

# Build Docker image (remove for PR testing to save time)
# make build-framework
```

## Troubleshooting

### Common Issues

1. **"./runtime.sh: Permission denied"**
   ```bash
   chmod +x runtime.sh
   chmod +x scripts/*.sh
   chmod +x tests/**/*.sh
   ```

2. **"docker-compose.yml not found in build context"**
   ```bash
   # Ensure .dockerignore has exceptions
   grep -q "!docker-compose.yml" .dockerignore || echo "!docker-compose.yml" >> .dockerignore
   grep -q "!Dockerfile" .dockerignore || echo "!Dockerfile" >> .dockerignore
   ```

3. **Hidden files not being imported**
   ```bash
   # Ensure agent-import.sh uses cp -ra with ./
   grep -q 'cp -ra "$SOURCE/\." "$AGENTS_DIR/$TARGET/"' scripts/agent-import.sh
   ```

4. **Tests failing due to missing dependencies**
   ```bash
   # Install required tools
   apt-get update && apt-get install -y curl git jq python3 docker.io
   ```

### Debug Mode

```bash
# Run tests with debugging
bash -x ./tests/e2e/test_hidden_files.sh

# Or set DEBUG environment variable
DEBUG=1 ./tests/run_all.sh
```

## Test Coverage

| Component | Tests | Status |
|-----------|-------|--------|
| Agent Import | Hidden files, standard structure | ✅ Covered |
| Agent Export | Hidden files, configuration | ✅ Covered |
| Agent Delete | --force flag, confirmation, cleanup | ✅ Covered |
| Agent List | Agent visibility | ✅ Covered |
| Docker Build | Context, docker-compose.yml | ✅ Covered |
| Runtime | --help, commands | ✅ Covered |
| Backup | Dry-run, configuration | ✅ Covered |
| Health Check | System status | ✅ Covered |
| Validation | Structure, permissions, skills | ✅ Covered |

## Contributing

When adding new tests:

1. Follow existing naming conventions (`test_<component>.sh`)
2. Use consistent pass/fail/test functions
3. Add cleanup with `trap` for temporary files
4. Test both success and failure cases
5. Update this documentation

### Test Template

```bash
#!/bin/bash
# Test: <Component> - <Feature>

set -uo pipefail

# Setup
PASS=0; FAIL=0; TOTAL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }
test() { echo "[TEST] $1"; TOTAL=$((TOTAL+1)); }

# Run tests
test "Description of test"
# ... test logic ...
pass "Test passed" || fail "Test failed"

# Summary
echo "Passed: $PASS / $TOTAL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
```

## Recent Improvements

### v1.0.0
- Added hidden files support tests
- Added delete agent functionality tests
- Updated test runner to support category filtering
- Added error handling and cleanup in tests
- Improved test output formatting

### Changes from Previous Version
- Fixed tests to handle missing directories gracefully
- Added timeout handling for long-running operations
- Improved test isolation with unique temporary directories
- Added comprehensive error messages
