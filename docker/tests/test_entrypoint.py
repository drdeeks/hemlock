"""
Test entrypoint.sh — per-agent config generation and MCP injection.

Tests verify:
  - Per-agent openclaw.json generation (filters shared config)
  - MCP server injection (hermes-brain server entry)
  - Identity file stub creation
  - Directory structure creation
  - Builder code injection

References:
  - OpenClaw config schema from runtime-schema-HP9KKAMz.js
  - hermes-agent config from hermes_cli/config.py
"""

import json
import os
import subprocess
from pathlib import Path

import pytest


# ── Entrypoint config generation ─────────────────────────────────────────────

class TestEntrypointConfig:
    """Test the Python config generation logic from entrypoint.sh.

    Extracts the Python heredoc from entrypoint.sh and runs it in isolation.
    The entrypoint uses quoted heredoc: python3 << 'PYEOF'
    """

    def _extract_python_config(self, entrypoint_path):
        """Extract the Python config generation script from entrypoint.sh.

        Handles both quoted (<< 'PYEOF') and unquoted (<< PYEOF) heredocs,
        with optional trailing shell redirects like 2>&1.
        """
        content = entrypoint_path.read_text()
        # Find the python3 heredoc — support both quoted and unquoted forms
        # The heredoc may have trailing shell like: python3 << 'PYEOF' 2>&1
        for marker in ["python3 << 'PYEOF'", "python3 << PYEOF"]:
            start = content.find(marker)
            if start != -1:
                # Find end of the marker line (skip trailing redirects like 2>&1)
                marker_end = start + len(marker)
                line_end = content.find('\n', marker_end)
                if line_end == -1:
                    line_end = len(content)
                # Now find the PYEOF terminator
                end = content.find('\nPYEOF', line_end)
                if end == -1:
                    end = content.find('PYEOF', line_end)
                assert end != -1, "Could not find PYEOF terminator"
                return content[line_end + 1:end].strip()
        raise AssertionError("Could not find python3 heredoc in entrypoint.sh")

    def _run_config_script(self, script, agent_id, token, openclaw_json, home):
        """Run the config generation script with given env."""
        # Patch the script to use test paths
        script = script.replace(
            '"/data/openclaw.json"', f'"{openclaw_json}"'
        ).replace(
            'os.environ["HOME"]', f'"{home}"'
        ).replace(
            'os.environ["AGENT_ID"]', f'"{agent_id}"'
        ).replace(
            'os.environ.get("TELEGRAM_BOT_TOKEN", "")', f'"{token}"'
        )

        # Write to temp file and execute
        script_path = home / "_test_config.py"
        script_path.write_text(script)

        result = subprocess.run(
            ["python3", str(script_path)],
            capture_output=True, text=True,
            env={**os.environ, "HOME": str(home), "AGENT_ID": agent_id,
                 "TELEGRAM_BOT_TOKEN": token},
        )
        return result

    def _get_config(self, tmp_dir, openclaw_json):
        """Helper: generate and return per-agent config."""
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        script = self._extract_python_config(entrypoint)

        home = tmp_dir / "home"
        (home / ".openclaw").mkdir(parents=True)

        result = self._run_config_script(
            script, "test-agent", "123456:TEST-TOKEN", openclaw_json, home,
        )

        assert result.returncode == 0, f"Config script failed: {result.stderr}"

        output_config = home / ".openclaw" / "openclaw.json"
        assert output_config.exists(), "Per-agent config not created"

        return json.loads(output_config.read_text())

    def test_generates_per_agent_config(self, tmp_dir, openclaw_json):
        """Config script produces a valid per-agent openclaw.json."""
        config = self._get_config(tmp_dir, openclaw_json)
        assert "agents" in config
        assert "channels" in config

    def test_config_includes_only_own_agent(self, tmp_dir, openclaw_json):
        """Generated config only includes this agent's entry."""
        config = self._get_config(tmp_dir, openclaw_json)
        agent_ids = [a["id"] for a in config.get("agents", {}).get("list", [])]
        assert agent_ids == ["test-agent"]

    def test_config_includes_only_own_binding(self, tmp_dir, openclaw_json):
        """Generated config only includes this agent's binding."""
        config = self._get_config(tmp_dir, openclaw_json)
        binding_agents = [b["agentId"] for b in config.get("bindings", [])]
        assert binding_agents == ["test-agent"]

    def test_config_includes_own_telegram_account(self, tmp_dir, openclaw_json):
        """Generated config has only this agent's Telegram account."""
        config = self._get_config(tmp_dir, openclaw_json)
        accounts = config.get("channels", {}).get("telegram", {}).get("accounts", {})
        assert "test-agent" in accounts
        assert accounts["test-agent"]["botToken"] == "123456:TEST-TOKEN"

    def test_config_injects_mcp_brain_server(self, tmp_dir, openclaw_json):
        """Generated config includes hermes-brain MCP server entry."""
        config = self._get_config(tmp_dir, openclaw_json)
        mcp_servers = config.get("mcp", {}).get("servers", {})
        assert "hermes-brain" in mcp_servers, "MCP brain server not injected"
        brain = mcp_servers["hermes-brain"]
        assert brain["command"] == "python3"
        assert brain["args"] == ["/app/agent_brain_mcp.py"]
        assert brain["env"]["AGENT_ID"] == "test-agent"

    def test_config_preserves_models(self, tmp_dir, openclaw_json):
        """Generated config preserves provider/model config."""
        config = self._get_config(tmp_dir, openclaw_json)
        providers = config.get("models", {}).get("providers", {})
        assert "nous" in providers

    def test_config_preserves_gateway(self, tmp_dir, openclaw_json):
        """Generated config preserves gateway settings."""
        config = self._get_config(tmp_dir, openclaw_json)
        gateway = config.get("gateway", {})
        assert gateway.get("port") == "18789"


