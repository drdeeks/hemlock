"""
Unit tests for crew lifecycle management (lifecycle.py).

Tests cover:
- Crew creation with agents
- State transition validation
- Crew activation, dormancy, completion, reactivation, archiving
- Crew deletion with cleanup
- State export and restoration
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


class MockKillswitchHandler:
    def __init__(self):
        self.broadcast_count = 0
        self.last_reason = None

    def broadcast(self, reason=None):
        self.broadcast_count += 1
        self.last_reason = reason


def AsyncMock(*args, **kwargs):
    m = MagicMock(*args, **kwargs)
    async def async_mock(*args, **kwargs):
        return m(*args, **kwargs)
    return async_mock


class TestCrewLifecycleManager(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.crews_dir = os.path.join(self.test_dir, 'crews')
        self.agents_dir = os.path.join(self.test_dir, 'agents')
        self.projects_dir = os.path.join(self.test_dir, 'projects')

        from crew.lifecycle import CrewLifecycleManager
        self.manager = CrewLifecycleManager(
            crews_dir=self.crews_dir,
            agents_dir=self.agents_dir
        )
        self.manager.projects_dir = Path(self.projects_dir)
        self.manager.killswitch = MockKillswitchHandler()

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    async def test_create_crew_basic(self):
        crew = await self.manager.create_crew('test-crew', ['agent1', 'agent2'])
        self.assertEqual(crew['name'], 'test-crew')
        self.assertEqual(crew['status'], 'created')
        self.assertEqual(crew['agents'], ['agent1', 'agent2'])
        self.assertIn('created_at', crew)
        self.assertEqual(crew['version'], '1.0')

    async def test_create_crew_with_resources(self):
        resources = {'budget': 1000, 'tools': ['python', 'bash']}
        crew = await self.manager.create_crew('resource-crew', ['agent1'], resources=resources)
        self.assertEqual(crew['resources'], resources)

    async def test_create_crew_duplicate(self):
        await self.manager.create_crew('dup-crew', ['agent1'])
        with self.assertRaises(Exception):
            await self.manager.create_crew('dup-crew', ['agent2'])

    async def test_create_crew_directory_structure(self):
        await self.manager.create_crew('struct-crew', ['agent1'])
        crew_dir = Path(self.crews_dir) / 'struct-crew'
        self.assertTrue((crew_dir / 'state').exists())
        self.assertTrue((crew_dir / 'logs').exists())
        self.assertTrue((crew_dir / 'backups').exists())
        self.assertTrue((crew_dir / 'crew.json').exists())

    async def test_create_crew_agent_identity(self):
        await self.manager.create_crew('identity-crew', ['alice', 'bob'])
        alice_identity = Path(self.agents_dir) / 'alice' / 'identity.json'
        bob_identity = Path(self.agents_dir) / 'bob' / 'identity.json'
        self.assertTrue(alice_identity.exists())
        self.assertTrue(bob_identity.exists())
        with open(alice_identity) as f:
            data = json.load(f)
        self.assertEqual(data['agent_id'], 'alice')
        self.assertEqual(data['crew'], 'identity-crew')
        self.assertEqual(data['role'], 'crew_member')
        self.assertEqual(data['status'], 'active')

    async def test_activate_crew(self):
        await self.manager.create_crew('activate-crew', ['agent1'])
        result = await self.manager.activate_crew('activate-crew')
        self.assertEqual(result['status'], 'active')
        crew = self.manager._load_crew('activate-crew')
        self.assertEqual(crew['status'], 'active')
        self.assertIn('activated_at', crew)

    async def test_activate_nonexistent_crew(self):
        from crew.lifecycle import CrewNotFoundError
        with self.assertRaises(CrewNotFoundError):
            await self.manager.activate_crew('nonexistent')

    async def test_complete_crew(self):
        await self.manager.create_crew('complete-crew', ['agent1'])
        await self.manager.activate_crew('complete-crew')
        result = await self.manager.complete_crew('complete-crew')
        self.assertEqual(result['status'], 'completed')

    async def test_mark_dormant(self):
        await self.manager.create_crew('dormant-crew', ['agent1'])
        await self.manager.activate_crew('dormant-crew')
        result = await self.manager.mark_dormant('dormant-crew', reason='Task complete')
        self.assertEqual(result['status'], 'dormant')
        self.assertEqual(result['reason'], 'Task complete')
        crew = self.manager._load_crew('dormant-crew')
        self.assertEqual(crew['status'], 'dormant')
        self.assertIn('dormant_at', crew)

    async def test_mark_dormant_creates_backup(self):
        await self.manager.create_crew('backup-crew', ['agent1'])
        await self.manager.activate_crew('backup-crew')
        await self.manager.mark_dormant('backup-crew', reason='Test')
        backup_dir = Path(self.crews_dir) / 'backup-crew' / 'backups'
        backups = list(backup_dir.glob('state_*.json'))
        self.assertGreater(len(backups), 0)

    async def test_reactivate_from_dormant(self):
        await self.manager.create_crew('reactivate-crew', ['agent1', 'agent2'])
        await self.manager.activate_crew('reactivate-crew')
        await self.manager.mark_dormant('reactivate-crew', reason='Done for now')
        result = await self.manager.reactivate('reactivate-crew')
        self.assertEqual(result['status'], 'active')
        self.assertEqual(result['previous_status'], 'dormant')
        self.assertIn('reactivated_at', result)

    async def test_reactivate_nonexistent_crew(self):
        from crew.lifecycle import CrewNotFoundError
        with self.assertRaises(CrewNotFoundError):
            await self.manager.reactivate('nonexistent')

    async def test_reactivate_from_created_should_fail(self):
        await self.manager.create_crew('created-crew', ['agent1'])
        from crew.lifecycle import InvalidStateTransitionError
        with self.assertRaises(InvalidStateTransitionError):
            await self.manager.reactivate('created-crew')

    async def test_archive_crew(self):
        await self.manager.create_crew('archive-crew', ['agent1'])
        await self.manager.activate_crew('archive-crew')
        result = await self.manager.archive_crew('archive-crew')
        self.assertEqual(result['status'], 'archived')

    async def test_delete_crew(self):
        await self.manager.create_crew('delete-crew', ['agent-del'])
        result = await self.manager.delete('delete-crew')
        self.assertEqual(result['status'], 'deleted')
        self.assertEqual(result['agents_cleaned'], 1)
        crew_dir = Path(self.crews_dir) / 'delete-crew'
        self.assertFalse(crew_dir.exists())
        agent_identity = Path(self.agents_dir) / 'agent-del' / 'identity.json'
        self.assertFalse(agent_identity.exists())

    async def test_delete_nonexistent_crew(self):
        result = await self.manager.delete('nonexistent')
        self.assertEqual(result['status'], 'deleted')
        self.assertEqual(result['agents_cleaned'], 0)

    async def test_list_crews(self):
        await self.manager.create_crew('crew-a', ['agent1'])
        await self.manager.create_crew('crew-b', ['agent2'])
        crews = await self.manager.list_crews()
        self.assertEqual(len(crews), 2)
        names = {c['name'] for c in crews}
        self.assertEqual(names, {'crew-a', 'crew-b'})

    async def test_list_crews_filtered(self):
        await self.manager.create_crew('active-crew', ['agent1'])
        await self.manager.create_crew('dormant-crew', ['agent2'])
        await self.manager.activate_crew('active-crew')
        await self.manager.activate_crew('dormant-crew')
        await self.manager.mark_dormant('dormant-crew')
        active_crews = await self.manager.list_crews(status_filter='active')
        self.assertEqual(len(active_crews), 1)
        self.assertEqual(active_crews[0]['name'], 'active-crew')

    async def test_get_crew_status(self):
        await self.manager.create_crew('status-crew', ['agent1', 'agent2'])
        status = await self.manager.get_crew_status('status-crew')
        self.assertEqual(status['name'], 'status-crew')
        self.assertEqual(status['status'], 'created')
        self.assertEqual(status['agent_count'], 2)
        self.assertIn('created_at', status)

    async def test_get_crew_status_not_found(self):
        from crew.lifecycle import CrewNotFoundError
        with self.assertRaises(CrewNotFoundError):
            await self.manager.get_crew_status('nonexistent')

    async def test_get_valid_transitions(self):
        from crew.lifecycle import CrewState
        created = self.manager.get_valid_transitions('created')
        self.assertIn('active', created)
        self.assertIn('archived', created)
        active = self.manager.get_valid_transitions('active')
        self.assertIn('completed', active)
        self.assertIn('dormant', active)
        self.assertIn('archived', active)

    async def test_invalid_transition_rejected(self):
        from crew.lifecycle import InvalidStateTransitionError
        await self.manager.create_crew('bad-crew', ['agent1'])
        with self.assertRaises(InvalidStateTransitionError):
            await self.manager.mark_dormant('bad-crew', reason='Cannot go dormant from created')

    async def test_update_crew_state(self):
        await self.manager.create_crew('state-crew', ['agent1'])
        state = await self.manager.update_crew_state('state-crew', {'progress': 50})
        self.assertEqual(state['progress'], 50)
        status = await self.manager.get_crew_status('state-crew')
        self.assertEqual(status['state']['progress'], 50)

    async def test_export_crew_state_returns_path(self):
        await self.manager.create_crew('export-crew', ['agent1'])
        await self.manager.activate_crew('export-crew')
        backup_path = await self.manager._export_crew_state('export-crew')
        self.assertTrue(backup_path.exists())
        with open(backup_path) as f:
            data = json.load(f)
        self.assertEqual(data['crew'], 'export-crew')
        self.assertIn('manifest', data)
        self.assertIn('agents', data)

    async def test_restore_crew_state_rebuilds_identities(self):
        await self.manager.create_crew('restore-crew', ['agent-x', 'agent-y'])
        await self.manager.activate_crew('restore-crew')
        await self.manager.mark_dormant('restore-crew', reason='Backup test')

        shutil.rmtree(Path(self.agents_dir) / 'agent-x')
        shutil.rmtree(Path(self.agents_dir) / 'agent-y')
        self.assertFalse((Path(self.agents_dir) / 'agent-x').exists())

        result = await self.manager.reactivate('restore-crew')
        self.assertTrue(result['state_restored'])

        x_id = Path(self.agents_dir) / 'agent-x' / 'identity.json'
        y_id = Path(self.agents_dir) / 'agent-y' / 'identity.json'
        self.assertTrue(x_id.exists())
        self.assertTrue(y_id.exists())

    async def test_restore_no_backup_returns_empty(self):
        await self.manager.create_crew('no-backup-crew', ['agent1'])
        result = await self.manager._restore_crew_state('no-backup-crew')
        self.assertEqual(result, {})

    async def test_full_lifecycle(self):
        crew = await self.manager.create_crew('full-lifecycle', ['a1', 'a2'])
        self.assertEqual(crew['status'], 'created')

        result = await self.manager.activate_crew('full-lifecycle')
        self.assertEqual(result['status'], 'active')

        state = await self.manager.update_crew_state('full-lifecycle', {'progress': 75, 'stage': 'testing'})
        self.assertEqual(state['progress'], 75)

        result = await self.manager.complete_crew('full-lifecycle')
        self.assertEqual(result['status'], 'completed')

        result = await self.manager.mark_dormant('full-lifecycle', reason='All tasks done')
        self.assertEqual(result['status'], 'dormant')

        backup_dir = Path(self.crews_dir) / 'full-lifecycle' / 'backups'
        backups = list(backup_dir.glob('state_*.json'))
        self.assertGreater(len(backups), 0)

        result = await self.manager.reactivate('full-lifecycle')
        self.assertEqual(result['status'], 'active')

        result = await self.manager.archive_crew('full-lifecycle')
        self.assertEqual(result['status'], 'archived')

        status = await self.manager.get_crew_status('full-lifecycle')
        self.assertEqual(status['status'], 'archived')

    async def test_state_enum_values(self):
        from crew.lifecycle import CrewState
        self.assertEqual(CrewState.CREATED.value, 'created')
        self.assertEqual(CrewState.ACTIVE.value, 'active')
        self.assertEqual(CrewState.COMPLETED.value, 'completed')
        self.assertEqual(CrewState.DORMANT.value, 'dormant')
        self.assertEqual(CrewState.REACTIVATED.value, 'reactivated')
        self.assertEqual(CrewState.ARCHIVED.value, 'archived')
        self.assertEqual(CrewState.DELETED.value, 'deleted')

    async def test_error_classes(self):
        from crew.lifecycle import CrewLifecycleError, CrewNotFoundError, InvalidStateTransitionError
        self.assertTrue(issubclass(CrewNotFoundError, CrewLifecycleError))
        self.assertTrue(issubclass(InvalidStateTransitionError, CrewLifecycleError))


class TestCompletionApproval(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.projects_dir = os.path.join(self.test_dir, 'projects')

        from project.approval import CompletionApproval
        self.approver = CompletionApproval('test-agent', timeout_hours=24, projects_dir=self.projects_dir)
        self.approver.decisions_dir = Path(self.projects_dir) / 'decisions'
        self.approver.decisions_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_initial_state(self):
        self.assertFalse(self.approver.approved)
        self.assertFalse(self.approver.rejected)
        self.assertFalse(self.approver.extended)
        self.assertFalse(self.approver.rework_requested)
        self.assertFalse(self.approver.cancelled)
        self.assertEqual(self.approver.agent_id, 'test-agent')

    def test_is_expired_false_by_default(self):
        self.assertFalse(self.approver.is_expired)

    def test_time_remaining_positive(self):
        remaining = self.approver.time_remaining
        self.assertGreater(remaining.total_seconds(), 0)

    def test_valid_choices(self):
        self.assertEqual(self.approver.VALID_CHOICES, {'A', 'R', 'E', 'Q'})

    def test_get_existing_decision_none(self):
        result = self.approver._load_existing_decision('unknown-project')
        self.assertIsNone(result)

    def test_save_and_load_decision_approved(self):
        self.approver._save_decision('test-project', 'approved')
        existing = self.approver._load_existing_decision('test-project')
        self.assertIsNotNone(existing)
        self.assertEqual(existing['decision'], 'approved')
        self.assertEqual(existing['agent'], 'test-agent')
        self.assertIn('timestamp', existing)

    def test_save_decision_with_notes(self):
        self.approver._save_decision('test-project', 'rejected', notes='Needs more work')
        existing = self.approver._load_existing_decision('test-project')
        self.assertEqual(existing['notes'], 'Needs more work')

    def test_save_decision_with_extension(self):
        self.approver._save_decision('test-project', 'extended', extension_hours=48)
        existing = self.approver._load_existing_decision('test-project')
        self.assertEqual(existing['extension_hours'], 48)

    def test_apply_decision_approved(self):
        self.approver._apply_decision('approved')
        self.assertTrue(self.approver.approved)

    def test_apply_decision_rejected(self):
        self.approver._apply_decision('rejected')
        self.assertTrue(self.approver.rejected)
        self.assertTrue(self.approver.rework_requested)

    def test_apply_decision_extended(self):
        self.approver._apply_decision('extended')
        self.assertTrue(self.approver.extended)

    def test_apply_decision_cancelled(self):
        self.approver._apply_decision('cancelled')
        self.assertTrue(self.approver.cancelled)

    def test_get_decision_returns_none_when_missing(self):
        result = self.approver.get_decision('no-decision')
        self.assertIsNone(result)

    def test_get_pending_projects_empty(self):
        self.approver._save_decision('completed-proj', 'approved')
        pending = self.approver.get_pending_projects()
        self.assertEqual(len(pending), 0)

    def test_get_pending_projects_with_pending(self):
        self.approver._save_decision('pending-proj', 'cancelled')
        pending = self.approver.get_pending_projects()
        self.assertIn('pending-proj', pending)

    def test_check_timeout_raises_when_expired(self):
        self.approver.created_at = self.approver.created_at.replace(
            year=self.approver.created_at.year - 1
        )
        from project.approval import ApprovalTimeoutError
        with self.assertRaises(ApprovalTimeoutError):
            self.approver._check_timeout()

    def test_check_timeout_passes_when_valid(self):
        self.approver._check_timeout()

    @patch('builtins.input', return_value='A')
    async def test_request_approve_flow(self, mock_input):
        from project.approval import ApprovalTimeoutError
        decision = self.approver.request_completion_acknowledgment(
            'test-project', 'Test summary'
        )
        self.assertEqual(decision['status'], 'approved')
        self.assertEqual(decision['agent'], 'test-agent')

    @patch('builtins.input', return_value='R')
    async def test_request_reject_flow(self, mock_input):
        decision = self.approver.request_completion_acknowledgment(
            'test-project', 'Test summary'
        )
        self.assertEqual(decision['status'], 'rejected')
        self.assertTrue(decision['rework_requested'])

    @patch('builtins.input', return_value='Q')
    async def test_request_quit_flow(self, mock_input):
        decision = self.approver.request_completion_acknowledgment(
            'test-project', 'Test summary'
        )
        self.assertEqual(decision['status'], 'cancelled')

    @patch('builtins.input', side_effect=['E', '48'])
    async def test_request_extend_flow(self, mock_input):
        decision = self.approver.request_completion_acknowledgment(
            'test-project', 'Test summary'
        )
        self.assertEqual(decision['status'], 'extended')
        self.assertEqual(decision['extension_hours'], 48)

    @patch('builtins.input', side_effect=['R', 'needs more testing'])
    async def test_request_reject_with_notes(self, mock_input):
        decision = self.approver.request_completion_acknowledgment(
            'test-project', 'Test summary'
        )
        self.assertEqual(decision['status'], 'rejected')
        self.assertEqual(decision['notes'], 'needs more testing')

if __name__ == '__main__':
    unittest.main()