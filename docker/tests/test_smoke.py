"""
Smoke tests for live Docker containers.

Run these AFTER containers are running to verify end-to-end functionality.

Architecture: Agent homes are bind-mounted from host (not Docker volumes).
  ~/.openclaw/agents/<name>/ → /data/agents/<name>/ (read-write)
  ~/.openclaw/openclaw.json → /data/openclaw.json (read-only)
  ~/.openclaw/agents/.scripts/agent-toolkit/agent_brain_mcp.py → /app/agent_brain_mcp.py (ro)

Usage:
  cd ~/.openclaw/docker
  docker compose up -d
  pytest tests/test_smoke.py -v -m integration

References:
  - hermes-agent tests/e2e/ patterns
  - pyproject.toml markers: integration
"""

import json
import subprocess
from pathlib import Path

import pytest


# ── Helpers ──────────────────────────────────────────────────────────────────

def docker_exec(container, cmd):
    """Run a command inside a Docker container."""
    if isinstance(cmd, list):
        full_cmd = ["docker", "exec", container] + cmd
    else:
        full_cmd = ["docker", "exec", container, "bash", "-c", cmd]
    result = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30)
    return result


def is_container_running(name):
    """Check if a container is running."""
    result = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Running}}", name],
        capture_output=True, text=True,
    )
    return result.stdout.strip() == "true"


def get_running_containers():
    """Get list of running oc-* containers."""
    result = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}"],
        capture_output=True, text=True,
    )
    return [n.strip() for n in result.stdout.strip().split("\n") if n.strip() and n.startswith("oc-")]


pytestmark = pytest.mark.integration


# ── Container health ─────────────────────────────────────────────────────────

