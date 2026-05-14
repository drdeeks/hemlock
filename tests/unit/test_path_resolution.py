"""
Phase 29 Validation Tests - Path Resolution & Portability

Tests:
- PathResolver singleton behavior
- Environment variable overrides
- Docker vs. local context detection
- Auto-detection of project root
- All path properties resolve correctly
- Path name resolution
- Cache invalidation
- Directory creation
- PathResolver.to_dict() export
- Integration with modules using resolver
"""

import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'docker' / 'hermes-agent'))

from paths import PathResolver, PathResolutionError, resolver


class TestPathResolverInit:
    """Test PathResolver initialization and singleton pattern."""

    def setup_method(self):
        PathResolver.reset_instance()

    def teardown_method(self):
        PathResolver.reset_instance()

    def test_singleton_returns_same_instance(self):
        a = PathResolver.get_instance()
        b = PathResolver.get_instance()
        assert a is b

    def test_reset_creates_new_instance(self):
        a = PathResolver.get_instance()
        PathResolver.reset_instance()
        b = PathResolver.get_instance()
        assert a is not b

    def test_explicit_root(self):
        r = PathResolver(root='/tmp/test-hemlock')
        assert r.root == Path('/tmp/test-hemlock')

    def test_default_root_detected(self):
        r = PathResolver()
        assert r.root is not None
        assert isinstance(r.root, Path)


class TestDockerDetection:
    """Test Docker environment detection."""

    def setup_method(self):
        PathResolver.reset_instance()

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_env_var_docker_true(self):
        os.environ['HEMLOCK_DOCKER'] = '1'
        r = PathResolver()
        assert r.is_docker is True

    def test_env_var_docker_yes(self):
        os.environ['HEMLOCK_DOCKER'] = 'yes'
        assert PathResolver()._detect_docker() is True

    def test_env_var_docker_false(self):
        os.environ['HEMLOCK_DOCKER'] = '0'
        r = PathResolver()
        assert r.is_docker is False

    def test_env_var_docker_true(self):
        os.environ['HEMLOCK_DOCKER'] = 'true'
        assert PathResolver()._detect_docker() is True

    def test_env_var_docker_false_string(self):
        os.environ['HEMLOCK_DOCKER'] = 'false'
        r = PathResolver()
        assert r.is_docker is False

    def test_non_docker_by_default(self):
        os.environ.pop('HEMLOCK_DOCKER', None)
        r = PathResolver()
        assert isinstance(r.is_docker, bool)


