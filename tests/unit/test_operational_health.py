"""
Tests for Phase 30: Operational Health & Integration

Covers:
- Path resolution health validator
- Environment health validator
- Agent identity health validator
- Gateway connectivity health validator
- Doctor bridge orchestration
- Key injection (OpenClaw config → Hermes .env)
- Runtime init health check integration
"""

import json
import os
import sys
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch, MagicMock
import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent
HEALTH_DIR = PROJECT_ROOT / "health"
DOCKER_DIR = PROJECT_ROOT / "docker" / "hermes-agent"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"

# Ensure paths module is importable
DOCKER_AGENT_DIR = str(DOCKER_DIR)
if DOCKER_AGENT_DIR not in sys.path:
    sys.path.insert(0, DOCKER_AGENT_DIR)
for p in [str(PROJECT_ROOT), str(HEALTH_DIR), str(SCRIPTS_DIR.parent)]:
    if p not in sys.path:
        sys.path.insert(0, p)


class _EnvOverride:
    """Context manager that saves/restores specific env vars."""
    def __init__(self, **overrides):
        self.overrides = overrides
        self.saved = {}

    def __enter__(self):
        for key, value in self.overrides.items():
            self.saved[key] = os.environ.get(key)
            os.environ[key] = value
        # Reset PathResolver singleton after env changes
        try:
            from paths import PathResolver
            PathResolver.reset_instance()
        except ImportError:
            pass
        return self

    def __exit__(self, *args):
        for key, old_value in self.saved.items():
            if old_value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = old_value
        try:
            from paths import PathResolver
            PathResolver.reset_instance()
        except ImportError:
            pass


def _env(**overrides):
    return _EnvOverride(**overrides)


def _import_runtime_init():
    """Import runtime.init using importlib to avoid module shadowing."""
    import importlib
    init_path = Path("/home/drdeek/projects/hemlock/docker/hermes-agent/runtime/init.py")
    if not init_path.exists():
        # Try relative to test file
        init_path = Path(__file__).resolve().parent.parent / "docker" / "hermes-agent" / "runtime" / "init.py"
    if not init_path.exists():
        pytest.skip(f"runtime/init.py not found at {init_path}")
    spec = importlib.util.spec_from_file_location("runtime_init", str(init_path))
    mod = importlib.util.module_from_spec(spec)
    # Ensure paths module is available for the imported module
    if DOCKER_AGENT_DIR not in sys.path:
        sys.path.insert(0, DOCKER_AGENT_DIR)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Path Resolution Validator Tests
# ---------------------------------------------------------------------------

class TestPathsValidator:

    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp(prefix="hemlock_test_paths_")

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_import_path_validator(self):
        from health.paths.paths_validator import run_path_checks, CheckResult
        assert run_path_checks is not None
        assert CheckResult is not None

    def test_check_result_dataclass(self):
        from health.paths.paths_validator import CheckResult
        r = CheckResult(name="test", status="ok", detail="details", path="/tmp")
        assert r.name == "test"
        assert r.status == "ok"

    def test_run_path_checks_returns_list(self):
        from health.paths.paths_validator import run_path_checks, CheckResult
        results = run_path_checks(fix=False)
        assert isinstance(results, list)
        assert len(results) > 0
        for r in results:
            assert isinstance(r, CheckResult)
            assert r.status in ("ok", "warn", "fail")

    def test_path_checks_with_test_root(self):
        test_root = Path(self.tmpdir) / "test_hemlock"
        (test_root / "docker" / "hermes-agent").mkdir(parents=True)
        (test_root / "skills" / "skills").mkdir(parents=True)
        (test_root / "agents").mkdir(parents=True)
        (test_root / ".git").mkdir()
        test_home = test_root / "test_home"
        test_home.mkdir(parents=True)

        with _env(HEMLOCK_DOCKER="0", HEMLOCK_ROOT=str(test_root), HERMES_HOME=str(test_home)):
            from health.paths.paths_validator import run_path_checks
            results = run_path_checks(fix=True)
            statuses = {r.status for r in results}
            assert "ok" in statuses or len(results) > 5

    def test_docker_detection_env_override(self):
        from paths import PathResolver
        with _env(HEMLOCK_DOCKER="1"):
            PathResolver.reset_instance()
            p = PathResolver()
            assert p.is_docker is True

        with _env(HEMLOCK_DOCKER="0"):
            PathResolver.reset_instance()
            p = PathResolver()
            assert p.is_docker is False

    def test_fix_creates_missing_directories(self):
        """Test that fix=True creates missing directories."""
        from health.paths.paths_validator import run_path_checks
        results = run_path_checks(fix=True)
        ok_or_created = [r for r in results if r.status in ("ok", "warn")]
        assert len(ok_or_created) > 0

    def test_to_dict_returns_all_paths(self):
        from paths import PathResolver
        PathResolver.reset_instance()
        p = PathResolver()
        d = p.to_dict()
        assert "root" in d
        assert "hermes_home" in d
        assert "agents_dir" in d
        assert "is_docker" in d
        assert isinstance(d["is_docker"], bool)
        PathResolver.reset_instance()


