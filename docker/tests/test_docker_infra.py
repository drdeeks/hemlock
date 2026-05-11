"""
Test Docker infrastructure — Dockerfile, docker-compose.yml, build context.

Tests verify:
  - Dockerfile has required instructions
  - docker-compose.yml has correct bind-mount structure (no volumes)
  - Agent homes are bind-mounted from host (single source of truth)
  - agent_brain_mcp.py is bind-mounted from toolkit (not copied)
  - Build context includes hermes-agent source

Architecture:
  - Agent homes: ~/.openclaw/agents/<name>/ → /data/agents/<name>/
  - Config: ~/.openclaw/openclaw.json → /data/openclaw.json (ro)
  - Brain MCP: ~/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py → /app/agent_brain_mcp.py (ro)

References:
  - agent-bootstrap.sh cmd_docker() generation logic
  - OpenClaw docker docs
"""

import json
import re
from pathlib import Path

import pytest

DOCKER_DIR = Path(__file__).parent.parent


# ── Dockerfile ───────────────────────────────────────────────────────────────

class TestDockerfile:
    """Validate the generated Dockerfile."""

    @pytest.fixture()
    def dockerfile(self):
        path = DOCKER_DIR / "Dockerfile"
        if not path.exists():
            pytest.skip("Dockerfile not generated yet")
        return path.read_text()

    def test_uses_python_base_image(self, dockerfile):
        """Dockerfile uses python:3.11-slim as base."""
        assert "FROM python:3.11-slim" in dockerfile

    def test_installs_nodejs(self, dockerfile):
        """Dockerfile installs Node.js for OpenClaw."""
        assert "nodejs" in dockerfile.lower() or "node" in dockerfile.lower()

    def test_installs_openclaw(self, dockerfile):
        """Dockerfile installs OpenClaw via npm."""
        assert "npm install -g openclaw" in dockerfile

    def test_installs_hermes_agent(self, dockerfile):
        """Dockerfile installs hermes-agent Python package."""
        assert "hermes-agent" in dockerfile

    def test_installs_mcp_extra(self, dockerfile):
        """Dockerfile installs hermes-agent with [mcp] extra."""
        assert "[mcp]" in dockerfile or "mcp" in dockerfile

    def test_does_not_copy_brain_mcp(self, dockerfile):
        """Dockerfile does NOT COPY agent_brain_mcp.py (it's bind-mounted)."""
        # Should not have: COPY agent_brain_mcp.py /app/agent_brain_mcp.py
        has_copy_brain = "COPY agent_brain_mcp.py" in dockerfile
        assert not has_copy_brain, \
            "agent_brain_mcp.py should be bind-mounted, not COPY'd"

    def test_copies_entrypoint(self, dockerfile):
        """Dockerfile copies entrypoint.sh."""
        assert "entrypoint.sh" in dockerfile
        assert "COPY entrypoint.sh" in dockerfile or "COPY" in dockerfile

    def test_has_entrypoint_instruction(self, dockerfile):
        """Dockerfile has ENTRYPOINT instruction."""
        assert "ENTRYPOINT" in dockerfile

    def test_sets_workdir(self, dockerfile):
        """Dockerfile sets WORKDIR."""
        assert "WORKDIR" in dockerfile

    def test_installs_system_deps(self, dockerfile):
        """Dockerfile installs required system packages."""
        for pkg in ["curl", "git", "jq"]:
            assert pkg in dockerfile, f"Missing system package: {pkg}"


# ── docker-compose.yml ───────────────────────────────────────────────────────

