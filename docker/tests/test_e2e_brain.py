"""
End-to-end tests for agent_brain_mcp.py with mocked MCP.

Tests the MCP brain server's tools by mocking the MCP SDK so tests
run without the mcp package installed. Covers every tool function,
error path, edge case, and failure mode.

References:
  - hermes-agent/tests/agent/test_memory_provider.py (fake provider pattern)
  - hermes-agent/tests/run_agent/test_agent_loop.py (mock server pattern)
"""

import json
import os
import sys
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


# ── Mock MCP SDK ─────────────────────────────────────────────────────────────

class FakeFastMCP:
    """Minimal FastMCP mock that captures registered tools."""
    def __init__(self, name, instructions=""):
        self.name = name
        self.instructions = instructions
        self._tools = {}
    def tool(self):
        def decorator(fn):
            self._tools[fn.__name__] = fn
            return fn
        return decorator
    def run(self):
        pass


# ── Helper: get module with patched _HERMES_HOME ─────────────────────────────

def _get_brain_module(fake_home):
    """Import agent_brain_mcp with _HERMES_HOME patched to fake_home."""
    # Ensure MCP mock is available
    for mod_name in ["mcp", "mcp.server", "mcp.server.fastmcp"]:
        if mod_name not in sys.modules or not hasattr(sys.modules[mod_name], 'FastMCP'):
            mock = MagicMock()
            if mod_name == "mcp.server.fastmcp":
                mock.FastMCP = FakeFastMCP
            sys.modules[mod_name] = mock

    # Import/reload module
    import importlib
    _toolkit = Path(__file__).parent.parent.parent / "agents" / ".scripts" / "agent-toolkit"
    if str(_toolkit) not in sys.path:
        sys.path.insert(0, str(_toolkit))

    if "agent_brain_mcp" in sys.modules:
        importlib.reload(sys.modules["agent_brain_mcp"])
    import agent_brain_mcp

    # Patch the module-level _HERMES_HOME
    agent_brain_mcp._HERMES_HOME = fake_home
    agent_brain_mcp._MCP_AVAILABLE = True
    agent_brain_mcp._FastMCP = FakeFastMCP
    return agent_brain_mcp


@pytest.fixture()
def brain_module(_isolate_hermes_home):
    """Provide agent_brain_mcp module with _HERMES_HOME set to test dir."""
    return _get_brain_module(_isolate_hermes_home)


@pytest.fixture()
def server(brain_module, _isolate_hermes_home):
    """Create a brain server with tools pointing to test dir."""
    return brain_module.create_brain_server()


# ── Helper function tests ────────────────────────────────────────────────────

class TestGetAgentId:
    def test_reads_from_env(self, monkeypatch):
        brain = _get_brain_module(Path("/tmp"))
        monkeypatch.setenv("AGENT_ID", "titan")
        assert brain._get_agent_id() == "titan"

    def test_returns_default_when_unset(self, monkeypatch):
        brain = _get_brain_module(Path("/tmp"))
        monkeypatch.delenv("AGENT_ID", raising=False)
        assert brain._get_agent_id() == "default"