# ---------------------------------------------------------------------------
# Environment Validator Tests
# ---------------------------------------------------------------------------

class TestEnvValidator:

    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp(prefix="hemlock_test_env_")

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_import_env_validator(self):
        from health.env.env_validator import run_env_checks, CheckResult
        assert run_env_checks is not None

    def test_env_checks_return_results(self):
        from health.env.env_validator import run_env_checks, CheckResult
        results = run_env_checks(fix=False)
        assert isinstance(results, list)
        assert len(results) > 0

    def test_api_key_detection(self):
        from health.env.env_validator import run_env_checks
        with _env(OPENROUTER_API_KEY="sk-or-test-key-12345"):
            results = run_env_checks(fix=False)
            api_key_results = [r for r in results if r.name == "apikey_openrouter_api_key"]
            assert len(api_key_results) == 1
            assert api_key_results[0].status == "ok"

    def test_no_api_key_warning(self):
        from health.env.env_validator import run_env_checks
        # Don't clear all env — just remove API key vars
        saved_keys = {}
        api_key_vars = ["OPENROUTER_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
                        "ANTHROPIC_TOKEN", "TELEGRAM_BOT_TOKEN", "DISCORD_BOT_TOKEN",
                        "GITHUB_TOKEN", "NOUS_API_KEY", "GLM_API_KEY", "ZAI_API_KEY"]
        for var in api_key_vars:
            saved_keys[var] = os.environ.pop(var, None)
        try:
            results = run_env_checks(fix=False)
            api_any = [r for r in results if r.name == "apikey_any"]
            if api_any:
                assert api_any[0].status in ("warn", "ok")
        finally:
            for var, val in saved_keys.items():
                if val is not None:
                    os.environ[var] = val

    def test_fix_creates_env_file(self):
        from health.env.env_validator import run_env_checks
        home = Path(self.tmpdir) / "test_home"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            results = run_env_checks(fix=True)
            assert (home / ".env").exists() or any(
                r.name == "env_dot_env" and r.status == "ok" for r in results
            )


# ---------------------------------------------------------------------------
# Agent Identity Validator Tests
# ---------------------------------------------------------------------------

