import asyncio
import json
import os
import struct
import sys
import tempfile
import time
import unittest
from pathlib import Path
BASE=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(BASE))
from launcher.udp_tunnel_player import LocalRelay
from launcher.runtime import status,process_identity
from installer.core import atomic_json,get_state
import test_player_tools as fixtures

class RecoveryTests(unittest.IsolatedAsyncioTestCase):
    async def test_same_udp_socket_reconnects_after_tcp_forward_rebuild(self):
        temp=tempfile.TemporaryDirectory(prefix='palcraft-reconnect-test-')
        root=Path(temp.name).resolve();received=asyncio.Queue();wires=set();connections=[]
        async def echo(reader,writer):
            wires.add(writer);connections.append(writer)
            try:
                while True:
                    h=await reader.readexactly(4);n=struct.unpack('!I',h)[0]
                    writer.write(h+await reader.readexactly(n));await writer.drain()
            except (OSError,asyncio.IncompleteReadError):pass
            finally:
                wires.discard(writer);writer.close();await writer.wait_closed()
        server=await asyncio.start_server(echo,'127.0.0.1',0);port=server.sockets[0].getsockname()[1]
        relay=LocalRelay(port,idle_seconds=5,status_file=root/'udp.json')
        transport,_=await asyncio.get_running_loop().create_datagram_endpoint(lambda:relay,local_addr=('127.0.0.1',0))
        class Receiver(asyncio.DatagramProtocol):
            def datagram_received(self,data,addr):received.put_nowait(data)
        client,_=await asyncio.get_running_loop().create_datagram_endpoint(Receiver,local_addr=('127.0.0.1',0))
        endpoint=transport.get_extra_info('sockname')
        try:
            client.sendto(b'before-ssh-rebuild',endpoint)
            self.assertEqual(await asyncio.wait_for(received.get(),2),b'before-ssh-rebuild')
            for writer in list(wires):writer.close();await writer.wait_closed()
            server.close();await server.wait_closed()
            deadline=time.monotonic()+2
            while relay.peers and time.monotonic()<deadline:await asyncio.sleep(.01)
            self.assertEqual(relay.peers,{})
            self.assertEqual(json.loads((root/'udp.json').read_text())['phase'],'reconnecting')
            server=await asyncio.start_server(echo,'127.0.0.1',port)
            client.sendto(b'after-ssh-rebuild',endpoint)
            self.assertEqual(await asyncio.wait_for(received.get(),2),b'after-ssh-rebuild')
            self.assertEqual(transport.get_extra_info('sockname'),endpoint)
            self.assertEqual(len(connections),2);self.assertEqual(relay.connections,2)
            relay.report();info=json.loads((root/'udp.json').read_text())
            self.assertEqual(info['connected_peers'],1);self.assertFalse(info['pal_session_verified'])
        finally:
            client.close();await relay.close();server.close();await server.wait_closed();temp.cleanup()

class ReadyTests(unittest.TestCase):
    def setUp(self):
        self.fixture=fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes');self.fixture.setUp();self.fixture.installed()
        self.root=self.fixture.root
        state=get_state(self.root);state['profile']['connection']['mode']='strict-player';atomic_json(self.root/'.palcraft/state.json',state)
        own={'pid':os.getpid(),'identity':process_identity(os.getpid())}
        atomic_json(self.root/'.palcraft/session.json',{'phase':'running','supervisor':own,'components':{k:own for k in ('client','ssh','udp','proxy','hud')}})
        atomic_json(self.root/'PalCraft-Dev/bridge/session-bind-status.json',{'state':'bound','authenticated_host':True,'updated_unix':time.time()})
        atomic_json(self.root/'PalCraft-Dev/bridge/client-status.json',{'unix':time.time(),'host_input_gate':{'allowed':True}})
        atomic_json(self.root/'.palcraft/transport/udp-status.json',{'updated_unix':time.time(),'connected_peers':1,'last_reply_unix':time.time()})
    def tearDown(self):self.fixture.tearDown()
    def test_fresh_real_gate_and_reply_required(self):
        self.assertTrue(status(self.root)['game_ready'])
        atomic_json(self.root/'.palcraft/transport/udp-status.json',{'updated_unix':time.time(),'connected_peers':1,'last_reply_unix':time.time()-30})
        self.assertFalse(status(self.root)['game_ready'])
        self.assertTrue(status(self.root)['supervisor_alive'])
    def test_fresh_binding_without_local_pal_gate_is_not_ready(self):
        atomic_json(self.root/'PalCraft-Dev/bridge/client-status.json',{'unix':time.time(),'host_input_gate':{'allowed':False}})
        self.assertFalse(status(self.root)['game_ready'])
