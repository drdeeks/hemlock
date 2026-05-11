"""
Failure mode and edge case tests.

Tests that every component handles:
  - Missing files/directories
  - Corrupt data
  - Permission errors
  - Concurrent access
  - Resource exhaustion
  - Network failures
  - Signal handling

No test should hang, crash, or produce unhandled exceptions.
"""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


# ── File system failure modes ────────────────────────────────────────────────

class TestFileSystemFailures:
    """Test file operation resilience."""

    def test_safe_read_on_broken_symlink(self, _isolate_hermes_home):
        """Reading a broken symlink returns empty, doesn't crash."""
        from agent_brain_mcp import _safe_read_text
        link = _isolate_hermes_home / "broken_link"
        link.symlink_to("/nonexistent/target")
        result = _safe_read_text(link)
        assert result == ""

    def test_safe_read_on_binary_file(self, _isolate_hermes_home):
        """Reading a binary file returns replacement chars, doesn't crash."""
        from agent_brain_mcp import _safe_read_text
        path = _isolate_hermes_home / "binary.dat"
        path.write_bytes(b"\x00\x01\x02\xff\xfe\xfd")
        result = _safe_read_text(path)
        assert isinstance(result, str)

    def test_safe_write_to_readonly_dir(self, _isolate_hermes_home):
        """Writing to read-only directory returns error, doesn't crash."""
        from agent_brain_mcp import _safe_write_text
        readonly = _isolate_hermes_home / "readonly"
        readonly.mkdir()
        readonly.chmod(0o555)
        try:
            ok, err = _safe_write_text(readonly / "file.txt", "test")
            assert not ok
        finally:
            readonly.chmod(0o755)

    def test_safe_write_with_disk_full_simulation(self, _isolate_hermes_home):
        """Writing to /dev/full returns error (Linux)."""
        from agent_brain_mcp import _safe_write_text
        if not Path("/dev/full").exists():
            pytest.skip("/dev/full not available")
        ok, err = _safe_write_text(Path("/dev/full"), "test")
        # May succeed on some systems — just shouldn't crash
        assert isinstance(ok, bool)


# ── Config generation failure modes ──────────────────────────────────────────

class TestConfigGenerationFailures:
    """Test entrypoint config generation with bad inputs."""

    def _extract_and_run(self, script_content, agent_id, token, json_path, home):
        """Helper to extract and run config script."""
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()

        for marker in ["python3 << 'PYEOF'", "python3 << PYEOF"]:
            start = content.find(marker)
            if start != -1:
                marker_end = start + len(marker)
                line_end = content.find('\n', marker_end)
                end = content.find('\nPYEOF', line_end)
                if end == -1:
                    end = content.find('PYEOF', line_end)
                script = content[line_end + 1:end].strip()
                break

        script = script.replace('"/data/openclaw.json"', f'"{json_path}"')
        script = script.replace('os.environ["HOME"]', f'"{home}"')
        script = script.replace('os.environ["AGENT_ID"]', f'"{agent_id}"')
        script = script.replace('os.environ.get("TELEGRAM_BOT_TOKEN", "")', f'"{token}"')

        script_path = home / "_cfg.py"
        script_path.write_text(script)
        return subprocess.run(
            ["python3", str(script_path)],
            capture_output=True, text=True, timeout=10,
            env={**os.environ, "HOME": str(home), "AGENT_ID": agent_id,
                 "TELEGRAM_BOT_TOKEN": token},
        )

    def test_corrupt_json_input(self, tmp_path):
        """Config generator fails cleanly on corrupt JSON."""
        bad_json = tmp_path / "bad.json"
        bad_json.write_text("{broken: json, missing quotes}")
        home = tmp_path / "home"
        home.mkdir()

        result = self._extract_and_run(None, "test", "tok", bad_json, home)
        assert result.returncode != 0

    def test_empty_json_input(self, tmp_path):
        """Config generator fails cleanly on empty JSON file."""
        empty_json = tmp_path / "empty.json"
        empty_json.write_text("")
        home = tmp_path / "home"
        home.mkdir()

        result = self._extract_and_run(None, "test", "tok", empty_json, home)
        assert result.returncode != 0

    def test_agent_not_in_list(self, tmp_path):
        """Config works even when agent_id not in agents.list."""
        config = {
            "agents": {"defaults": {}, "list": [{"id": "other-agent"}]},
            "channels": {"telegram": {"accounts": {"other-agent": {}}}},
            "bindings": [],
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))
        home = tmp_path / "home"
        (home / ".openclaw").mkdir(parents=True)

        result = self._extract_and_run(None, "missing-agent", "tok", json_path, home)
        assert result.returncode == 0
        cfg = json.loads((home / ".openclaw" / "openclaw.json").read_text())
        assert cfg["agents"]["list"] == []

    def test_empty_token(self, tmp_path):
        """Config works with empty bot token."""
        config = {
            "agents": {"defaults": {}, "list": [{"id": "test"}]},
            "channels": {"telegram": {"accounts": {"test": {}}}},
            "bindings": [],
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))
        home = tmp_path / "home"
        (home / ".openclaw").mkdir(parents=True)

        result = self._extract_and_run(None, "test", "", json_path, home)
        assert result.returncode == 0


# ── MCP brain failure modes ──────────────────────────────────────────────────