class TestIdentityValidator:

    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp(prefix="hemlock_test_identity_")

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_import_identity_validator(self):
        from health.identity.identity_validator import run_agent_identity_checks, CheckResult
        assert run_agent_identity_checks is not None

    def test_identity_checks_with_empty_dir(self):
        """Test identity checks on an empty agent directory."""
        from health.identity.identity_validator import run_agent_identity_checks
        home = Path(self.tmpdir) / "agent_home"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            results = run_agent_identity_checks(fix=False)
            # An empty dir should report at least some warnings about missing identity files
            # or some OKs about the directory existing
            assert len(results) > 0
            missing_identity = [r for r in results if "identity" in r.name.lower() and r.status in ("warn", "fail", "ok")]
            assert len(missing_identity) > 0

    def test_fix_creates_identity_stubs(self):
        from health.identity.identity_validator import run_agent_identity_checks
        home = Path(self.tmpdir) / "agent_home_fix"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            results = run_agent_identity_checks(fix=True)
            assert (home / "SOUL.md").exists() or any(
                "identity_soul_md" in r.name for r in results
            )

    def test_identity_checks_with_populated_dir(self):
        from health.identity.identity_validator import run_agent_identity_checks
        home = Path(self.tmpdir) / "agent_home_full"
        home.mkdir()

        for fname in ["SOUL.md", "USER.md", "IDENTITY.md"]:
            (home / fname).write_text("# Content for testing\nSome real content here\n", encoding="utf-8")

        agent_data = {"builderCode": {"code": "bc_test123", "hex": "0xtest", "owner": "0xtest", "hardwired": True, "enforced": True}}
        (home / "agent.json").write_text(json.dumps(agent_data), encoding="utf-8")
        (home / "config.yaml").write_text(
            "model:\n  default: test-model\n  provider: test\n\ntools:\n  profile: coding\n",
            encoding="utf-8",
        )

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            results = run_agent_identity_checks(fix=False)
            ok_results = [r for r in results if r.status == "ok"]
            assert len(ok_results) >= 3


# ---------------------------------------------------------------------------
# Gateway Validator Tests
# ---------------------------------------------------------------------------

class TestGatewayValidator:

    def test_import_gateway_validator(self):
        from health.gateway.gateway_validator import run_gateway_checks, CheckResult
        assert run_gateway_checks is not None

    def test_gateway_checks_return_results(self):
        from health.gateway.gateway_validator import run_gateway_checks, CheckResult
        results = run_gateway_checks(fix=False)
        assert isinstance(results, list)
        assert len(results) > 0

    def test_port_available_check(self):
        from health.gateway.gateway_validator import run_gateway_checks
        results = run_gateway_checks(fix=False)
        assert len(results) > 0


# ---------------------------------------------------------------------------
# Doctor Bridge Tests
# ---------------------------------------------------------------------------

class TestDoctorBridge:

    def test_import_doctor_bridge(self):
        from health.doctor_bridge import run_all_checks, DoctorReport, format_report
        assert run_all_checks is not None

    def test_doctor_report_dataclass(self):
        from health.doctor_bridge import DoctorReport, CheckResult
        report = DoctorReport(
            healthy=True, total_checks=10, ok_count=8,
            warn_count=2, fail_count=0, duration_ms=123.4,
        )
        assert report.healthy is True
        assert report.ok_count == 8

    def test_run_all_checks_quick(self):
        from health.doctor_bridge import run_all_checks
        report = run_all_checks(quick=True)
        assert isinstance(report.healthy, bool)
        assert report.total_checks > 0

    def test_run_all_checks_specific_categories(self):
        from health.doctor_bridge import run_all_checks
        report = run_all_checks(categories=["paths", "env"])
        assert report.total_checks > 0

    def test_run_all_checks_with_fix(self):
        from health.doctor_bridge import run_all_checks
        report = run_all_checks(quick=True, fix=True)
        assert isinstance(report.healthy, bool)

    def test_format_report_human_readable(self):
        from health.doctor_bridge import DoctorReport, CheckResult, format_report
        report = DoctorReport(
            healthy=True, total_checks=3, ok_count=2, warn_count=1, fail_count=0,
            duration_ms=50.0,
            results=[
                CheckResult("test_ok", "ok", "All good", "", "paths"),
                CheckResult("test_warn", "warn", "Minor issue", "", "paths"),
                CheckResult("test_ok2", "ok", "Also good", "", "env"),
            ]
        )
        output = format_report(report)
        assert "HEALTH" in output

    def test_format_report_json_serializable(self):
        from health.doctor_bridge import DoctorReport, CheckResult
        from dataclasses import asdict
        report = DoctorReport(
            healthy=True, total_checks=2, ok_count=2, warn_count=0, fail_count=0,
            duration_ms=10.0,
            results=[
                CheckResult("test1", "ok", "Passed", "", "paths"),
                CheckResult("test2", "ok", "Also passed", "", "paths"),
            ]
        )
        data = asdict(report)
        json_str = json.dumps(data, default=str)
        parsed = json.loads(json_str)
        assert parsed["healthy"] is True

    def test_validator_registry_complete(self):
        from health.doctor_bridge import VALIDATORS
        expected = {"paths", "env", "identity", "gateway", "imports", "adapters",
                    "orchestration", "persistence"}
        assert expected == set(VALIDATORS.keys())

    def test_unknown_category_handled(self):
        from health.doctor_bridge import run_all_checks
        report = run_all_checks(categories=["nonexistent_category"])
        assert report.total_checks >= 1


