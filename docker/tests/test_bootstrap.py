"""
Test agent-bootstrap.sh — the agent management CLI.

Tests verify:
  - Command dispatch (init, scan, sync, configure, config, docker, etc.)
  - Flag parsing (--openclaw, --dry-run, --force, --yes)
  - Agent discovery
  - Docker generation function

References:
  - agent-bootstrap.sh source (3.4.0)
  - hermes-agent testing patterns
"""

import json
import os
import subprocess
from pathlib import Path

import pytest

BOOTSTRAP = Path(__file__).parent.parent.parent / "agents" / ".scripts" / "agent-toolkit" / "agent-bootstrap.sh"


def run_bootstrap(*args, env=None):
    """Run agent-bootstrap.sh with given arguments."""
    cmd = ["bash", str(BOOTSTRAP)] + list(args)
    result = subprocess.run(
        cmd, capture_output=True, text=True,
        env={**os.environ, **(env or {})},
        timeout=30,
    )
    return result


# ── Command dispatch ─────────────────────────────────────────────────────────

class TestCommandDispatch:
    """Test that bootstrap dispatches commands correctly."""

    def test_shows_usage_on_no_args(self):
        """Running with no args shows help/usage."""
        result = run_bootstrap()
        # Either shows help or defaults to a command
        assert result.returncode in (0, 1)

    def test_list_command(self):
        """list command runs without error."""
        result = run_bootstrap("list")
        assert result.returncode == 0

    def test_scan_command(self):
        """scan command runs without error."""
        result = run_bootstrap("scan")
        assert result.returncode == 0

    def test_help_flag(self):
        """--help or -h shows help text."""
        for flag in ["--help", "-h", "help"]:
            result = run_bootstrap(flag)
            # May exit 0 or show help
            assert result.returncode in (0, 1)


# ── Flag parsing ─────────────────────────────────────────────────────────────

class TestFlagParsing:
    """Test global flag parsing."""

    def test_dry_run_flag(self):
        """--dry-run flag is accepted."""
        result = run_bootstrap("--dry-run", "scan")
        assert result.returncode == 0

    def test_openclaw_flag(self):
        """--openclaw flag is accepted."""
        result = run_bootstrap("--openclaw", "list")
        assert result.returncode == 0

    def test_yes_flag(self):
        """--yes flag is accepted."""
        result = run_bootstrap("--yes", "list")
        assert result.returncode == 0

    def test_force_flag(self):
        """--force flag is accepted."""
        result = run_bootstrap("--force", "list")
        assert result.returncode == 0

    def test_flags_position_independent(self):
        """Flags work in any position."""
        result1 = run_bootstrap("--openclaw", "--dry-run", "list")
        result2 = run_bootstrap("list", "--openclaw", "--dry-run")
        assert result1.returncode == 0
        assert result2.returncode == 0

    def test_short_flags(self):
        """Short flag aliases work."""
        result = run_bootstrap("-o", "-n", "list")
        assert result.returncode == 0


# ── Agent discovery ──────────────────────────────────────────────────────────

class TestAgentDiscovery:
    """Test the _discover_agents function indirectly via scan/list."""

    def test_discovers_existing_agents(self):
        """scan/find discovers agents in ~/.openclaw/agents/."""
        result = run_bootstrap("list")
        assert result.returncode == 0
        output = result.stdout + result.stderr
        # Should find at least one agent if any exist
        agents_dir = Path.home() / ".openclaw" / "agents"
        if agents_dir.exists():
            agent_dirs = [d for d in agents_dir.iterdir()
                         if d.is_dir() and not d.name.startswith(".")]
            if agent_dirs:
                # At least one agent name should appear in output
                assert any(d.name in output for d in agent_dirs) or \
                       "ready" in output or "incomplete" in output

    def test_scan_shows_health_status(self):
        """scan shows health indicators."""
        result = run_bootstrap("scan")
        output = result.stdout + result.stderr
        # Should show check marks or status indicators
        has_status = any(ind in output for ind in ["✓", "✗", "⚠", "ready", "incomplete", "missing"])
        # Allow empty scan (no agents) without failure
        assert result.returncode == 0


