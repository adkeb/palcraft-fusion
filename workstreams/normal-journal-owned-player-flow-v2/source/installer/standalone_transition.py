"""Parameterised migration of an existing owned SP install/backend; no actors or world initialization."""
import argparse
import copy
import hashlib
import json
import time
from pathlib import Path

from installer.core import (DEV, TOOLS, USER, configure_standalone_transition, fail,
                            get_state, marker, read_json, validate_profile)
from installer.standalone import generated_files


def json_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def plan_transition(root, backend_root, existing_config, existing_launch_dir, save_account_directory=None):
    root = Path(root).absolute()
    backend = Path(backend_root).absolute()
    state = get_state(root)
    before = state['profile']
    if (before.get('platform') != 'crossover' or before.get('pal_entry_mode') != 'singleplayer'
            or before['connection'].get('transport') != 'local' or before['connection'].get('mode') != 'strict-player'):
        fail('TRANSITION_SCOPE', '迁移只接受本安装原本已选定的 Mac 本地严格单机 profile。')
    identity = before['connection']['identity']
    scope = read_json(root / '.palcraft/standalone/scope.json')
    account = str(save_account_directory or scope['steam_save_directory'])
    if (scope.get('world_directory') != identity['world_id'] or scope.get('pal_uid') != identity['pal_uid']
            or scope.get('steam_save_directory') != account):
        fail('TRANSITION_IDENTITY', '原正常 scope 的世界、Pal UID 或 Saved 账户目录不一致。')
    level = root / USER / 'Saved/SaveGames' / account / identity['world_id'] / 'Level.sav'
    world = backend / 'server/world'
    candidates = [world / folder / (identity['mc_uuid'] + '.dat') for folder in ('players/data', 'playerdata')]
    matches = [path for path in candidates if path.is_file()]
    if len(matches) != 1:
        fail('TRANSITION_PLAYERDATA', '原权威 MC 背包必须在现有版本布局中唯一存在，不能造一个替代文件。')
    playerdata = matches[0]
    guest = backend / 'players' / identity['mc_uuid'] / 'minecraft'
    if (not level.is_file() or not (world / 'level.dat').is_file() or not playerdata.is_file() or not guest.is_dir()
            or Path(scope['installed_level_path_host']).resolve() != level.resolve()):
        fail('TRANSITION_EXISTING_DATA', '必须保留原已存在的 Level、MC world/playerdata 和同 UUID guest；不能初始化或复制替代世界。')
    cfg_path = Path(existing_config).absolute()
    cfg = read_json(cfg_path)
    expected = {'software_root': backend, 'server_game_dir': backend / 'server', 'guest_game_dir': guest,
                'rpc_root': root / 'BridgeLab/rpc', 'server_bridge_dir': root / DEV / 'bridge',
                'guest_bridge_dir': root / DEV / 'bridge', 'exchange_dir': root / DEV / 'bridge/exchange',
                'entity_dir': root / 'BridgeLab/rpc/entities', 'frame_file': root / DEV / 'bridge/mcpt-hud.bin'}
    if (cfg.get('guest_mc_uuid') != identity['mc_uuid'] or cfg.get('guest_mc_name') != identity['mc_name']
            or any(Path(cfg[key]).resolve() != path.resolve() for key, path in expected.items())):
        fail('TRANSITION_BACKEND_SCOPE', '原后端配置与这一本安装、原世界或同一持久玩家不一致。')
    roles = {}
    launch_dir = Path(existing_launch_dir).absolute()
    for role in ('server', 'guest', 'hud'):
        old = read_json(launch_dir / (role + '.json'))
        cwd = {'server': backend / 'server', 'guest': guest, 'hud': root / DEV / 'bridge'}[role]
        if (old.get('role') != role or Path(old['config']).resolve() != cfg_path.resolve()
                or Path(old['cwd']).resolve() != cwd.resolve() or old.get('same_original_uuid') != identity['mc_uuid']
                or old.get('frame_file') != cfg['frame_file'] or not isinstance(old.get('arguments'), list)):
            fail('TRANSITION_ROLE_SCOPE', '原角色元数据与现有正常配置不一致：' + role)
        roles[role] = {key: old[key] for key in ('role', 'cwd', 'executable', 'main', 'arguments', 'same_original_uuid', 'frame_file')}
    profile = copy.deepcopy(before)
    preserved = copy.deepcopy(cfg)
    preserved['preserve_launch_template'] = str(root / TOOLS / 'standalone/previous-launch-plan.json')
    profile['standalone'] = {**profile.get('standalone', {}), 'backend_root': str(backend),
        'save_account_directory': account, 'enrollment_pending': True, 'backend_configuration': preserved}
    profile['connection']['server_session_id'] = None  # Cold boot must use the original new normal enrollment.
    profile = validate_profile(profile, root)
    generated = generated_files(profile, state['manifest'])
    selected = {}
    for target in ('.palcraft/standalone/scope.json', '.palcraft/standalone/resume.json', TOOLS + '/standalone/mac-runtime-config.json'):
        value = json.loads(generated[target])
        if target.endswith('/scope.json'):
            value = {**scope, **value}
        selected[target] = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    selected[TOOLS + '/standalone/previous-launch-plan.json'] = (json.dumps({'schema': 1, 'roles': roles,
        'source_configuration_sha256': json_sha(cfg), 'role_arguments_preserved': True}, ensure_ascii=False, indent=2) + '\n').encode()
    return {'schema': 1, 'root': str(root), 'root_id': marker(root)['id'], 'before_profile_sha256': json_sha(before),
        'before_manifest_sha256': json_sha(state['manifest']), 'profile': profile,
        'generated_files': {key: value.decode() for key, value in selected.items()},
        'persistent_identity_unchanged': True, 'world_origin_unchanged': True,
        'existing_data': {'Level': str(level), 'server_world': str(world), 'server_playerdata': str(playerdata), 'guest_game_dir': str(guest)},
        'existing_roles_source': str(launch_dir), 'role_arguments_preserved': True,
        'source_allOff_required': True, 'backend_or_Saved_or_ledger_copy_or_initialization': False,
        'actors_adopted_started_stopped_or_signalled': False, 'new_SID_or_credential_or_permission': False}


