"""
Unit tests for Phase 27: Script Modernization

Tests cover:
- runtime/cli.py: Click CLI commands, bring-up sequence, status, plugin injection, monitor
- autonomy/protocol.py: AutonomyProtocol decision framework, 6 layers, reflection, logging
"""

import asyncio
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'docker' / 'hermes-agent'))


class TestAutonomyLayer(unittest.TestCase):
    """Test AutonomyLayer enum."""

    def test_layer_values(self):
        from autonomy.protocol import AutonomyLayer
        self.assertEqual(AutonomyLayer.PM, 0)
        self.assertEqual(AutonomyLayer.SCRIPT, 1)
        self.assertEqual(AutonomyLayer.TOOL, 2)
        self.assertEqual(AutonomyLayer.SKILL, 3)
        self.assertEqual(AutonomyLayer.SUBAGENT, 4)
        self.assertEqual(AutonomyLayer.MAIN_AGENT, 5)

    def test_layer_count(self):
        from autonomy.protocol import AutonomyLayer
        self.assertEqual(len(AutonomyLayer), 6)

    def test_layer_names(self):
        from autonomy.protocol import AutonomyLayer
        names = [l.name for l in AutonomyLayer]
        self.assertEqual(names, ['PM', 'SCRIPT', 'TOOL', 'SKILL', 'SUBAGENT', 'MAIN_AGENT'])


class TestDecisionResult(unittest.TestCase):
    """Test DecisionResult data class."""

    def test_creation(self):
        from autonomy.protocol import DecisionResult, AutonomyLayer
        result = DecisionResult(
            task="Test task",
            layer=AutonomyLayer.SCRIPT,
            reason="Task is deterministic",
            axioms=["That which can be deterministic OUGHT to be"],
            action="Write a script",
            metadata={"key": "value"}
        )
        self.assertEqual(result.task, "Test task")
        self.assertEqual(result.layer, AutonomyLayer.SCRIPT)
        self.assertEqual(result.layer_name, "SCRIPT")
        self.assertEqual(result.layer_value, 1)
        self.assertEqual(result.action, "Write a script")
        self.assertIsNotNone(result.timestamp)

    def test_to_dict(self):
        from autonomy.protocol import DecisionResult, AutonomyLayer
        result = DecisionResult(
            task="Test",
            layer=AutonomyLayer.TOOL,
            reason="Tool exists",
            axioms=["Use a tool"],
            action="Use tool",
        )
        d = result.to_dict()
        self.assertEqual(d['task'], 'Test')
        self.assertEqual(d['layer'], 2)
        self.assertEqual(d['layer_name'], 'TOOL')
        self.assertIn('timestamp', d)

    def test_repr(self):
        from autonomy.protocol import DecisionResult, AutonomyLayer
        result = DecisionResult(
            task="task", layer=AutonomyLayer.SCRIPT,
            reason="r", axioms=[], action="a"
        )
        r = repr(result)
        self.assertIn('SCRIPT', r)
        self.assertIn('task', r)


