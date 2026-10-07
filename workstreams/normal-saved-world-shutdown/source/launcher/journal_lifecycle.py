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
SAVED_CRASH_KIND = 'palcraft-owned-saved-crash-off-v1'
SAVED_CRASH_RECEIPT = 'saved-crash-off-receipt.json'
UNSAVED_CRASH_KIND = 'palcraft-owned-unsaved-crash-off-v1'
UNSAVED_CRASH_RECEIPT = 'unsaved-crash-off-receipt.json'


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


def _saved_crash_receipt_matches(root, scope, session, receipt):
    """Read the original failed boot's truth; never issue or repair a receipt."""
    clients = [value for value in receipt.get('actor_exits', {}).values() if value.get('role') == 'client']
    if len(clients) != 1:
        return False
    code = clients[0].get('exit_code')
    host = read_json(owned_path(root, '.palcraft/control/' + session['token'] + '.host.json'), {})
    late=receipt.get('final_post_exit_level_witness')
    if late is not None:
        level=Path(read_json(root / '.palcraft/standalone/scope.json')['installed_level_path_host'])
        if (late.get('kind')!='palcraft-final-late-game-save-observation-v1'
                or late.get('normal_save_id')!=receipt.get('normal_save_witness',{}).get('normal_save_id')
                or late.get('native_scope')!=scope.get('native_scope')
                or late.get('original_early_witness_preserved') is not True
                or late.get('standard_codec_reparsed_this_call') is not True
                or late.get('level_identity')!=file_identity(level)
                or late.get('level_sha256')!=digest(level)):
            return False
    return (session.get('phase') == 'failed' and session.get('code') == 'CLIENT_EXIT'
        and receipt.get('kind') == SAVED_CRASH_KIND and receipt.get('saved_crash_off_completed') is True
        and receipt.get('normal_title_Quit_and_native_exit0') is False
        and receipt.get('original_session_phase') == session['phase']
        and receipt.get('original_session_code') == session['code']
        and receipt.get('normal_stop_stage') == session.get('normal_stop_stage')
        and receipt.get('normal_title_observed') == bool(scope.get('normal_title_observed'))
        and type(code) is int and code != 0 and receipt.get('client_exit_code') == code
        and receipt.get('host_observation') == host and host.get('exit_code') == code
        and host.get('phase') == 'failed' and host.get('primary_pid') == scope.get('native_scope', {}).get('pid')
        and host.get('primary_alive') is False and host.get('job_active_processes') == 0
        and session.get('journal_lifecycle', {}).get('actor_exits') == receipt.get('actor_exits')
        and receipt.get('normal_save_witness', {}).get('normal_save_completed') is True)

