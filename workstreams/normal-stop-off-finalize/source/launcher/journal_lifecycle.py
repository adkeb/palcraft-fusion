"""The existing singleplayer supervisor owns this boot's journal actors and normal off witness."""
import json
import os
import re
import signal
import subprocess
import time
import uuid
from pathlib import Path

from installer.core import (DEV, TOOLS, USER, PlayerError, atomic_json, digest, fail,
                            get_state, marker, owned_path, read_json)

EVENTS = 'BridgeLab/rpc/palcraft-events.ndjson'
LIFECYCLE = '.palcraft/standalone/journal-lifecycle'


def enabled(profile):
    return (profile.get('standalone') is not None and profile.get('platform') == 'crossover'
            and profile.get('pal_entry_mode') == 'singleplayer'
            and profile['connection'].get('transport') == 'local')


def file_identity(path):
    s = path.stat()
    return {'device': s.st_dev, 'inode': s.st_ino, 'bytes': s.st_size, 'mtime_ns': s.st_mtime_ns}


def _scope_path(root, token, name):
    if not re.fullmatch(r'[a-f0-9]{32}', token):
        fail('JOURNAL_TOKEN', '日志生命周期必须使用本安装的真实监督器 token。')
    return owned_path(root, LIFECYCLE + '/' + token + '/' + name)


def request_normal_stop(root, session):
    scope = read_json(_scope_path(root, session['token'], 'scope.json'))
    if scope.get('token') != session['token'] or scope.get('root_id') != marker(root)['id']:
        fail('JOURNAL_SCOPE', '正常关闭请求属于另一本安装或 boot。')
    path = _scope_path(root, session['token'], 'stop-request.json')
    if not path.exists():
        atomic_json(path, {'schema': 1, 'token': session['token'], 'root_id': scope['root_id'],
                           'requested_unix': time.time(), 'force': False})
    return path


def _check_previous_actors(root, scope):
    from launcher.runtime import process_matches
    for name, actor in scope.get('actors', {}).items():
        if process_matches(actor):
            fail('JOURNAL_ACTOR_ALIVE', '上一事件卷仍有本 boot 的实际进程：' + name)


def prepare_cold_boot(root, dry_run=False, normal_stop_receipt=None):
    """Use the unchanged rotator before token allocation, never from promotion."""
    from installer.standalone import rotate_events
    root = Path(root).absolute()
    pointer = read_json(owned_path(root, LIFECYCLE + '/current.json'), {})
    scope = read_json(_scope_path(root, pointer['token'], 'scope.json'), {}) if pointer else {}
    if scope:
        _check_previous_actors(root, scope)
    source = owned_path(root, EVENTS)
    if not source.exists():
        return {'ok': True, 'dry_run': dry_run, 'active_volume_absent': True, 'rotation_needed': False}
    automatic = normal_stop_receipt is None
    path = (_scope_path(root, scope['token'], 'normal-stop-receipt.json') if automatic and scope
            else Path(normal_stop_receipt) if not automatic else None)
    if path is None or not path.is_file():
        fail('JOURNAL_STOP_REQUIRED', '上一事件卷尚无完整正常保存及本 boot 全部进程停机见证，未重放历史卷。')
    receipt = read_json(path)
    if automatic:
        previous = read_json(owned_path(root, '.palcraft/session.json'), {})
        if (receipt.get('kind') != 'palcraft-owned-normal-stop-v1'
                or receipt.get('token') != scope.get('token') or previous.get('token') != scope.get('token')
                or receipt.get('root_id') != marker(root)['id'] or receipt.get('root') != str(root)
                or receipt.get('stream_identity') != file_identity(source)
                or receipt.get('native_scope') != scope.get('native_scope')
                or not receipt.get('actor_exits') or set(receipt['actor_exits']) != set(scope['actors'])
                or any(not v.get('actual_wait_completed') for v in receipt['actor_exits'].values())
                or any(any(receipt['actor_exits'][key].get(field) != actor.get(field)
                           for field in ('pid', 'identity', 'role')) for key, actor in scope['actors'].items())
                or not receipt.get('normal_title_Quit_and_native_exit0')
                or not receipt.get('Saved_and_WAL_stable_after_all_actors_off')):
            fail('JOURNAL_STALE_RECEIPT', '停机见证不属于这一 boot、这一事件卷或真实等待结束的进程。')
        if _persistent_inventory(root) != receipt['persistent_stat_inventory']:
            fail('JOURNAL_SAVE_CHANGED', '正常停机后 Saved/WAL 已更改，未使用旧见证。')
    else:
        # Existing sole-runtime receipts remain an explicit transition path.
        witness = receipt.get('normal_save_witness', {})
        observed = receipt.get('observed_unix', 0)
        if (receipt.get('root_id') != marker(root)['id'] or receipt.get('root') != str(root)
                or receipt.get('active_events_path') != str(source)
                or not witness.get('normal_save_id') or witness.get('after_submission') is not True
                or witness.get('stable') is not True or observed * 1e9 < source.stat().st_mtime_ns):
            fail('JOURNAL_STALE_RECEIPT', '明确转交的原停机回执必须包含本卷之后的真实 save ID 和文件见证。')
    result = rotate_events(root, path, dry_run=dry_run)
    if not dry_run and scope:
        atomic_json(_scope_path(root, scope['token'], 'rotation-consumed.json'), result)
    return result


