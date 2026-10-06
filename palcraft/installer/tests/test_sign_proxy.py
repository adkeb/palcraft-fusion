"""One actual proxy/receiver glyph flow with synthetic identity and a tiny PNG."""
import asyncio
import base64
import hashlib
import json
import struct
import time
import unittest
import zlib
from pathlib import Path

import test_sessions as fixtures
from launcher.session_proxy import sign_receiver_from_path


def tiny_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(b'\x00\xff\x00\x00\xff')) + chunk(b'IEND', b''))


class SignProxyWire(unittest.IsolatedAsyncioTestCase):
    async def test_glyphs_remain_private_and_retry_uses_original_fence(self):
        fixture = fixtures.ProxyTests(methodName='test_hmac_bind_scopes_camera_and_preserves_world_session')
        await fixture.asyncSetUp()
        try:
            receiver = Path(__file__).resolve().parents[3] / 'sign-text/python/receiver.py'
            fixture.proxy.sign_receiver_factory = sign_receiver_from_path(receiver)
            wire = await fixture.native()
            await wire.receive()
            request = dict(t='sign_text_view', op='bind', world_session='wire-world', dim='minecraft:overworld',
                           view=7, mapping='native-mapping:7', mc_uuid=fixture.credential['identity']['mc_uuid'],
                           bounds=[0, 0, 0, 16, 256, 16])
            await wire.send(json.dumps(request))
            first = await asyncio.wait_for(fixture.received.get(), 2)
            host = first['session']
            self.assertEqual({k: first[k] for k in request}, request)
            await wire.receive()
            guest = next(iter(fixture.guest_wires))
            sink = fixture.root / 'sign-text-v1'
            raw = tiny_png()
            sha = hashlib.sha256(raw).hexdigest()
            envelope = {k: request[k] for k in ('world_session', 'dim', 'view', 'mapping', 'mc_uuid')}
            envelope.update(schema=1, producer='wire-mc', epoch=1, seq=1, created_ms=time.time_ns() // 1000000)
            image = dict(sha256=sha, path='textures/' + sha + '.png', width=1, height=1)
            snapshot = dict(envelope, t='sign_text', complete=True, available=True,
                            rows=[dict(at=[3, 64, 2], front={'image': image}, back={'image': image})])
            await guest.send(json.dumps(dict(envelope, t='sign_text_snapshot', snapshot=snapshot, host_session=host)))
            retry = await asyncio.wait_for(fixture.received.get(), 2)
            self.assertEqual({k: retry[k] for k in request}, request)
            self.assertGreater(retry['seq'], first['seq'])
            self.assertFalse((sink / 'snapshot.json').exists())
            # Only the fixture's response to retry reaches native, never the glyph footer.
            self.assertEqual(json.loads(await wire.receive())['t'], 'blockpatch')
            asset = dict(envelope, t='sign_text_asset', sha256=sha, bytes=len(raw), offset=0,
                         final=True, width=1, height=1, data=base64.b64encode(raw).decode())
            await guest.send(json.dumps(dict(asset, host_session=host)))
            await guest.send(json.dumps(dict(t='blockpatch', marker='after-asset', host_session=host)))
            self.assertEqual(json.loads(await wire.receive()), dict(t='blockpatch', marker='after-asset'))
            self.assertEqual((sink / 'textures' / (sha + '.png')).read_bytes(), raw)
            self.assertEqual(json.loads((sink / 'snapshot.json').read_text()), snapshot)
            changed = dict(request, view=8, mapping='native-mapping:8')
            await wire.send(json.dumps(changed))
            await asyncio.wait_for(fixture.received.get(), 2)
            await wire.receive()
            self.assertFalse((sink / 'snapshot.json').exists())
            await guest.send(json.dumps(dict(envelope, t='sign_text_snapshot', snapshot=snapshot, host_session=host)))
            await guest.send(json.dumps(dict(t='blockpatch', marker='after-old-view', host_session=host)))
            self.assertEqual(json.loads(await wire.receive()).get('marker'), 'after-old-view')
            self.assertFalse((sink / 'snapshot.json').exists())
            # A second partial asset is removed when the host lease is rejected.
            raw2 = raw + b'fixture-pending'
            partial = dict(asset, view=8, mapping=changed['mapping'], seq=2, sha256=hashlib.sha256(raw2).hexdigest(),
                           bytes=len(raw2), final=False, data=base64.b64encode(raw2[:20]).decode())
            await guest.send(json.dumps(dict(partial, host_session=host)))
            await guest.send(json.dumps(dict(t='blockpatch', marker='partial-started', host_session=host)))
            self.assertEqual(json.loads(await wire.receive()).get('marker'), 'partial-started')
            self.assertEqual(len(list((sink / '.receiving').glob('*.part'))), 1)
            stale_host = dict(host, generation=host['generation'] - 1)
            await guest.send(json.dumps(dict(asset, host_session=stale_host)))
            with self.assertRaises((EOFError, asyncio.IncompleteReadError)):
                await asyncio.wait_for(wire.receive(), 2)
            self.assertFalse(list((sink / '.receiving').glob('*.part')))
            self.assertFalse((sink / 'snapshot.json').exists())
            self.assertNotIn('sign_text_receiver', json.loads((fixture.root / 'status.json').read_text()))
            self.assertIsNone(fixture.error)
        finally:
            await fixture.asyncTearDown()


if __name__ == '__main__':
    unittest.main()