def _normal_late_receipt_matches(root, scope, receipt):
    late = receipt.get('final_post_exit_level_witness')
    if late is None:
        return True
    selected = Path(read_json(root / '.palcraft/standalone/scope.json')['installed_level_path_host'])
    level = owned_path(root, selected.relative_to(root).as_posix())
    host = read_json(owned_path(root, '.palcraft/control/' + scope['token'] + '.host.json'))
    codec = late.get('final_level_codec_observation', {})
    files = codec.get('files', {})
    player = level.parent / 'Players' / (scope['native_scope']['pal_uid'].replace('-', '').upper() + '.sav')
    expected_files = {path.relative_to(root).as_posix() for path in (level, player)}
    return (late.get('kind') == 'palcraft-final-normal-game-save-observation-v1'
        and late.get('normal_save_id') == receipt.get('normal_save_witness', {}).get('normal_save_id')
        and late.get('native_scope') == scope.get('native_scope')
        and late.get('original_early_witness_preserved') is True
        and late.get('standard_codec_reparsed_this_call') is True
        and late.get('normal_save_completed') is True
        and late.get('level_identity') == file_identity(level) and late.get('level_sha256') == digest(level)
        and late.get('original_host_exit_observation') == host
        and host.get('exit_code') == 0 and host.get('phase') == 'stopped'
        and host.get('primary_pid') == scope['native_scope']['pid']
        and host.get('primary_alive') is False and host.get('job_active_processes') == 0
        and codec.get('kind') == 'final-owned-normal-Level-codec-observation-v1'
        and codec.get('world_id') == scope['native_scope']['world_id']
        and codec.get('pal_uid') == scope['native_scope']['pal_uid']
        and codec.get('standard_codec_reparsed') is True and codec.get('level_and_player_parsed') is True
        and codec.get('owned_UID_in_Level') is True and set(files) == expected_files
        and codec.get('standard_codec') == 'palworld_save_tools decompress_sav_to_gvas + GvasFile.read PALWORLD_TYPE_HINTS'
        and all(value == {'identity': file_identity(owned_path(root, name)), 'sha256': digest(owned_path(root, name))}
                for name, value in files.items()))


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
    saved_crash = False
    unsaved_crash = False
    if automatic and scope:
        previous = read_json(owned_path(root, '.palcraft/session.json'), {})
        crash_path = _scope_path(root, scope['token'], SAVED_CRASH_RECEIPT)
        unsaved_path = _scope_path(root, scope['token'], UNSAVED_CRASH_RECEIPT)
        if previous.get('phase') == 'failed' and unsaved_path.is_file():
            path, unsaved_crash = unsaved_path, True
        elif previous.get('phase') == 'failed' and crash_path.is_file():
            path, saved_crash = crash_path, True
        elif previous.get('phase') == 'failed':
            fail('JOURNAL_CRASH_OFF_REQUIRED', '上一失败 boot 尚无真实 off 回执，先运行适用的 finalize-crash-off 或 finalize-saved-crash。')
    if automatic and scope and path is not None and not path.is_file():
        # start calls this before allocating a new token and outside its lock.
        # Reuse the original completed stop; never request a second shutdown.
        completed = finalize_stop(root, dry_run=dry_run)
        if completed.get('ok') is not True:
            fail('JOURNAL_WITNESS_PENDING', '上一正常退出尚未完成收尾，不能启动新会话。')
        if dry_run:
            return {**completed, 'would_finalize_original_stop': True,
                    'rotation_needed': True, 'rotation_performed': False}
    if path is None or not path.is_file():
        fail('JOURNAL_STOP_REQUIRED', '上一事件卷尚无完整正常保存及本 boot 全部进程停机见证，未重放历史卷。')
    receipt = read_json(path)
    if automatic:
        previous = read_json(owned_path(root, '.palcraft/session.json'), {})
        if (receipt.get('kind') != (UNSAVED_CRASH_KIND if unsaved_crash else SAVED_CRASH_KIND if saved_crash else 'palcraft-owned-normal-stop-v1')
                or receipt.get('token') != scope.get('token') or previous.get('token') != scope.get('token')
                or receipt.get('root_id') != marker(root)['id'] or receipt.get('root') != str(root)
                or receipt.get('stream_identity') != file_identity(source)
                or receipt.get('native_scope') != scope.get('native_scope')
                or not receipt.get('actor_exits') or set(receipt['actor_exits']) != set(scope['actors'])
                or any(not v.get('actual_wait_completed') for v in receipt['actor_exits'].values())
                or any(any(receipt['actor_exits'][key].get(field) != actor.get(field)
                           for field in ('pid', 'identity', 'role')) for key, actor in scope['actors'].items())
                or (not _unsaved_crash_receipt_matches(root, scope, previous, receipt) if unsaved_crash
                     else not _saved_crash_receipt_matches(root, scope, previous, receipt) if saved_crash
                    else not receipt.get('normal_title_Quit_and_native_exit0') or not _normal_late_receipt_matches(root, scope, receipt))
                or not receipt.get('Saved_and_WAL_stable_after_all_actors_off')):
            fail('JOURNAL_STALE_RECEIPT', '停机见证不属于这一 boot、这一事件卷或真实等待结束的进程。')
        inventory = _crash_persistent_inventory if unsaved_crash else _persistent_inventory
        if inventory(root) != receipt['persistent_stat_inventory']:
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
    if unsaved_crash:
        result.update(normal_save_completed=False, mutations_may_be_unpersisted=True,
                      original_business_recovery=receipt['original_business_recovery'],
                      events_archive_only_no_replay_or_exactly_once_persistence_claim=True)
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
        from installer.performance import role_environment
        for role, launch, argv in plans:
            name = {'server': 'mc_server', 'guest': 'mc_guest', 'hud': 'hud_relay'}[role]
            output = (self.root / '.palcraft/logs' / (name + '.log')).open('ab')
            self.role_outputs.append(output)
            env = (role_environment(self.root, self.token, name, os.environ)
                   if role in ('guest', 'hud') else dict(os.environ))
            child = subprocess.Popen(argv, cwd=launch['cwd'], stdin=subprocess.PIPE if role == 'server' else subprocess.DEVNULL,
                                     stdout=output, stderr=subprocess.STDOUT, start_new_session=True, env=env)
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
            prefix += "local r=sp.local_realm:current()\nif r then assert(r.server_session_id==" + q(native['server_session_id']) + " and r.world_id==" + q(native['world_id']) + " and r.host_uid==" + q(native['pal_uid']) + ",'Loaded world changed') end\n"
            witness = self.save_witness
            if not witness or witness.get('normal_save_completed') is not True or witness.get('native_scope') != native:
                fail('JOURNAL_SAVE_REQUIRED', '本 boot 原成功正常 Save 见证缺失，不能请求已保存关闭。')
            request = '{kind="normal_saved_world_shutdown_v1",action="return_title",token=' + q(self.token) + ',normal_save_id=' + q(witness['normal_save_id']) + '}'
            prefix += (
                "if r then assert(r.save_manager:IsWorldAutoSaving()==false,'Native world autosave still active') end\n"
                "local title\nif not r then local found={}\n"
                "for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if pc:IsValid() and not pc:GetFullName():find('Default__',1,true) and pc.Player:IsValid() and pc.Player:GetFullName():match('^PalLocalPlayer ') and pc:GetFullName():find('BP_PalPlayerController_Title_C',1,true)then found[#found+1]=pc end end\n"
                "assert(#found==1,'Actual Title local controller pending');title=found[1] end\n"
                "local stopped=assert(sp.world).normal_saved_shutdown(assert(_G.PalCraftServerFeatures)," + request + ")\n"
                "assert(stopped.stop_ok==true,'Original owned world cleanup pending')\n"
                "if stopped.context_alive then assert(r,'Actual saved MainWorld unavailable');r.pc:ClientReturnToMainMenu('PalCraft normal saved singleplayer stop') else assert(title,'Actual Title local controller pending') end\n"
            )
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
    return _issue_off_receipt(root, token, scope, exits, save_witness, phase, quiet_seconds, dry_run)


