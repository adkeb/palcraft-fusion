"""Existing BridgeLab RPC via a private Mac file queue or explicit legacy SSH."""
import argparse
import base64
import contextlib
import json
import os
import re
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

METHODS = ('status', 'operation', 'models', 'build', 'geometry', 'materials', 'catalog',
           'dismantle', 'terrain', 'transform', 'finish', 'bases', 'storage',
           'storage_plan', 'storage_apply', 'storage_operation')


def _uuid(value):
    if not isinstance(value, str) or str(uuid.UUID(value)) != value:
        raise ValueError('request_id must be a canonical UUID')
    return value


def _request(method, params, request_id):
    request_id = _uuid(str(uuid.uuid4()) if request_id is None else request_id)
    if method not in METHODS or (params is not None and not isinstance(params, dict)):
        raise ValueError('Unsupported method or invalid params')
    request = {'id': request_id, 'method': method, 'params': params or {}}
    json.dumps(request, ensure_ascii=False, allow_nan=False)
    return request


def _timeout(value):
    if type(value) not in (int, float) or not 0 < value <= 120:
        raise ValueError('timeout_seconds must be finite and between 0 and 120')
    return value


def _physical_path(value):
    """CrossOver's standard Z: -> / mapping; other drives are never guessed."""
    value = str(value)
    if re.match(r'^[A-Za-z]:', value):
        if value[:2].lower() != 'z:' or len(value) < 3 or value[2] not in '/\\':
            raise ValueError('localStandalone requires the standard absolute Z: path')
        value = value[2:].replace('\\', '/')
    path = Path(value)
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('The local root must be an absolute physical or Z: path')
    return path


def _no_links(path):
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError('The private RPC path must not contain symlinks')
    return path


def _read_json(path):
    _no_links(path)
    return json.loads(path.read_text(encoding='utf-8-sig'))