def apply_transition(plan, normal_stop_receipt, dry_run=False, fault=None):
    root = Path(plan['root']).absolute()
    def preflight():
        state = get_state(root)
        session = read_json(root / '.palcraft/session.json', {})
        receipt = read_json(normal_stop_receipt)
        witness = receipt.get('normal_save_witness', {})
        if (marker(root)['id'] != plan['root_id'] or json_sha(state['profile']) != plan['before_profile_sha256']
                or json_sha(state['manifest']) != plan['before_manifest_sha256']):
            fail('TRANSITION_CHANGED', '原 profile/manifest 已变化，先重新生成本轮迁移计划。')
        if (receipt.get('root') != str(root) or receipt.get('root_id') != plan['root_id']
                or receipt.get('active_events_path') != str(root / 'BridgeLab/rpc/palcraft-events.ndjson')
                or receipt.get('normal_save_completed') is not True
                or receipt.get('normal_title_Quit_and_native_exit0') is not True
                or receipt.get('MC_server_normal_stop_exit') != 0
                or receipt.get('all_owned_producers_and_consumers_stopped') is not True
                or receipt.get('all_this_stream_producers_and_consumers_off_before_rotation') is not True
                or receipt.get('observed_unix', 0) < session.get('started_unix', 0)
                or receipt.get('token', session.get('token')) != session.get('token')
                or not witness.get('normal_save_id') or witness.get('after_submission') is not True
                or witness.get('stable') is not True):
            fail('TRANSITION_ALL_OFF', '迁移必须等本轮原正常保存/Title/native exit0/sharedMC stop0及全部 stream allOff真实回执。')
    extras = {key: value.encode() for key, value in plan['generated_files'].items()}
    if dry_run:
        return configure_standalone_transition(root, plan['profile'], extras, dry_run=True)
    result = configure_standalone_transition(root, plan['profile'], extras, fault=fault, preflight=preflight)
    return {**result, 'next_boot': 'original bootstrap then actual normal enrollment and prepare_launch; original promote --sync-receipt creates new owned Popen',
            'old_external_actor_adoption': False, 'normal_stop_receipt': str(Path(normal_stop_receipt).absolute())}