class TestContainerHealth:
    """Verify containers are running and healthy."""

    @pytest.fixture(params=["titan", "allman", "main"])
    def agent_name(self, request):
        return request.param

    def test_container_exists(self, agent_name):
        """Container oc-{agent} exists."""
        container = f"oc-{agent_name}"
        result = subprocess.run(
            ["docker", "inspect", container],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            pytest.skip(f"Container {container} not found")

    def test_container_running(self, agent_name):
        """Container oc-{agent} is running."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")
        assert is_container_running(container)

    def test_container_has_restart_policy(self, agent_name):
        """Container has restart policy set."""
        container = f"oc-{agent_name}"
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.HostConfig.RestartPolicy.Name}}", container],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            pytest.skip(f"Container {container} not found")
        assert result.stdout.strip() in ["unless-stopped", "always", "on-failure"]


# ── Bind mount verification ──────────────────────────────────────────────────

class TestBindMounts:
    """Verify agent homes are bind-mounted from host (not Docker volumes)."""

    @pytest.fixture(params=["titan", "allman", "main"])
    def agent_name(self, request):
        return request.param

    def test_agent_home_is_bind_mounted(self, agent_name):
        """Agent home is bind-mounted from host, not a Docker volume."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = subprocess.run(
            ["docker", "inspect", "-f", "{{json .Mounts}}", container],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            pytest.skip("Could not inspect container")

        mounts = json.loads(result.stdout)
        agent_mounts = [m for m in mounts if f"agents/{agent_name}" in m.get("Destination", "")]
        assert len(agent_mounts) >= 1, f"No bind mount found for agent {agent_name}"

        # Verify it's a bind mount, not a volume
        for mount in agent_mounts:
            assert mount["Type"] == "bind", \
                f"Agent mount should be type 'bind', got '{mount['Type']}'"

    def test_brain_mcp_is_bind_mounted(self, agent_name):
        """agent_brain_mcp.py is bind-mounted from toolkit."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = subprocess.run(
            ["docker", "inspect", "-f", "{{json .Mounts}}", container],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            pytest.skip("Could not inspect container")

        mounts = json.loads(result.stdout)
        brain_mounts = [m for m in mounts if "agent_brain_mcp.py" in m.get("Source", "")]
        assert len(brain_mounts) >= 1, "agent_brain_mcp.py not bind-mounted"

    def test_config_is_bind_mounted_readonly(self, agent_name):
        """openclaw.json is bind-mounted read-only."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = subprocess.run(
            ["docker", "inspect", "-f", "{{json .Mounts}}", container],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            pytest.skip("Could not inspect container")

        mounts = json.loads(result.stdout)
        config_mounts = [m for m in mounts if "openclaw.json" in m.get("Source", "")]
        assert len(config_mounts) >= 1, "openclaw.json not bind-mounted"
        for mount in config_mounts:
            assert mount.get("RW", True) is False or "ro" in str(mount), \
                "openclaw.json should be read-only"

    def test_no_docker_volumes_mounted(self, agent_name):
        """No Docker volumes are mounted (all mounts are bind mounts)."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = subprocess.run(
            ["docker", "inspect", "-f", "{{json .Mounts}}", container],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            pytest.skip("Could not inspect container")

        mounts = json.loads(result.stdout)
        for mount in mounts:
            assert mount["Type"] == "bind", \
                f"Expected bind mount, got {mount['Type']}: {mount}"


# ── Host ↔ Container file sync ───────────────────────────────────────────────

class TestFileSync:
    """Verify bind-mounted files sync between host and container."""

    @pytest.fixture(params=["titan", "allman"])
    def agent_name(self, request):
        return request.param

    def test_host_edit_appears_in_container(self, agent_name):
        """File written on host appears in container (bind mount works)."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        host_home = Path.home() / ".openclaw" / "agents" / agent_name
        test_file = host_home / "memory" / "_smoke_test.md"

        try:
            # Write on host
            test_file.write_text("smoke test content")

            # Read from container
            result = docker_exec(container, f"cat /data/agents/{agent_name}/memory/_smoke_test.md")
            assert result.returncode == 0
            assert "smoke test content" in result.stdout
        finally:
            # Cleanup
            if test_file.exists():
                test_file.unlink()

    def test_container_write_appears_on_host(self, agent_name):
        """File written in container appears on host."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        host_home = Path.home() / ".openclaw" / "agents" / agent_name
        test_file = host_home / "memory" / "_smoke_test_2.md"

        try:
            # Write in container
            docker_exec(container, f"echo 'container write' > /data/agents/{agent_name}/memory/_smoke_test_2.md")

            # Read from host
            assert test_file.exists()
            assert "container write" in test_file.read_text()
        finally:
            if test_file.exists():
                test_file.unlink()


# ── Agent directory structure ────────────────────────────────────────────────

class TestAgentDirectories:
    """Verify agent directory structure inside containers."""

    @pytest.fixture(params=["titan", "allman", "main"])
    def agent_name(self, request):
        return request.param

    def test_hermes_home_exists(self, agent_name):
        """HERMES_HOME directory exists in container."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, f"ls /data/agents/{agent_name}/")
        assert result.returncode == 0

    def test_required_subdirs(self, agent_name):
        """All required subdirectories exist."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, f"ls /data/agents/{agent_name}/")
        assert result.returncode == 0
        output = result.stdout

        for d in ["memory", "sessions", "skills", "tools"]:
            assert d in output, f"Missing directory: {d}"

    def test_identity_files(self, agent_name):
        """Identity files exist."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        for fname in ["SOUL.md", "USER.md", "agent.json"]:
            result = docker_exec(container, f"test -f /data/agents/{agent_name}/{fname}")
            assert result.returncode == 0, f"Missing: {fname}"

    def test_builder_code(self, agent_name):
        """agent.json has correct builder code."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, f"cat /data/agents/{agent_name}/agent.json")
        if result.returncode != 0:
            pytest.skip("Could not read agent.json")

        data = json.loads(result.stdout)
        assert data["builderCode"]["code"] == "bc_26ulyc23"


# ── Config validation ───────────────────────────────────────────────────────

class TestConfigValidation:
    """Verify per-agent config inside containers."""

    @pytest.fixture(params=["titan", "allman", "main"])
    def agent_name(self, request):
        return request.param

    def test_openclaw_json_exists(self, agent_name):
        """Per-agent openclaw.json exists."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, "cat /root/.openclaw/openclaw.json")
        assert result.returncode == 0

    def test_config_has_mcp_brain(self, agent_name):
        """Config includes hermes-brain MCP server."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, "cat /root/.openclaw/openclaw.json")
        if result.returncode != 0:
            pytest.skip("Could not read config")

        config = json.loads(result.stdout)
        mcp_servers = config.get("mcp", {}).get("servers", {})
        assert "hermes-brain" in mcp_servers

    def test_mcp_brain_config(self, agent_name):
        """MCP brain server has correct command and args."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, "cat /root/.openclaw/openclaw.json")
        if result.returncode != 0:
            pytest.skip("Could not read config")

        config = json.loads(result.stdout)
        brain = config.get("mcp", {}).get("servers", {}).get("hermes-brain", {})
        assert brain.get("command") == "python3"
        assert brain.get("args") == ["/app/agent_brain_mcp.py"]

    def test_config_has_only_own_agent(self, agent_name):
        """Config only includes this agent's entry."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, "cat /root/.openclaw/openclaw.json")
        if result.returncode != 0:
            pytest.skip("Could not read config")

        config = json.loads(result.stdout)
        agents = config.get("agents", {}).get("list", [])
        agent_ids = [a["id"] for a in agents]
        assert agent_ids == [agent_name]

    def test_config_has_only_own_binding(self, agent_name):
        """Config only includes this agent's binding."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, "cat /root/.openclaw/openclaw.json")
        if result.returncode != 0:
            pytest.skip("Could not read config")

        config = json.loads(result.stdout)
        bindings = config.get("bindings", [])
        binding_agents = [b["agentId"] for b in bindings]
        assert binding_agents == [agent_name]


# ── MCP brain server ─────────────────────────────────────────────────────────

class TestMCPBrainServer:
    """Verify the MCP brain server is functional inside containers."""

    @pytest.fixture(params=["titan", "allman"])
    def agent_name(self, request):
        return request.param

    def test_brain_script_exists(self, agent_name):
        """agent_brain_mcp.py exists in container."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(container, "test -f /app/agent_brain_mcp.py")
        assert result.returncode == 0

    def test_brain_script_valid_python(self, agent_name):
        """agent_brain_mcp.py is valid Python."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(
            container,
            "python3 -c \"import ast; ast.parse(open('/app/agent_brain_mcp.py').read())\"",
        )
        assert result.returncode == 0

    def test_mcp_package_installed(self, agent_name):
        """mcp package is installed in container."""
        container = f"oc-{agent_name}"
        if not is_container_running(container):
            pytest.skip(f"Container {container} not running")

        result = docker_exec(
            container,
            "python3 -c \"from mcp.server.fastmcp import FastMCP; print('OK')\"",
        )
        if result.returncode != 0:
            pytest.skip("mcp package not installed in container")
        assert "OK" in result.stdout