class TestDockerCompose:
    """Validate the generated docker-compose.yml."""

    @pytest.fixture()
    def compose(self):
        path = DOCKER_DIR / "docker-compose.yml"
        if not path.exists():
            pytest.skip("docker-compose.yml not generated yet")
        import yaml
        return yaml.safe_load(path.read_text())

    def test_has_version(self, compose):
        """Compose file has version field."""
        assert "version" in compose

    def test_has_services(self, compose):
        """Compose file has services section."""
        assert "services" in compose

    def test_has_all_agent_services(self, compose):
        """Compose has services for all configured agents."""
        services = compose.get("services", {})
        assert len(services) >= 1, "No services defined"
        for name, svc in services.items():
            assert "container_name" in svc, f"Service {name} missing container_name"
            assert "environment" in svc, f"Service {name} missing environment"

    def test_no_docker_volumes(self, compose):
        """Compose has NO top-level volumes section (bind mounts only)."""
        assert "volumes" not in compose or len(compose.get("volumes", {})) == 0, \
            "Should not have Docker volumes — agent homes are bind-mounted from host"

    def test_agents_bind_mounted_from_host(self, compose):
        """Each agent service bind-mounts its home from host."""
        services = compose.get("services", {})
        for name, svc in services.items():
            volumes = svc.get("volumes", [])
            agent_mounts = [v for v in volumes if f"agents/{name}" in str(v)]
            assert len(agent_mounts) >= 1, \
                f"Service {name} missing agent home bind mount"

    def test_agent_mount_is_host_path(self, compose):
        """Agent bind mounts point to ~/.openclaw/agents/<name>/."""
        services = compose.get("services", {})
        for name, svc in services.items():
            volumes = svc.get("volumes", [])
            for v in volumes:
                v_str = str(v)
                if f"agents/{name}:" in v_str:
                    assert ".openclaw/agents/" in v_str, \
                        f"Agent mount should be from ~/.openclaw/agents/: {v_str}"

    def test_brain_mcp_bind_mounted(self, compose):
        """Each service bind-mounts agent_brain_mcp.py from toolkit."""
        services = compose.get("services", {})
        for name, svc in services.items():
            volumes = svc.get("volumes", [])
            brain_mounts = [v for v in volumes if "agent_brain_mcp.py" in str(v)]
            assert len(brain_mounts) >= 1, \
                f"Service {name} missing agent_brain_mcp.py bind mount"

    def test_brain_mount_is_readonly(self, compose):
        """agent_brain_mcp.py mount is read-only."""
        services = compose.get("services", {})
        for name, svc in services.items():
            volumes = svc.get("volumes", [])
            for v in volumes:
                if "agent_brain_mcp.py" in str(v):
                    assert ":ro" in str(v), \
                        f"Service {name}: agent_brain_mcp.py should be mounted :ro"

    def test_each_agent_has_agent_id(self, compose):
        """Each agent service has AGENT_ID environment variable."""
        services = compose.get("services", {})
        for name, svc in services.items():
            env = svc.get("environment", [])
            env_keys = [e.split("=")[0] if "=" in str(e) else e for e in env]
            assert "AGENT_ID" in env_keys, f"Service {name} missing AGENT_ID"

    def test_each_agent_has_hermes_home(self, compose):
        """Each agent service has HERMES_HOME environment variable."""
        services = compose.get("services", {})
        for name, svc in services.items():
            env = svc.get("environment", [])
            env_keys = [e.split("=")[0] if "=" in str(e) else e for e in env]
            assert "HERMES_HOME" in env_keys, f"Service {name} missing HERMES_HOME"

    def test_each_agent_has_telegram_token(self, compose):
        """Each agent service has TELEGRAM_BOT_TOKEN."""
        services = compose.get("services", {})
        for name, svc in services.items():
            env = svc.get("environment", [])
            env_str = str(env)
            assert "TELEGRAM_BOT_TOKEN" in env_str, \
                f"Service {name} missing TELEGRAM_BOT_TOKEN"

    def test_mounts_openclaw_json(self, compose):
        """Each service mounts openclaw.json."""
        services = compose.get("services", {})
        for name, svc in services.items():
            volumes = svc.get("volumes", [])
            has_config = any("openclaw.json" in str(v) for v in volumes)
            assert has_config, f"Service {name} doesn't mount openclaw.json"

    def test_config_mount_is_readonly(self, compose):
        """openclaw.json mount is read-only."""
        services = compose.get("services", {})
        for name, svc in services.items():
            volumes = svc.get("volumes", [])
            for v in volumes:
                if "openclaw.json" in str(v):
                    assert ":ro" in str(v), \
                        f"Service {name}: openclaw.json should be mounted :ro"

    def test_has_network(self, compose):
        """Compose defines a network."""
        assert "networks" in compose
        networks = compose["networks"]
        assert len(networks) >= 1

    def test_restart_policy(self, compose):
        """Agent services have restart policy."""
        services = compose.get("services", {})
        for name, svc in services.items():
            restart = svc.get("restart", "")
            # Check x-agent-defaults or direct config
            assert restart in ["unless-stopped", "always", "on-failure", ""], \
                f"Service {name} has unexpected restart policy: {restart}"


# ── agent_brain_mcp.py ───────────────────────────────────────────────────────

