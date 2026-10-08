"""Standalone parameters over the existing installer transaction and normal enrollment."""
import hashlib
import json
import os
import re
import shutil
import time
import uuid
from pathlib import Path

from installer.core import (BIN, DEV, TOOLS, USER, atomic_json, digest, ensure_no_session,
                            fail, get_state, install, operation_lock, owned_path, read_json,
                            uninstall, validate_profile)


def offline_uuid(name):
    if not re.fullmatch(r'[A-Za-z0-9_]{1,16}', name):
        fail('MC_NAME', 'Minecraft 名称应为 1–16 个字母、数字或下划线。')
    data = bytearray(hashlib.md5(('OfflinePlayer:' + name).encode()).digest())
    data[6], data[8] = (data[6] & 15) | 48, (data[8] & 63) | 128
    return str(uuid.UUID(bytes=bytes(data)))


def make_profile(root, resume, *, bottle_name, bottle_root, crossover_app, backend_root,
                 bottle_mode='existing-selected', copy_mode='copy'):
    root = Path(root).absolute()
    identity = resume.get('persistent_identity', resume.get('identity', {})).copy()
    if set(identity) != {'world_id', 'pal_uid', 'mc_name', 'mc_uuid'}:
        fail('RESUME_IDENTITY', '提供自己的正常单机 world/Pal UID 和 Minecraft 名称/持久 UUID；不能使用作者的快照。')
    expected = offline_uuid(identity['mc_name'])
    if identity['mc_uuid'] is None:
        identity['mc_uuid'] = expected
    if identity['mc_uuid'] != expected or str(uuid.UUID(identity['pal_uid'])) != identity['pal_uid']:
        fail('RESUME_IDENTITY', '正常单机身份格式或 Minecraft 持久 UUID 不一致。')
    if not re.fullmatch(r'[A-Fa-f0-9]{32}', identity['world_id']):
        fail('RESUME_WORLD', '提供自己真实世界目录的 32 位标识。')
    account = str(resume.get('save_account_directory', ''))
    if not re.fullmatch(r'[0-9]{1,24}', account):
        fail('RESUME_SAVE', '提供自己的 Saved/SaveGames 下数字目录名。')
    origin = resume.get('world_origin')
    if not isinstance(origin, dict):
        fail('RESUME_ORIGIN', '提供自己正常单机的共享坐标原点。')
    backend = Path(backend_root).expanduser().absolute()
    if backend == root or root.is_relative_to(backend):
        fail('BACKEND_ROOT', '后端软件目录不能包含玩家安装目录。')
    profile = {'schema': 1, 'platform': 'crossover', 'bottle_name': bottle_name,
        'bottle_root': str(Path(bottle_root).expanduser().absolute()), 'bottle_mode': bottle_mode,
        'crossover_app': str(Path(crossover_app).expanduser().absolute()), 'pal_entry_mode': 'singleplayer',
        'launch_shipping': True, 'game_copy_mode': copy_mode, 'fps': 60, 'mute': True,
        'performance': {'preset': 'normal', 'pal_fps': 60, 'mc_fps': 60, 'hud_fps': 30},
        'connection': {'mode': 'strict-player', 'transport': 'local', 'identity': identity,
            # Installation precedes normal native observation/enrollment; no SID is invented.
            'server_session_id': None, 'world_origin': origin,
            'frame_mapping': 'Local' + chr(92) + 'MCPassthroughFrame-' + identity['mc_uuid'],
            'remote_ports': {'udp_tcp': 18321, 'mc_ws': 25599, 'mc_server': 25567, 'hud': 25603},
            'local_ports': {'mc_ws': 29599}},
        'standalone': {'backend_root': str(backend), 'save_account_directory': account,
                       'enrollment_pending': True}}
    return validate_profile(profile, root)