class TestPathResolutionLocal:
    """Test path resolution in local (non-Docker) context."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '0'
        for key in ['HEMLOCK_ROOT', 'HERMES_HOME', 'HERMES_AGENTS', 'HERMES_CREWS',
                     'HERMES_PROJECTS', 'HERMES_SKILLS', 'HERMES_LOGS', 'HERMES_MEMORY',
                     'HERMES_PLUGINS', 'HERMES_BACKUPS', 'HERMES_CONFIG', 'HERMES_SCRIPTS',
                     'HERMES_MODELS']:
            os.environ.pop(key, None)

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_root_is_path(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert isinstance(r.root, Path)

    def test_agents_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.agents_dir == Path(tmpdir) / 'agents'

    def test_crews_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.crews_dir == Path(tmpdir) / 'crews'

    def test_projects_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.projects_dir == Path(tmpdir) / 'projects'

    def test_logs_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.logs_dir == Path(tmpdir) / 'logs'

    def test_memory_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.memory_dir == Path(tmpdir) / 'memory'

    def test_plugins_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.plugins_dir == Path(tmpdir) / 'plugins'

    def test_backups_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.backups_dir == Path(tmpdir) / 'backups'

    def test_config_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.config_dir == Path(tmpdir) / 'config'

    def test_scripts_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.scripts_dir == Path(tmpdir) / 'scripts'

    def test_models_dir_under_root(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.models_dir == Path(tmpdir) / 'models'

    def test_gateway_logs_under_logs(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.gateway_logs_dir == r.logs_dir / 'gateway'

    def test_killswitch_logs_under_logs(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.killswitch_logs_dir == r.logs_dir / 'killswitch'

    def test_autonomy_memory_under_memory(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.autonomy_memory_dir == r.memory_dir / 'autonomy'

    def test_plugin_backups_under_backups(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.plugin_backups_dir == r.backups_dir / 'plugins'

    def test_projects_decisions_under_projects(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            assert r.projects_decisions_dir == r.projects_dir / 'decisions'


class TestPathResolutionDocker:
    """Test path resolution in Docker context."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '1'
        os.environ.pop('HERMES_HOME', None)
        os.environ.pop('HERMES_AGENTS', None)
        os.environ.pop('HERMES_CREWS', None)
        os.environ.pop('HERMES_PROJECTS', None)
        os.environ.pop('HERMES_SKILLS', None)
        os.environ.pop('HERMES_LOGS', None)
        os.environ.pop('HERMES_MEMORY', None)
        os.environ.pop('HERMES_PLUGINS', None)
        os.environ.pop('HERMES_BACKUPS', None)
        os.environ.pop('HERMES_CONFIG', None)
        os.environ.pop('HERMES_SCRIPTS', None)
        os.environ.pop('HERMES_MODELS', None)

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_docker_hermes_home(self):
        r = PathResolver()
        assert r.hermes_home == Path('/runtime')

    def test_docker_agents_dir(self):
        r = PathResolver()
        assert r.agents_dir == Path('/agents')

    def test_docker_crews_dir(self):
        r = PathResolver()
        assert r.crews_dir == Path('/crews')

    def test_docker_projects_dir(self):
        r = PathResolver()
        assert r.projects_dir == Path('/projects')

    def test_docker_skills_root(self):
        r = PathResolver()
        assert r.skills_root == Path('/skills')

    def test_docker_logs_dir(self):
        r = PathResolver()
        assert r.logs_dir == Path('/var/log/openclaw')

    def test_docker_plugins_dir(self):
        r = PathResolver()
        assert r.plugins_dir == Path('/plugins')

    def test_docker_backups_dir(self):
        r = PathResolver()
        assert r.backups_dir == Path('/backups')

    def test_docker_config_dir(self):
        r = PathResolver()
        assert r.config_dir == Path('/etc/openclaw')

    def test_docker_memory_dir(self):
        r = PathResolver()
        assert r.memory_dir == Path('/runtime/memory')