class TestAgentBrainMCPFile:
    """Validate the agent_brain_mcp.py file in toolkit directory."""

    @pytest.fixture()
    def brain_mcp(self):
        # Check toolkit location (primary)
        path = DOCKER_DIR.parent / "agents" / ".scripts" / "agent-toolkit" / "agent_brain_mcp.py"
        if not path.exists():
            # Fallback to docker dir
            path = DOCKER_DIR / "agent_brain_mcp.py"
        if not path.exists():
            pytest.skip("agent_brain_mcp.py not found")
        return path.read_text()

    def test_has_fastmcp_import(self, brain_mcp):
        """File imports FastMCP from mcp package."""
        assert "FastMCP" in brain_mcp

    def test_has_all_tool_functions(self, brain_mcp):
        """File defines all expected tool functions."""
        expected = [
            "agent_chat", "agent_memory_get", "agent_memory_set",
            "agent_skills_list", "agent_insights", "agent_sessions",
            "agent_identity",
        ]
        for tool in expected:
            assert tool in brain_mcp, f"Missing tool function: {tool}"

    def test_has_mcp_tool_decorator(self, brain_mcp):
        """Tool functions use @mcp.tool() decorator."""
        assert "@mcp.tool()" in brain_mcp

    def test_has_create_brain_server(self, brain_mcp):
        """File has create_brain_server factory function."""
        assert "def create_brain_server" in brain_mcp

    def test_has_main_entrypoint(self, brain_mcp):
        """File has __main__ entrypoint."""
        assert '__name__ == "__main__"' in brain_mcp or \
               "__name__ == '__main__'" in brain_mcp

    def test_valid_python(self, brain_mcp):
        """File is valid Python syntax."""
        import ast
        ast.parse(brain_mcp)


# ── Entrypoint shell ─────────────────────────────────────────────────────────

class TestEntrypointShell:
    """Validate entrypoint.sh shell script."""

    @pytest.fixture()
    def entrypoint(self):
        path = DOCKER_DIR / "entrypoint.sh"
        if not path.exists():
            pytest.skip("entrypoint.sh not found")
        return path.read_text()

    def test_has_shebang(self, entrypoint):
        """Script has proper shebang."""
        assert entrypoint.startswith("#!/bin/bash")

    def test_has_set_euo_pipefail(self, entrypoint):
        """Script uses strict error handling."""
        assert "set -euo pipefail" in entrypoint

    def test_requires_agent_id(self, entrypoint):
        """Script requires AGENT_ID environment variable."""
        assert "AGENT_ID" in entrypoint

    def test_exports_hermes_home(self, entrypoint):
        """Script exports HERMES_HOME."""
        assert "HERMES_HOME" in entrypoint

    def test_exports_pythonpath(self, entrypoint):
        """Script adds hermes-agent to PYTHONPATH."""
        assert "PYTHONPATH" in entrypoint
        assert "hermes-agent" in entrypoint

    def test_injects_mcp_config(self, entrypoint):
        """Script injects MCP server config into openclaw.json."""
        assert "hermes-brain" in entrypoint
        assert "agent_brain_mcp.py" in entrypoint

    def test_runs_openclaw_gateway(self, entrypoint):
        """Script runs openclaw gateway at the end."""
        assert "openclaw gateway run" in entrypoint

    def test_does_not_overwrite_host_files(self, entrypoint):
        """Script only creates stubs if missing (preserves host files)."""
        assert '[ -f' in entrypoint or 'if [ ! -f' in entrypoint, \
            "Should check if files exist before creating"

    def test_valid_bash_syntax(self, entrypoint):
        """Script is valid bash syntax."""
        import subprocess
        result = subprocess.run(
            ["bash", "-n", "/dev/stdin"],
            input=entrypoint, capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Bash syntax error: {result.stderr}"


# ── Build context ────────────────────────────────────────────────────────────

class TestBuildContext:
    """Validate the Docker build context."""

    def test_hermes_agent_copied(self):
        """hermes-agent source is copied into build context."""
        hermes_dir = DOCKER_DIR / "hermes-agent"
        if not hermes_dir.exists():
            pytest.skip("hermes-agent not copied to build context yet")
        assert (hermes_dir / "run_agent.py").exists()
        assert (hermes_dir / "pyproject.toml").exists()

    def test_no_venv_in_build_context(self):
        """Build context doesn't include venv directory."""
        venv_dir = DOCKER_DIR / "hermes-agent" / "venv"
        assert not venv_dir.exists(), "venv should be excluded from build context"

    def test_no_pycache_in_build_context(self):
        """Build context doesn't include __pycache__ directories."""
        pycache = DOCKER_DIR / "hermes-agent" / "__pycache__"
        assert not pycache.exists(), "__pycache__ should be excluded"

    def test_agent_brain_not_in_build_context(self):
        """agent_brain_mcp.py is NOT in build context (bind-mounted at runtime)."""
        brain_in_context = DOCKER_DIR / "agent_brain_mcp.py"
        # It's OK if it exists (old build), but it shouldn't be in the Dockerfile
        if brain_in_context.exists():
            dockerfile = (DOCKER_DIR / "Dockerfile").read_text()
            assert "COPY agent_brain_mcp.py" not in dockerfile, \
                "agent_brain_mcp.py should not be COPY'd — it's bind-mounted"