def _atomic_write(path, value):
    _no_links(path)
    fd, temporary = tempfile.mkstemp(prefix='agent-request-', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            json.dump(value, output, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def _response(value, request_id):
    if not isinstance(value, dict) or value.get('id') != request_id or type(value.get('ok')) is not bool:
        raise RuntimeError('Invalid RPC result; operation_id=' + request_id)
    return value


def _result(value, request_id):
    value = _response(value, request_id)
    if not value['ok']:
        raise RuntimeError('operation_id=' + request_id + '; ' + str(value.get('error', 'Agent error')))
    if 'result' not in value:
        raise RuntimeError('Missing RPC result; operation_id=' + request_id)
    return value['result']


class LocalQueueClient:
    """A producer for the existing single-slot game-thread queue; no new reader."""
    def __init__(self, owned_root, rpc_directory='BridgeLab/rpc', windows_root=None,
                 timeout_seconds=40, poll_seconds=.1):
        self.root = _no_links(_physical_path(owned_root))
        if not self.root.is_dir() or self.root.resolve() != self.root:
            raise ValueError('Configured owned root is not an existing physical directory')
        try:
            owner = _read_json(self.root / '.palcraft/owner.json')
        except FileNotFoundError as error:
            raise ValueError('Configured root has no player installer ownership marker') from error
        if owner.get('kind') != 'palcraft-player-owned-root' or owner.get('root') != str(self.root):
            raise ValueError('Configured root is not owned by the player installer')
        self.windows_root = 'Z:' + self.root.as_posix()
        if windows_root is not None and _physical_path(windows_root) != self.root:
            raise ValueError('Windows root and Mac physical owned root disagree')
        value = str(rpc_directory).replace('\\', '/')
        directory = _physical_path(value) if value.startswith('/') or re.match(r'^[A-Za-z]:', value) else self.root / value
        if '..' in directory.parts or directory == self.root or not directory.is_relative_to(self.root):
            raise ValueError('RPC directory must be inside this owned root')
        self.directory = _no_links(directory)
        if not self.directory.is_dir():
            raise ValueError('Configured private RPC directory does not exist')
        self.timeout_seconds = _timeout(timeout_seconds)
        if type(poll_seconds) not in (int, float) or not .005 <= poll_seconds <= 1:
            raise ValueError('poll_seconds must be between .005 and 1')
        self.poll_seconds = poll_seconds

    @contextlib.contextmanager
    def _lock(self, deadline, request_id):
        import fcntl
        path = _no_links(self.directory / 'agent-client.lock')
        fd = os.open(path, os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        with os.fdopen(fd, 'a+b') as lock:
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise TimeoutError('RPC queue busy; request not submitted; operation_id=' + request_id)
                    time.sleep(min(self.poll_seconds, max(0, deadline - time.monotonic())))
            try:
                yield
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)

    def call(self, method, params=None, request_id=None):
        request = _request(method, params, request_id)
        deadline = time.monotonic() + self.timeout_seconds
        current_path = self.directory / 'agent-request.json'
        result_path = self.directory / ('agent-result-' + request['id'] + '.json')
        with self._lock(deadline, request['id']):
            while True:
                previous = _read_json(current_path) if current_path.exists() else None
                if previous is not None:
                    if not isinstance(previous, dict):
                        raise RuntimeError('Invalid existing agent request; queue was not replaced')
                    previous_id = _uuid(previous.get('id'))
                    _request(previous.get('method'), previous.get('params'), previous_id)
                    if previous_id == request['id']:
                        if {'id': previous_id, 'method': previous['method'], 'params': previous.get('params') or {}} != request:
                            raise ValueError('Same operation_id has different method/params: ' + request['id'])
                        break  # Observe this pending ID without rewriting or resubmitting it.
                if result_path.exists():
                    return _result(_read_json(result_path), request['id'])
                if previous is None or (self.directory / ('agent-result-' + previous_id + '.json')).exists():
                    if previous is not None:
                        _response(_read_json(self.directory / ('agent-result-' + previous_id + '.json')), previous_id)
                        _atomic_write(self.directory / 'agent-request.previous.json', previous)
                    _atomic_write(current_path, request)
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError('Previous BridgeLab operation pending: ' + previous_id +
                                       '; request not submitted; operation_id=' + request['id'])
                time.sleep(min(self.poll_seconds, max(0, deadline - time.monotonic())))
            while True:
                if result_path.exists():
                    try:
                        value = _read_json(result_path)
                    except (json.JSONDecodeError, FileNotFoundError):
                        pass  # Existing game writer may still be replacing its result.
                    else:
                        return _result(value, request['id'])
                if time.monotonic() >= deadline:
                    raise TimeoutError('BridgeLab operation pending or outcome unknown; operation_id=' + request['id'] +
                                       '. Inspect this same ID; do not retry a mutation with a new ID.')
                time.sleep(min(self.poll_seconds, max(0, deadline - time.monotonic())))


def load_config(config=None):
    if isinstance(config, dict):
        value = dict(config)
    else:
        configured = config or os.environ.get('PALCRAFT_AI_CONFIG')
        path = Path(configured) if configured else Path(__file__).with_name('ai-transport.json')
        if configured and not path.is_file():
            raise ValueError('AI transport profile does not exist: ' + str(path))
        value = json.loads(path.read_text(encoding='utf-8')) if path.is_file() else {'transport': 'localStandalone'}
    if not isinstance(value, dict) or value.get('schema', 1) != 1:
        raise ValueError('Invalid AI transport profile')
    return value


def _configured_root(config):
    root = config.get('owned_root') or os.environ.get(config.get('root_environment', 'PALCRAFT_WINDOWS_ROOT'))
    if not root:
        for parent in Path(__file__).resolve().parents:
            if (parent / '.palcraft/owner.json').is_file():
                return str(parent)
        raise ValueError('localStandalone requires owned_root or PALCRAFT_WINDOWS_ROOT in its runtime profile')
    return root


def _ssh_call(request, config):
    target = config.get('ssh_target', '5090')
    if not isinstance(target, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._@-]{0,190}', target):
        raise ValueError('Invalid SSH target')
    script = config.get('invoke_agent', 'D:/PalworldServer-LAN/BridgeLab/Invoke-Agent.ps1')
    if not isinstance(script, str) or not re.match(r'^[A-Za-z]:[/\\]', script) or any(c in script for c in '\r\n\x00'):
        raise ValueError('Invalid Invoke-Agent path')
    ps = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';[Console]::InputEncoding=[Text.Encoding]::UTF8;[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false);& '" + script.replace("'", "''") + "'"
    encoded = base64.b64encode(ps.encode('utf-16le')).decode()
    command = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=5',
               '-o', 'ServerAliveCountMax=2', target, 'powershell -NoProfile -NonInteractive -EncodedCommand ' + encoded]
    for attempt in range(3):
        try:
            response = subprocess.run(command, input=json.dumps(request, ensure_ascii=False).encode(),
                                      capture_output=True, timeout=_timeout(config.get('timeout_seconds', 40)), check=False)
        except subprocess.TimeoutExpired:
            if attempt == 2:
                raise RuntimeError('Transport timeout; operation_id=' + request['id'] + '. Inspect this same operation ID before retrying.')
            time.sleep(.5)
            continue
        if response.returncode == 0:
            break
        if attempt == 2:
            raise RuntimeError('operation_id=' + request['id'] + '; ' + response.stderr.decode('utf-8', errors='replace')[-3500:])
        time.sleep(.5)
    value = json.loads(response.stdout.decode('utf-8-sig'))
    if not value['ok']:
        raise RuntimeError(value['error'])
    return value['result']


def call(method, params=None, request_id=None, *, config=None):
    config = load_config(config)
    transport = config.get('transport', 'localStandalone')
    if transport == 'localStandalone':
        client = LocalQueueClient(_configured_root(config), config.get('rpc_directory', 'BridgeLab/rpc'),
                                  config.get('windows_root'), config.get('timeout_seconds', 40))
        return client.call(method, params, request_id)
    if transport == 'ssh':
        return _ssh_call(_request(method, params, request_id), config)
    raise ValueError('Unsupported AI transport: ' + str(transport))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('method', choices=METHODS)
    parser.add_argument('params', nargs='?')
    parser.add_argument('--request-id')
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--config')
    source.add_argument('--root', help='Owned Mac physical root or its standard Z: path')
    parser.add_argument('--timeout', type=float)
    args = parser.parse_args()
    config = load_config(args.config)
    if args.root:
        config.update(transport='localStandalone', owned_root=args.root)
    if args.timeout is not None:
        config['timeout_seconds'] = _timeout(args.timeout)
    params = json.loads(Path(args.params).read_text()) if args.params else {}
    print(json.dumps(call(args.method, params, args.request_id, config=config), ensure_ascii=False, indent=2))