class TestAutonomyProtocol(unittest.TestCase):
    """Test AutonomyProtocol decision framework."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.memory_dir = os.path.join(self.test_dir, 'autonomy')
        from autonomy.protocol import AutonomyProtocol
        self.protocol = AutonomyProtocol(memory_dir=self.memory_dir)

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_decide_strategic_goes_to_pm(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide("Define project roadmap", is_strategic=True)
        self.assertEqual(result.layer, AutonomyLayer.PM)
        self.assertIn("Strategic", result.reason)

    def test_decide_deterministic_goes_to_script(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide("Run backup script", is_deterministic=True)
        self.assertEqual(result.layer, AutonomyLayer.SCRIPT)
        self.assertIn("deterministic", result.reason.lower())

    def test_decide_tool_exists_goes_to_tool(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide(
            "Deploy container",
            is_deterministic=False,
            tool_exists=True
        )
        self.assertEqual(result.layer, AutonomyLayer.TOOL)
        self.assertIn("tool", result.reason.lower())

    def test_decide_methodology_goes_to_skill(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide(
            "Review code changes",
            is_deterministic=False,
            tool_exists=False,
            methodology_exists=True
        )
        self.assertEqual(result.layer, AutonomyLayer.SKILL)
        self.assertIn("methodology", result.reason.lower())

    def test_decide_llm_judgment_goes_to_subagent(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide(
            "Analyze complex data",
            is_deterministic=False,
            tool_exists=False,
            methodology_exists=False,
            needs_llm_judgment=True,
            is_self_contained=True
        )
        self.assertEqual(result.layer, AutonomyLayer.SUBAGENT)
        self.assertIn("LLM", result.reason)

    def test_decide_fallback_to_main_agent(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide(
            "Handle ambiguous request",
            is_deterministic=False,
            tool_exists=False,
            methodology_exists=False,
            needs_llm_judgment=False
        )
        self.assertEqual(result.layer, AutonomyLayer.MAIN_AGENT)
        self.assertIn("No lower layer", result.reason)

    def test_decide_records_to_memory(self):
        self.protocol.decide("Test task", is_deterministic=True)
        decision_files = list(Path(self.memory_dir).glob('decision_*.json'))
        self.assertEqual(len(decision_files), 1)
        with open(decision_files[0]) as f:
            data = json.load(f)
        self.assertEqual(data['task'], 'Test task')

    def test_decide_returns_axioms(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide("Test", is_deterministic=True)
        self.assertIsInstance(result.axioms, list)
        self.assertGreater(len(result.axioms), 0)

    def test_record_outcome(self):
        self.protocol.decide("Test task", is_deterministic=True)
        self.protocol.record_outcome("Test task", "success", "Worked well")
        outcome_files = list(Path(self.memory_dir).glob('outcome_*.json'))
        self.assertEqual(len(outcome_files), 1)
        with open(outcome_files[0]) as f:
            data = json.load(f)
        self.assertEqual(data['outcome'], 'success')
        self.assertEqual(data['notes'], 'Worked well')

    def test_get_decision_history_empty(self):
        history = self.protocol.get_decision_history()
        self.assertEqual(history, [])

    def test_get_decision_history_with_decisions(self):
        self.protocol.decide("Task 1", is_deterministic=True)
        self.protocol.decide("Task 2", is_strategic=True)
        history = self.protocol.get_decision_history(limit=10)
        self.assertEqual(len(history), 2)

    def test_get_layer_stats(self):
        self.protocol.decide("Script task", is_deterministic=True)
        self.protocol.decide("PM task", is_strategic=True)
        self.protocol.decide("Tool task", is_deterministic=False, tool_exists=True)
        stats = self.protocol.get_layer_stats()
        self.assertEqual(stats['SCRIPT'], 1)
        self.assertEqual(stats['PM'], 1)
        self.assertEqual(stats['TOOL'], 1)

    def test_connect_reflection_engine(self):
        mock_engine = MagicMock()
        self.protocol.connect_reflection_engine(mock_engine)
        self.assertEqual(self.protocol.reflection_engine, mock_engine)

    def test_outcome_forwarded_to_reflection_engine(self):
        mock_engine = MagicMock()
        self.protocol.connect_reflection_engine(mock_engine)
        self.protocol.decide("Test task", is_deterministic=True)
        self.protocol.record_outcome("Test task", "success")
        mock_engine.record_decision_outcome.assert_called_once_with("Test task", "success")

    def test_all_layers_have_descriptions(self):
        from autonomy.protocol import LAYER_DESCRIPTIONS, AutonomyLayer
        for layer in AutonomyLayer:
            self.assertIn(layer, LAYER_DESCRIPTIONS)

    def test_all_layers_have_axioms(self):
        from autonomy.protocol import LAYER_AXIOMS, AutonomyLayer
        for layer in AutonomyLayer:
            self.assertIn(layer, LAYER_AXIOMS)
            self.assertIsInstance(LAYER_AXIOMS[layer], list)

    def test_decide_with_metadata(self):
        from autonomy.protocol import AutonomyLayer
        result = self.protocol.decide(
            "Test with meta",
            is_deterministic=True,
            metadata={"source": "test", "priority": "high"}
        )
        self.assertEqual(result.metadata["source"], "test")
        self.assertEqual(result.metadata["priority"], "high")

    def test_multiple_decisions_per_session(self):
        self.protocol.decide("Task 1", is_deterministic=True)
        self.protocol.decide("Task 2", tool_exists=True)
        self.protocol.decide("Task 3", is_strategic=True)
        self.assertEqual(len(self.protocol.decisions), 3)


class TestRuntimeCLI(unittest.TestCase):
    """Test the Click CLI commands."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        from click.testing import CliRunner
        from runtime.cli import cli
        self.runner = CliRunner()
        self.cli = cli

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_cli_help(self):
        result = self.runner.invoke(self.cli, ['--help'])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('Hemlock Runtime Management', result.output)

    def test_cli_version(self):
        result = self.runner.invoke(self.cli, ['--version'])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('1.0.0', result.output)

    def test_bring_up_command_exists(self):
        result = self.runner.invoke(self.cli, ['bring-up', '--help'])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('bring-up', result.output.lower())

    def test_status_command_exists(self):
        result = self.runner.invoke(self.cli, ['status', '--help'])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('cognitive', result.output.lower())

    def test_inject_plugins_command_exists(self):
        result = self.runner.invoke(self.cli, ['inject-plugins', '--help'])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('plugin', result.output.lower())

    def test_monitor_command_exists(self):
        result = self.runner.invoke(self.cli, ['monitor', '--help'])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('monitor', result.output.lower())

    def test_status_json_output(self):
        result = self.runner.invoke(self.cli, [
            '--root', self.test_dir, 'status', '--json'
        ])
        self.assertEqual(result.exit_code, 0)
        data = json.loads(result.output)
        self.assertIn('timestamp', data)
        self.assertIn('runtime_root', data)
        self.assertIn('agent_count', data)
        self.assertIn('crew_count', data)

    def test_status_text_output(self):
        result = self.runner.invoke(self.cli, [
            '--root', self.test_dir, 'status'
        ])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('Hemlock Runtime Status', result.output)

    def test_ensure_dirs_creates_directories(self):
        test_root = os.path.join(self.test_dir, 'test_runtime')
        os.makedirs(test_root, exist_ok=True)
        result = self.runner.invoke(self.cli, [
            '--root', test_root, 'status'
        ])
        self.assertTrue(os.path.isdir(os.path.join(test_root, 'agents')))
        self.assertTrue(os.path.isdir(os.path.join(test_root, 'crews')))
        self.assertTrue(os.path.isdir(os.path.join(test_root, 'config')))
        self.assertTrue(os.path.isdir(os.path.join(test_root, 'logs')))

    def test_bring_up_skip_flags(self):
        result = self.runner.invoke(self.cli, [
            '--root', self.test_dir, 'bring-up',
            '--skip-docker', '--skip-validation', '--skip-memory'
        ])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('Bring-Up Complete', result.output)

    def test_status_with_agents(self):
        agents_dir = os.path.join(self.test_dir, 'agents')
        os.makedirs(agents_dir, exist_ok=True)
        agent_dir = os.path.join(agents_dir, 'test-agent')
        os.makedirs(agent_dir, exist_ok=True)
        identity = {"agent_id": "test-agent", "status": "active", "model": "test"}
        with open(os.path.join(agent_dir, 'identity.json'), 'w') as f:
            json.dump(identity, f)

        result = self.runner.invoke(self.cli, [
            '--root', self.test_dir, 'status', '--agents'
        ])
        self.assertEqual(result.exit_code, 0)
        self.assertIn('test-agent', result.output)

    def test_inject_plugins_missing_agent(self):
        result = self.runner.invoke(self.cli, [
            '--root', self.test_dir, 'inject-plugins', '--agent', 'nonexistent'
        ])
        self.assertNotEqual(result.exit_code, 0)


