"""One Mac temporary-directory fixture; never contacts a game or SSH host."""
import contextlib
import io
import json
import os
import runpy
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ai_client
import ai_tools


def write(path, value):
    temporary = path.with_suffix('.fixture-tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False))
    os.replace(temporary, path)


class LocalQueueTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-ai-local-')
        self.root = Path(self.temp.name).resolve() / '玩家 客户端'
        (self.root / '.palcraft').mkdir(parents=True)
        self.rpc = self.root / 'BridgeLab/rpc'
        self.rpc.mkdir(parents=True)
        write(self.root / '.palcraft/owner.json', {'kind': 'palcraft-player-owned-root', 'root': str(self.root)})
        self.config = {'schema': 1, 'transport': 'localStandalone', 'owned_root': str(self.root),
                       'windows_root': 'Z:' + self.root.as_posix(), 'rpc_directory': 'BridgeLab/rpc', 'timeout_seconds': .3}
        self.client = ai_client.LocalQueueClient(self.root, timeout_seconds=.3, poll_seconds=.005)
        self.requests, self.fixture_errors = [], []
        self.done = threading.Event()
        self.thread = None
        self.no_network = patch.object(ai_client.subprocess, 'run', side_effect=AssertionError('No subprocess/SSH allowed in local fixture'))
        self.no_network.start()

    def tearDown(self):
        self.done.set()
        if self.thread:
            self.thread.join(timeout=1)
            self.assertFalse(self.thread.is_alive())
        self.no_network.stop()
        self.assertEqual(self.fixture_errors, [])
        self.temp.cleanup()

    def agent_fixture(self, delay=0):
        def run():
            seen = set()
            try:
                while not self.done.is_set():
                    current = self.rpc / 'agent-request.json'
                    if current.exists():
                        request = json.loads(current.read_text())
                        if request['id'] not in seen:
                            seen.add(request['id'])
                            self.requests.append(request)
                            time.sleep(delay)
                            write(self.rpc / ('agent-result-' + request['id'] + '.json'),
                                  {'id': request['id'], 'ok': True, 'result': {'echo': request}})
                    self.done.wait(.002)
            except BaseException as error:
                self.fixture_errors.append(str(error))
        self.thread = threading.Thread(target=run)
        self.thread.start()

    def test_all_existing_rpc_methods_keep_exact_request_and_result_format(self):
        self.agent_fixture()
        for method in ai_client.METHODS:
            request_id = str(uuid.uuid4())
            params = {'fixture': '中文路径', 'nested': {'n': 1}}
            result = self.client.call(method, params, request_id)
            self.assertEqual(result, {'echo': {'id': request_id, 'method': method, 'params': params}})
        self.assertEqual(len(self.requests), 16)
        self.assertEqual(list(self.rpc.glob('agent-request-*.tmp')), [])
        self.assertEqual((self.rpc / 'agent-request.json').stat().st_mode & 0o777, 0o600)

    def test_unknown_mutation_same_id_is_observed_without_resubmission(self):
        client = ai_client.LocalQueueClient(self.root, timeout_seconds=.02, poll_seconds=.005)
        request_id = str(uuid.uuid4())
        params = {'mode': 'survival', 'fixture': 'never executed'}
        with self.assertRaisesRegex(TimeoutError, request_id):
            client.call('build', params, request_id)
        pending = self.rpc / 'agent-request.json'
        before = (pending.read_bytes(), pending.stat().st_mtime_ns, pending.stat().st_ino)
        with self.assertRaisesRegex(TimeoutError, request_id):
            client.call('build', params, request_id)
        with self.assertRaisesRegex(TimeoutError, 'request not submitted'):
            client.call('build', params, str(uuid.uuid4()))
        self.assertEqual(before, (pending.read_bytes(), pending.stat().st_mtime_ns, pending.stat().st_ino))
        with self.assertRaisesRegex(ValueError, 'different method/params'):
            client.call('build', {'mode': 'creative'}, request_id)
        write(self.rpc / ('agent-result-' + request_id + '.json'), {'id': request_id, 'ok': True, 'result': {'accepted': True}})
        self.assertEqual(client.call('build', params, request_id), {'accepted': True})
        self.assertEqual(before, (pending.read_bytes(), pending.stat().st_mtime_ns, pending.stat().st_ino))

    def test_concurrent_local_producers_do_not_overwrite_a_pending_request(self):
        self.agent_fixture(delay=.015)
        ids = [str(uuid.uuid4()), str(uuid.uuid4())]
        results, errors = [], []
        def submit(request_id):
            try:
                results.append(self.client.call('status', {}, request_id))
            except Exception as error:
                errors.append(str(error))
        threads = [threading.Thread(target=submit, args=(request_id,)) for request_id in ids]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=1)
            self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual({result['echo']['id'] for result in results}, set(ids))
        self.assertEqual({request['id'] for request in self.requests}, set(ids))

    def test_result_identity_error_and_completed_slot_are_preserved(self):
        request_id = str(uuid.uuid4())
        write(self.rpc / ('agent-result-' + request_id + '.json'), {'id': str(uuid.uuid4()), 'ok': True, 'result': {}})
        with self.assertRaisesRegex(RuntimeError, 'Invalid RPC result'):
            self.client.call('status', {}, request_id)
        write(self.rpc / 'agent-request.json', {'id': request_id, 'method': 'status', 'params': {}})
        write(self.rpc / ('agent-result-' + request_id + '.json'), {'id': request_id, 'ok': False, 'error': 'fixture agent error'})
        with self.assertRaisesRegex(RuntimeError, 'fixture agent error'):
            self.client.call('status', {}, request_id)
        self.agent_fixture()
        next_id = str(uuid.uuid4())
        self.assertEqual(self.client.call('bases', {}, next_id)['echo']['id'], next_id)
        self.assertEqual(json.loads((self.rpc / 'agent-request.previous.json').read_text())['id'], request_id)

    def test_standard_z_mapping_and_private_scope_are_required(self):
        root_windows = 'Z:' + self.root.as_posix()
        client = ai_client.LocalQueueClient(root_windows.replace('/', chr(92)),
            root_windows + '/BridgeLab/rpc', windows_root=root_windows)
        self.assertEqual(client.directory, self.rpc)
        with self.assertRaises(ValueError):
            ai_client.LocalQueueClient(self.root, '../outside')
        with self.assertRaises(ValueError):
            ai_client.LocalQueueClient(self.root, windows_root='D:/PalworldServer-LAN')
        alias = self.root / 'rpc-link'
        alias.symlink_to(self.rpc)
        with self.assertRaises(ValueError):
            ai_client.LocalQueueClient(self.root, 'rpc-link')
        with self.assertRaises(ValueError):
            ai_client.LocalQueueClient(self.root.parent)

    def test_existing_stdio_tools_use_the_current_local_profile(self):
        self.agent_fixture()
        config = self.root.parent / 'private-ai-transport.json'
        write(config, self.config)
        requests = [{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
                    {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
                     'params': {'name': 'palworld_ai_status', 'arguments': {}}}]
        output = io.StringIO()
        with patch.dict(os.environ, {'PALCRAFT_AI_CONFIG': str(config)}), \
                patch.object(sys, 'stdin', io.StringIO(''.join(json.dumps(request) + '\n' for request in requests))), \
                contextlib.redirect_stdout(output):
            runpy.run_path(str(Path(ai_tools.__file__)), run_name='__main__')
        answers = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(answers[0]['result']['tools']), 15)
        self.assertEqual(answers[1]['result']['structuredContent']['echo']['method'], 'status')
        self.assertEqual(ai_client.load_config()['transport'], 'localStandalone')

    def test_explicit_legacy_ssh_keeps_the_same_uuid_and_configured_target(self):
        request_id = str(uuid.uuid4())
        completed = subprocess.CompletedProcess([], 0, json.dumps({'ok': True, 'result': {'legacy': True}}).encode(), b'')
        with patch.object(ai_client.subprocess, 'run', return_value=completed) as run:
            result = ai_client.call('status', {}, request_id, config={'transport': 'ssh', 'ssh_target': 'future-host'})
        self.assertEqual(result, {'legacy': True})
        self.assertIn('future-host', run.call_args.args[0])
        self.assertEqual(json.loads(run.call_args.kwargs['input'])['id'], request_id)


if __name__ == '__main__':
    unittest.main()