class TestGetModel:
    def test_prefers_hermes_model_env(self, monkeypatch, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        monkeypatch.setenv("HERMES_MODEL", "custom/model-v1")
        assert brain._get_model() == "custom/model-v1"

    def test_reads_config_yaml(self, _isolate_hermes_home):
        import yaml
        brain = _get_brain_module(_isolate_hermes_home)
        cfg_path = _isolate_hermes_home / "config.yaml"
        cfg_path.write_text(yaml.dump({"model": {"primary": "from/config"}}))
        assert brain._get_model() == "from/config"

    def test_falls_back_to_anthropic_key(self, monkeypatch, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        monkeypatch.delenv("HERMES_MODEL", raising=False)
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
        assert "anthropic" in brain._get_model()

    def test_returns_default_when_nothing_set(self, monkeypatch, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        monkeypatch.delenv("HERMES_MODEL", raising=False)
        for k in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "NOUS_API_KEY"]:
            monkeypatch.delenv(k, raising=False)
        assert brain._get_model()


class TestGetApiKey:
    def test_reads_from_env(self, monkeypatch, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test123")
        assert brain._get_api_key() == "sk-ant-test123"

    def test_reads_from_env_file(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        (_isolate_hermes_home / ".env").write_text(
            "# Comment\nTELEGRAM_BOT_TOKEN=123:abc\nNOUS_API_KEY=from-env-file\n"
        )
        assert brain._get_api_key() == "from-env-file"

    def test_returns_none_when_nothing(self, monkeypatch, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        for k in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "NOUS_API_KEY",
                   "NOUS_INFERENCE_API_KEY", "OPENROUTER_API_KEY"]:
            monkeypatch.delenv(k, raising=False)
        assert brain._get_api_key() is None


class TestValidateFilename:
    def test_accepts_simple(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        ok, _ = brain._validate_filename("notes.md")
        assert ok

    def test_rejects_traversal(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        ok, err = brain._validate_filename("../../etc/passwd")
        assert not ok

    def test_rejects_absolute(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        ok, _ = brain._validate_filename("/etc/passwd")
        assert not ok

    def test_rejects_unsafe_chars(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        ok, _ = brain._validate_filename("file;rm -rf /")
        assert not ok


class TestSafeReadWrite:
    def test_read_existing(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        path = _isolate_hermes_home / "test.md"
        path.write_text("hello")
        assert brain._safe_read_text(path) == "hello"

    def test_read_missing(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        assert brain._safe_read_text(_isolate_hermes_home / "nope.md") == ""

    def test_write_creates_parents(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        path = _isolate_hermes_home / "sub" / "file.md"
        ok, _ = brain._safe_write_text(path, "data")
        assert ok and path.exists()


class TestClamp:
    def test_clamp(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        assert brain._clamp(5, 1, 10) == 5
        assert brain._clamp(0, 1, 10) == 1
        assert brain._clamp(15, 1, 10) == 10


class TestDiagnostics:
    def test_returns_all_fields(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        diag = brain._diagnose_startup()
        assert "agent_id" in diag
        assert "issues" in diag

    def test_detects_missing_soul(self, _isolate_hermes_home):
        brain = _get_brain_module(_isolate_hermes_home)
        (_isolate_hermes_home / "SOUL.md").unlink(missing_ok=True)
        diag = brain._diagnose_startup()
        assert any("SOUL.md" in i for i in diag["issues"])


# ── MCP tool tests ───────────────────────────────────────────────────────────

class TestMCPToolMemoryGet:
    def test_returns_memory_md(self, server, _isolate_hermes_home):
        (_isolate_hermes_home / "MEMORY.md").write_text("# Memory\nPrefers dark mode\n")
        result = json.loads(server._tools["agent_memory_get"]())
        assert result["count"] >= 1

    def test_filters_by_query(self, server, _isolate_hermes_home):
        (_isolate_hermes_home / "MEMORY.md").write_text("Uses PostgreSQL")
        (_isolate_hermes_home / "memory" / "prefs.md").write_text("Prefers VS Code")
        result = json.loads(server._tools["agent_memory_get"](query="postgres"))
        assert result["count"] == 1

    def test_returns_empty(self, server, _isolate_hermes_home):
        result = json.loads(server._tools["agent_memory_get"]())
        assert result["count"] == 0


class TestMCPToolMemorySet:
    def test_appends_to_memory_md(self, server, _isolate_hermes_home):
        (_isolate_hermes_home / "MEMORY.md").write_text("# Existing\n")
        result = json.loads(server._tools["agent_memory_set"]("New fact"))
        assert result.get("ok") is True

    def test_creates_named_file(self, server, _isolate_hermes_home):
        result = json.loads(server._tools["agent_memory_set"]("data", filename="notes"))
        assert result.get("ok") is True
        assert (_isolate_hermes_home / "memory" / "notes.md").exists()

    def test_rejects_empty(self, server):
        result = json.loads(server._tools["agent_memory_set"](""))
        assert "error" in result

    def test_rejects_traversal(self, server):
        result = json.loads(server._tools["agent_memory_set"]("x", filename="../../etc/passwd"))
        assert "error" in result


class TestMCPToolSkillsList:
    def test_lists_skills(self, server, _isolate_hermes_home):
        d = _isolate_hermes_home / "skills" / "github"
        d.mkdir()
        (d / "SKILL.md").write_text("# GitHub\nManage repos.\n")
        result = json.loads(server._tools["agent_skills_list"]())
        assert result["count"] == 1
        assert result["skills"][0]["name"] == "github"

    def test_empty_dir(self, server):
        result = json.loads(server._tools["agent_skills_list"]())
        assert result["count"] == 0


class TestMCPToolSessions:
    def test_from_json(self, server, _isolate_hermes_home):
        sd = _isolate_hermes_home / "sessions"
        sd.mkdir(exist_ok=True)
        (sd / "sessions.json").write_text(json.dumps({"tg:1": {"platform": "tg"}}))
        result = json.loads(server._tools["agent_sessions"]())
        assert result["count"] >= 1

    def test_from_jsonl(self, server, _isolate_hermes_home):
        sd = _isolate_hermes_home / "sessions"
        sd.mkdir(exist_ok=True)
        (sd / "s1.jsonl").write_text("{}\n")
        result = json.loads(server._tools["agent_sessions"]())
        assert result["count"] == 1


class TestMCPToolIdentity:
    def test_returns_identity(self, server, _isolate_hermes_home):
        (_isolate_hermes_home / "SOUL.md").write_text("# Soul\nYou are helpful.\n")
        result = json.loads(server._tools["agent_identity"]())
        assert "soul" in result
        assert "helpful" in result["soul"]


class TestMCPToolChat:
    def test_rejects_empty(self, server):
        result = json.loads(server._tools["agent_chat"](""))
        assert "error" in result

    def test_rejects_whitespace(self, server):
        result = json.loads(server._tools["agent_chat"]("   \n  "))
        assert "error" in result

    def test_handles_import_error(self, server):
        with patch.dict("sys.modules", {"run_agent": None}):
            result = json.loads(server._tools["agent_chat"]("test"))
            assert "error" in result


class TestMCPToolInsights:
    def test_handles_import_error(self, server):
        with patch.dict("sys.modules", {"hermes_state": None}):
            result = json.loads(server._tools["agent_insights"]())
            assert "error" in result