def transfer_sync(root, previous_sync, fresh_sync, enrolled_profile, output):
    """Retain original snapshot history only after the original issuer supplied current enrollment facts."""
    root = Path(root).absolute()
    previous, fresh = read_json(previous_sync), read_json(fresh_sync)
    profile = validate_profile(read_json(enrolled_profile), root)
    session = read_json(root / '.palcraft/session.json')
    native = read_json(root / DEV / 'bridge/lab-identity.json')
    permission = read_json(root / '.palcraft/standalone/owned-loaded-save-permission.json')
    sid = profile['connection']['server_session_id']
    identity = profile['connection']['identity']
    verification_path = fresh.get('actual_fresh_enrollment_signature_verification')
    verification = read_json(verification_path, {}) if verification_path else {}
    if (session.get('phase') != 'bootstrap' or not isinstance(sid, str) or not sid.startswith('standalone:')
            or native.get('server_session_id') != sid or permission.get('process_epoch') != native.get('process_epoch')
            or permission.get('published_unix', 0) < session.get('started_unix', 0)
            or native.get('world_directory') != identity['world_id'] or native.get('host_uid') != identity['pal_uid']
            or fresh.get('actual_standalone_host_identity_enrolled') is not True
            or fresh.get('actual_standalone_server_session_id') != sid
            or fresh.get('actual_standalone_pal_uid') != identity['pal_uid']
            or fresh.get('normal_enrollment_observed_unix', 0) < session.get('started_unix', 0)
            or verification.get('exit_code') != 0 or verification.get('observed_unix', 0) < session.get('started_unix', 0)
            or fresh.get('mc_uuid') != identity['mc_uuid']):
        fail('TRANSITION_ENROLLMENT', '只能转接原 issuer 对本 bootstrap 的新正常登记/验签结果，不能复制旧 SID 或历史 enrolled 标记。')
    if not all(previous.get(key) is True for key in ('previous_world_producers_stopped', 'immutable_snapshot_synced',
                                                   'same_mc_uuid_preserved', 'ledger_configuration_preserved')):
        fail('TRANSITION_SYNC_HISTORY', '需要原真实 save/stop 和原同 UUID world/ledger 同步历史。')
    if previous.get('mc_uuid') != identity['mc_uuid']:
        fail('TRANSITION_SYNC_HISTORY', '原同步历史不是同一个持久 MC 玩家。')
    target = Path(output)
    if target.exists(): fail('OUTPUT_EXISTS', '不覆盖原已用同步回执。')
    result = {**previous, **fresh, 'normal_profile_transition_same_world_preserved': True,
              'world_or_playerdata_or_ledger_recreated_or_recopied': False,
              'history_flags_are_not_new_world_initialization_proof': True}
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return {'ok': True, 'sync_receipt': str(target), 'new_identity_or_authority_created': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    prepare = sub.add_parser('plan')
    for name in ('root', 'backend-root', 'existing-config', 'existing-launch-dir', 'output'):
        prepare.add_argument('--' + name, required=True, type=Path)
    prepare.add_argument('--save-account-directory')
    apply = sub.add_parser('apply')
    apply.add_argument('--plan', required=True, type=Path)
    apply.add_argument('--normal-stop-receipt', required=True, type=Path)
    apply.add_argument('--dry-run', action='store_true')
    sync = sub.add_parser('sync')
    for name in ('root', 'previous-sync', 'fresh-sync', 'enrolled-profile', 'output'):
        sync.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    if args.command == 'plan':
        if args.output.exists(): fail('OUTPUT_EXISTS', '迁移计划不能覆盖既有私有规格。')
        plan = plan_transition(args.root, args.backend_root, args.existing_config, args.existing_launch_dir, args.save_account_directory)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({'planned_only': True, 'private_output': str(args.output), 'live_root_written': False}))
    elif args.command == 'apply':
        print(json.dumps(apply_transition(read_json(args.plan), args.normal_stop_receipt, args.dry_run), ensure_ascii=False))
    else:
        print(json.dumps(transfer_sync(args.root, args.previous_sync, args.fresh_sync, args.enrolled_profile, args.output), ensure_ascii=False))


if __name__ == '__main__':
    main()
