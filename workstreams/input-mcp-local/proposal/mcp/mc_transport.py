"""Normal MC tools over the existing owned queues, never a second WS controller."""
import base64
import contextlib
import datetime
import hashlib
import json
import os
import subprocess
import time
import uuid
from pathlib import Path
import ai_client

METHODS = {'block', 'inspect', 'collisions', 'status', 'blocks', 'action', 'slot', 'hud'}


def request_id(value=None):
    value = str(uuid.uuid4()) if value is None else value
    if not isinstance(value, str) or str(uuid.UUID(value)) != value:
        raise ValueError('request_id must be a canonical UUID')
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False)


def atomic(path, value):
    ai_client._atomic_write(path, value)


@contextlib.contextmanager
def queue_lock(path, deadline, poll):
    import fcntl
    ai_client._no_links(path)
    with os.fdopen(os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), 'a+b') as stream:
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError('Queue busy; operation was not submitted')
                time.sleep(poll)
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def lua_string(text):
    delimiter = '===='
    while ']' + delimiter + ']' in text:
        delimiter += '='
    return '[' + delimiter + '[' + text + ']' + delimiter + ']'


class LocalMCClient:
    def __init__(self, config):
        self.config = config
        self.root = ai_client._no_links(ai_client._physical_path(ai_client._configured_root(config)))
        owner = ai_client._read_json(self.root / '.palcraft/owner.json')
        if owner.get('kind') != 'palcraft-player-owned-root' or owner.get('root') != str(self.root) or self.root.resolve() != self.root:
            raise ValueError('Private player-owned root required')
        if config.get('windows_root') is not None and ai_client._physical_path(config['windows_root']) != self.root:
            raise ValueError('Configured Mac and Windows roots disagree')
        self.windows_root = 'Z:' + self.root.as_posix()
        self.bridge = self.path('PalCraft-Dev/bridge')
        self.lab = self.path('BridgeLab/rpc')
        self.timeout = ai_client._timeout(config.get('timeout_seconds', 40))
        self.poll = config.get('poll_seconds', .1)
        if type(self.poll) not in (int, float) or not .005 <= self.poll <= 1:
            raise ValueError('Invalid poll_seconds')
        self.records = self.path('PalCraft-Dev/bridge/mcp-normal-operations')
        self.records.mkdir(mode=0o700, exist_ok=True)
        self.max_response_bytes = config.get('max_response_bytes', 16 * 1024 * 1024)
        if type(self.max_response_bytes) is not int or not 65536 <= self.max_response_bytes <= 64 * 1024 * 1024:
            raise ValueError('Invalid bounded MC response size')

    def path(self, relative):
        value = str(relative).replace('\\', '/')
        if value.startswith('/') or '..' in Path(value).parts or ':' in value:
            raise ValueError('Installation-relative path required')
        return ai_client._no_links(self.root / value)

    def read(self, relative):
        return ai_client._read_json(self.path(relative))

    def scope(self):
        now = time.time()
        identity = self.read('PalCraft-Dev/bridge/runtime-config.json')['identity']
        host = self.read('PalCraft-Dev/bridge/session-bind-status.json')
        boot = self.read('PalCraft-Dev/bridge/mc-bootstrap-status.json')
        native = boot.get('native_binding') or {}
        view = boot.get('world_view') or {}
        host_scope = boot.get('host_scope') or {}
        keys = ('pal_uid', 'mc_uuid', 'mc_name', 'world_id')
        expected = {k: identity[k] for k in keys}
        if any(host.get('identity', {}).get(k) != expected[k] or boot.get('identity', {}).get(k) != expected[k] for k in keys):
            raise RuntimeError('Actual configured player identity mismatch')
        if (host.get('state') != 'bound' or host.get('authenticated_host') is not True or boot.get('native_mc_verified') is not True
                or boot.get('authenticated_host') is not True or native.get('v') != 2 or native.get('legacy') is not False):
            raise RuntimeError('Actual authenticated HOST/native MC binding unavailable')
        for value in (host, boot):
            if not isinstance(value.get('updated_unix'), (int, float)) or not -5 <= now - value['updated_unix'] <= 5:
                raise RuntimeError('Runtime binding observation is stale')
        if any(native.get(k) != expected[k] for k in ('pal_uid', 'mc_uuid', 'world_id')):
            raise RuntimeError('Native MC identity mismatch')
        if native.get('server_session_id') != host.get('server_session_id') or native.get('expires_at', 0) <= now or host.get('expires_at', 0) <= now:
            raise RuntimeError('Runtime binding expired or changed')
        if host_scope.get('session_id') != host.get('session_id') or host_scope.get('generation') != host.get('generation'):
            raise RuntimeError('Bootstrap belongs to a different actual HOST lease')
        for value in (host, native):
            request_id(value.get('session_id'))
            if type(value.get('generation')) is not int or value['generation'] < 1:
                raise RuntimeError('Actual session generation unavailable')
        if not native.get('mc_epoch') or not view.get('world_session') or not view.get('dim'):
            raise RuntimeError('Actual MC world epoch unavailable')
        return {'identity': expected, 'server_session_id': host['server_session_id'], 'host_session_id': host['session_id'],
                'host_generation': host['generation'], 'mc_session_id': native['session_id'], 'mc_generation': native['generation'],
                'mc_epoch': native['mc_epoch'], 'world_session': view['world_session'], 'dim': view['dim']}

    def still_current(self, scope):
        if self.scope() != scope:
            raise RuntimeError('Actual runtime scope changed; outcome unknown, do not resubmit')

    def status(self):
        result = {'environment': 'MacStandalone', 'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'production_task': None, 'lab_task': None, 'windows_tasks_applicable': False}
        for name in ('client-status', 'render-status'):
            path = self.path('PalCraft-Dev/bridge/' + name + '.json')
            if path.is_file():
                result['last_' + name] = ai_client._read_json(path)
                result[name + '-file-utc'] = datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc).isoformat()
        try:
            result['actual_scope'] = self.scope(); result['guest_running'] = True
        except (FileNotFoundError, KeyError, RuntimeError, ValueError) as error:
            result['guest_running'] = None; result['scope_error'] = str(error)
        result['test_client_running'] = None  # A saved status file alone is not process-liveness proof.
        return result

    def command_source(self, operation, scope):
        data = canonical({'id': operation['id'], 'digest': operation['digest'], 'scope': scope,
                          'query': operation['query'], 'windows_root': self.windows_root})
        return '''assert(IsInGameThread(),'Normal MC command requires game thread')
local request_json=''' + lua_string(data) + '''
local root=assert(os.getenv('PALCRAFT_WINDOWS_ROOT')):gsub('\\\\','/'):gsub('/+$','')
local J=dofile(root..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
local q=J.decode(request_json);assert(root==q.windows_root,'Configured owned root changed')
local function read(name)local f=assert(io.open(root..'/PalCraft-Dev/bridge/'..name,'rb'));local v=J.decode(f:read('*a'));f:close();return v end
local function current()
 local host=read('session-bind-status.json');local boot=read('mc-bootstrap-status.json');local n=boot.native_binding
 assert(host.authenticated_host==true and boot.native_mc_verified==true and n.v==2 and n.legacy==false,'Actual native binding missing')
 assert(host.expires_at>os.time()and os.time()-host.updated_unix<=5 and os.time()-boot.updated_unix<=5,'Runtime binding stale')
 assert(host.session_id==q.scope.host_session_id and host.generation==q.scope.host_generation and host.server_session_id==q.scope.server_session_id,'HOST scope changed')
 assert(boot.host_scope.session_id==host.session_id and boot.host_scope.generation==host.generation,'Bootstrap HOST lease changed')
 assert(n.session_id==q.scope.mc_session_id and n.generation==q.scope.mc_generation and n.mc_epoch==q.scope.mc_epoch and n.expires_at>os.time(),'Native MC epoch changed')
 for _,key in ipairs({'pal_uid','mc_uuid','mc_name','world_id'})do assert(host.identity[key]==q.scope.identity[key],'Player identity changed')end
 for _,key in ipairs({'pal_uid','mc_uuid','world_id'})do assert(n[key]==q.scope.identity[key],'Native player identity changed')end
 assert(boot.world_view.world_session==q.scope.world_session and boot.world_view.dim==q.scope.dim,'World scope changed')
 return true
end
current()
local features=assert(_G.PalCraftClientFeatures);local command=assert(features.composition.features.commands)
assert(command.phase=='running'and command.instance,'Normal command bus unavailable')
local binding=assert(features.binding,'Live configured player binding missing')
assert(binding.session_id==q.scope.host_session_id and binding.generation==q.scope.host_generation and binding.expires_at>os.time(),'Live HOST binding changed')
if q.query.method=='action'or q.query.method=='slot'or q.query.method=='hud'then
 assert(not _G.PalCraftClientView.status().held,'World view held; normal input unavailable')
end
local file=root..'/PalCraft-Dev/bridge/mcp-normal-operations/'..q.id..'-dispatch.json'
local exists=io.open(file,'rb');if exists then local old=J.decode(exists:read('*a'));exists:close();assert(old.digest==q.digest,'Operation ID payload changed');return old end
local function save(value)local f=assert(io.open(file..'.pending','wb'));f:write(J.encode(value));f:close();os.remove(file);assert(os.rename(file..'.pending',file))end
local result={request_id=q.id,digest=q.digest,accepted=false,state='reserved',effect_confirmed=false}
save(result) -- Persist intent before touching the existing bus; ambiguity must not replay.
local method=q.query.method
local dispatched,dispatch_error=pcall(function()
if method=='action'then
 assert(command.instance.send{t='key',k=q.query.key,down=true,request_id=q.id}==true,'Normal command was not queued')
 result.accepted=true;result.state='submitted';save(result)
 ExecuteInGameThreadWithDelay(q.query.duration_ms,function()
  local ok,why=pcall(function()current();command.instance.send{t='key',k=q.query.key,down=false,request_id=q.id}end)
  result.state=ok and'submitted_release'or'unknown';result.error=not ok and tostring(why)or nil;save(result)
 end)
else
 local types={inspect='inspect',block='blockinspect',blocks='blocksync',slot='slot',hud='hud'}
 local row={t=assert(types[method]),request_id=q.id}
 if method=='block'then row.x=q.query.x;row.y=q.query.y;row.z=q.query.z
 elseif method=='blocks'then row.r=q.query.radius
 elseif method=='slot'then row.n=q.query.slot
 elseif method=='hud'then row.hidden=q.query.hidden end
 assert(command.instance.send(row)==true,'Normal command was not queued')
 result.accepted=true;result.state='submitted';save(result)
end
end)
if not dispatched then result.state='failed';result.error=tostring(dispatch_error);save(result)end
return result
'''

    def submit_client_op(self, record, scope, deadline):
        mailbox = self.path('PalCraft-Dev/bridge/client-op.lua')
        while mailbox.exists():
            if time.monotonic() >= deadline:
                raise TimeoutError('Client operation slot busy; request not submitted; operation_id=' + record['id'])
            time.sleep(self.poll)
        self.still_current(scope)
        record['state'] = 'submitted'; self.save(record)
        source = self.command_source(record, scope)
        temporary = self.path('PalCraft-Dev/bridge/client-op.pending')
        temporary.write_text(source, encoding='utf-8'); os.replace(temporary, mailbox)

    def save(self, record):
        atomic(self.records / (record['id'] + '.json'), record)

    def dispatch_result(self, record):
        path = self.records / (record['id'] + '-dispatch.json')
        return ai_client._read_json(path) if path.is_file() else None

    def wait_query(self, record, deadline):
        scope = record['scope']; method = record['query']['method']
        path = self.path('BridgeLab/rpc/palcraft-events.ndjson')
        offset = record['journal_offset']; pending = b''; rows = list(record.get('rows', []))
        expected = record.get('expected_chunks'); ended = set(record.get('ended_snapshots', []))
        response_bytes = record.get('response_bytes', 0)
        while time.monotonic() < deadline:
            self.still_current(scope)
            if path.is_file():
                if path.stat().st_size < offset:
                    raise RuntimeError('Authenticated journal truncated; outcome unknown')
                with path.open('rb') as stream:
                    stream.seek(offset); raw = stream.read(65536); offset = stream.tell()
                pending += raw
                if len(pending) > 1048576:
                    raise RuntimeError('MC response exceeds bounded journal record')
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    record['journal_offset'] = offset - len(pending)
                    if not line: continue
                    row = json.loads(line.decode('utf-8'))
                    if row.get('request_id') != record['id']: continue
                    response_bytes += len(line)
                    if response_bytes > self.max_response_bytes:
                        record.update(state='failed', error='Requested response exceeds bounded result size'); self.save(record)
                        raise RuntimeError(record['error'])
                    if method in ('inspect', 'block'):
                        if row.get('t') != ('inspection' if method == 'inspect' else 'blockinspection'): continue
                        if method == 'inspect' and row.get('uuid') != scope['identity']['mc_uuid']:
                            raise RuntimeError('Inspection player mismatch')
                        record.update(state='complete', result=row); self.save(record); return row
                    if row.get('t') != 'blocks' or row.get('session') != scope['world_session'] or row.get('dim') != scope['dim']:
                        raise RuntimeError('Block snapshot scope mismatch')
                    rows.append(row)
                    for event in row.get('lifecycle', []):
                        if event.get('op') == 'sync_requested': expected = event['chunks']
                        if event.get('op') in ('snapshot_cancel', 'resync_required'):
                            record.update(state='failed', error='Requested snapshot cancelled or capacity rejected'); self.save(record)
                            raise RuntimeError(record['error'])
                        if event.get('op') == 'snapshot_end': ended.add(event['snapshot'])
                    record.update(rows=rows, expected_chunks=expected, ended_snapshots=sorted(ended), response_bytes=response_bytes); self.save(record)
                    if expected is not None and len(ended) >= expected:
                        result = {'t': 'blocks', 'request_id': record['id'], 'events': rows,
                                  'set': [v for r in rows for v in r.get('set', [])], 'clear': [v for r in rows for v in r.get('clear', [])],
                                  'geometry': [v for r in rows for v in r.get('geometry', [])]}
                        record.update(state='complete', result=result); self.save(record); return result
                self.save(record)
            time.sleep(self.poll)
        raise TimeoutError('MC response pending/unknown; operation_id=' + record['id'] + '; inspect same ID, never resubmit')

    def collisions(self, record, deadline):
        request = {'id': record['id'], 'method': 'palcraft_' + record['query']['action']}
        target = self.path('BridgeLab/rpc/agent-request.json')
        result = self.path('BridgeLab/rpc/agent-result-' + record['id'] + '.json')
        with queue_lock(self.path('BridgeLab/rpc/agent-client.lock'), deadline, self.poll):
            if record['state'] == 'prepared':
                if result.is_file():
                    value = ai_client._read_json(result)
                    if value.get('id') != request['id'] or type(value.get('ok')) is not bool: raise RuntimeError('Lab result ID invalid')
                    if not value['ok']: raise RuntimeError(str(value.get('error')))
                    record.update(state='complete', result=value['result']); self.save(record); return value['result']
                observe_existing = False
                if target.is_file():
                    previous = ai_client._read_json(target)
                    if previous.get('id') == request['id'] and previous != request: raise ValueError('Same ID changed legacy Lab method')
                    observe_existing = previous.get('id') == request['id']
                    if previous.get('id') != request['id'] and not self.path('BridgeLab/rpc/agent-result-' + request_id(previous.get('id')) + '.json').is_file():
                        raise RuntimeError('Previous Lab operation pending; request not submitted')
                self.still_current(record['scope']); record['state'] = 'submitted'; self.save(record)
                if not observe_existing: atomic(target, request)
            while time.monotonic() < deadline:
                self.still_current(record['scope'])
                if result.is_file():
                    value = ai_client._read_json(result)
                    if value.get('id') != request['id'] or type(value.get('ok')) is not bool: raise RuntimeError('Lab result ID invalid')
                    if not value['ok']: raise RuntimeError(str(value.get('error')))
                    record.update(state='complete', result=value['result']); self.save(record); return value['result']
                time.sleep(self.poll)
        raise TimeoutError('Lab operation pending/unknown; operation_id=' + record['id'] + '; do not resubmit')

    def call(self, query, operation_id=None):
        method = query.get('method'); operation_id = request_id(operation_id)
        if method not in METHODS: raise ValueError('Unsupported normal MC method')
        deadline = time.monotonic() + self.timeout
        with queue_lock(self.path('.palcraft/operation.lock'), deadline, self.poll):
            path = self.records / (operation_id + '.json')
            digest = hashlib.sha256(canonical(query).encode()).hexdigest()
            if path.is_file():
                record = ai_client._read_json(path)
                if record.get('digest') != digest: raise ValueError('Same request_id has different arguments')
                if record['state'] in ('complete', 'submission_complete'): return record['result']
                if record['state'] == 'failed': raise RuntimeError(record.get('error', 'Operation failed'))
                self.still_current(record['scope'])
            else:
                if method == 'status':
                    result = self.status(); self.save({'id': operation_id, 'digest': digest, 'state': 'complete', 'result': result}); return result
                scope = self.scope(); journal = self.path('BridgeLab/rpc/palcraft-events.ndjson')
                record = {'id': operation_id, 'digest': digest, 'query': query, 'scope': scope, 'state': 'prepared',
                          'journal_offset': journal.stat().st_size if journal.is_file() else 0}; self.save(record)
            if method == 'collisions': return self.collisions(record, deadline)
            if record['state'] == 'prepared': self.submit_client_op(record, record['scope'], deadline)
            if method in ('block', 'inspect', 'blocks'): return self.wait_query(record, deadline)
            while time.monotonic() < deadline:
                self.still_current(record['scope']); answer = self.dispatch_result(record)
                if answer and answer.get('digest') == record['digest'] and answer.get('state') in ('failed', 'unknown'):
                    raise RuntimeError('operation_id=' + operation_id + '; ' + str(answer.get('error', 'Outcome unknown')))
                if answer and answer.get('digest') == record['digest'] and answer.get('state') in ('submitted', 'submitted_release'):
                    if method == 'action' and answer['state'] != 'submitted_release': time.sleep(self.poll); continue
                    result = {'operation_id': operation_id, 'accepted': True, 'effect_confirmed': False,
                              'completion': 'submission_only', 'dispatch': 'accepted_by_normal_command_bus'}
                    if method == 'action': result.update(sent=query['key'], duration_ms=query['duration_ms'], mode='Minecraft survival input')
                    elif method == 'slot': result['selected_slot'] = query['slot']
                    else: result['hud_hidden'] = query['hidden']
                    record.update(state='submission_complete', result=result); self.save(record); return result
                time.sleep(self.poll)
            raise TimeoutError('Command outcome pending/unknown; operation_id=' + operation_id + '; do not resubmit')