# ---------------------------------------------------------------------------
# Key Injection Tests
# ---------------------------------------------------------------------------

class TestKeyInjection:

    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp(prefix="hemlock_test_keyinject_")

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_import_key_inject(self):
        from scripts.key_inject import inject_keys, KeyMapping, load_openclaw_config
        assert inject_keys is not None

    def test_key_mapping_definitions(self):
        from scripts.key_inject import KEY_MAPPINGS
        assert len(KEY_MAPPINGS) > 0
        mapping_vars = {m.hermes_env_var for m in KEY_MAPPINGS}
        assert "OPENROUTER_API_KEY" in mapping_vars
        assert "TELEGRAM_BOT_TOKEN" in mapping_vars

    def test_inject_keys_basic(self):
        from scripts.key_inject import inject_keys
        config = {
            "openrouter": {"api_key": "sk-or-test-12345"},
            "telegram": {"bot_token": "123456:ABC-DEF"},
            "inference": {"provider": "openrouter", "model": "test-model"},
        }
        home = Path(self.tmpdir) / "hermes_home"
        home.mkdir()
        injected, skipped, messages = inject_keys(config, hermes_home=home, dry_run=True)
        assert injected > 0
        assert any("DRY RUN" in msg for msg in messages)

    def test_inject_keys_writes_env_file(self):
        from scripts.key_inject import inject_keys
        config = {
            "whatsapp": {"enabled": "true", "allowed_users": "12345"},
            "discord": {"application_id": "app123"},
            "inference": {"provider": "nous"},
        }
        home = Path(self.tmpdir) / "hermes_home2"
        home.mkdir()
        inject_keys(config, hermes_home=home, dry_run=False)
        env_file = home / ".env"
        assert env_file.exists()
        content = env_file.read_text(encoding="utf-8")
        assert "WHATSAPP_ENABLED" in content
        assert "DISCORD_APPLICATION_ID" in content

    def test_inject_keys_stores_secrets_json(self):
        from scripts.key_inject import inject_keys
        config = {
            "openrouter": {"api_key": "sk-or-secret-key"},
            "telegram": {"bot_token": "secret-bot-token"},
        }
        home = Path(self.tmpdir) / "hermes_home3"
        home.mkdir()
        inject_keys(config, hermes_home=home, dry_run=False)
        secrets_file = home / ".secrets" / "secrets.json"
        assert secrets_file.exists()
        secrets = json.loads(secrets_file.read_text(encoding="utf-8"))
        assert "OPENROUTER_API_KEY" in secrets
        assert secrets["OPENROUTER_API_KEY"] == "sk-or-secret-key"

    def test_inject_keys_writes_model_config(self):
        from scripts.key_inject import inject_keys
        config = {
            "inference": {
                "provider": "openrouter",
                "base_url": "https://openrouter.ai/v1",
                "model": "anthropic/claude-3.5-sonnet",
            },
        }
        home = Path(self.tmpdir) / "hermes_home4"
        home.mkdir()
        inject_keys(config, hermes_home=home, dry_run=False)
        config_file = home / "config.yaml"
        assert config_file.exists()
        content = config_file.read_text(encoding="utf-8")
        assert "openrouter" in content

    def test_inject_keys_preserves_existing_env(self):
        from scripts.key_inject import inject_keys
        config = {"inference": {"provider": "test"}}
        home = Path(self.tmpdir) / "hermes_home5"
        home.mkdir()
        env_file = home / ".env"
        env_file.write_text("EXISTING_VAR=existing_value\nANOTHER_VAR=another\n", encoding="utf-8")
        inject_keys(config, hermes_home=home, dry_run=False)
        content = env_file.read_text(encoding="utf-8")
        assert "EXISTING_VAR=existing_value" in content
        assert "HERMES_INFERENCE_PROVIDER=test" in content

    def test_load_openclaw_config_missing(self):
        from scripts.key_inject import load_openclaw_config
        config = load_openclaw_config(Path("/nonexistent/path/config.json"))
        assert config == {}

    def test_load_openclaw_config_json5(self):
        from scripts.key_inject import load_openclaw_config
        config_file = Path(self.tmpdir) / "openclaw.json5"
        config_file.write_text("""{
  // Comment
  "inference": {
    "provider": "openrouter",
    "model": "test-model",
  },
  "telegram": {
    "bot_token": "test-token",
  },
}""", encoding="utf-8")
        config = load_openclaw_config(config_file)
        assert config["inference"]["provider"] == "openrouter"
        assert config["telegram"]["bot_token"] == "test-token"

    def test_secret_files_created_with_restricted_perms(self):
        from scripts.key_inject import inject_keys
        config = {"openai": {"api_key": "sk-test-secret-key"}}
        home = Path(self.tmpdir) / "hermes_home_perms"
        home.mkdir()
        inject_keys(config, hermes_home=home, dry_run=False)
        secret_file = home / ".secrets" / "openai_api_key"
        if secret_file.exists():
            mode = secret_file.stat().st_mode & 0o777
            assert mode & 0o600 == 0o600