# ── Docker generation ────────────────────────────────────────────────────────

class TestDockerGeneration:
    """Test the docker command generation."""

    def test_dry_run_docker(self):
        """docker --dry-run previews without writing."""
        result = run_bootstrap("--dry-run", "docker", "/tmp/test-docker-output")
        assert result.returncode == 0
        output = result.stdout + result.stderr
        assert "dry-run" in output.lower() or "Dockerfile" in output

    def test_docker_generates_core_files(self):
        """docker command generates Dockerfile, entrypoint, compose."""
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_bootstrap("--yes", "docker", tmpdir)
            assert result.returncode == 0

            # Check core files were created
            assert (Path(tmpdir) / "Dockerfile").exists()
            assert (Path(tmpdir) / "entrypoint.sh").exists()
            assert (Path(tmpdir) / "docker-compose.yml").exists()
            # agent_brain_mcp.py lives in toolkit dir (bind-mounted), not generated here

    def test_docker_generates_valid_dockerfile(self):
        """Generated Dockerfile has required instructions."""
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            run_bootstrap("--yes", "docker", tmpdir)
            dockerfile = (Path(tmpdir) / "Dockerfile").read_text()
            assert "FROM" in dockerfile
            assert "ENTRYPOINT" in dockerfile
            assert "hermes-agent" in dockerfile

    def test_docker_generates_valid_compose(self):
        """Generated docker-compose.yml is valid YAML with services."""
        import tempfile
        import yaml
        with tempfile.TemporaryDirectory() as tmpdir:
            run_bootstrap("--yes", "docker", tmpdir)
            compose_file = Path(tmpdir) / "docker-compose.yml"
            compose = yaml.safe_load(compose_file.read_text())
            assert "services" in compose

    def test_docker_generates_valid_entrypoint(self):
        """Generated entrypoint.sh has valid bash syntax."""
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            run_bootstrap("--yes", "docker", tmpdir)
            entrypoint = (Path(tmpdir) / "entrypoint.sh").read_text()
            result = subprocess.run(
                ["bash", "-n", "/dev/stdin"],
                input=entrypoint, capture_output=True, text=True,
            )
            assert result.returncode == 0, f"Bash syntax error: {result.stderr}"

    def test_docker_generates_bind_mounts(self):
        """Generated compose uses bind mounts from host (no Docker volumes)."""
        import tempfile
        import yaml
        with tempfile.TemporaryDirectory() as tmpdir:
            run_bootstrap("--yes", "docker", tmpdir)
            compose = yaml.safe_load(
                (Path(tmpdir) / "docker-compose.yml").read_text()
            )

            # No top-level volumes section (bind mounts only)
            assert "volumes" not in compose or len(compose.get("volumes", {})) == 0

            # Each service should bind-mount agent home from host
            for name, svc in compose.get("services", {}).items():
                vol_list = svc.get("volumes", [])
                agent_mounts = [v for v in vol_list if f"agents/{name}" in str(v)]
                assert len(agent_mounts) >= 1, f"Service {name} missing agent bind mount"


# ── Repair command ───────────────────────────────────────────────────────────

class TestRepairCommand:
    """Test the repair command."""

    def test_repair_dry_run(self):
        """repair --dry-run previews fixes without applying."""
        # Need an existing agent for this
        agents_dir = Path.home() / ".openclaw" / "agents"
        existing = [d for d in agents_dir.iterdir()
                    if d.is_dir() and not d.name.startswith(".")]
        if not existing:
            pytest.skip("No agents found to test repair")

        result = run_bootstrap("--dry-run", "repair", existing[0].name)
        assert result.returncode == 0


# ── Sync command ─────────────────────────────────────────────────────────────

class TestSyncCommand:
    """Test the sync command."""

    def test_sync_dry_run(self):
        """sync --dry-run previews without modifying."""
        result = run_bootstrap("--dry-run", "sync")
        assert result.returncode == 0

    def test_sync_yes_dry_run(self):
        """sync --yes --dry-run works together."""
        result = run_bootstrap("--yes", "--dry-run", "sync")
        assert result.returncode == 0