def _issue_off_receipt(root, token, scope, exits, save_witness, phase, quiet_seconds=2, dry_run=False,
                       saved_crash=False, session=None, late_level_witness=None):
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
    if saved_crash:
        for name in ('phase_stopped', 'title_observed', 'client_exit0', 'host_exit0', 'host_phase_stopped'):
            requirements.pop(name)
        code = current_exits.get('client', {}).get('exit_code')
        requirements.update(phase_failed=phase == 'failed',
            client_actual_nonzero_exit=type(code) is int and code != 0,
            host_same_actual_nonzero_exit=host.get('exit_code') == code,
            host_phase_failed=host.get('phase') == 'failed',
            original_client_exit_session=session is not None and session.get('code') == 'CLIENT_EXIT')
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
            atomic_json(_scope_path(root, token, 'incomplete-saved-crash-off.json' if saved_crash else 'incomplete-stop.json'), pending)
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
    final_level_witness = late_level_witness or save_witness
    if (hashes.get(level_relative) != final_level_witness.get('level_sha256')
            or before.get(level_relative, {}).get('bytes') != final_level_witness.get('level_bytes')
            or before.get(level_relative, {}).get('mtime_ns', 0) / 1e9 != final_level_witness.get('level_mtime')):
        fail('JOURNAL_SAVE_CHANGED', '签发时原 Level 见证不再匹配，未使用新文件替代。')
    source = root / EVENTS
    stream = file_identity(source) if source.exists() else None
    if stream != initial_stream:
        fail('JOURNAL_SAVE_PENDING', '正常停机后的事件卷仍在变化，未签发见证。')
    if any(process_matches(v) for v in exits.values()):
        fail('JOURNAL_ACTOR_ALIVE', '散列期间原进程重新出现，未签发停机见证。')
    if not all(_port_free(port) for port in (25567, 25599, 25603)):
        fail('JOURNAL_WITNESS_PENDING', '停机见证签发前后端端口仍不可用。')
    receipt = {'schema': 1, 'kind': SAVED_CRASH_KIND if saved_crash else 'palcraft-owned-normal-stop-v1', 'root': str(root),
        'root_id': scope['root_id'], 'token': token, 'native_scope': native,
        'active_events_path': str(source), 'stream_identity': stream, 'actor_exits': exits,
        'normal_save_completed': True, 'normal_save_witness': save_witness,
        'normal_title_Quit_and_native_exit0': not saved_crash, 'MC_guest_normal_exit': current_exits.get('mc_guest', {}).get('exit_code'),
        'MC_server_normal_stop_exit': current_exits.get('mc_server', {}).get('exit_code'),
        'all_owned_producers_and_consumers_stopped': True,
        'all_this_stream_producers_and_consumers_off_before_rotation': True,
        'Saved_and_WAL_stable_after_all_actors_off': True, 'persistent_stat_inventory': before,
        'persistent_sha256': hashes, 'observed_unix': time.time(),
        'new_SID_credential_permission_ACK_reader_offset_or_transaction_WAL_written': False}
    if late_level_witness is not None:
        assert late_level_witness['original_early_witness_preserved']
        assert late_level_witness['kind'] == ('palcraft-final-late-game-save-observation-v1' if saved_crash
                                             else 'palcraft-final-normal-game-save-observation-v1')
        receipt['final_post_exit_level_witness'] = late_level_witness
    if saved_crash:
        receipt.update(saved_crash_off_completed=True, original_session_phase=session['phase'],
            original_session_code=session['code'], normal_stop_stage=session.get('normal_stop_stage'),
            normal_title_observed=bool(scope.get('normal_title_observed')),
            client_exit_code=current_exits['client']['exit_code'], host_observation=host)
    path = _scope_path(root, token, SAVED_CRASH_RECEIPT if saved_crash else 'normal-stop-receipt.json')
    atomic_json(path, receipt)
    key = 'saved_crash_off_receipt' if saved_crash else 'normal_stop_receipt'
    return {'ok': True, key: str(path), 'actor_exits': exits,
            'normal_save_completed': True, 'next_cold_boot_uses_original_rotator': True}