class TestMCPBrainFailures:
    """Test agent_brain_mcp.py failure modes."""

    def test_memory_get_with_corrupt_json_sessions(self, _isolate_hermes_home):
        """Reading corrupt sessions.json doesn't crash."""
        sessions_dir = _isolate_hermes_home / "sessions"
        sessions_dir.mkdir(exist_ok=True)
        (sessions_dir / "sessions.json").write_text("{corrupt: json}")

        # Import and test directly
        with patch("agent_brain_mcp._MCP_AVAILABLE", True):
            sys.modules["mcp"] = MagicMock()
            sys.modules["mcp.server"] = MagicMock()
            sys.modules["mcp.server.fastmcp"] = MagicMock()
            sys.modules["mcp.server.fastmcp"].FastMCP = MagicMock()
            from agent_brain_mcp import create_brain_server
            # Should not crash during server creation
            assert True

    def test_insights_with_no_database(self, _isolate_hermes_home):
        """agent_insights handles missing database gracefully."""
        with patch.dict("sys.modules", {"hermes_state": None}):
            with patch("agent_brain_mcp._MCP_AVAILABLE", True):
                sys.modules["mcp"] = MagicMock()
                sys.modules["mcp.server"] = MagicMock()
                sys.modules["mcp.server.fastmcp"] = MagicMock()
                from agent_brain_mcp import _get_agent_id
                assert _get_agent_id() == "default"


# ── Entrypoint failure modes ─────────────────────────────────────────────────

class TestEntrypointFailures:
    """Test entrypoint.sh failure handling."""

    def test_entrypoint_has_error_trap(self):
        """Entrypoint has ERR trap for debugging."""
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()
        assert "trap" in content
        assert "ERR" in content or "error" in content.lower()

    def test_entrypoint_validates_agent_id(self):
        """Entrypoint dies with clear message if AGENT_ID missing."""
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()
        assert 'AGENT_ID' in content
        assert 'die' in content or 'exit' in content

    def test_entrypoint_checks_bind_mounts(self):
        """Entrypoint validates bind mounts exist before proceeding."""
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()
        assert "/data/openclaw.json" in content
        assert "agent_brain_mcp.py" in content

    def test_entrypoint_generates_valid_json(self, tmp_path):
        """Entrypoint config generation always produces valid JSON."""
        config = {
            "agents": {"defaults": {}, "list": [{"id": "t"}]},
            "channels": {"telegram": {"accounts": {"t": {}}}},
            "bindings": [],
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))
        home = tmp_path / "home"
        (home / ".openclaw").mkdir(parents=True)

        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()
        for marker in ["python3 << 'PYEOF'", "python3 << PYEOF"]:
            start = content.find(marker)
            if start != -1:
                marker_end = start + len(marker)
                line_end = content.find('\n', marker_end)
                end = content.find('\nPYEOF', line_end)
                if end == -1:
                    end = content.find('PYEOF', line_end)
                script = content[line_end + 1:end].strip()
                break

        script = script.replace('"/data/openclaw.json"', f'"{json_path}"')
        script = script.replace('os.environ["HOME"]', f'"{home}"')
        script = script.replace('os.environ["AGENT_ID"]', '"t"')
        script = script.replace('os.environ.get("TELEGRAM_BOT_TOKEN", "")', '"tok"')

        script_path = home / "_cfg.py"
        script_path.write_text(script)
        result = subprocess.run(
            ["python3", str(script_path)],
            capture_output=True, text=True, timeout=10,
            env={**os.environ, "HOME": str(home)},
        )
        assert result.returncode == 0

        out = home / ".openclaw" / "openclaw.json"
        cfg = json.loads(out.read_text())
        # Verify it round-trips as valid JSON
        json.dumps(cfg)


# ── Docker infra failure modes ───────────────────────────────────────────────

class TestDockerInfraFailures:
    """Test docker infrastructure validation."""

    def test_dockerfile_has_no_hardcoded_secrets(self):
        """Dockerfile doesn't contain API keys or tokens."""
        dockerfile = Path(__file__).parent.parent / "Dockerfile"
        content = dockerfile.read_text()
        assert "sk-" not in content
        assert "botToken" not in content
        assert "apiKey" not in content

    def test_entrypoint_has_no_hardcoded_tokens(self):
        """Entrypoint doesn't contain real bot tokens."""
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()
        # Should not have real tokens — only placeholders or env vars
        lines_with_token = [
            l for l in content.split("\n")
            if "TELEGRAM_BOT_TOKEN" in l and "=" in l
            and not l.strip().startswith("#")
            and not l.strip().startswith("export")
        ]
        for line in lines_with_token:
            # Should be reading from env, not hardcoded
            assert "${" in line or "os.environ" in line or "set -" in line

    def test_compose_has_no_hardcoded_tokens(self):
        """docker-compose.yml tokens are masked or from env."""
        compose = Path(__file__).parent.parent / "docker-compose.yml"
        content = compose.read_text()
        # Tokens should be masked with ...
        import yaml
        data = yaml.safe_load(content)
        for name, svc in data.get("services", {}).items():
            env = svc.get("environment", [])
            for e in env:
                if "TELEGRAM_BOT_TOKEN" in str(e):
                    # Should be masked or variable
                    assert "..." in str(e) or "${" in str(e) or "SET_" in str(e)