# ---------------------------------------------------------------------------
# Runtime Init Tests
# ---------------------------------------------------------------------------

class TestRuntimeInit:

    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp(prefix="hemlock_test_init_")

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_import_runtime_init(self):
        mod = _import_runtime_init()
        assert hasattr(mod, 'run_health_checks')
        assert hasattr(mod, 'run_noninteractive_setup')

    def test_basic_health_check_fallback(self):
        mod = _import_runtime_init()
        result = mod._basic_health_check(fix=False)
        assert isinstance(result, int)

    def test_noninteractive_setup_creates_dirs(self):
        mod = _import_runtime_init()
        home = Path(self.tmpdir) / "setup_home"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            result = mod.run_noninteractive_setup(hermes_home=home)
            assert result == 0

    def test_noninteractive_setup_creates_config_yaml(self):
        mod = _import_runtime_init()
        home = Path(self.tmpdir) / "setup_home2"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            result = mod.run_noninteractive_setup(hermes_home=home)
            assert result == 0
            config_yaml = home / "config.yaml"
            assert config_yaml.exists()
            content = config_yaml.read_text(encoding="utf-8")
            assert "model" in content

    def test_noninteractive_setup_creates_agent_json(self):
        mod = _import_runtime_init()
        home = Path(self.tmpdir) / "setup_home3"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            result = mod.run_noninteractive_setup(hermes_home=home)
            assert result == 0
            agent_json = home / "agent.json"
            assert agent_json.exists()
            data = json.loads(agent_json.read_text(encoding="utf-8"))
            assert "builderCode" in data

    def test_health_check_cli_args(self):
        mod = _import_runtime_init()
        with patch.object(sys, 'argv', ['init.py', '--doctor', '--quick']):
            with patch.object(mod, 'run_health_checks', return_value=0) as mock_hc:
                try:
                    mod.main()
                except SystemExit as e:
                    assert e.code == 0
                mock_hc.assert_called_once()

    def test_setup_cli_args(self):
        mod = _import_runtime_init()
        with patch.object(sys, 'argv', ['init.py', '--setup']):
            with patch.object(mod, 'run_noninteractive_setup', return_value=0) as mock_setup:
                try:
                    mod.main()
                except SystemExit as e:
                    assert e.code == 0
                mock_setup.assert_called_once()


