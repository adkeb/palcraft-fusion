import asyncio
import json
import tempfile
import time
import unittest
import uuid
from pathlib import Path

import test_sessions as session_fixtures
from test_sessions import credential, protocol
from launcher.native_bootstrap import NativeBootstrap


class NativeBootstrapLifecycle(unittest.TestCase):
    def test_accepted_replay_survives_idle_and_tracks_world_then_disconnect(self):
        proof = credential()
        public = protocol.inspect_grant(proof['grant'])
        lease = protocol.HostSession(proof)
        host = dict(public['identity'], v=2, legacy=False, server_session_id=public['server_session_id'],
                    session_id=str(uuid.uuid4()), generation=3, expires_at=public['expires_at'])
        lease.bound({'t': 'bound', 'session': host})
        native = dict(host, session_id=str(uuid.uuid4()), generation=7, mc_epoch='fixture-mc-epoch')
        clock = [time.time()]
        with tempfile.TemporaryDirectory(prefix='palcraft-native-bootstrap-') as folder:
            path = Path(folder) / 'mc-bootstrap-status.json'
            state = NativeBootstrap(path, public, clock=lambda: clock[0])
            state.bound(lease)
            state.heartbeat(lease)
            self.assertFalse(json.loads(path.read_text())['native_mc_verified'])
            view = {'player': public['identity']['mc_uuid'], 'world_session': 'fixture-world-lifetime',
                    'dim': 'minecraft:overworld', 'view': 1, 'waiting_ack': False, 'mapping': None, 'bounds': None}
            state.message(lease.receive({'t': 'blocks', 'host_session': host,
                                         'native_binding': native, 'world_view': view}), lease)
            first = json.loads(path.read_text())
            self.assertEqual(first['state'], 'bound')
            self.assertNotEqual(first['host_scope']['session_id'], first['native_binding']['session_id'])
            clock[0] += 4
            state.heartbeat(lease)
            idle = json.loads(path.read_text())
            self.assertEqual(idle['updated_unix'], clock[0])
            self.assertEqual(idle['source_observed_unix'], first['source_observed_unix'])
            self.assertEqual(idle['native_binding'], native)
            state.message(lease.receive({'t': 'blocks', 'host_session': host, 'session': view['world_session'],
                                         'lifecycle': [{'op': 'player_view', 'player': view['player'],
                                                        'to': 'minecraft:the_nether', 'view': 2, 'waiting_ack': True}]}), lease)
            self.assertTrue(json.loads(path.read_text())['world_view']['waiting_ack'])
            state.message(lease.receive({'t': 'world_view_applied', 'host_session': host, 'player': view['player'],
                                         'world_session': view['world_session'], 'dim': 'minecraft:the_nether',
                                         'view': 2, 'applied': True}), lease)
            current = json.loads(path.read_text())
            self.assertFalse(current['world_view']['waiting_ack'])
            self.assertEqual(current['world_view']['dim'], 'minecraft:the_nether')
            state.unbound('disconnected')
            lease.disconnected()
            last = json.loads(path.read_text())
            self.assertFalse(last['native_mc_verified'])
            self.assertIsNone(last['native_binding'])
            self.assertIsNone(last['world_view'])


class NativeBootstrapProxyWire(unittest.IsolatedAsyncioTestCase):
    async def test_proxy_publishes_and_refreshes_accepted_bootstrap(self):
        fixture = session_fixtures.ProxyTests(methodName='test_hmac_bind_scopes_camera_and_preserves_world_session')
        await fixture.asyncSetUp()
        try:
            wire = await fixture.native()
            await wire.receive()
            await wire.send(json.dumps({'t': 'inspect'}))
            sent = await asyncio.wait_for(fixture.received.get(), 2)
            await wire.receive()
            host = sent['session']
            native = dict(host, session_id=str(uuid.uuid4()), generation=9, mc_epoch='fixture-wire-epoch')
            view = {'player': host['mc_uuid'], 'world_session': 'fixture-wire-world',
                    'dim': 'minecraft:overworld', 'view': 1, 'waiting_ack': False, 'mapping': None, 'bounds': None}
            await next(iter(fixture.guest_wires)).send(json.dumps({'t': 'blocks', 'host_session': host,
                                                                   'native_binding': native, 'world_view': view,
                                                                   'session': view['world_session'], 'set': [], 'clear': []}))
            await asyncio.wait_for(wire.receive(), 2)
            path = fixture.root / 'mc-bootstrap-status.json'
            first = json.loads(path.read_text())
            self.assertTrue(first['native_mc_verified'])
            self.assertEqual(first['native_binding']['session_id'], native['session_id'])
            await asyncio.sleep(2.15)
            after = json.loads(path.read_text())
            self.assertGreater(after['updated_unix'], first['updated_unix'] + 1)
            self.assertEqual(after['source_observed_unix'], first['source_observed_unix'])
            self.assertEqual(after['world_view'], view)
            await wire.close()
            await asyncio.wait_for(fixture.disconnected.wait(), 2)
            for _ in range(50):
                if not json.loads(path.read_text())['native_mc_verified']:
                    break
                await asyncio.sleep(.02)
            self.assertFalse(json.loads(path.read_text())['native_mc_verified'])
            self.assertIsNone(fixture.error)
        finally:
            await fixture.asyncTearDown()


if __name__ == '__main__':
    unittest.main()
