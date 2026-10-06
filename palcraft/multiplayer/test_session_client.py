from __future__ import annotations
import copy
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from session_client import HostSession, host_answer, inspect_grant, load_credential
from prepare_guest import prepare

FIXTURES = Path(__file__).parent / 'test-fixtures'


class ProtocolInterop(unittest.TestCase):
    def setUp(self):
        self.credential = load_credential(FIXTURES / 'synthetic-credential.json')
        self.vector = json.loads((FIXTURES / 'public-vector.json').read_text())
        self.grant = inspect_grant(self.credential['grant'])
        self.bound = {'t': 'bound', 'session': {**self.grant['identity'], 'v': 2, 'server_session_id': self.grant['server_session_id'],
                      'session_id': str(uuid.uuid4()), 'generation': 1, 'expires_at': self.grant['expires_at'], 'legacy': False}}

    def test_hmac_is_byte_exact_with_production_java(self):
        self.assertEqual(host_answer(self.credential, self.vector['challenge'], now=self.vector['now']), self.vector['answer'])

    def test_other_world_player_boot_and_expiry_rejected(self):
        for key in ('world_id', 'server_session_id', 'mc_uuid'):
            challenge = copy.deepcopy(self.vector['challenge']); challenge[key] = str(uuid.uuid4())
            with self.assertRaises(ValueError): host_answer(self.credential, challenge, now=self.vector['now'])
        with self.assertRaises(ValueError): host_answer(self.credential, self.vector['challenge'], now=self.grant['expires_at'])

    def test_observer_is_explicit_and_does_not_change_proof(self):
        answer = host_answer(self.credential, self.vector['challenge'], now=self.vector['now'], observer=True)
        self.assertTrue(answer.pop('observer')); self.assertEqual(answer, self.vector['answer'])

    def test_bound_actor_and_generation_checked(self):
        for key, wrong in [('pal_uid', str(uuid.uuid4())), ('mc_uuid', str(uuid.uuid4())), ('generation', True), ('legacy', True)]:
            bound = copy.deepcopy(self.bound); bound['session'][key] = wrong
            with self.assertRaises(ValueError): HostSession(self.credential).bound(bound)

    def test_input_sequence_and_world_context_are_separate(self):
        session = HostSession(self.credential); session.bound(self.bound)
        one = session.stamp({'t': 'world_view_ack', 'session': 'MC-world-lifetime', 'view': 'nether-3'})
        two = session.stamp({'t': 'pointer', 'x': .5, 'y': .5})
        self.assertEqual(one['seq'], 1); self.assertEqual(two['seq'], 2)
        self.assertEqual(one['world_session'], 'MC-world-lifetime'); self.assertEqual(one['view'], 'nether-3')
        self.assertEqual(one['session'], self.bound['session'])

    def test_other_actor_old_generation_event_rejected(self):
        session = HostSession(self.credential); session.bound(self.bound)
        for key, wrong in [('session_id', str(uuid.uuid4())), ('pal_uid', str(uuid.uuid4())), ('generation', 2)]:
            message = {'t': 'feedback', 'host_session': copy.deepcopy(self.bound['session'])}; message['host_session'][key] = wrong
            with self.assertRaises(ValueError): session.receive(message)
        good = {'t': 'player_view', 'session': 'world-lifetime', 'host_session': self.bound['session'], 'view': 'nether-3'}
        stripped = session.receive(good); self.assertEqual(stripped['session'], 'world-lifetime'); self.assertNotIn('host_session', stripped)

    def test_disconnect_discards_bound_gui_state(self):
        session = HostSession(self.credential); session.bound(self.bound); session.stamp({'t': 'key'})
        session.disconnected(); self.assertIsNone(session.session); self.assertEqual(session.sequence, 0)
        with self.assertRaises(ValueError): session.stamp({'t': 'pointer'})

    def test_guest_plan_consumes_persistent_identity_and_assigned_ports(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); manifest = prepare(str(FIXTURES / 'synthetic-credential.json'), remote_root='D:/PalworldServer-LAN/PalCraft-Dev',
                mc_ws_port=29901, hud_port=29903, mc_server_address='127.0.0.1:25567', allocation_file=root/'allocations.json',
                output=root/'guest.json', now=self.vector['now'])
            self.assertEqual(manifest['guest']['mc_args'], ['--username', self.grant['mc_name'], '--uuid', self.grant['mc_uuid']])
            self.assertIn(self.grant['mc_uuid'], manifest['guest']['bridge_dir']); self.assertIn(self.grant['mc_uuid'], manifest['guest']['frame_mapping'])
            self.assertEqual(manifest['guest']['mc_ws_port'], 29901); self.assertEqual(manifest['guest']['hud_port'], 29903)
            self.assertTrue(manifest['prepared_only']); self.assertFalse(manifest['starts_processes'])
            data = json.dumps(manifest); self.assertNotIn('holder_private', data); self.assertNotIn('host_secret', data); self.assertNotIn(self.credential['grant'], data)

    def test_guest_plan_rejects_shared_guest_ports_and_expired_registration(self):
        with tempfile.TemporaryDirectory() as d:
            options = dict(remote_root='D:/PalworldServer-LAN/PalCraft-Dev', mc_ws_port=29901, hud_port=29901,
                           mc_server_address='127.0.0.1:25567', allocation_file=Path(d)/'allocations.json', output=Path(d)/'guest.json', now=self.vector['now'])
            with self.assertRaises(ValueError): prepare(str(FIXTURES/'synthetic-credential.json'), **options)
            options.update(hud_port=29903, now=self.grant['expires_at'])
            with self.assertRaises(ValueError): prepare(str(FIXTURES/'synthetic-credential.json'), **options)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProtocolInterop)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(json.dumps({'ok': result.wasSuccessful(), 'suite': 'python_java_host_protocol_interop_and_guest_plan', 'tests': result.testsRun,
                      'failures': len(result.failures), 'errors': len(result.errors), 'binds_ports': False, 'two_real_pal_clients_verified': False}))
    raise SystemExit(0 if result.wasSuccessful() else 1)
