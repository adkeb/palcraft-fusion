"""A finite filesystem fixture for the normal-tool producer, no game or sockets."""
import importlib.util
import json
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path
from unittest.mock import patch

work = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(work / 'proposal/mcp'))
import mc_transport
import server


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding='utf-8')


with tempfile.TemporaryDirectory(dir=work / 'tests') as temporary:
    root = Path(temporary) / 'Owned Root'
    bridge = root / 'PalCraft-Dev/bridge'
    lab = root / 'BridgeLab/rpc'
    bridge.mkdir(parents=True); lab.mkdir(parents=True)
    write(root / '.palcraft/owner.json', {'kind': 'palcraft-player-owned-root', 'root': str(root)})
    identity = {'pal_uid': str(uuid.uuid4()), 'mc_uuid': str(uuid.uuid4()), 'mc_name': 'Fixture', 'world_id': 'fixture-world'}
    host_id, native_id = str(uuid.uuid4()), str(uuid.uuid4())
    sid, world = str(uuid.uuid4()), str(uuid.uuid4())
    host = {'state': 'bound', 'authenticated_host': True, 'identity': identity, 'session_id': host_id,
            'generation': 3, 'server_session_id': sid, 'expires_at': time.time() + 1000, 'updated_unix': time.time()}
    native = {'v': 2, 'legacy': False, **identity, 'session_id': native_id, 'generation': 4,
              'server_session_id': sid, 'expires_at': time.time() + 1000, 'mc_epoch': 'actual-fixture-epoch'}
    boot = {'native_mc_verified': True, 'authenticated_host': True, 'identity': identity, 'native_binding': native,
            'host_scope': {'session_id': host_id, 'generation': 3},
            'updated_unix': time.time(), 'world_view': {'world_session': world, 'dim': 'minecraft:overworld'}}
    write(bridge / 'runtime-config.json', {'identity': identity})
    write(bridge / 'session-bind-status.json', host); write(bridge / 'mc-bootstrap-status.json', boot)
    config = {'schema': 1, 'transport': 'localStandalone', 'owned_root': str(root), 'timeout_seconds': .5, 'poll_seconds': .005}
    client = mc_transport.LocalMCClient(config)
    submitted = []
    original_submit = client.submit_client_op

    def consumer(query, operation_id):
        deadline = time.monotonic() + 1
        mailbox = bridge / 'client-op.lua'
        while not mailbox.exists() and time.monotonic() < deadline: time.sleep(.002)
        source = mailbox.read_text(); mailbox.unlink()
        assert 'command.instance.send' in source and 'GetAsyncKeyState' not in source and 'agent-request.json' not in source
        record = json.loads((client.records / (operation_id + '.json')).read_text())
        submitted.append(operation_id)
        method = query['method']
        if method in ('slot', 'hud', 'action'):
            write(client.records / (operation_id + '-dispatch.json'), {'digest': record['digest'],
                  'state': 'submitted_release' if method == 'action' else 'submitted', 'accepted': True})
        else:
            if method == 'inspect': rows = [{'t': 'inspection', 'request_id': operation_id, 'uuid': identity['mc_uuid'], 'inventory': []}]
            elif method == 'block': rows = [{'t': 'blockinspection', 'request_id': operation_id, 'loaded': False}]
            else:
                common = {'t': 'blocks', 'request_id': operation_id, 'session': world, 'dim': 'minecraft:overworld'}
                rows = [{**common, 'lifecycle': [{'op': 'sync_requested', 'chunks': 1}]},
                        {**common, 'set': [1, 2, 3], 'geometry': [{'at': [1, 2, 3]}]},
                        {**common, 'lifecycle': [{'op': 'snapshot_end', 'snapshot': 'real-snapshot'}]}]
            with (lab / 'palcraft-events.ndjson').open('a') as stream:
                # A wrong request ID must not be mistaken for this operation.
                stream.write(json.dumps({'t': 'inspection', 'request_id': str(uuid.uuid4()), 'uuid': 'wrong'}) + '\n')
                for row in rows: stream.write(json.dumps(row) + '\n')

    queries = [{'method': 'inspect'}, {'method': 'block', 'x': 1, 'y': 2, 'z': 3}, {'method': 'blocks', 'radius': 32},
               {'method': 'action', 'key': 'use', 'duration_ms': 20}, {'method': 'slot', 'slot': 2}, {'method': 'hud', 'hidden': True}]
    for query in queries:
        operation_id = str(uuid.uuid4())
        thread = threading.Thread(target=consumer, args=(query, operation_id)); thread.start()
        result = client.call(query, operation_id); thread.join()
        assert result is not None
        cached = client.call(query, operation_id)
        assert cached == result and submitted.count(operation_id) == 1

    # Original collisions agent protocol only, not a WS packet in the AI queue.
    operation_id = str(uuid.uuid4())
    def lab_consumer():
        target = lab / 'agent-request.json'
        while not target.exists(): time.sleep(.002)
        value = json.loads(target.read_text())
        assert value == {'id': operation_id, 'method': 'palcraft_status'}
        write(lab / ('agent-result-' + operation_id + '.json'), {'id': operation_id, 'ok': True, 'result': {'running': True}})
    thread = threading.Thread(target=lab_consumer); thread.start()
    assert client.call({'method': 'collisions', 'action': 'status'}, operation_id) == {'running': True}; thread.join()
    assert client.call({'method': 'status'})['environment'] == 'MacStandalone'

    # A timed-out submitted ID remains observational; no new mailbox write.
    operation_id = str(uuid.uuid4()); client.timeout = .025
    try: client.call({'method': 'slot', 'slot': 1}, operation_id)
    except TimeoutError: pass
    else: raise AssertionError('Unknown mutation must timeout')
    before = (bridge / 'client-op.lua').read_bytes()
    try: client.call({'method': 'slot', 'slot': 1}, operation_id)
    except TimeoutError: pass
    else: raise AssertionError('Same pending ID must stay pending')
    assert (bridge / 'client-op.lua').read_bytes() == before
    try: client.call({'method': 'slot', 'slot': 3}, operation_id)
    except ValueError: pass
    else: raise AssertionError('ID cannot change payload')
    (bridge / 'client-op.lua').unlink()

    # Correlated snapshot cancellation and capacity rejection must never complete partial data.
    for event in ('snapshot_cancel', 'resync_required'):
        operation_id = str(uuid.uuid4()); scope = client.scope(); query = {'method': 'blocks', 'radius': 1}
        record = {'id': operation_id, 'digest': 'fixture', 'query': query, 'scope': scope, 'state': 'submitted',
                  'journal_offset': (lab / 'palcraft-events.ndjson').stat().st_size}
        client.save(record)
        with (lab / 'palcraft-events.ndjson').open('a') as stream:
            stream.write(json.dumps({'t': 'blocks', 'request_id': operation_id, 'session': world, 'dim': scope['dim'],
                                     'lifecycle': [{'op': event}]}) + '\n')
        try: client.wait_query(record, time.monotonic() + .2)
        except RuntimeError: pass
        else: raise AssertionError('Cancelled/capacity subset cannot be success')
        assert json.loads((client.records / (operation_id + '.json')).read_text())['state'] == 'failed'

    # Authentic epoch changes reject rather than manufacturing a new scope or retrying.
    old_scope = client.scope(); changed = dict(boot); changed['native_binding'] = {**native, 'mc_epoch': 'new-real-epoch'}
    write(bridge / 'mc-bootstrap-status.json', changed)
    try: client.still_current(old_scope)
    except RuntimeError: pass
    else: raise AssertionError('Old epoch must not be reused')

    # Existing MCP schema/15 AI delegation stays intact; local sends no ssh.
    with patch.object(mc_transport, 'call', return_value={'accepted': True}) as invoke:
        for tool in server.TOOLS:
            arguments = {'palcraft_block': {'x': 0, 'y': 64, 'z': 0}, 'palcraft_collisions': {'action': 'status'},
                         'palcraft_action': {'key': 'attack'}, 'palcraft_slot': {'slot': 0}, 'palcraft_hud': {'hidden': False}}.get(tool['name'], {})
            server.invoke(tool['name'], arguments)
        assert invoke.call_count == 8
    assert len(server.TOOLS) == 8
    assert len(server.dispatch({'method': 'tools/list'})['tools']) == 23
    with patch.object(mc_transport.subprocess, 'run') as ssh:
        ssh.return_value.returncode = 0; ssh.return_value.stdout = b'{"legacy":true}'
        assert mc_transport.call({'method': 'inspect'}, config={'transport': 'ssh', 'ssh_target': 'fixture-host'}) == {'legacy': True}
        assert ssh.call_count == 1
print(json.dumps({'fixture': 'normal_mc_local_protocol', 'tools': 8, 'groups': 5,
                  'same_ID_single_submission': True, 'cancel_capacity_epoch_reject': True,
                  'explicit_windows_branch_retained': True, 'new_network_connections': 0, 'live_game_calls': 0}))