class TestAutonomyProtocolInteractive(unittest.TestCase):
    """Test interactive decision flow."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.memory_dir = os.path.join(self.test_dir, 'autonomy')

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    @patch('builtins.input')
    def test_interactive_script_layer(self, mock_input):
        from autonomy.protocol import AutonomyProtocol, AutonomyLayer
        mock_input.side_effect = ['y']
        protocol = AutonomyProtocol(memory_dir=self.memory_dir)
        result = protocol.decide_interactive("Run daily backup")
        self.assertEqual(result.layer, AutonomyLayer.SCRIPT)

    @patch('builtins.input')
    def test_interactive_tool_layer(self, mock_input):
        from autonomy.protocol import AutonomyProtocol, AutonomyLayer
        mock_input.side_effect = ['n', 'n', 'y']
        protocol = AutonomyProtocol(memory_dir=self.memory_dir)
        result = protocol.decide_interactive("Deploy to production")
        self.assertEqual(result.layer, AutonomyLayer.TOOL)

    @patch('builtins.input')
    def test_interactive_skill_layer(self, mock_input):
        from autonomy.protocol import AutonomyProtocol, AutonomyLayer
        mock_input.side_effect = ['n', 'n', 'n', 'y']
        protocol = AutonomyProtocol(memory_dir=self.memory_dir)
        result = protocol.decide_interactive("Debug performance issue")
        self.assertEqual(result.layer, AutonomyLayer.SKILL)

    @patch('builtins.input')
    def test_interactive_subagent_layer(self, mock_input):
        from autonomy.protocol import AutonomyProtocol, AutonomyLayer
        mock_input.side_effect = ['n', 'n', 'n', 'n', 'y', 'y']
        protocol = AutonomyProtocol(memory_dir=self.memory_dir)
        result = protocol.decide_interactive("Analyze sentiment in reviews")
        self.assertEqual(result.layer, AutonomyLayer.SUBAGENT)

    @patch('builtins.input')
    def test_interactive_main_agent_fallback(self, mock_input):
        from autonomy.protocol import AutonomyProtocol, AutonomyLayer
        mock_input.side_effect = ['n', 'n', 'n', 'n', 'n']
        protocol = AutonomyProtocol(memory_dir=self.memory_dir)
        result = protocol.decide_interactive("Handle ambiguous request")
        self.assertEqual(result.layer, AutonomyLayer.MAIN_AGENT)


if __name__ == '__main__':
    unittest.main()