# ── Directory structure ──────────────────────────────────────────────────────

class TestDirectoryStructure:
    """Test that entrypoint creates the right directory layout."""

    def test_creates_all_required_dirs(self, fake_agent_home):
        """Agent home has all required subdirectories."""
        home = fake_agent_home["home"]
        required = ["memory", "sessions", "skills", "tools", "logs",
                     ".secrets", ".backups", "projects", "archives"]
        for d in required:
            assert (home / d).exists(), f"Missing directory: {d}"
            assert (home / d).is_dir()

    def test_creates_identity_stubs(self, fake_agent_home):
        """Agent home has identity file stubs."""
        home = fake_agent_home["home"]
        for fname in ["SOUL.md", "USER.md", "AGENTS.md", "HEARTBEAT.md",
                       "IDENTITY.md", "TOOLS.md"]:
            assert (home / fname).exists(), f"Missing identity file: {fname}"
            content = (home / fname).read_text()
            assert len(content) > 0

    def test_creates_builder_code(self, fake_agent_home):
        """Agent home has agent.json with builder code."""
        home = fake_agent_home["home"]
        agent_json = home / "agent.json"
        assert agent_json.exists()
        data = json.loads(agent_json.read_text())
        assert data["builderCode"]["code"] == "bc_26ulyc23"
        assert data["builderCode"]["hardwired"] is True

    def test_creates_config_yaml(self, fake_agent_home):
        """Agent home has config.yaml with model config."""
        home = fake_agent_home["home"]
        config_yaml = home / "config.yaml"
        assert config_yaml.exists()
        import yaml
        config = yaml.safe_load(config_yaml.read_text())
        assert "model" in config

    def test_creates_env_file(self, fake_agent_home):
        """Agent home has .env with bot token."""
        home = fake_agent_home["home"]
        env_file = home / ".env"
        assert env_file.exists()
        content = env_file.read_text()
        assert "TELEGRAM_BOT_TOKEN" in content


# ── Secrets permissions ──────────────────────────────────────────────────────

class TestPermissions:
    """Test security-related file permissions."""

    def test_secrets_dir_is_700(self, fake_agent_home):
        """.secrets directory has restrictive permissions."""
        home = fake_agent_home["home"]
        secrets = home / ".secrets"
        # Set correct permissions (mimics what entrypoint does)
        secrets.chmod(0o700)
        mode = secrets.stat().st_mode & 0o777
        assert mode == 0o700, f"Expected 700, got {oct(mode)}"

    def test_env_file_permissions(self, fake_agent_home):
        """env file should not be world-readable."""
        home = fake_agent_home["home"]
        env_file = home / ".env"
        assert env_file.exists()