def call(query, operation_id=None, config=None):
    configured = config or os.environ.get('PALCRAFT_MC_CONFIG')
    config = ai_client.load_config(configured)
    transport = config.get('transport', 'localStandalone')
    if transport == 'localStandalone': return LocalMCClient(config).call(query, operation_id)
    if transport != 'ssh': raise ValueError('Unsupported normal MC transport')
    # Explicit legacy Windows branch; never fallback from a failed local operation.
    payload = base64.b64encode(canonical(query).encode()).decode()
    script = config.get('invoke_palcraft', 'D:/PalworldServer-LAN/PalCraft-Dev/Invoke-PalCraft.ps1')
    if not isinstance(script, str) or any(c in script for c in '\r\n\x00'): raise ValueError('Invalid legacy script')
    import re
    target = config.get('ssh_target', '5090')
    if not isinstance(target, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._@-]{0,190}', target): raise ValueError('Invalid explicit SSH target')
    command = "& '" + script.replace("'", "''") + "' -PayloadBase64 '" + payload + "'"
    encoded = base64.b64encode(command.encode('utf-16le')).decode()
    try:
        process = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', target,
                                  'powershell -NoProfile -NonInteractive -EncodedCommand ' + encoded], capture_output=True,
                                 timeout=ai_client._timeout(config.get('timeout_seconds', 20)))
    except subprocess.TimeoutExpired as error:
        raise TimeoutError('Explicit legacy transport outcome unknown; do not retry automatically') from error
    if process.returncode: raise RuntimeError(process.stderr.decode('utf-8', errors='replace')[-1500:])
    return json.loads(process.stdout.decode('utf-8-sig'))