def _late_saved_level(root, token, scope, session, save, witness, level):
    """Observe a final game-written Level alongside, never instead of, the original witness."""
    import xml.etree.ElementTree as ET
    actual = file_identity(level)
    host_path = owned_path(root, '.palcraft/control/' + token + '.host.json')
    host = read_json(host_path)
    if (actual['mtime_ns'] <= int(witness['level_mtime'] * 1e9)
            or actual['mtime_ns'] <= int(save['submitted_unix'] * 1e9)
            or host.get('primary_pid') != scope['native_scope']['pid']
            or host.get('primary_alive') is not False or host.get('job_active_processes') != 0
            or host.get('exit_code') != 3 or host.get('phase') != 'failed'):
        fail('JOURNAL_SAVE_CHANGED', '晚写 Level 没有原已保存 crash-off 的真实边界。')
    reports=[]
    for path in (root / USER / 'Saved/Crashes').glob('*/CrashContext.runtime-xml'):
        raw=path.read_bytes()
        text=raw.decode('utf-16') if raw.startswith((bytes.fromhex('fffe'),bytes.fromhex('feff'))) else raw.decode('utf-8-sig')
        try:
            document=ET.fromstring(re.sub(r'^<?xml[^>]*?>','',text))
            pid=int(document.findtext('.//ProcessId') or '0')
        except (ValueError,ET.ParseError):
            continue
        stamp=file_identity(path)
        if (pid==scope['native_scope']['pid'] and stamp['mtime_ns'] >= actual['mtime_ns']
                and stamp['mtime_ns'] <= host_path.stat().st_mtime_ns
                and stamp['mtime_ns']/1e9 >= scope['started_unix']
                and document.findtext('.//CrashType')=='Crash'):
            reports.append((path,stamp))
    if len(reports)!=1:
        fail('JOURNAL_SAVE_CHANGED', '缺少同 native PID 晚写之后、原 host 退出之前的唯一 crash report。')
    import os
    codec_path=Path(os.environ.get('PALCRAFT_LATE_LEVEL_CODEC_PROOF',''))
    if not codec_path.is_absolute() or not codec_path.is_file():
        fail('JOURNAL_SAVE_CHANGED', '晚写收尾需要原标准 codec 的只读归属解析记录。')
    codec=read_json(codec_path)
    if (codec.get('schema')!=1 or codec.get('codec_parse_succeeded') is not True
            or codec.get('standard_original_codec')!='palworld_save_tools decompress_sav_to_gvas + GvasFile.read PALWORLD_TYPE_HINTS'
            or codec.get('Level_bytes')!=actual['bytes'] or codec.get('Level_sha256')!=digest(level)
            or codec.get('owned_path_world_id')!=scope['native_scope']['world_id']
            or codec.get('uid1_exists_in_CharacterSaveParameterMap') is not True
            or codec.get('uid1_PlayerSav_exists') is not True
            or scope['native_scope']['pal_uid']!='00000000-0000-0000-0000-000000000001'
            or codec.get('same_normal_save_id')!=witness['normal_save_id']
            or codec.get('same_native_scope')!=scope['native_scope']
            or codec.get('save_or_side_effects') is not False
            or codec.get('observed_unix',0)<session.get('stopped_unix',0)):
        fail('JOURNAL_SAVE_CHANGED', '原标准 codec 解析记录不属于该最终 Level、UID 或原保存 boot。')
    codec_python=Path(codec.get('codec_python_executable',''))
    if not codec_python.is_absolute() or not codec_python.is_file():
        fail('JOURNAL_SAVE_CHANGED', '原标准 codec Python 入口不可用。')
    verify_code = '''import json,sys
from palworld_save_tools.palsav import decompress_sav_to_gvas
from palworld_save_tools.gvas import GvasFile
from palworld_save_tools.paltypes import PALWORLD_TYPE_HINTS
from contextlib import redirect_stdout
import io
data=decompress_sav_to_gvas(open(sys.argv[1],"rb").read())[0]
with redirect_stdout(io.StringIO()):
    parsed=GvasFile.read(data,PALWORLD_TYPE_HINTS,{},allow_nan=True)
entries=parsed.properties["worldSaveData"]["value"]["CharacterSaveParameterMap"]["value"]
entries=entries.get("values",[]) if isinstance(entries,dict) else entries
uid=sys.argv[2].lower()
found=any(str(row["key"]["PlayerUId"]["value"]).lower()==uid for row in entries)
print(json.dumps({"parsed":True,"owned_uid_present":found}))
'''
    codec_env=os.environ.copy()
    codec_env['PYTHONPATH']=str(root / DEV / 'mcp/vendor')
    check=subprocess.run([str(codec_python),'-B','-c',verify_code,str(level),scope['native_scope']['pal_uid']],
        capture_output=True,text=True,timeout=30,env=codec_env)
    if check.returncode!=0:
        fail('JOURNAL_SAVE_CHANGED', '原标准 codec 不能重新解析最终 Level。')
    try:
        actual_codec=json.loads(check.stdout)
    except ValueError:
        fail('JOURNAL_SAVE_CHANGED', '原标准 codec 返回不可解析。')
    if actual_codec!={'parsed':True,'owned_uid_present':True}:
        fail('JOURNAL_SAVE_CHANGED', '最终 Level 不包含该原生 UID。')
    player=level.parent/'Players'/(scope['native_scope']['pal_uid'].replace('-','').upper()+'.sav')
    if not player.is_file() or player.stat().st_size!=codec.get('uid1_PlayerSav_bytes'):
        fail('JOURNAL_SAVE_CHANGED', '晚写角色文件不属于该标准解析记录。')
    report,identity=reports[0]
    if actual!=file_identity(level):
        fail('JOURNAL_SAVE_PENDING', '解析期间晚写 Level 又变化。')
    return {'schema':1,'kind':'palcraft-final-late-game-save-observation-v1','normal_save_id':witness['normal_save_id'],
        'native_scope':scope['native_scope'],'level_mtime':actual['mtime_ns']/1e9,'level_bytes':actual['bytes'],
        'level_sha256':codec['Level_sha256'],'level_identity':actual,'after_submission':True,'stable':True,
        'normal_save_completed':True,'original_early_witness_preserved':True,
        'game_crash_report':{'relative_path':report.relative_to(root).as_posix(),'identity':identity,'sha256':digest(report),
            'file_creation_not_exact_fault_time':True},
        'original_host_exit_observation':host,'codec_observation_record_sha256':digest(codec_path),
        'codec_ownership':{'world_id':codec['owned_path_world_id'],'pal_uid':scope['native_scope']['pal_uid'],
            'CharacterSaveParameterMap_contains_UID1':True,'UID1_PlayerSav_bytes':codec['uid1_PlayerSav_bytes']},
        'extra_native_BootRegistry_not_claimed':True,'standard_codec_reparsed_this_call':True,'observed_unix':time.time()}