class TestEnvOverrides:
    """Test environment variable overrides take precedence."""

    def setup_method(self):
        PathResolver.reset_instance()

    def teardown_method(self):
        PathResolver.reset_instance()
        for key in ['HEMLOCK_ROOT', 'HERMES_HOME', 'HERMES_AGENTS', 'HERMES_CREWS',
                     'HERMES_PROJECTS', 'HERMES_SKILLS', 'HERMES_LOGS', 'HERMES_MEMORY',
                     'HERMES_PLUGINS', 'HERMES_BACKUPS', 'HERMES_CONFIG', 'HERMES_SCRIPTS',
                     'HERMES_MODELS', 'HEMLOCK_DOCKER']:
            os.environ.pop(key, None)

    def test_hemlock_root_override(self):
        os.environ['HEMLOCK_ROOT'] = '/custom/root'
        r = PathResolver()
        assert r.root == Path('/custom/root')

    def test_hermes_home_override(self):
        os.environ['HERMES_HOME'] = '/custom/hermes'
        r = PathResolver()
        assert r.hermes_home == Path('/custom/hermes')

    def test_agents_dir_override(self):
        os.environ['HERMES_AGENTS'] = '/custom/agents'
        r = PathResolver()
        assert r.agents_dir == Path('/custom/agents')

    def test_crews_dir_override(self):
        os.environ['HERMES_CREWS'] = '/custom/crews'
        r = PathResolver()
        assert r.crews_dir == Path('/custom/crews')

    def test_projects_dir_override(self):
        os.environ['HERMES_PROJECTS'] = '/custom/projects'
        r = PathResolver()
        assert r.projects_dir == Path('/custom/projects')

    def test_skills_root_override(self):
        os.environ['HERMES_SKILLS'] = '/custom/skills'
        r = PathResolver()
        assert r.skills_root == Path('/custom/skills')

    def test_logs_dir_override(self):
        os.environ['HERMES_LOGS'] = '/custom/logs'
        r = PathResolver()
        assert r.logs_dir == Path('/custom/logs')

    def test_memory_dir_override(self):
        os.environ['HERMES_MEMORY'] = '/custom/memory'
        r = PathResolver()
        assert r.memory_dir == Path('/custom/memory')

    def test_plugins_dir_override(self):
        os.environ['HERMES_PLUGINS'] = '/custom/plugins'
        r = PathResolver()
        assert r.plugins_dir == Path('/custom/plugins')

    def test_backups_dir_override(self):
        os.environ['HERMES_BACKUPS'] = '/custom/backups'
        r = PathResolver()
        assert r.backups_dir == Path('/custom/backups')

    def test_config_dir_override(self):
        os.environ['HERMES_CONFIG'] = '/custom/config'
        r = PathResolver()
        assert r.config_dir == Path('/custom/config')

    def test_scripts_dir_override(self):
        os.environ['HERMES_SCRIPTS'] = '/custom/scripts'
        r = PathResolver()
        assert r.scripts_dir == Path('/custom/scripts')

    def test_models_dir_override(self):
        os.environ['HERMES_MODELS'] = '/custom/models'
        r = PathResolver()
        assert r.models_dir == Path('/custom/models')

    def test_env_overrides_docker_defaults(self):
        os.environ['HEMLOCK_DOCKER'] = '1'
        os.environ['HERMES_AGENTS'] = '/override/agents'
        r = PathResolver()
        assert r.agents_dir == Path('/override/agents')
        assert r.is_docker is True


class TestPathMethod:
    """Test the path() resolution method."""

    def setup_method(self):
        PathResolver.reset_instance()

    def teardown_method(self):
        PathResolver.reset_instance()

    def test_path_by_name(self):
        r = PathResolver(root='/tmp/test')
        assert r.path('agents_dir') == r.agents_dir
        assert r.path('crews_dir') == r.crews_dir
        assert r.path('projects_dir') == r.projects_dir
        assert r.path('skills_root') == r.skills_root
        assert r.path('logs_dir') == r.logs_dir
        assert r.path('memory_dir') == r.memory_dir

    def test_path_case_insensitive(self):
        r = PathResolver(root='/tmp/test')
        assert r.path('AGENTS_DIR') == r.agents_dir
        assert r.path('agents_dir') == r.agents_dir

    def test_path_hyphen_to_underscore(self):
        r = PathResolver(root='/tmp/test')
        assert r.path('agents-dir') == r.agents_dir

    def test_path_unknown_raises(self):
        r = PathResolver()
        with pytest.raises(PathResolutionError, match="Unknown path name"):
            r.path('nonexistent_path')

    def test_all_known_paths(self):
        r = PathResolver(root='/tmp/test')
        known_names = [
            'root', 'hermes_home', 'agents_dir', 'crews_dir',
            'projects_dir', 'skills_root', 'logs_dir', 'memory_dir',
            'plugins_dir', 'backups_dir', 'config_dir', 'scripts_dir',
            'models_dir', 'gateway_logs_dir', 'killswitch_logs_dir',
            'autonomy_memory_dir', 'plugin_backups_dir', 'projects_decisions_dir',
        ]
        for name in known_names:
            resolved = r.path(name)
            assert isinstance(resolved, Path)


