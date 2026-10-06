import asyncio
import json
import unittest
import uuid
from pathlib import Path

import test_sessions as session_fixtures
from launcher.session_proxy import sign_receiver_from_path


class TravelMirrorWire(unittest.IsolatedAsyncioTestCase):
    async def test_server_travel_reaches_local_journal_without_rewriting_native_scope(self):
        fixture = session_fixtures.ProxyTests(methodName='test_hmac_bind_scopes_camera_and_preserves_world_session')
        await fixture.asyncSetUp()
        try:
            receiver = Path(__file__).resolve().parents[3] / 'sign-text/python/receiver.py'
            fixture.proxy.sign_receiver_factory = sign_receiver_from_path(receiver)
            wire = await fixture.native()
            await wire.receive()
            status = json.loads((fixture.root / 'status.json').read_text())
            self.assertEqual(status['sign_text_receiver'], {'version': 1, 'installed': True})
            await wire.send(json.dumps({'t': 'inspect'}))
            host = (await asyncio.wait_for(fixture.received.get(), 2))['session']
            await wire.receive()
            native_sid = str(uuid.uuid4())
            common = dict(t='travel', v=1, player=host['mc_uuid'], pal_uid=host['pal_uid'],
                          world_id=host['world_id'], server_session_id=host['server_session_id'],
                          session_id=native_sid, session_generation=8, mc_epoch='fixture-native-epoch',
                          world_session='fixture-world', dim='minecraft:the_nether', view=2, tx='fixture-trip:1')
            path = fixture.root / 'travel-events.ndjson'
            expected = []
            guest = next(iter(fixture.guest_wires))
            for phase in ('prepare', 'committed', 'complete'):
                row = dict(common, phase=phase)
                expected.append(row)
                await guest.send(json.dumps(dict(row, host_session=host)))
                self.assertEqual(json.loads(await asyncio.wait_for(wire.receive(), 2)), row)
            actual = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(actual, expected)
            self.assertNotEqual(actual[0]['session_id'], host['session_id'])
            self.assertTrue(all('host_session' not in row for row in actual))
            for operation in ('travel_ready', 'travel_observed', 'travel_abort'):
                query = dict(common, t=operation, phase=operation.removeprefix('travel_'))
                await wire.send(json.dumps(query))
                received = await asyncio.wait_for(fixture.received.get(), 2)
                self.assertEqual(received['t'], operation)
                self.assertEqual(received['tx'], common['tx'])
                self.assertEqual(received['session']['session_id'], host['session_id'])
                self.assertEqual(received['session_id'], native_sid)
                await asyncio.wait_for(wire.receive(), 2)
            # A stale HOST envelope never reaches either native or its local journal.
            bad_scope = dict(host, generation=host['generation'] - 1)
            await guest.send(json.dumps(dict(common, phase='prepare', host_session=bad_scope)))
            with self.assertRaises((EOFError, asyncio.IncompleteReadError)):
                await asyncio.wait_for(wire.receive(), 2)
            self.assertEqual([json.loads(line) for line in path.read_text().splitlines()], expected)
            status = json.loads((fixture.root / 'status.json').read_text())
            self.assertNotIn('sign_text_receiver', status)
            self.assertIsNone(fixture.error)
        finally:
            await fixture.asyncTearDown()


if __name__ == '__main__':
    unittest.main()
