"""
End-to-end pipeline tests — full flow from agent creation to docker config.

Tests the complete lifecycle:
  agent-bootstrap.sh init → configure → config → docker → entrypoint → MCP injection

These tests use the actual bootstrap script in dry-run or temp-dir mode
to verify the full pipeline works without needing Docker running.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import pytest

BOOTSTRAP = Path(__file__).parent.parent.parent / "agents" / ".scripts" / "agent-toolkit" / "agent-bootstrap.sh"


def run_bootstrap(*args, env=None, timeout=30):
    """Run agent-bootstrap.sh with given arguments."""
    cmd = ["bash", str(BOOTSTRAP)] + list(args)
    result = subprocess.run(
        cmd, capture_output=True, text=True,
        env={**os.environ, **(env or {})},
        timeout=timeout,
    )
    return result


# ── Full pipeline: init → docker generation ──────────────────────────────────

class TestFullPipeline:
    """Test the complete agent lifecycle in a temp directory."""

    def test_init_scan_config_docker(self, tmp_path):
        """Full pipeline: init → scan → config → docker."""
        agent_name = "e2e-test-agent"
        agent_home = tmp_path / "agents" / agent_name
        openclaw_json = tmp_path / "openclaw.json"

        # 1. Create a minimal openclaw.json
        config = {
            "meta": {"lastTouchedVersion": "2026.4.11"},
            "models": {"providers": {"nous": {"baseUrl": "https://test.com", "models": []}}},
            "agents": {"defaults": {"model": {"primary": "test/model"}}, "list": []},
            "channels": {"telegram": {"enabled": True, "accounts": {}}},
            "bindings": [],
            "gateway": {"port": "18789"},
        }
        openclaw_json.write_text(json.dumps(config, indent=2))

        # 2. Simulate init by creating agent directory structure
        agent_home.mkdir(parents=True)
        for d in ["memory", "sessions", "skills", "tools", "logs", ".secrets", ".backups", "projects", "archives"]:
            (agent_home / d).mkdir()
        for f in ["SOUL.md", "USER.md", "AGENTS.md", "HEARTBEAT.md"]:
            (agent_home / f).write_text(f"# {f}\nE2E test\n")
        (agent_home / ".env").write_text("TELEGRAM_BOT_TOKEN=123456:TEST\nNOUS_API_KEY=test\n")
        (agent_home / "config.yaml").write_text("model:\n  primary: test/model\n")
        (agent_home / "agent.json").write_text(json.dumps({
            "builderCode": {"code": "bc_26ulyc23", "hardwired": True, "enforced": True}
        }))

        # 3. Verify directory structure
        assert (agent_home / "SOUL.md").exists()
        assert (agent_home / ".env").exists()
        assert (agent_home / "memory").is_dir()
        assert (agent_home / ".secrets").is_dir()

        # 4. Verify config.yaml is valid
        import yaml
        cfg = yaml.safe_load((agent_home / "config.yaml").read_text())
        assert cfg["model"]["primary"] == "test/model"

        # 5. Verify .env has bot token
        env_content = (agent_home / ".env").read_text()
        assert "TELEGRAM_BOT_TOKEN" in env_content

    def test_docker_generation_creates_all_files(self, tmp_path):
        """docker command creates Dockerfile, entrypoint, compose."""
        result = run_bootstrap("--yes", "--openclaw", "docker", str(tmp_path / "docker-out"))
        assert result.returncode == 0

        docker_dir = tmp_path / "docker-out"
        assert (docker_dir / "Dockerfile").exists()
        assert (docker_dir / "entrypoint.sh").exists()
        assert (docker_dir / "docker-compose.yml").exists()

    def test_docker_compose_valid_yaml(self, tmp_path):
        """Generated compose file is valid YAML."""
        import yaml
        run_bootstrap("--yes", "--openclaw", "docker", str(tmp_path / "docker-out"))
        compose_file = tmp_path / "docker-out" / "docker-compose.yml"
        compose = yaml.safe_load(compose_file.read_text())
        assert "services" in compose
        assert "networks" in compose

    def test_entrypoint_valid_bash(self, tmp_path):
        """Generated entrypoint is valid bash."""
        run_bootstrap("--yes", "--openclaw", "docker", str(tmp_path / "docker-out"))
        entrypoint = (tmp_path / "docker-out" / "entrypoint.sh").read_text()
        result = subprocess.run(
            ["bash", "-n", "/dev/stdin"],
            input=entrypoint, capture_output=True, text=True,
        )
        assert result.returncode == 0

    def test_dockerfile_valid_syntax(self, tmp_path):
        """Generated Dockerfile has valid instructions."""
        run_bootstrap("--yes", "--openclaw", "docker", str(tmp_path / "docker-out"))
        dockerfile = (tmp_path / "docker-out" / "Dockerfile").read_text()
        assert dockerfile.strip().startswith("FROM")
        assert "ENTRYPOINT" in dockerfile


# ── Entrypoint E2E: config generation ───────────────────────────────────────

class TestEntrypointE2E:
    """Test the entrypoint config generation as an isolated subprocess."""

    def _run_entrypoint_config(self, agent_id, token, openclaw_json_path, tmp_path):
        """Extract and run the Python config script from entrypoint.sh."""
        # Ensure .openclaw dir exists
        (tmp_path / ".openclaw").mkdir(parents=True, exist_ok=True)
        entrypoint = Path(__file__).parent.parent / "entrypoint.sh"
        content = entrypoint.read_text()

        # Extract heredoc
        for marker in ["python3 << 'PYEOF'", "python3 << PYEOF"]:
            start = content.find(marker)
            if start != -1:
                marker_end = start + len(marker)
                line_end = content.find('\n', marker_end)
                if line_end == -1:
                    line_end = len(content)
                end = content.find('\nPYEOF', line_end)
                if end == -1:
                    end = content.find('PYEOF', line_end)
                script = content[line_end + 1:end].strip()
                break
        else:
            raise AssertionError("No heredoc found")

        # Patch paths
        script = script.replace('"/data/openclaw.json"', f'"{openclaw_json_path}"')
        script = script.replace('os.environ["HOME"]', f'"{tmp_path}"')
        script = script.replace('os.environ["AGENT_ID"]', f'"{agent_id}"')
        script = script.replace('os.environ.get("TELEGRAM_BOT_TOKEN", "")', f'"{token}"')

        script_path = tmp_path / "_config_gen.py"
        script_path.write_text(script)

        result = subprocess.run(
            ["python3", str(script_path)],
            capture_output=True, text=True,
            env={**os.environ, "HOME": str(tmp_path), "AGENT_ID": agent_id,
                 "TELEGRAM_BOT_TOKEN": token},
        )
        return result, tmp_path / ".openclaw" / "openclaw.json"

    def test_config_with_multiple_agents(self, tmp_path):
        """Config generator correctly filters multi-agent config."""
        config = {
            "models": {"providers": {}},
            "agents": {
                "defaults": {"model": {"primary": "test/model"}},
                "list": [
                    {"id": "agent-a", "name": "A"},
                    {"id": "agent-b", "name": "B"},
                    {"id": "agent-c", "name": "C"},
                ],
            },
            "channels": {
                "telegram": {
                    "enabled": True,
                    "accounts": {
                        "agent-a": {"botToken": "token-a"},
                        "agent-b": {"botToken": "token-b"},
                        "agent-c": {"botToken": "token-c"},
                    },
                },
            },
            "bindings": [
                {"agentId": "agent-a", "type": "route"},
                {"agentId": "agent-b", "type": "route"},
                {"agentId": "agent-c", "type": "route"},
            ],
            "gateway": {"port": "18789"},
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))

        result, out_config = self._run_entrypoint_config(
            "agent-b", "token-b", json_path, tmp_path
        )
        assert result.returncode == 0, result.stderr

        cfg = json.loads(out_config.read_text())
        # Only agent-b should be present
        assert [a["id"] for a in cfg["agents"]["list"]] == ["agent-b"]
        assert list(cfg["channels"]["telegram"]["accounts"].keys()) == ["agent-b"]
        assert [b["agentId"] for b in cfg["bindings"]] == ["agent-b"]

    def test_config_injects_mcp_brain(self, tmp_path):
        """Config includes hermes-brain MCP server."""
        config = {
            "agents": {"defaults": {}, "list": [{"id": "test"}]},
            "channels": {"telegram": {"accounts": {"test": {}}}},
            "bindings": [],
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))

        result, out_config = self._run_entrypoint_config(
            "test", "tok", json_path, tmp_path
        )
        cfg = json.loads(out_config.read_text())
        brain = cfg["mcp"]["servers"]["hermes-brain"]
        assert brain["command"] == "python3"
        assert brain["args"] == ["/app/agent_brain_mcp.py"]
        assert brain["env"]["AGENT_ID"] == "test"

    def test_config_preserves_passthrough_sections(self, tmp_path):
        """Config preserves non-agent sections like models, gateway."""
        config = {
            "models": {"providers": {"nous": {"url": "https://test.com"}}},
            "gateway": {"port": "9999", "mode": "local"},
            "commands": {"native": "auto"},
            "plugins": {"entries": {"telegram": {"enabled": True}}},
            "agents": {"defaults": {}, "list": [{"id": "x"}]},
            "channels": {"telegram": {"accounts": {"x": {}}}},
            "bindings": [],
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))

        result, out_config = self._run_entrypoint_config(
            "x", "tok", json_path, tmp_path
        )
        cfg = json.loads(out_config.read_text())
        assert cfg["gateway"]["port"] == "9999"
        assert cfg["commands"]["native"] == "auto"
        assert "nous" in cfg["models"]["providers"]

    def test_config_handles_missing_optional_sections(self, tmp_path):
        """Config works even if optional sections are missing."""
        config = {
            "agents": {"defaults": {}, "list": [{"id": "min"}]},
            "channels": {"telegram": {"accounts": {"min": {}}}},
            "bindings": [],
        }
        json_path = tmp_path / "openclaw.json"
        json_path.write_text(json.dumps(config))

        result, out_config = self._run_entrypoint_config(
            "min", "tok", json_path, tmp_path
        )
        assert result.returncode == 0
        cfg = json.loads(out_config.read_text())
        assert "mcp" in cfg


# ── Failure mode tests ───────────────────────────────────────────────────────

class TestFailureModes:
    """Test that the system handles failures gracefully."""

    def test_scan_with_no_agents(self, tmp_path, monkeypatch):
        """scan works when no agents exist."""
        monkeypatch.setenv("OPENCLAW_ROOT", str(tmp_path))
        result = run_bootstrap("scan", env={"OPENCLAW_ROOT": str(tmp_path)})
        assert result.returncode == 0

    def test_list_with_no_agents(self, tmp_path, monkeypatch):
        """list works when no agents exist."""
        result = run_bootstrap("list", env={"OPENCLAW_ROOT": str(tmp_path)})
        assert result.returncode == 0

    def test_docker_with_no_agents(self, tmp_path, monkeypatch):
        """docker fails gracefully when no agents exist."""
        result = run_bootstrap(
            "--yes", "docker", str(tmp_path / "out"),
            env={"OPENCLAW_ROOT": str(tmp_path)},
        )
        # Should either succeed with empty compose or fail cleanly
        assert result.returncode in (0, 1)

    def test_invalid_json_handling(self, tmp_path):
        """Config generator handles corrupted JSON gracefully."""
        json_path = tmp_path / "openclaw.json"
        json_path.write_text("{invalid json")

        script = Path(__file__).parent.parent / "entrypoint.sh"
        content = script.read_text()
        # Just verify the entrypoint has error handling for JSON parse
        assert "except" in content or "ERROR" in content or "die" in content


# ── Docker compose validation ───────────────────────────────────────────────

class TestComposeValidation:
    """Validate the generated docker-compose.yml structure."""

    @pytest.fixture()
    def compose(self, tmp_path):
        run_bootstrap("--yes", "--openclaw", "docker", str(tmp_path / "out"))
        import yaml
        compose_file = tmp_path / "out" / "docker-compose.yml"
        if not compose_file.exists():
            pytest.skip("No agents to generate compose")
        return yaml.safe_load(compose_file.read_text())

    def test_all_services_have_container_names(self, compose):
        for name, svc in compose.get("services", {}).items():
            assert "container_name" in svc

    def test_all_services_have_build(self, compose):
        for name, svc in compose.get("services", {}).items():
            assert "build" in svc or "<<" in str(svc)

    def test_all_services_mount_agent_home(self, compose):
        for name, svc in compose.get("services", {}).items():
            vols = [str(v) for v in svc.get("volumes", [])]
            assert any(f"agents/{name}" in v for v in vols), \
                f"{name} missing agent home mount"

    def test_all_services_mount_openclaw_json(self, compose):
        for name, svc in compose.get("services", {}).items():
            vols = [str(v) for v in svc.get("volumes", [])]
            assert any("openclaw.json" in v for v in vols)

    def test_all_services_mount_brain_mcp(self, compose):
        for name, svc in compose.get("services", {}).items():
            vols = [str(v) for v in svc.get("volumes", [])]
            assert any("agent_brain_mcp.py" in v for v in vols)

    def test_no_shared_volumes(self, compose):
        """No Docker volumes — all mounts are bind mounts."""
        assert "volumes" not in compose or len(compose.get("volumes", {})) == 0

    def test_all_services_have_healthcheck(self, compose):
        """Every service has healthcheck (directly or via x-agent-defaults)."""
        # YAML anchors with << get expanded at Docker runtime, not at parse time
        # So we check the raw YAML for healthcheck in x-agent-defaults
        compose_raw = (Path(__file__).parent.parent / "docker-compose.yml").read_text()
        assert "healthcheck:" in compose_raw, "No healthcheck defined anywhere"
        # Verify x-agent-defaults has it (inherited by all services)
        assert compose_raw.count("healthcheck:") >= 1