def generated_files(profile, manifest=None):
    root, win = Path(profile['root']), profile['windows_root']
    manifest = manifest if manifest is not None else get_state(root)['manifest']
    mods = [entry for entry in manifest['files'] if entry.get('role') == 'minecraft_mod']
    if len(mods) != 1 or not mods[0]['target'].startswith(DEV + '/minecraft-mods/'):
        fail('MC_MOD_ROLE', '当前发布包必须包含唯一受管理的 Minecraft 模组。')
    mod_filename, mod_sha256 = Path(mods[0]['target']).name, mods[0]['sha256']
    spec = profile['standalone']; identity = profile['connection']['identity']
    backend = Path(spec['backend_root']); bridge = root / DEV / 'bridge'; rpc = root / 'BridgeLab/rpc'
    scripts = 'BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts'
    user = root / USER
    level_relative = USER + '/Saved/SaveGames/' + spec['save_account_directory'] + '/' + identity['world_id'] + '/Level.sav'
    scope = {'kind': 'palcraft_standalone_runtime', 'mode': 'standalone',
        'configured_for_runtime': False, 'authority_or_game_ready_claimed': False,
        'world_directory': identity['world_id'], 'pal_uid': identity['pal_uid'],
        'steam_save_directory': spec['save_account_directory'], 'install_root_windows': win,
        'wine_prefix_host': profile['bottle_root'], 'private_user_dir_host': str(user),
        'private_user_dir_windows': win + '/' + USER,
        'installed_level_path_host': str(root / level_relative), 'installed_level_path_windows': win + '/' + level_relative,
        'scripts_dir_windows': win + '/' + scripts + '/',
        'executable_sha256': 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'}
    for name, relative in {'pal_exe': BIN + 'Palworld-Win64-Shipping.exe',
        'rpc_root': 'BridgeLab/rpc', 'exchange_root': DEV + '/bridge/exchange',
        'durable_dll': scripts + '/PalCraftExchangeDurable-v3.dll',
        'credit_dll': scripts + '/PalCraftEscrowCredit-client-v1.dll'}.items():
        scope[name + '_host'] = str(root / relative); scope[name + '_windows'] = win + '/' + relative
    scope['fluid_dll_windows'] = win + '/' + BIN + 'PalCraftFluidPhysics-v1.dll'
    scope['client_log_windows'] = win + '/' + BIN + 'ue4ss/UE4SS.log'
    mcp = {'schema': 1, 'transport': 'localStandalone', 'owned_root': str(root), 'windows_root': win,
           'rpc_directory': 'BridgeLab/rpc', 'lab_rpc_directory': 'BridgeLab/rpc',
           'mc_bridge_directory': DEV + '/bridge', 'timeout_seconds': 40}
    cfg = {'schema': 1, 'configured_for_actual_boot': False, 'software_root': str(backend),
        'backend_data_root': str(root), 'guest_mc_uuid': identity['mc_uuid'], 'guest_mc_name': identity['mc_name'],
        'java_home': str(backend / 'java/Contents/Home'), 'server_game_dir': str(backend / 'server'),
        'guest_game_dir': str(backend / 'players' / identity['mc_uuid'] / 'minecraft'),
        'server_bridge_dir': str(bridge), 'guest_bridge_dir': str(bridge), 'entity_dir': str(rpc / 'entities'),
        'rpc_root': str(rpc), 'exchange_dir': str(bridge / 'exchange'),
        'authority_public': str(rpc / 'session-auth/authority-public.json'),
        'credential_file': str(root / '.palcraft/credentials/credential.json'),
        'frame_file': str(bridge / 'mcpt-hud.bin'), 'frame_transport': 'file-map',
        'minecraft_server': '127.0.0.1:25567', 'guest_ws': 25599, 'hud': '127.0.0.1:25603',
        'frontend_proxy': '127.0.0.1:29599', 'assets_dir': str(backend / 'assets'),
        'mod_filename': mod_filename,
        'mod_sha256': mod_sha256,
        'launch_dir': str(root / TOOLS / 'standalone/launch'),
        'hud_relay_script': str(root / TOOLS / 'mac/hud/hud_relay.py'),
        'feature_jvm_public': {'palcraft.exchange.enabled': 'true', 'palcraft.travel.enabled': 'true',
            'palcraft.worldScopedCam.enabled': 'true', 'palcraft.entityLab': 'false',
            'palcraft.legacyPlayerTeleportEvents': 'false', 'palcraft.legacyNetherEffects': 'false'},
        'performance': {'mc_fps': 60, 'hud_fps': 30, 'render_distance': 8, 'simulation_distance': 12, 'mute': True}}
    preserved = spec.get('backend_configuration')
    if preserved is not None:
        if not isinstance(preserved, dict):
            fail('BACKEND_CONFIG', '原后端配置必须为参数字典。')
        # Keep real existing JVM/performance/unknown options across normal updates.
        # Installation paths, persistent identity and current managed mod remain derived from this profile.
        fixed = {key: cfg[key] for key in ('software_root', 'backend_data_root', 'guest_mc_uuid', 'guest_mc_name',
            'server_game_dir', 'guest_game_dir', 'server_bridge_dir', 'guest_bridge_dir', 'entity_dir', 'rpc_root',
            'exchange_dir', 'authority_public', 'credential_file', 'frame_file', 'frame_transport',
            'mod_filename', 'mod_sha256', 'launch_dir', 'hud_relay_script')}
        cfg.update(preserved)
        cfg.update(fixed)
        cfg['configured_for_actual_boot'] = False
    values = {'.palcraft/standalone/scope.json': scope, '.palcraft/standalone/resume.json': {
        'persistent_identity': identity, 'save_account_directory': spec['save_account_directory'],
        'world_origin': profile['connection']['world_origin'], 'fresh_normal_enrollment_required': True},
        TOOLS + '/standalone/mac-runtime-config.json': cfg,
        DEV + '/mcp/ai-transport.json': mcp, DEV + '/mcp/mc-transport.json': mcp}
    return {key: (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode() for key, value in values.items()}


def setup_standalone(root, game, bundle, resume, **options):
    dry = options.pop('dry_run', False)
    profile = make_profile(root, resume, **options)
    result = install(root, game, bundle, profile, dry_run=dry)
    if not dry:
        from launcher.runtime import create_bottle
        bottle = create_bottle(root)
    else:
        bottle = {'planned': profile['bottle_mode'], 'created': False}
    return {'ok': True, 'dry_run': dry, 'installation': result, 'bottle': bottle,
        'entry': 'start --root ROOT --boot-singleplayer', 'profile_is_not_enrollment': True,
        'normal_load_observation_permission_and_enrollment_required': True,
        'backend_config': str(Path(root).absolute() / TOOLS / 'standalone/mac-runtime-config.json'),
        'Saved_or_world_or_SID_created_or_copied': False, 'processes_or_RPC_started': []}


def prepare_backend(root, dry_run=False):
    root = Path(root).absolute(); state = get_state(root)
    profile = state['profile']; cfg_path = root / TOOLS / 'standalone/mac-runtime-config.json'
    cfg = read_json(cfg_path); backend = Path(profile['standalone']['backend_root'])
    source = root / DEV / 'minecraft-mods' / cfg['mod_filename']
    destinations = [backend / 'mods' / source.name, backend / 'server/mods' / source.name,
                    Path(cfg['guest_game_dir']) / 'mods' / source.name]
    plan = {'ok': True, 'dry_run': dry_run, 'copies': [str(p) for p in destinations],
            'launch_generator': str(root / TOOLS / 'mac/scripts/prepare_launch.py'),
            'config': str(cfg_path), 'software_dependencies_required': str(backend),
            'world_playerdata_Saved_changed': False, 'processes_started': []}
    if dry_run: return plan
    with operation_lock(root):
        session = read_json(root / '.palcraft/session.json', {})
        if session.get('launch_mode')=='singleplayer-bootstrap' and session.get('phase')=='bootstrap':
            from launcher.runtime import process_matches, _port_free
            if (set(session.get('components',{}))!={'client'}
                    or not process_matches(session.get('supervisor',{}))
                    or not process_matches(session['components']['client'])
                    or not all(_port_free(port) for port in (25567,25599,25603))):
                fail('BACKEND_ACTIVE', '后端准备只允许本安装的原 bootstrap、尚未启动任何 MC/HUD 后端。')
        else:
            ensure_no_session(root)
        source_sha = digest(source)
        if source_sha != cfg['mod_sha256']:
            fail('BACKEND_MOD_HASH', '本安装的模组与当前发布包配置校验不一致。')
        previous = read_json(root / '.palcraft/standalone/backend-files.json', {})
        managed = {entry['path']: entry['sha256'] for entry in previous.get('files', [])} if previous.get('backend_root') == str(backend) else {}
        if not managed:
            # These first-generation backend copies predate backend-files.json.
            # Adopt only the exact old mod of this installation's committed upgrade.
            candidates=set()
            for journal_path in (root / '.palcraft/transactions').glob('*/journal.json'):
                journal=read_json(journal_path,{})
                before=journal.get('before_state') or {}
                if journal.get('phase')!='committed' or before.get('profile',{}).get('standalone',{}).get('backend_root')!=str(backend):
                    continue
                old_mods=[v for v in before.get('manifest',{}).get('files',[]) if v.get('role')=='minecraft_mod']
                if len(old_mods)!=1 or Path(old_mods[0]['target']).name!=source.name:
                    continue
                old_mod=old_mods[0]
                changes=[v for v in journal.get('changes',[]) if v.get('target')==old_mod['target']
                    and v.get('old_sha256')==old_mod['sha256'] and v.get('new_sha256')==source_sha]
                backup=journal_path.parent/'before'/old_mod['target']
                if len(changes)==1 and backup.is_file() and digest(backup)==old_mod['sha256']:
                    candidates.add(old_mod['sha256'])
            if len(candidates)==1:
                old_sha=next(iter(candidates))
                if all(destination.is_file() and digest(destination)==old_sha for destination in destinations):
                    managed={str(destination):old_sha for destination in destinations}
        # Update only the existing owned copies that still have their recorded bytes.
        # Complete this preflight before replacing any of the three normal targets.
        for destination in destinations:
            if destination.exists():
                actual = digest(destination)
                if actual != source_sha and managed.get(str(destination)) != actual:
                    fail('BACKEND_MOD_EXISTS', '目标同名模组未由本安装管理或内容已更改，未作覆盖。')
        files = []
        for destination in destinations:
            destination.parent.mkdir(parents=True, exist_ok=True)
            pending = destination.with_suffix('.palcraft-pending')
            shutil.copy2(source, pending); os.replace(pending, destination)
            files.append({'path': str(destination), 'sha256': source_sha})
        atomic_json(root / '.palcraft/standalone/backend-files.json', {'backend_root': str(backend), 'files': files})
    return plan


def enrollment_profile(root, guest_manifest, output):
    """Read the original issuer's credential; never creates a SID/key/grant."""
    from installer.credentials import prepare_credential_profile
    root = Path(root).absolute(); state = get_state(root)
    profile, inspected = prepare_credential_profile(state['profile'], root,
        root / '.palcraft/credentials/credential.json', guest_manifest)
    profile['standalone']['enrollment_pending'] = False
    scope_path = root / '.palcraft/standalone/scope.json'
    permission = read_json(root / '.palcraft/standalone/owned-loaded-save-permission.json')
    if permission.get('native_context', {}).get('world_id') != profile['connection']['identity']['world_id']:
        fail('ENROLLMENT_OBSERVATION', '先完成原正常 loaded-save/process 观察授权，再准备本轮配置。')
    scope = read_json(scope_path); scope['configured_for_runtime'] = True
    scope['client_log_windows'] = profile['windows_root'] + '/' + BIN + 'ue4ss/UE4SS.log'
    atomic_json(scope_path, scope)
    cfg_path = root / TOOLS / 'standalone/mac-runtime-config.json'
    cfg = read_json(cfg_path); cfg['configured_for_actual_boot'] = True
    atomic_json(cfg_path, cfg)
    atomic_json(output, profile)
    return {'ok': True, 'public_profile': str(output), 'inspection_only': inspected['inspection_only'],
            'signature_verified_locally': False, 'new_identity_SID_grant_or_private_key_generated': False}


def uninstall_standalone(root, dry_run=False):
    root = Path(root).absolute()
    record = read_json(root / '.palcraft/standalone/backend-files.json', {})
    removed, kept = [], []
    if record and not dry_run:
        with operation_lock(root):
            ensure_no_session(root)
            for item in record['files']:
                path = Path(item['path'])
                if path.is_file() and digest(path) == item['sha256']:
                    path.unlink(); removed.append(str(path))
                elif path.exists(): kept.append(str(path))
    result = uninstall(root, dry_run=dry_run)
    return {**result, 'backend_package_files_removed': removed, 'modified_backend_files_preserved': kept,
            'backend_world_playerdata_ledger_preserved': True}


def rotate_events(root, stop_receipt, dry_run=False):
    """Archive only the ordinary event journal after the original sole-owner stop."""
    from installer.core import marker
    root = Path(root).absolute(); state = get_state(root)
    profile = state['profile']; receipt = read_json(stop_receipt)
    if profile.get('pal_entry_mode') != 'singleplayer' or profile['connection'].get('transport') != 'local':
        fail('JOURNAL_SCOPE', '此分卷入口仅用于本机独立单机安装。')
    original_receipt = (receipt.get('active_events_path') == str(root / 'BridgeLab/rpc/palcraft-events.ndjson') and
        receipt.get('normal_title_Quit_and_native_exit0') is True and receipt.get('MC_server_normal_stop_exit') == 0 and
        receipt.get('all_this_stream_producers_and_consumers_off_before_rotation') is True)
    named_receipt = (receipt.get('root') == str(root) and receipt.get('root_id') == marker(root)['id'] and
        receipt.get('normal_save_completed') is True and receipt.get('all_owned_producers_and_consumers_stopped') is True)
    unsaved_named_receipt = False
    if receipt.get('kind') == 'palcraft-owned-unsaved-crash-off-v1':
        from launcher.journal_lifecycle import (LIFECYCLE, _scope_path, _unsaved_crash_receipt_matches)
        session = read_json(owned_path(root, '.palcraft/session.json'))
        scope = read_json(_scope_path(root, session.get('token', ''), 'scope.json'))
        unsaved_named_receipt = (_unsaved_crash_receipt_matches(root, scope, session, receipt)
            and receipt.get('normal_save_completed') is False and receipt.get('mutations_may_be_unpersisted') is True
            and receipt.get('root') == str(root) and receipt.get('root_id') == marker(root)['id']
            and all(receipt.get(key) is True for key in ('all_owned_producers_and_consumers_stopped',
                'all_this_stream_producers_and_consumers_off_before_rotation', 'Saved_and_WAL_stable_after_all_actors_off')))
    if not (original_receipt or named_receipt or unsaved_named_receipt):
        fail('JOURNAL_STOP', '需要原正常保存退出流程对本 root 的唯一停机回执；不能旋转运行实例或其他玩家。')
    source = owned_path(root, 'BridgeLab/rpc/palcraft-events.ndjson')
    archive = owned_path(root, 'BridgeLab/rpc/journal-archives/' + str(time.time_ns()) + '/palcraft-events.ndjson')
    result = {'ok': True, 'dry_run': dry_run, 'same_writer_path': str(source), 'archive': str(archive),
              'Saved_world_playerdata_food_escrow_WAL_touched': False, 'fake_rows_ACK_or_reader_offsets': False}
    if unsaved_named_receipt:
        result.update(normal_save_completed=False, mutations_may_be_unpersisted=True,
            original_business_recovery=receipt['original_business_recovery'],
            events_archive_only_no_replay_or_exactly_once_persistence_claim=True)
    if dry_run:return result
    with operation_lock(root):
        ensure_no_session(root)
        before = source.stat(); original_sha = digest(source)
        if (source.stat().st_size, source.stat().st_mtime_ns) != (before.st_size, before.st_mtime_ns):
            fail('JOURNAL_RUNNING', 'journal 仍被写入，未执行分卷。')
        archive.parent.mkdir(parents=True)
        os.replace(source, archive)
        result.update(archived_bytes=before.st_size, archived_sha256=original_sha,
                      new_volume_created_by_original_writer_only=True)
        atomic_json(archive.parent / 'rotation-receipt.json', result)
    return result