def _late_normal_saved_level(root, token, scope, session, save, witness, level, codec_python=None):
    """Keep the early successful save witness and observe a later game-written save after normal exit."""
    host_path = owned_path(root, '.palcraft/control/' + token + '.host.json')
    host = read_json(host_path)
    native = scope['native_scope']
    actual = file_identity(level)
    if (session.get('phase') != 'stopped' or session.get('normal_stop_stage') != 'await_native_exit'
            or not scope.get('normal_title_observed') or witness.get('normal_save_completed') is not True
            or host.get('primary_pid') != native.get('pid') or host.get('primary_alive') is not False
            or host.get('job_active_processes') != 0 or host.get('exit_code') != 0
            or host.get('phase') != 'stopped'
            or actual['mtime_ns'] <= int(witness['level_mtime'] * 1e9)
            or actual['mtime_ns'] <= int(save['submitted_unix'] * 1e9)
            or actual['mtime_ns'] > host_path.stat().st_mtime_ns):
        fail('JOURNAL_SAVE_CHANGED', '晚写 Level 不属于原正常保存、Title/Quit 及 native exit0 的真实边界。')
    # This existing helper reparses Level and Player through the standard codec,
    # checks the exact owned world/UID and checks both files again afterwards.
    # Keep only the codec's observation facts, not its unsaved-boot labels.
    observed = _existing_level_codec(root, {'profile': get_state(root)['profile'], 'scope': scope}, codec_python=codec_python)
    codec = {key: observed[key] for key in ('world_id', 'pal_uid', 'files', 'standard_codec',
             'codec_python_executable', 'standard_codec_reparsed', 'level_and_player_parsed', 'owned_UID_in_Level')}
    codec['kind'] = 'final-owned-normal-Level-codec-observation-v1'
    if actual != file_identity(level):
        fail('JOURNAL_SAVE_PENDING', '正常退出后的最终 Level 在只读解析期间又变化。')
    row = codec['files'][level.relative_to(root).as_posix()]
    return {'schema': 1, 'kind': 'palcraft-final-normal-game-save-observation-v1',
            'normal_save_id': witness['normal_save_id'], 'native_scope': native,
            'level_mtime': actual['mtime_ns'] / 1e9, 'level_bytes': actual['bytes'],
            'level_identity': actual, 'level_sha256': row['sha256'],
            'after_submission': True, 'stable': True, 'normal_save_completed': True,
            'original_early_witness_preserved': True, 'original_host_exit_observation': host,
            'standard_codec_reparsed_this_call': True, 'final_level_codec_observation': codec,
            'extra_native_BootRegistry_not_claimed': True, 'observed_unix': time.time()}

def finalize_stop(root, dry_run=False, quiet_seconds=2, codec_python=None):
    return _finalize_off(root, dry_run, quiet_seconds, codec_python=codec_python)


def finalize_saved_crash(root, dry_run=False, quiet_seconds=2):
    """Sign only saved, actually waited crash-off facts; never claim a normal exit."""
    return _finalize_off(root, dry_run, quiet_seconds, saved_crash=True)


