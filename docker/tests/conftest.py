"""
Shared fixtures for OpenClaw + Hermes Brain MCP test suite.

Follows hermes-agent testing conventions from:
  ~/.hermes/hermes-agent/tests/conftest.py

Key patterns:
  - _isolate_hermes_home: redirects HERMES_HOME to tmp dir
  - mock_config: minimal config dict for unit tests
  - tmp_dir: auto-cleaned temporary directory
"""

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ── Path setup ──────────────────────────────────────────────────────────────
OPENCLAW_DOCKER = Path(__file__).parent.parent  # ~/.openclaw/docker
AGENT_TOOLKIT = Path(__file__).parent.parent.parent / "agents" / ".scripts" / "agent-toolkit"
HERMES_AGENT = Path.home() / ".hermes" / "hermes-agent"

# Add hermes-agent to path for importing hermes modules
if str(HERMES_AGENT) not in sys.path:
    sys.path.insert(0, str(HERMES_AGENT))

# Add TOOLKIT dir first (canonical agent_brain_mcp.py location)
# Then docker dir as fallback
if str(AGENT_TOOLKIT) not in sys.path:
    sys.path.insert(0, str(AGENT_TOOLKIT))
if str(OPENCLAW_DOCKER) not in sys.path:
    sys.path.insert(0, str(OPENCLAW_DOCKER))


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def _isolate_hermes_home(tmp_path, monkeypatch):
    """Redirect HERMES_HOME to a temp dir so tests never touch real data.

    Matches the pattern from hermes-agent/tests/conftest.py::_isolate_hermes_home.
    """
    fake_home = tmp_path / "hermes_test"
    fake_home.mkdir()
    for subdir in ["memory", "sessions", "skills", "tools", "logs",
                    ".secrets", ".backups", "projects", "archives"]:
        (fake_home / subdir).mkdir()
    monkeypatch.setenv("HERMES_HOME", str(fake_home))
    # Avoid leaking real API keys into tests
    for key in ["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "OPENAI_API_KEY",
                 "NOUS_API_KEY", "NOUS_INFERENCE_API_KEY"]:
        monkeypatch.delenv(key, raising=False)
    yield fake_home


@pytest.fixture()
def tmp_dir(tmp_path):
    """Provide a temporary directory that is cleaned up automatically."""
    return tmp_path


@pytest.fixture()
def mock_config():
    """Return a minimal hermes config dict suitable for unit tests.

    Matches hermes-agent/tests/conftest.py::mock_config pattern.
    """
    return {
        "model": {
            "primary": "test/mock-model",
        },
        "tools": {"profile": "coding"},
        "memory": {"enabled": True, "max_chars": 100000},
        "skills": {"enabled": True},
    }


@pytest.fixture()
def fake_agent_home(tmp_path):
    """Create a full fake agent home directory structure.

    Mimics what entrypoint.sh creates in a Docker container.
    """
    agent_id = "test-agent"
    home = tmp_path / "agents" / agent_id
    home.mkdir(parents=True)

    for subdir in ["memory", "sessions", "skills", "tools", "logs",
                    ".secrets", ".backups", "projects", "archives"]:
        (home / subdir).mkdir()

    # Identity files
    for fname in ["SOUL.md", "USER.md", "AGENTS.md", "HEARTBEAT.md",
                   "IDENTITY.md", "TOOLS.md", "MEMORY.md"]:
        (home / fname).write_text(f"# {fname}\nTest content\n")

    # agent.json (builder code)
    (home / "agent.json").write_text(json.dumps({
        "builderCode": {
            "code": "bc_26ulyc23",
            "hex": "0x62635f3236756c79633233",
            "owner": "0x12F1B38DC35AA65B50E5849d02559078953aE24b",
            "hardwired": True,
            "enforced": True,
        }
    }))

    # config.yaml
    (home / "config.yaml").write_text("""
model:
  primary: "test/mock-model"
tools:
  profile: coding
memory:
  enabled: true
  max_chars: 100000
""")

    # .env
    (home / ".env").write_text(
        "TELEGRAM_BOT_TOKEN=123456:TEST-TOKEN\n"
        "NOUS_API_KEY=test-key\n"
    )

    return {"agent_id": agent_id, "home": home, "parent": tmp_path}


@pytest.fixture()
def mock_openai_client():
    """Mock OpenAI client for testing agent_chat without API calls.

    Returns a mock that responds with a simple text completion.
    """
    mock_client = MagicMock()

    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = "Mock response from agent"
    mock_response.choices[0].message.role = "assistant"
    mock_response.choices[0].message.tool_calls = None
    mock_response.choices[0].finish_reason = "stop"
    mock_response.usage.prompt_tokens = 100
    mock_response.usage.completion_tokens = 50
    mock_response.model = "mock-model"

    mock_client.chat.completions.create.return_value = mock_response
    return mock_client


@pytest.fixture()
def openclaw_json(tmp_path):
    """Create a minimal openclaw.json for testing."""
    config = {
        "meta": {"lastTouchedVersion": "2026.4.11"},
        "auth": {"profiles": {}},
        "models": {
            "mode": "merge",
            "providers": {
                "nous": {
                    "baseUrl": "https://inference-api.nousresearch.com/v1",
                    "apiKey": "test-key",
                    "models": [{
                        "id": "xiaomi/mimo-v2-pro",
                        "name": "Test Model",
                        "reasoning": True,
                        "input": ["text"],
                        "contextWindow": 131072,
                        "maxTokens": 16384,
                    }],
                },
            },
        },
        "agents": {
            "defaults": {
                "model": {"primary": "nous/xiaomi/mimo-v2-pro"},
                "workspace": str(tmp_path / "agents"),
            },
            "list": [
                {
                    "id": "test-agent",
                    "name": "Test Agent",
                    "workspace": str(tmp_path / "agents" / "test-agent"),
                    "agentDir": str(tmp_path / "agents" / "test-agent"),
                },
            ],
        },
        "bindings": [
            {
                "type": "route",
                "agentId": "test-agent",
                "match": {"channel": "telegram", "accountId": "test-agent"},
            },
        ],
        "channels": {
            "telegram": {
                "enabled": True,
                "dmPolicy": "pairing",
                "groupPolicy": "allowlist",
                "allowFrom": ["*"],
                "streaming": {"mode": "partial"},
                "accounts": {
                    "test-agent": {
                        "botToken": "123456:TEST-TOKEN",
                        "dmPolicy": "pairing",
                        "groupPolicy": "allowlist",
                        "streaming": {"mode": "partial"},
                    },
                },
            },
        },
        "gateway": {
            "port": "18789",
            "mode": "local",
            "bind": "loopback",
        },
    }
    path = tmp_path / "openclaw.json"
    path.write_text(json.dumps(config, indent=2))
    return path