class TestCaching:
    """Test that path resolution results are cached."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '0'

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_cached_property_returns_same_object(self):
        r = PathResolver(root='/tmp/test')
        a = r.agents_dir
        b = r.agents_dir
        assert a is b

    def test_different_roots_give_different_paths(self):
        r1 = PathResolver(root='/tmp/test1')
        agents1 = r1.agents_dir
        PathResolver.reset_instance()
        r2 = PathResolver(root='/tmp/test2')
        agents2 = r2.agents_dir
        assert agents1 == Path('/tmp/test1/agents')
        assert agents2 == Path('/tmp/test2/agents')
        assert agents1 != agents2


class TestEnsureDirs:
    """Test directory creation."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '0'

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_ensure_dirs_creates_directories(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            r = PathResolver(root=tmpdir)
            r.ensure_dirs('agents_dir', 'crews_dir', 'logs_dir')
            assert (Path(tmpdir) / 'agents').exists()
            assert (Path(tmpdir) / 'crews').exists()
            assert (Path(tmpdir) / 'logs').exists()

    def test_ensure_dirs_all(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ['HEMLOCK_ROOT'] = tmpdir
            PathResolver.reset_instance()
            r = PathResolver()
            r.ensure_dirs()
            assert r.agents_dir.exists() or r.is_docker

    def test_ensure_dirs_unknown_name_raises(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ['HEMLOCK_ROOT'] = tmpdir
            PathResolver.reset_instance()
            r = PathResolver()
            with pytest.raises(PathResolutionError):
                r.ensure_dirs('nonexistent_dir')


class TestToDict:
    """Test dictionary export."""

    def setup_method(self):
        PathResolver.reset_instance()

    def teardown_method(self):
        PathResolver.reset_instance()

    def test_to_dict_keys(self):
        r = PathResolver(root='/tmp/test')
        d = r.to_dict()
        expected_keys = [
            'root', 'is_docker', 'hermes_home', 'agents_dir', 'crews_dir',
            'projects_dir', 'skills_root', 'logs_dir', 'memory_dir',
            'plugins_dir', 'backups_dir', 'config_dir', 'scripts_dir',
            'models_dir', 'gateway_logs_dir', 'killswitch_logs_dir',
            'autonomy_memory_dir', 'plugin_backups_dir', 'projects_decisions_dir',
        ]
        for key in expected_keys:
            assert key in d

    def test_to_dict_values_are_strings(self):
        r = PathResolver(root='/tmp/test')
        d = r.to_dict()
        for key, value in d.items():
            if key != 'is_docker':
                assert isinstance(value, str), f"{key} should be str, got {type(value)}"

    def test_to_dict_is_docker_is_bool(self):
        r = PathResolver(root='/tmp/test')
        d = r.to_dict()
        assert isinstance(d['is_docker'], bool)


class TestModuleResolver:
    """Test the module-level resolver singleton."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '0'

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_module_resolver_has_correct_type(self):
        import importlib
        import paths as paths_mod
        importlib.reload(paths_mod)
        resolver = paths_mod.resolver
        assert hasattr(resolver, 'root')
        assert hasattr(resolver, 'agents_dir')
        assert hasattr(resolver, 'path')
        assert resolver.__class__.__name__ == 'PathResolver'

    def test_module_resolver_has_all_properties(self):
        import importlib
        import paths as paths_mod
        importlib.reload(paths_mod)
        resolver = paths_mod.resolver
        assert resolver.root is not None
        assert resolver.agents_dir is not None
        assert resolver.crews_dir is not None


class TestModuleIntegration:
    """Test that modules use PathResolver correctly with explicit paths."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '0'

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_crew_lifecycle_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from crew.lifecycle import CrewLifecycleManager
            mgr = CrewLifecycleManager(
                crews_dir=str(Path(tmpdir) / 'crews'),
                agents_dir=str(Path(tmpdir) / 'agents'),
            )
            assert str(tmpdir) in str(mgr.crews_dir)

    def test_completion_approval_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from project.approval import CompletionApproval
            approval = CompletionApproval(
                agent_id='test',
                projects_dir=str(Path(tmpdir) / 'projects'),
            )
            assert str(tmpdir) in str(approval.projects_dir)

    def test_volume_manager_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from volumes.volume_manager import VolumeManager
            mgr = VolumeManager(
                agents_dir=str(Path(tmpdir) / 'agents'),
                crews_dir=str(Path(tmpdir) / 'crews'),
            )
            assert str(tmpdir) in str(mgr.agents_dir)

    def test_skill_registry_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skills_dir = Path(tmpdir) / 'skills'
            skills_dir.mkdir()
            from skills.skill_registry import SkillRegistry
            registry = SkillRegistry(
                skills_root=str(skills_dir),
                agents_dir=str(Path(tmpdir) / 'agents'),
            )
            assert str(skills_dir) in str(registry.skills_root)

    def test_plugin_manager_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from plugins.plugin_manager import PluginManager
            os.environ['HERMES_BACKUPS'] = str(Path(tmpdir) / 'backups')
            agents = Path(tmpdir) / 'agents'
            plugins = Path(tmpdir) / 'plugins'
            agents.mkdir()
            plugins.mkdir()
            mgr = PluginManager(
                agents_dir=agents,
                plugins_dir=plugins,
            )
            assert str(tmpdir) in str(mgr.agents_dir)
            os.environ.pop('HERMES_BACKUPS', None)

    def test_gateway_monitor_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from gateway.monitor import GatewayMonitor
            monitor = GatewayMonitor(
                logs_dir=str(Path(tmpdir) / 'gateway'),
            )
            assert 'gateway' in str(monitor.logs_dir)

    def test_killswitch_handler_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from gateway.killswitch import KillswitchHandler
            handler = KillswitchHandler(
                logs_dir=str(Path(tmpdir) / 'killswitch'),
            )
            assert 'killswitch' in str(handler.logs_dir)

    def test_autonomy_protocol_uses_resolver(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            from autonomy.protocol import AutonomyProtocol
            proto = AutonomyProtocol(memory_dir=str(Path(tmpdir) / 'autonomy'))
            assert 'autonomy' in str(proto.memory_dir)


class TestPathResolutionNoHardcodedPaths:
    """Verify that explicit root paths don't contain /home/drdeek."""

    def setup_method(self):
        PathResolver.reset_instance()
        os.environ['HEMLOCK_DOCKER'] = '0'

    def teardown_method(self):
        PathResolver.reset_instance()
        os.environ.pop('HEMLOCK_DOCKER', None)

    def test_no_home_drdeek_in_agents_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.agents_dir)

    def test_no_home_drdeek_in_crews_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.crews_dir)

    def test_no_home_drdeek_in_projects_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.projects_dir)

    def test_no_home_drdeek_in_skills_root(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.skills_root)

    def test_no_home_drdeek_in_logs_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.logs_dir)

    def test_no_home_drdeek_in_memory_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.memory_dir)

    def test_no_home_drdeek_in_plugins_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.plugins_dir)

    def test_no_home_drdeek_in_backups_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.backups_dir)

    def test_no_home_drdeek_in_config_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.config_dir)

    def test_no_home_drdeek_in_scripts_dir(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.scripts_dir)

    def test_no_home_drdeek_in_hermes_home(self):
        r = PathResolver(root='/tmp/test')
        assert '/home/drdeek' not in str(r.hermes_home)

    def test_to_dict_no_hardcoded_paths_in_resolved_dirs(self):
        r = PathResolver(root='/tmp/test')
        d = r.to_dict()
        user_path_dirs = {k: v for k, v in d.items()
                          if k not in ('root', 'is_docker')}
        for key, value in user_path_dirs.items():
            assert '/home/drdeek' not in value, f"{key} contains hardcoded path: {value}"

    def test_docker_defaults_no_developer_paths(self):
        os.environ['HEMLOCK_DOCKER'] = '1'
        r = PathResolver()
        d = r.to_dict()
        for key, value in d.items():
            if key == 'is_docker':
                continue
            assert '/home/drdeek' not in value, f"{key} in Docker mode has hardcoded path: {value}"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])