def _finalize_off(root, dry_run=False, quiet_seconds=2, saved_crash=False, codec_python=None):
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
        valid_phase = (session.get('phase') == 'failed' and session.get('code') == 'CLIENT_EXIT' if saved_crash
                       else session.get('phase') == 'stopped' and session.get('normal_stop_stage') == 'await_native_exit')
        if (not enabled(profile) or not valid_phase
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
        late_level_witness = None
        level_changed = (actual['mtime_ns'] <= save['submitted_unix'] * 1e9
                or actual['mtime_ns'] / 1e9 != witness['level_mtime']
                or actual['bytes'] != witness['level_bytes'] or digest(level) != witness['level_sha256'])
        if level_changed and saved_crash:
            late_level_witness = _late_saved_level(root, token, scope, session, save, witness, level)
        for action in (() if saved_crash else ('return_title', 'observe_title', 'quit_title')):
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
        if level_changed and not saved_crash:
            late_level_witness = _late_normal_saved_level(root, token, scope, session, save, witness, level, codec_python=codec_python)
        # Same issuer as normal finish. No fake owner/Popen and no phase/state edit.
        return _issue_off_receipt(root, token, scope, exits, witness, session['phase'], quiet_seconds, dry_run,
                                  saved_crash=saved_crash, session=session, late_level_witness=late_level_witness)


def _crash_persistent_inventory(root):
    rows = _persistent_inventory(root)
    directory = root / 'BridgeLab/rpc/entities'
    if directory.exists():
        for path in directory.rglob('*'):
            if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
                fail('JOURNAL_SAVE_LINK', '未保存 crash-off 不读取外部链接 WAL。')
            if path.is_file():
                rows[path.relative_to(root).as_posix()] = file_identity(path)
    return dict(sorted(rows.items()))


def _crash_off_facts(root):
    """Original persisted Popen waits only; no signals, PID adoption or phase repair."""
    from launcher.runtime import process_identity, _port_free
    session = read_json(owned_path(root, '.palcraft/session.json'))
    token = session.get('token', '')
    scope = read_json(_scope_path(root, token, 'scope.json'))
    pointer = read_json(owned_path(root, LIFECYCLE + '/current.json'))
    profile = get_state(root)['profile']; native = scope.get('native_scope', {})
    owner = marker(root)
    if (not enabled(profile) or session.get('phase') != 'failed' or session.get('code') != 'CLIENT_EXIT'
            or pointer.get('token') != token or scope.get('token') != token
            or scope.get('root') != str(root) or scope.get('root_id') != owner['id']
            or scope.get('active_events_path') != str(root / EVENTS)
            or native.get('world_id') != profile['connection']['identity']['world_id']
            or native.get('pal_uid') != profile['connection']['identity']['pal_uid']
            or bool(scope.get('normal_title_observed'))):
        fail('JOURNAL_CRASH_SCOPE', '只接受本安装同一次未保存、未进入 Title 的真实 CLIENT_EXIT。')
    if (any(_scope_path(root, token, name).exists() for name in
            ('save-request.json', 'normal-save-file-witness.json', 'normal-stop-receipt.json', SAVED_CRASH_RECEIPT))
            or scope.get('normal_save_completed') is True):
        fail('JOURNAL_CRASH_SAVE', '已有原保存请求或见证，必须使用原 saved/normal 收尾入口。')
    binding = read_json(owned_path(root, DEV + '/bridge/exchange/escrow-client-process-binding.json'))
    permission = read_json(owned_path(root, '.palcraft/standalone/owned-loaded-save-permission.json'))
    filetime = binding.get('process_created_filetime', '')
    if (type(native.get('pid')) is not int or native['pid'] < 1
            or not isinstance(filetime, str) or not filetime.isdecimal()
            or binding.get('pid') != native['pid'] or binding.get('boot_id') != native.get('save_boot_id')
            or native.get('process_epoch') != str(native['pid']) + ':' + filetime
            or permission.get('process_epoch') != native.get('process_epoch')
            or binding.get('world_directory') != native.get('world_id') or binding.get('pal_uid') != native.get('pal_uid')):
        fail('JOURNAL_CRASH_SCOPE', '原 PID/FILETIME/boot binding 与 loaded-save observation 不一致。')
    pending = read_json(_scope_path(root, token, 'incomplete-stop.json'))
    exits = session.get('journal_lifecycle', {}).get('actor_exits', {})
    actors = scope.get('actors', {})
    if (pending.get('token') != token or pending.get('code') != 'JOURNAL_WITNESS_PENDING'
            or pending.get('normal_save_witness') not in (None, {})
            or pending.get('actor_exits') != exits or not actors or set(exits) != set(actors)):
        fail('JOURNAL_WITNESS_PENDING', '原监督器同 boot 的 actual-wait 集合不完整，未重造退出记录。')
    for key, actor in actors.items():
        result = exits[key]
        if (type(actor.get('pid')) is not int or not actor.get('identity')
                or result.get('actual_wait_completed') is not True
                or type(result.get('exit_code')) is not int
                or any(result.get(field) != actor.get(field) for field in ('pid', 'identity', 'role'))
                or process_identity(actor['pid']) is not None):
            fail('JOURNAL_ACTOR_ALIVE', '原 actor 身份/actual-wait 缺失或 PID 仍存在。')
        if actor['role'] in ('proxy', 'hud', 'udp', 'ssh'):
            worker = read_json(owned_path(root, '.palcraft/control/' + token + '.' + actor['role'] + '.' + str(actor['pid']) + '-exit.json'))
            child = worker.get('child', {})
            if (worker != result.get('owned_child_exit') or worker.get('token') != token
                    or worker.get('component') != actor['role'] or worker.get('actual_wait_completed') is not True
                    or type(child.get('pid')) is not int or not child.get('identity')
                    or process_identity(child['pid']) is not None):
                fail('JOURNAL_WITNESS_PENDING', '原 worker 子进程 wait/absence 证据不完整。')
    supervisor = session.get('supervisor', {})
    if (type(supervisor.get('pid')) is not int or not supervisor.get('identity')
            or process_identity(supervisor['pid']) is not None):
        fail('JOURNAL_ACTOR_ALIVE', '原监督器尚未实际退出。')
    clients = [value for value in exits.values() if value.get('role') == 'client']
    host_path = owned_path(root, '.palcraft/control/' + token + '.host.json')
    host = read_json(host_path)
    if (len(clients) != 1 or clients[0]['exit_code'] == 0 or host.get('exit_code') != clients[0]['exit_code']
            or host.get('phase') != 'failed' or host.get('primary_pid') != native.get('pid')
            or host.get('primary_alive') is not False or host.get('job_active_processes') != 0):
        fail('JOURNAL_CRASH_HOST', '需要同 native PID 的实际非零 host/client 退出及 empty job。')
    import xml.etree.ElementTree as ET
    reports = []
    crash_dir = owned_path(root, USER + '/Saved/Crashes')
    for report in crash_dir.glob('*/CrashContext.runtime-xml'):
        report = owned_path(root, report.relative_to(root).as_posix())
        if report.stat().st_size > 1048576:
            fail('JOURNAL_CRASH_REPORT', 'CrashContext 超出原只读诊断边界。')
        try:
            raw = report.read_bytes()
            text = raw.decode('utf-16') if raw.startswith((bytes.fromhex('fffe'), bytes.fromhex('feff'))) else raw.decode('utf-8-sig')
            # Decode the physical BOM first; only Unicode content reaches ET.
            text = re.sub(r'^\s*<\?xml\b.*?\?>', '', text, count=1, flags=re.IGNORECASE)
            document = ET.fromstring(text)
            pid = int(document.findtext('.//ProcessId') or '0')
        except (ValueError, ET.ParseError):
            continue
        identity = file_identity(report)
        if (pid == native.get('pid') and document.findtext('.//CrashType') == 'Crash'
                and identity['mtime_ns'] / 1e9 >= scope.get('started_unix', float('inf'))
                and identity['mtime_ns'] <= host_path.stat().st_mtime_ns):
            reports.append({'relative_path': report.relative_to(root).as_posix(),
                'identity': identity, 'sha256': digest(report), 'file_creation_not_exact_fault_time': True})
    if len(reports) != 1:
        fail('JOURNAL_CRASH_REPORT', '需要本 boot 同 native PID 的唯一当前 CrashContext。')
    ports = {str(port): _port_free(port) for port in (25567, 25599, 25603)}
    if not all(ports.values()):
        fail('JOURNAL_WITNESS_PENDING', '原后端端口尚未全部释放。')
    return {'session': session, 'scope': scope, 'profile': profile, 'exits': exits,
            'host': host, 'crash': reports[0], 'ports': ports}


def _existing_level_codec(root, facts, codec_python=None):
    """Read the existing Level/UID only; never attest this failed boot was saved."""
    import sys
    profile, scope = facts['profile'], facts['scope']; native = scope['native_scope']
    level = owned_path(root, USER + '/Saved/SaveGames/' + profile['standalone']['save_account_directory'] + '/' + native['world_id'] + '/Level.sav')
    selected = read_json(owned_path(root, '.palcraft/standalone/scope.json'))
    if Path(selected['installed_level_path_host']) != level or selected.get('world_directory') != native['world_id'] or selected.get('pal_uid') != native['pal_uid']:
        fail('JOURNAL_CRASH_CODEC', '既有 Level 不属于当前选定的同一世界和原 native UID。')
    player = owned_path(root, level.parent.relative_to(root).as_posix() + '/Players/' + native['pal_uid'].replace('-', '').upper() + '.sav')
    before = {str(path.relative_to(root)): {'identity': file_identity(path), 'sha256': digest(path)} for path in (level, player)}
    python = Path(codec_python or sys.executable)
    if not python.is_absolute() or not python.is_file():
        fail('JOURNAL_CRASH_CODEC', '原标准 codec 的 Python 可执行文件不可用。')
    code = '''import json,sys,io
from contextlib import redirect_stdout
from palworld_save_tools.palsav import decompress_sav_to_gvas
from palworld_save_tools.gvas import GvasFile
from palworld_save_tools.paltypes import PALWORLD_TYPE_HINTS
def parse(path):
    data=decompress_sav_to_gvas(open(path,"rb").read())[0]
    return GvasFile.read(data,PALWORLD_TYPE_HINTS,{},allow_nan=True)
with redirect_stdout(io.StringIO()):
    level=parse(sys.argv[1]);player=parse(sys.argv[2])
rows=level.properties["worldSaveData"]["value"]["CharacterSaveParameterMap"]["value"]
rows=rows.get("values",[]) if isinstance(rows,dict) else rows
found=any(str(row["key"]["PlayerUId"]["value"]).lower()==sys.argv[3].lower() for row in rows)
print(json.dumps({"level_parsed":True,"owned_uid_present":found,"player_parsed":True}))
'''
    environment = os.environ.copy(); environment['PYTHONPATH'] = str(root / DEV / 'mcp/vendor')
    result = subprocess.run([str(python), '-B', '-c', code, str(level), str(player), native['pal_uid']],
        capture_output=True, text=True, timeout=30, env=environment, cwd=root / DEV / 'mcp/vendor')
    try:
        parsed = json.loads(result.stdout)
    except ValueError:
        parsed = None
    if result.returncode != 0 and 'No module named' in result.stderr and ('ooz' in result.stderr or 'pyooz' in result.stderr):
        fail('JOURNAL_CODEC_DEPENDENCY', '所选 Python 缺少 pyooz（ooz）；标准 codec 未解析保存，也未签发回执。',
             '选择已安装 PalCraft-Dev/mcp/requirements-runtime.txt 中 pyooz==0.0.8 的现有 Python；finalize-stop --root OWNED_ROOT --codec-python EXISTING_PYTHON。')
    if result.returncode != 0 or parsed != {'level_parsed': True, 'owned_uid_present': True, 'player_parsed': True}:
        fail('JOURNAL_CRASH_CODEC', '标准 codec 未确认当前既有 Level/Player 和原 native UID。')
    if any(value != {'identity': file_identity(root / name), 'sha256': digest(root / name)} for name, value in before.items()):
        fail('JOURNAL_SAVE_PENDING', '只读 codec 期间既有保存发生变化。')
    return {'kind': 'existing-owned-Level-codec-observation-v1', 'world_id': native['world_id'],
        'pal_uid': native['pal_uid'], 'files': before, 'standard_codec': 'palworld_save_tools decompress_sav_to_gvas + GvasFile.read PALWORLD_TYPE_HINTS',
        'codec_python_executable': str(python), 'standard_codec_reparsed': True, 'level_and_player_parsed': True,
        'owned_UID_in_Level': True, 'normal_save_completed': False, 'this_boot_mutation_persistence_verified': False}


def _crash_business_recovery_report(root, inventory, hashes):
    """Preserve every observed business file; no invented terminal/commit verdict."""
    names = [name for name in inventory if '/Saved/' not in name and
        any(term in Path(name).name.lower() for term in ('escrow', 'food', 'credit', 'ledger', 'lease', 'pal-client-save'))]
    return {'original_business_recovery_required': bool(names), 'original_recovery_or_counterpart_witness_verified': False,
        'money_food_WAL_files': {name: {'identity': inventory[name], 'sha256': hashes[name]} for name in names},
        'no_WAL_counterparty_transaction_or_reader_offset_changed': True,
        'new_boot_replay_or_exactly_once_durability_claimed': False,
        'ledger_commit_resolution_not_asserted': True,
        'action': 'Keep every original Money/Food WAL for original replay/reconcile; no auto-ACK. This receipt archives only ordinary events.'}


def _unsaved_crash_receipt_matches(root, scope, session, receipt):
    try:
        facts = _crash_off_facts(root)
        codec = receipt.get('existing_level_codec_observation', {})
        if (receipt.get('schema') != 1 or receipt.get('root') != str(root)
                or receipt.get('root_id') != scope.get('root_id') or receipt.get('token') != session.get('token')
                or receipt.get('active_events_path') != str(root / EVENTS)
                or receipt.get('stream_identity') != (file_identity(root / EVENTS) if (root / EVENTS).exists() else None)
                or receipt.get('kind') != UNSAVED_CRASH_KIND or receipt.get('unsaved_crash_off_completed') is not True
                or receipt.get('normal_save_completed') is not False or receipt.get('mutations_may_be_unpersisted') is not True
                or receipt.get('normal_title_Quit_and_native_exit0') is not False
                or receipt.get('normal_title_observed') is not False
                or receipt.get('original_session_phase') != 'failed' or receipt.get('original_session_code') != 'CLIENT_EXIT'
                or facts['session'].get('token') != session.get('token') or facts['scope'] != scope
                or receipt.get('actor_exits') != facts['exits'] or receipt.get('host_observation') != facts['host']
                or receipt.get('game_crash_report') != facts['crash'] or receipt.get('native_scope') != scope.get('native_scope')
                or receipt.get('normal_save_witness') not in (None, {}) or receipt.get('normal_save_id') is not None
                or codec.get('kind') != 'existing-owned-Level-codec-observation-v1'
                or codec.get('standard_codec') != 'palworld_save_tools decompress_sav_to_gvas + GvasFile.read PALWORLD_TYPE_HINTS'
                or codec.get('this_boot_mutation_persistence_verified') is not False
                or codec.get('standard_codec_reparsed') is not True or codec.get('level_and_player_parsed') is not True
                or codec.get('owned_UID_in_Level') is not True or codec.get('normal_save_completed') is not False
                or codec.get('world_id') != scope['native_scope']['world_id'] or codec.get('pal_uid') != scope['native_scope']['pal_uid']
                or _crash_persistent_inventory(root) != receipt.get('persistent_stat_inventory')):
            return False
        profile = facts['profile']; native = scope['native_scope']
        level = owned_path(root, USER + '/Saved/SaveGames/' + profile['standalone']['save_account_directory'] + '/' + native['world_id'] + '/Level.sav')
        player = owned_path(root, level.parent.relative_to(root).as_posix() + '/Players/' + native['pal_uid'].replace('-', '').upper() + '.sav')
        if set(codec.get('files', {})) != {level.relative_to(root).as_posix(), player.relative_to(root).as_posix()}:
            return False
        hashes = receipt.get('persistent_sha256', {})
        if set(hashes) != set(receipt['persistent_stat_inventory']) or any(digest(root / name) != value for name, value in hashes.items()):
            return False
        if any(value != {'identity': file_identity(root / name), 'sha256': digest(root / name)} for name, value in codec.get('files', {}).items()) or len(codec.get('files', {})) != 2:
            return False
        report = _crash_business_recovery_report(root, receipt['persistent_stat_inventory'], hashes)
        return receipt.get('original_business_recovery') == report
    except (PlayerError, OSError, KeyError, ValueError, TypeError):
        return False


def finalize_crash_off(root, dry_run=False, quiet_seconds=2, codec_python=None):
    """A distinct unsaved failed/off receipt; never Save/Title/stop or repair state."""
    import contextlib
    from installer.core import operation_lock
    root = Path(root).absolute()
    with (contextlib.nullcontext() if dry_run else operation_lock(root)):
        facts = _crash_off_facts(root); scope, session = facts['scope'], facts['session']; token = session['token']
        existing = _scope_path(root, token, UNSAVED_CRASH_RECEIPT)
        if existing.is_file():
            receipt = read_json(existing)
            if not _unsaved_crash_receipt_matches(root, scope, session, receipt):
                fail('JOURNAL_STALE_RECEIPT', '原 unsaved crash-off 回执与当前静止文件或失败事实不一致。')
            return {'ok': True, 'dry_run': dry_run, 'unsaved_crash_off_receipt': str(existing),
                    'normal_save_completed': False, 'mutations_may_be_unpersisted': True,
                    'original_business_recovery': receipt['original_business_recovery'], 'already_issued': True}
        if dry_run:
            return {'ok': True, 'dry_run': True, 'receipt_created': False, 'normal_save_completed': False,
                    'mutations_may_be_unpersisted': True, 'actor_exits': facts['exits'],
                    'would_check_quiet_Saved_WAL_and_standard_codec_before_issuance': True}
        source = owned_path(root, EVENTS); stream = file_identity(source) if source.exists() else None
        before = _crash_persistent_inventory(root); time.sleep(quiet_seconds)
        if before != _crash_persistent_inventory(root):
            fail('JOURNAL_SAVE_PENDING', '全部原 actor off 后 Saved/WAL 仍在变化。')
        codec = _existing_level_codec(root, facts, codec_python)
        hashes = {name: digest(root / name) for name in before}
        if (before != _crash_persistent_inventory(root) or _crash_off_facts(root) != facts
                or (file_identity(source) if source.exists() else None) != stream):
            fail('JOURNAL_SAVE_PENDING', '解析/散列期间原保存、WAL、事件卷或退出事实发生变化。')
        recovery = _crash_business_recovery_report(root, before, hashes)
        receipt = {'schema': 1, 'kind': UNSAVED_CRASH_KIND, 'root': str(root), 'root_id': scope['root_id'],
            'token': token, 'native_scope': scope['native_scope'], 'active_events_path': str(source),
            'stream_identity': stream, 'actor_exits': facts['exits'], 'host_observation': facts['host'],
            'game_crash_report': facts['crash'], 'port_checks': facts['ports'], 'unsaved_crash_off_completed': True,
            'original_session_phase': session['phase'], 'original_session_code': session['code'],
            'normal_save_completed': False, 'mutations_may_be_unpersisted': True,
            'normal_title_observed': False, 'normal_title_Quit_and_native_exit0': False,
            'existing_level_codec_observation': codec, 'original_business_recovery': recovery,
            'all_owned_producers_and_consumers_stopped': True,
            'all_this_stream_producers_and_consumers_off_before_rotation': True,
            'Saved_and_WAL_stable_after_all_actors_off': True, 'persistent_stat_inventory': before,
            'persistent_sha256': hashes, 'observed_unix': time.time(),
            'SaveID_SID_UID_phase_generatedHashes_or_transaction_WAL_fabricated_or_rewritten': False,
            'events_archive_only_no_replay_or_exactly_once_persistence_claim': True}
        atomic_json(existing, receipt)
        return {'ok': True, 'unsaved_crash_off_receipt': str(existing), 'normal_save_completed': False,
                'mutations_may_be_unpersisted': True, 'original_business_recovery': recovery,
                'next_cold_boot_uses_original_archive_only_rotator': True}