def _persistent_inventory(root):
    # Inspect the owned private save and original immutable WAL locations only.
    directories = [root / USER / 'Saved', root / DEV / 'bridge/exchange', root / 'BridgeLab/rpc/travel',
                   root / 'BridgeLab/rpc/food']
    files = set()
    for directory in directories:
        if directory.exists():
            if directory.is_symlink():
                fail('JOURNAL_SAVE_LINK', '保存见证不能使用链接目录。')
            for path in directory.rglob('*'):
                if path.is_symlink():
                    fail('JOURNAL_SAVE_LINK', '保存见证不读取链接。')
                if path.is_file():
                    files.add(path)
    rpc = root / 'BridgeLab/rpc'
    if rpc.exists():
        files.update(path for path in rpc.iterdir() if path.is_file()
                     and path.name.startswith(('food-', 'escrow-', 'travel-')))
    rows = {}
    for path in sorted(files):
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            fail('JOURNAL_SAVE_LINK', '保存见证不读取本安装之外的链接。')
        rows[path.relative_to(root).as_posix()] = file_identity(path)
    return rows


class NormalLifecycle:
    def __init__(self, supervisor, quiet_seconds=2):
        self.owner, self.root, self.token = supervisor, supervisor.root, supervisor.token
        self.quiet_seconds = quiet_seconds
        self.scope_path = _scope_path(self.root, self.token, 'scope.json')
        self.scope = read_json(self.scope_path, {})
        if not self.scope:
            self.scope = {'schema': 1, 'root': str(self.root), 'root_id': marker(self.root)['id'],
                          'token': self.token, 'active_events_path': str(self.root / EVENTS),
                          'started_unix': supervisor.session['started_unix'], 'actors': {}}
            self.save_scope()
            atomic_json(owned_path(self.root, LIFECYCLE + '/current.json'), {'token': self.token})
        if self.scope['root_id'] != marker(self.root)['id'] or self.scope['token'] != self.token:
            fail('JOURNAL_SCOPE', '监督器不能接管另一 boot 的事件流。')
        self.roles, self.role_outputs, self.exits, self.actor_keys = {}, [], {}, {}
        self.stage, self.pending, self.save_witness = 'idle', None, None
        self.candidate_stat, self.candidate_since = None, None
        self.last_mailbox = 0

    def save_scope(self):
        atomic_json(self.scope_path, self.scope)

    def register(self, name, record):
        index = 1
        key = name
        while key in self.scope['actors']:
            index += 1
            key = name + '#' + str(index)
        self.actor_keys[(name, record['pid'])] = key
        self.scope['actors'][key] = dict(record, role=name)
        self.save_scope()

    def record_exit(self, name, child, stop_request=None):
        if child.poll() is None:
            fail('JOURNAL_ACTOR_ALIVE', '实际子进程尚未 wait 完成：' + name)
        key = self.actor_keys[(name, child.pid)]
        self.exits[key] = {**self.scope['actors'][key], 'actual_wait_completed': True,
                           'exit_code': child.wait(), 'normal_stop_request': stop_request}
        if name in ('proxy', 'hud', 'udp', 'ssh'):
            path = self.root / '.palcraft/control' / (self.token + '.' + name + '.' + str(child.pid) + '-exit.json')
            record = read_json(path, {})
            if record.get('token') == self.token and record.get('component') == name:
                self.exits[key]['owned_child_exit'] = record

    def bind_native(self, profile=None):
        state = get_state(self.root)
        profile = state['profile'] if profile is None else profile
        permission = read_json(self.root / '.palcraft/standalone/owned-loaded-save-permission.json')
        identity = read_json(self.root / DEV / 'bridge/lab-identity.json')
        host = read_json(self.root / '.palcraft/control' / (self.token + '.host.json'))
        binding = read_json(self.root / DEV / 'bridge/exchange/escrow-client-process-binding.json')
        persistent = profile['connection']['identity']
        epoch = str(binding['pid']) + ':' + binding['process_created_filetime']
        sid = identity.get('server_session_id')  # Read the real issuer; never allocate or guess a SID.
        if (not isinstance(sid, str) or not sid.startswith('standalone:')
                or identity.get('server_session_id') != sid or identity.get('process_epoch') != epoch
                or profile['connection'].get('server_session_id') not in (None, sid)
                or permission.get('process_epoch') != epoch or host.get('primary_pid') != binding['pid']
                or host.get('primary_alive') is not True or host.get('phase') not in ('running', 'closing')
                or permission.get('published_unix', 0) < self.scope['started_unix']
                or binding.get('world_directory') != persistent['world_id']
                or binding.get('pal_uid') != persistent['pal_uid']
                or permission.get('native_context', {}).get('world_id') != persistent['world_id']
                or permission.get('native_context', {}).get('host_uid') != persistent['pal_uid']):
            fail('JOURNAL_NATIVE_SCOPE', '需要本 boot 的真实 PID/FILETIME、loaded-save 和原正常登记 SID。')
        native = {'server_session_id': sid, 'process_epoch': epoch, 'pid': binding['pid'],
                  'world_id': persistent['world_id'], 'pal_uid': persistent['pal_uid'],
                  'save_boot_id': binding['boot_id']}
        if self.scope.get('native_scope') not in (None, native):
            fail('JOURNAL_NATIVE_SCOPE', '正常停止不能跨 native boot 或世界。')
        self.scope['native_scope'] = native
        self.save_scope()
        return native

    def start_roles(self, sync_receipt, profile=None):
        from mac.scripts.start_role import validated_launch
        if self.roles:
            fail('JOURNAL_ACTOR_DUPLICATE', '本 boot 的后端已由监督器拥有。')
        self.bind_native(profile)
        if sync_receipt is None:
            fail('STANDALONE_SYNC', '完整接入需要原正常 save/stop、同一 UUID 和当前实际登记的 sync receipt。')
        state = get_state(self.root)
        profile = state['profile'] if profile is None else profile
        cfg_path = self.root / TOOLS / 'standalone/mac-runtime-config.json'
        cfg = read_json(cfg_path)
        mods = [entry for entry in state['manifest']['files'] if entry.get('role') == 'minecraft_mod']
        if len(mods) != 1 or (cfg['mod_filename'], cfg['mod_sha256']) != (Path(mods[0]['target']).name, mods[0]['sha256']):
            fail('JOURNAL_MOD_SCOPE', '监督器后端必须使用当前唯一受管理模组。')
        expected_cwd = {'server': Path(profile['standalone']['backend_root']) / 'server',
                        'guest': Path(cfg['guest_game_dir']), 'hud': self.root / DEV / 'bridge'}
        if not expected_cwd['guest'].resolve().is_relative_to(Path(profile['standalone']['backend_root']).resolve()):
            fail('JOURNAL_ROLE_SCOPE', 'guest 数据目录不属于当前选定后端。')
        plans = []
        for role in ('server', 'guest', 'hud'):
            try:
                launch, role_cfg, argv = validated_launch(Path(cfg['launch_dir']) / (role + '.json'), sync_receipt)
            except RuntimeError as error:
                fail('STANDALONE_ROLE_GUARD', '原后端角色检查拒绝启动：' + str(error))
            if (Path(launch['config']).resolve() != cfg_path.resolve() or role_cfg != cfg
                    or launch['role'] != role or Path(cfg['rpc_root']).resolve() != (self.root / 'BridgeLab/rpc').resolve()
                    or cfg['guest_mc_uuid'] != profile['connection']['identity']['mc_uuid']
                    or cfg['software_root'] != profile['standalone']['backend_root']
                    or Path(launch['cwd']).resolve() != expected_cwd[role].resolve()
                    or (launch['mod_filename'], launch['mod_sha256']) != (cfg['mod_filename'], cfg['mod_sha256'])):
                fail('JOURNAL_ROLE_SCOPE', '后端角色配置属于另一安装、玩家或事件流。')
            plans.append((role, launch, argv))
        from launcher.runtime import process_identity
        for role, launch, argv in plans:
            name = {'server': 'mc_server', 'guest': 'mc_guest', 'hud': 'hud_relay'}[role]
            output = (self.root / '.palcraft/logs' / (name + '.log')).open('ab')
            self.role_outputs.append(output)
            child = subprocess.Popen(argv, cwd=launch['cwd'], stdin=subprocess.PIPE if role == 'server' else subprocess.DEVNULL,
                                     stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            self.roles[name] = child
            record = {'pid': child.pid, 'identity': process_identity(child.pid), 'created_by_this_supervisor': True}
            self.register(name, record)
            self.owner.session['components'][name] = record
            self.owner.save('promoting')
            port, kind = {'server': (25567, 'mc_server'), 'guest': (25599, 'mc_ws'), 'hud': (25603, 'hud')}[role]
            deadline = time.monotonic() + 15
            while True:
                self.owner.beat()
                if child.poll() is not None:
                    fail('STANDALONE_ROLE_EXIT', '本 boot 的角色在启动时退出：' + name)
                try:
                    self.owner.probe(port, kind, timeout=.5)
                    break
                except (OSError, PlayerError):
                    if time.monotonic() >= deadline:
                        fail('STANDALONE_ROLE_PENDING', '本 boot 的角色未就绪：' + name)
                    time.sleep(self.owner.poll_seconds)

    def _lua_operation(self, action, request_id):
        native = self.scope['native_scope']
        # Only validated lifecycle identifiers enter this source. Paths come from the original native scope.
        q = lambda value: json.dumps(value, ensure_ascii=False)
        prefix = "assert(IsInGameThread(),'Owned game thread required')\nlocal sp=assert(_G.PalCraftStandaloneBootstrap)\n"
        prefix += "local p,epoch=assert(_G.PalCraftStandalonePermissions).process()\nassert(epoch==" + q(native['process_epoch']) + ",'Native boot changed')\n"
        result = "return {request_id=" + q(request_id) + ",token=" + q(self.token) + ",process_epoch=epoch,action=" + q(action) + ",observed_unix=os.time()}\n"
        if action == 'return_title':
            prefix += "local r=assert(sp.local_realm:current())\nassert(r.server_session_id==" + q(native['server_session_id']) + " and r.world_id==" + q(native['world_id']) + " and r.host_uid==" + q(native['pal_uid']) + ",'Loaded world changed')\n"
            prefix += "assert(r.save_manager:IsWorldAutoSaving()==false,'Native world autosave still active')\nr.pc:ClientReturnToMainMenu('PalCraft normal saved singleplayer stop')\n"
        else:
            prefix += "local found={}\nfor _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if pc:IsValid() and not pc:GetFullName():find('Default__',1,true) and pc.Player:IsValid() and pc.Player:GetFullName():match('^PalLocalPlayer ') and pc:GetFullName():find('BP_PalPlayerController_Title_C',1,true) then found[#found+1]=pc end end\nassert(#found==1,'Actual Title local controller pending')\n"
            if action == 'quit_title':
                prefix += "local pc=found[1]\nStaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):QuitGame(pc,pc,0,true)\n"
        return prefix + result

    def _submit_operation(self, action):
        bridge = self.root / DEV / 'bridge'
        target = bridge / 'client-op.lua'
        if target.exists() or time.monotonic() - self.last_mailbox < 1:
            return False
        request_id = uuid.uuid4().hex  # Existing operation correlation, not a world SID or credential.
        source = self._lua_operation(action, request_id)
        result = bridge / 'client-op-result.json'
        self.pending = {'request_id': request_id, 'action': action,
                        'prior_result': file_identity(result) if result.exists() else None, 'submitted_unix': time.time()}
        pending = bridge / 'client-op.pending'
        pending.write_text(source, encoding='utf-8')
        os.replace(pending, target)
        self.last_mailbox = time.monotonic()
        atomic_json(_scope_path(self.root, self.token, action + '-request.json'), self.pending)
        return True

    def _operation_result(self):
        if self.pending is None:
            return None
        result_path = self.root / DEV / 'bridge/client-op-result.json'
        if not result_path.exists() or file_identity(result_path) == self.pending['prior_result']:
            return None
        receipt = read_json(result_path)
        value = receipt.get('result')
        if receipt.get('ok') is True and isinstance(value, dict):
            if (value.get('request_id') != self.pending['request_id'] or value.get('token') != self.token
                    or value.get('process_epoch') != self.scope['native_scope']['process_epoch']
                    or value.get('action') != self.pending['action']):
                return None  # Another existing mailbox operation cannot acknowledge this request.
            atomic_json(_scope_path(self.root, self.token, value['action'] + '-observation.json'), receipt)
            self.pending = None
            return value
        if (self.root / DEV / 'bridge/client-op.lua').exists():
            return None
        self.pending = None
        return False

    def tick(self):
        if not _scope_path(self.root, self.token, 'stop-request.json').exists():
            return
        request = read_json(_scope_path(self.root, self.token, 'stop-request.json'))
        if request.get('token') != self.token or request.get('root_id') != self.scope['root_id']:
            fail('JOURNAL_SCOPE', '保存关闭请求不属于本 boot。')
        if self.stage == 'idle':
            native = self.bind_native()
            self.level = Path(read_json(self.root / '.palcraft/standalone/scope.json')['installed_level_path_host'])
            profile = get_state(self.root)['profile']
            expected_level = (self.root / USER / 'Saved/SaveGames' / profile['standalone']['save_account_directory']
                              / native['world_id'] / 'Level.sav')
            if self.level.resolve() != expected_level.resolve():
                fail('JOURNAL_SAVE_SCOPE', 'Level 保存见证必须属于本安装私有 UserDir。')
            command_path = self.root / DEV / 'bridge/exchange/escrow-client-save-command.json'
            previous = read_json(command_path, {})
            if previous:
                old_id = previous.get('id', '')
                if not re.fullmatch(r'[a-f0-9-]{36}', old_id):
                    fail('JOURNAL_SAVE_REQUEST_PENDING', '原正常 save command 无有效 ID，未覆盖。')
                old_row_path = command_path.parent / ('pal-client-save-' + old_id + '.r000002.json')
                old_row = read_json(old_row_path, {})
                if (old_row.get('status') != 'normal_save_requested'
                        or old_row != read_json(old_row_path.with_suffix('.durable.json'), {})):
                    fail('JOURNAL_SAVE_REQUEST_PENDING', '原 save 请求未确定完成 API 提交，保留其 ID 和不可变审计。')
            self.save_id = str(uuid.uuid4())
            command = {'protocol': 3, 'id': self.save_id, 'world_directory': native['world_id'], 'pal_uid': native['pal_uid']}
            self.save_request = {'request': command, 'submitted_unix': time.time(), 'level_before': file_identity(self.level)}
            atomic_json(_scope_path(self.root, self.token, 'save-request.json'), self.save_request)
            atomic_json(command_path, command)
            self.stage = 'saving'
        if self.stage == 'saving':
            native = self.scope['native_scope']
            wal = self.root / DEV / 'bridge/exchange' / ('pal-client-save-' + self.save_id + '.r000002.json')
            row = read_json(wal, {})
            durable = read_json(wal.with_suffix('.durable.json'), {})
            intent_path = wal.with_name(wal.name.replace('.r000002.', '.r000001.'))
            intent = read_json(intent_path, {})
            if (intent != read_json(intent_path.with_suffix('.durable.json'), {})
                    or intent.get('status') != 'normal_save_intent' or intent.get('revision') != 1
                    or any(intent.get(key) != row.get(key) for key in ('protocol', 'id', 'boot_id', 'world_directory', 'pal_uid'))
                    or row.get('protocol') != 3 or row.get('revision') != 2
                    or row != durable or row.get('status') != 'normal_save_requested' or row.get('id') != self.save_id
                    or row.get('boot_id') != native['save_boot_id'] or row.get('world_directory') != native['world_id']
                    or row.get('pal_uid') != native['pal_uid']):
                return
            current = file_identity(self.level)
            if current['mtime_ns'] <= self.save_request['submitted_unix'] * 1e9:
                return
            if current != self.candidate_stat:
                self.candidate_stat, self.candidate_since = current, time.monotonic()
                return
            if time.monotonic() - self.candidate_since < self.quiet_seconds:
                return
            sha = digest(self.level)
            if file_identity(self.level) != current:
                self.candidate_stat = None
                return
            self.save_witness = {'normal_save_id': self.save_id, 'level_mtime': current['mtime_ns'] / 1e9,
                'level_bytes': current['bytes'], 'level_sha256': sha, 'after_submission': True, 'stable': True,
                'normal_save_completed': True, 'observed_unix': time.time(),
                'native_API_intent_is_not_completion': True,
                'completion_basis': 'Original save request durable row + actual Level mtime after submission and stable bytes',
                'native_scope': native, 'save_request_durable_sha256': digest(wal)}
            atomic_json(_scope_path(self.root, self.token, 'normal-save-file-witness.json'), self.save_witness)
            self.stage = 'return_title'
        if self.stage in ('return_title', 'observe_title', 'quit_title'):
            value = self._operation_result()
            if value:
                if self.stage == 'return_title':
                    self.stage = 'observe_title'
                elif self.stage == 'observe_title':
                    self.scope['normal_title_observed'] = value
                    self.save_scope()
                    self.stage = 'quit_title'
                else:
                    self.stage = 'await_native_exit'
            if self.pending is None and self.stage != 'await_native_exit':
                self._submit_operation(self.stage)
        self.owner.session['normal_stop_stage'] = self.stage

    def stop_roles(self):
        """Only original Popen handles are signaled; never use a stored PID as a signal target."""
        for name in ('mc_guest', 'hud_relay', 'mc_server'):
            child = self.roles.get(name)
            if child is None:
                continue
            requested = self.scope.setdefault('role_stop_requests', {})
            key = self.actor_keys[(name, child.pid)]
            if key not in requested and child.poll() is None:
                if name == 'mc_server':
                    child.stdin.write(b'stop\n'); child.stdin.flush()
                    requested[key] = 'owned_server_stdin_stop'
                else:
                    child.send_signal(signal.SIGINT if name == 'mc_guest' else signal.SIGTERM)
                    requested[key] = 'owned_guest_SIGINT' if name == 'mc_guest' else 'owned_relay_SIGTERM'
                self.save_scope()
            while child.poll() is None:
                self.owner.beat()
                time.sleep(self.owner.poll_seconds)
            self.record_exit(name, child, requested.get(key))
        for output in self.role_outputs:
            output.close()

    def finish(self, phase):
        for name, child in self.owner.children.items():
            if child.poll() is not None:
                self.record_exit(name, child)
        return _issue_normal_stop(self.root, self.token, self.scope, self.exits,
                                  self.save_witness, phase, self.quiet_seconds)

def _issue_normal_stop(root, token, scope, exits, save_witness, phase, quiet_seconds=2, dry_run=False):
    from launcher.runtime import process_matches
    current_exits = {v['role']: v for v in exits.values()}
    native = scope.get('native_scope', {})
    host = read_json(root / '.palcraft/control' / (token + '.host.json'), {})
    requirements = {
        'phase_stopped': phase == 'stopped',
        'save_witness_exists': save_witness is not None,
        'title_observed': bool(scope.get('normal_title_observed')),
        'client_exit0': current_exits.get('client', {}).get('exit_code') == 0,
        'host_exit0': host.get('exit_code') == 0,
        'host_primary_matches': host.get('primary_pid') == native.get('pid'),
        'primary_not_alive': host.get('primary_alive') is False,
        'job_empty': host.get('job_active_processes') == 0,
        'host_phase_stopped': host.get('phase') == 'stopped',
        'actor_keys_same': set(exits) == set(scope['actors']),
        'all_actualwait_and_absent': all(v.get('actual_wait_completed') and not process_matches(v) for v in exits.values()),
        'server_original_stop0': all(v['exit_code'] == 0 and v.get('normal_stop_request') == 'owned_server_stdin_stop'
                                   for v in exits.values() if v['role'] == 'mc_server'),
        'guest_original_stop': all(v['exit_code'] in (0, 130) and v.get('normal_stop_request') == 'owned_guest_SIGINT'
                                  for v in exits.values() if v['role'] == 'mc_guest'),
        'wrapper_child_wait_and_absent': all(v.get('owned_child_exit', {}).get('actual_wait_completed') is True
                                           and not process_matches(v['owned_child_exit']['child'])
                                           for v in exits.values() if v['role'] in ('proxy', 'hud', 'udp', 'ssh'))}
    ready = all(requirements.values())
    ports = {}
    if ready:
        from launcher.runtime import _port_free
        # A separately launched unowned backend is never adopted or shut down.
        ports = {str(port): _port_free(port) for port in (25567, 25599, 25603)}
        ready = all(ports.values())
    if not ready:
        pending = {'ok': False, 'code': 'JOURNAL_WITNESS_PENDING', 'token': token,
                   'actor_exits': exits, 'normal_save_witness': save_witness,
                   'normal_title_observed': bool(scope.get('normal_title_observed')),
                   'normal_stop_receipt_created': False, 'port_checks': ports,
                   'readiness_checked_unix': time.time(), 'readiness_checks': requirements,
                   'failed_conjuncts': [key for key, value in requirements.items() if not value]
                       + ['port:' + port for port, available in ports.items() if not available]}
        if not dry_run:
            atomic_json(_scope_path(root, token, 'incomplete-stop.json'), pending)
        return pending
    if dry_run:
        return {'ok': True, 'dry_run': True, 'token': token, 'normal_stop_receipt_created': False,
                'readiness_checks': requirements, 'port_checks': ports, 'save_or_stop_requested': False,
                'would_check_persistent_quiet_and_hash_before_issuance': True}
    source = root / EVENTS
    initial_stream = file_identity(source) if source.exists() else None
    before = _persistent_inventory(root)
    time.sleep(quiet_seconds)
    if before != _persistent_inventory(root):
        fail('JOURNAL_SAVE_PENDING', '全部进程退出后 Saved/WAL 仍在变化，未签发完整停机见证。')
    hashes = {rel: digest(root / rel) for rel in before}
    if before != _persistent_inventory(root):
        fail('JOURNAL_SAVE_PENDING', 'Saved/WAL 在散列期间变化，未签发完整停机见证。')
    level = Path(read_json(root / '.palcraft/standalone/scope.json')['installed_level_path_host'])
    level_relative = level.relative_to(root).as_posix()
    if (hashes.get(level_relative) != save_witness.get('level_sha256')
            or before.get(level_relative, {}).get('bytes') != save_witness.get('level_bytes')
            or before.get(level_relative, {}).get('mtime_ns', 0) / 1e9 != save_witness.get('level_mtime')):
        fail('JOURNAL_SAVE_CHANGED', '签发时原 Level 见证不再匹配，未使用新文件替代。')
    source = root / EVENTS
    stream = file_identity(source) if source.exists() else None
    if stream != initial_stream:
        fail('JOURNAL_SAVE_PENDING', '正常停机后的事件卷仍在变化，未签发见证。')
    if any(process_matches(v) for v in exits.values()):
        fail('JOURNAL_ACTOR_ALIVE', '散列期间原进程重新出现，未签发停机见证。')
    if not all(_port_free(port) for port in (25567, 25599, 25603)):
        fail('JOURNAL_WITNESS_PENDING', '停机见证签发前后端端口仍不可用。')
    receipt = {'schema': 1, 'kind': 'palcraft-owned-normal-stop-v1', 'root': str(root),
        'root_id': scope['root_id'], 'token': token, 'native_scope': native,
        'active_events_path': str(source), 'stream_identity': stream, 'actor_exits': exits,
        'normal_save_completed': True, 'normal_save_witness': save_witness,
        'normal_title_Quit_and_native_exit0': True, 'MC_guest_normal_exit': current_exits.get('mc_guest', {}).get('exit_code'),
        'MC_server_normal_stop_exit': current_exits.get('mc_server', {}).get('exit_code'),
        'all_owned_producers_and_consumers_stopped': True,
        'all_this_stream_producers_and_consumers_off_before_rotation': True,
        'Saved_and_WAL_stable_after_all_actors_off': True, 'persistent_stat_inventory': before,
        'persistent_sha256': hashes, 'observed_unix': time.time(),
        'new_SID_credential_permission_ACK_reader_offset_or_transaction_WAL_written': False}
    path = _scope_path(root, token, 'normal-stop-receipt.json')
    atomic_json(path, receipt)
    return {'ok': True, 'normal_stop_receipt': str(path), 'actor_exits': exits,
            'normal_save_completed': True, 'next_cold_boot_uses_original_rotator': True}

def finalize_stop(root, dry_run=False, quiet_seconds=2):
    """Finish this same completed boot from original persisted waits; no new save/stop/signals."""
    from installer.core import operation_lock
    from launcher.runtime import process_identity
    root = Path(root).absolute()
    with operation_lock(root):
        session = read_json(owned_path(root, '.palcraft/session.json'))
        token = session.get('token', '')
        scope = read_json(_scope_path(root, token, 'scope.json'))
        pointer = read_json(owned_path(root, LIFECYCLE + '/current.json'))
        owner = marker(root)
        state = get_state(root); profile = state['profile']; native = scope.get('native_scope', {})
        if (not enabled(profile) or session.get('phase') != 'stopped'
                or session.get('normal_stop_stage') != 'await_native_exit'
                or pointer.get('token') != token or scope.get('token') != token
                or scope.get('root') != str(root) or scope.get('root_id') != owner['id']
                or scope.get('active_events_path') != str(root / EVENTS)
                or native.get('world_id') != profile['connection']['identity']['world_id']
                or native.get('pal_uid') != profile['connection']['identity']['pal_uid']):
            fail('JOURNAL_SCOPE', '收尾只接受本安装同一次完整正常停机的原 boot。')
        request = read_json(_scope_path(root, token, 'stop-request.json'))
        if request.get('token') != token or request.get('root_id') != owner['id'] or request.get('force') is not False:
            fail('JOURNAL_SCOPE', '缺少原同 boot 的正常关闭请求。')
        pending = read_json(_scope_path(root, token, 'incomplete-stop.json'))
        witness = read_json(_scope_path(root, token, 'normal-save-file-witness.json'))
        if (pending.get('token') != token or pending.get('code') != 'JOURNAL_WITNESS_PENDING'
                or pending.get('normal_save_witness') != witness
                or session.get('journal_lifecycle', {}).get('actor_exits') != pending.get('actor_exits')
                or witness.get('native_scope') != native or witness.get('after_submission') is not True
                or witness.get('stable') is not True or witness.get('normal_save_completed') is not True):
            fail('JOURNAL_WITNESS_PENDING', '原保存及 actual-wait 记录不完整，未重造见证。')
        exits = pending['actor_exits']
        if not exits or set(exits) != set(scope.get('actors', {})):
            fail('JOURNAL_WITNESS_PENDING', '原 actor actual-wait 集合不完整。')
        for key, actor in scope['actors'].items():
            result = exits[key]
            if (any(result.get(k) != actor.get(k) for k in ('pid', 'identity', 'role'))
                    or result.get('actual_wait_completed') is not True
                    or not isinstance(actor.get('pid'), int) or not actor.get('identity')):
                fail('JOURNAL_WITNESS_PENDING', '原进程身份或 actual-wait 记录缺失。')
            if process_identity(actor['pid']) is not None:
                fail('JOURNAL_ACTOR_ALIVE', '原 PID 当前仍存在；未收养或操作该进程。')
            if actor['role'] in ('proxy', 'hud', 'udp', 'ssh'):
                worker = read_json(owned_path(root, '.palcraft/control/' + token + '.' + actor['role'] + '.' + str(actor['pid']) + '-exit.json'))
                if (worker != result.get('owned_child_exit') or worker.get('token') != token
                        or worker.get('component') != actor['role'] or worker.get('actual_wait_completed') is not True
                        or not worker.get('child', {}).get('identity')
                        or process_identity(worker['child']['pid']) is not None):
                    fail('JOURNAL_WITNESS_PENDING', '原 worker 子进程 actual-wait 或退出记录不完整。')
        supervisor = session.get('supervisor', {})
        if not supervisor.get('identity') or process_identity(supervisor.get('pid')) is not None:
            fail('JOURNAL_ACTOR_ALIVE', '原监督器尚未退出，不能从持久记录补收尾。')
        save = read_json(_scope_path(root, token, 'save-request.json'))
        save_id = witness.get('normal_save_id', '')
        if not re.fullmatch(r'[a-f0-9-]{36}', save_id):
            fail('JOURNAL_SAVE_SCOPE', '原正常保存 ID 无效。')
        wal = owned_path(root, DEV + '/bridge/exchange/pal-client-save-' + save_id + '.r000002.json')
        row = read_json(wal); intent_path = wal.with_name(wal.name.replace('.r000002.', '.r000001.'))
        intent = read_json(intent_path)
        expected = {'protocol': 3, 'id': save_id, 'world_directory': native['world_id'], 'pal_uid': native['pal_uid']}
        if (save.get('request') != expected or row != read_json(wal.with_suffix('.durable.json'))
                or intent != read_json(intent_path.with_suffix('.durable.json'))
                or intent.get('status') != 'normal_save_intent' or intent.get('revision') != 1
                or row.get('status') != 'normal_save_requested' or row.get('revision') != 2
                or any(row.get(k) != v for k, v in expected.items())
                or any(intent.get(k) != row.get(k) for k in ('protocol', 'id', 'boot_id', 'world_directory', 'pal_uid'))
                or row.get('boot_id') != native.get('save_boot_id')
                or digest(wal) != witness.get('save_request_durable_sha256')):
            fail('JOURNAL_SAVE_SCOPE', '原保存 durable r1/r2 与本 boot/file witness 不一致。')
        level = owned_path(root, USER + '/Saved/SaveGames/' + profile['standalone']['save_account_directory'] + '/' + native['world_id'] + '/Level.sav')
        actual = file_identity(level)
        if (actual['mtime_ns'] <= save['submitted_unix'] * 1e9
                or actual['mtime_ns'] / 1e9 != witness['level_mtime']
                or actual['bytes'] != witness['level_bytes'] or digest(level) != witness['level_sha256']):
            fail('JOURNAL_SAVE_CHANGED', '原提交之后的 Level 文件见证已变化。')
        for action in ('return_title', 'observe_title', 'quit_title'):
            submitted = read_json(_scope_path(root, token, action + '-request.json'))
            observed = read_json(_scope_path(root, token, action + '-observation.json'))
            value = observed.get('result', {})
            if (observed.get('ok') is not True or value.get('action') != action
                    or value.get('request_id') != submitted.get('request_id')
                    or value.get('token') != token or value.get('process_epoch') != native.get('process_epoch')
                    or value.get('observed_unix', 0) < submitted.get('submitted_unix', 0) - 1):
                fail('JOURNAL_SCOPE', '原正常 Title/Quit 关联记录不完整。')
            if action == 'observe_title' and scope.get('normal_title_observed') != value:
                fail('JOURNAL_SCOPE', '原 Title 回执与 scope 不一致。')
        # Same issuer as normal finish. No fake owner/Popen and no phase/state edit.
        return _issue_normal_stop(root, token, scope, exits, witness, session['phase'], quiet_seconds, dry_run)