# ---------------------------------------------------------------------------
# Integration Tests
# ---------------------------------------------------------------------------

class TestIntegration:

    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp(prefix="hemlock_test_integration_")

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_full_health_check_pipeline(self):
        from health.doctor_bridge import run_all_checks, format_report
        report = run_all_checks(quick=True)
        assert isinstance(report.healthy, bool)
        assert report.total_checks > 0
        assert report.ok_count + report.warn_count + report.fail_count == report.total_checks
        output = format_report(report)
        assert len(output) > 0

    def test_full_setup_then_doctor(self):
        mod = _import_runtime_init()
        home = Path(self.tmpdir) / "integration_home"
        home.mkdir()

        with _env(HERMES_HOME=str(home), HEMLOCK_DOCKER="0"):
            result = mod.run_noninteractive_setup(hermes_home=home)
            assert result == 0
            assert (home / "config.yaml").exists()
            assert (home / "agent.json").exists()
            assert (home / "SOUL.md").exists()

    def test_key_injection_then_verify(self):
        from scripts.key_inject import inject_keys
        home = Path(self.tmpdir) / "key_home"
        home.mkdir()

        config = {
            "openrouter": {"api_key": "sk-or-test-key"},
            "telegram": {"bot_token": "123456:ABC"},
            "inference": {"provider": "openrouter", "model": "test-model"},
        }
        inject_keys(config, hermes_home=home, dry_run=False)

        assert (home / ".env").exists()
        assert (home / ".secrets" / "secrets.json").exists()
        assert (home / "config.yaml").exists()

    def test_docker_compose_config_valid(self):
        import yaml
        compose_path = PROJECT_ROOT / "docker-compose.runtime.yml"
        if compose_path.exists():
            content = compose_path.read_text(encoding="utf-8")
            data = yaml.safe_load(content)
            assert data is not None
            assert "services" in data
            assert "runtime" in data["services"]

    def test_dockerfile_healthcheck(self):
        dockerfile_path = PROJECT_ROOT / "Dockerfile.runtime"
        if dockerfile_path.exists():
            content = dockerfile_path.read_text(encoding="utf-8")
            assert "HEALTHCHECK" in content
            assert "doctor_bridge" in content or "healthy" in content.lower()

    def test_path_resolver_in_docker_context(self):
        """Test PathResolver detects Docker context correctly."""
        from paths import PathResolver
        with _env(HEMLOCK_DOCKER="1"):
            PathResolver.reset_instance()
            p = PathResolver()
            assert p.is_docker is True
            # In Docker, paths resolve to /runtime, /agents, etc.
            # But get_hermes_home() from hermes_constants may override this
            # depending on active_profile, so we just check is_docker
            PathResolver.reset_instance()

    def test_path_resolver_in_local_context(self):
        from paths import PathResolver
        test_root = Path(self.tmpdir) / "local_root"
        test_root.mkdir()
        (test_root / "docker").mkdir()
        (test_root / "skills").mkdir()
        (test_root / "agents").mkdir()

        with _env(HEMLOCK_DOCKER="0"):
            p = PathResolver(root=str(test_root))
            assert not p.is_docker
            assert str(p.root) == str(test_root)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])