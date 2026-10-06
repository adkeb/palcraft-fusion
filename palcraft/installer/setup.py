"""One personal installation entry; backend and save migration remain explicit plans."""
from pathlib import Path

from installer.core import DEV, USER, atomic_json, fail, get_state, install, owned_path
from installer.credentials import import_credential, prepare_credential_profile
from installer.resources import prepare_resources
from launcher.runtime import create_bottle


def launch_plan(root, profile, previous_root=None, fabric_entry=None, source_user_dir=None):
    root = Path(root).absolute()
    identity = profile['connection']['identity']
    migration = {'required': False, 'performed': False, 'server_world_or_playerdata_touched': False}
    if previous_root is not None:
        previous = Path(previous_root).absolute()
        if previous == root:
            fail('SAVE_SOURCE', '迁移源与新安装目录不能相同。')
        old = get_state(previous)
        if old['profile']['connection'].get('identity') != identity:
            fail('SAVE_IDENTITY', '旧个人安装与当前凭据身份不同，不能沿用其存档或生成替代 UUID。')
        migration.update(required=True, source=str(previous / USER), destination=str(root / USER),
                         prerequisite='stop both owned personal sessions; then explicit verified copy in the clean-save window')
    if source_user_dir is not None:
        source = Path(source_user_dir).absolute()
        if source == root / USER or source.is_relative_to(root) or root.is_relative_to(source):
            fail('SAVE_SOURCE', '原 UserDir 与新安装目录不能相互包含。')
        migration.update(required=True, source=str(source), destination=str(root / USER),
                         source_verified_by_runtime_owner_only=True,
                         prerequisite='runtime verifies current client identity and normal exit, then explicit incremental UserDir copy; no Steam/account/private captures')
    return {'schema': 1, 'kind': 'personal-player-launch-plan', 'identity': identity,
            'mc_uuid': identity['mc_uuid'], 'pal_uid': identity['pal_uid'],
            'world_id': identity['world_id'], 'new_uuid_generated': False,
            'pal_user_directory': str(root / USER), 'save_migration': migration,
            'isolated_shipping_launch': profile.get('launch_shipping') is True,
            'java_fabric': {'mode': 'standard standalone Jar and registered guest, never development DLI',
                            'entry': fabric_entry, 'entry_declared': fabric_entry is not None, 'ready': False,
                            'required': {'java': '>=25', 'fabric_loader': '>=0.19.5', 'minecraft': '~26.3'},
                            'guest_uuid': identity['mc_uuid'], 'guest_name': identity['mc_name'],
                            'world_and_playerdata': 'reuse existing matching world/UUID after the clean-save window; do not generate a replacement world'},
            'pal_launch': ['python3', str(root / 'PalCraft-Dev/player-tools/launcher/palcraft.py'), 'start', '--root', str(root)],
            'actual_player_startup_accepted': False, 'backend_started_or_stopped': []}


def setup_player(root, game, bundle, profile, credential, guest_manifest, *, minecraft_jar=None,
                 previous_root=None, fabric_entry=None, source_user_dir=None, dry_run=False, bottle_runner=None):
    root = Path(root).absolute()
    profile, _ = prepare_credential_profile(profile, root, credential, guest_manifest)
    plan = install(root, game, bundle, profile, dry_run=True)
    after = launch_plan(root, profile, previous_root, fabric_entry, source_user_dir)
    if dry_run:
        return {'ok': True, 'dry_run': True, 'install': plan, 'launch': after,
                'credential_copied': False, 'bottle_created': False, 'game_or_services_started': []}
    result = install(root, game, bundle, profile)
    imported = import_credential(root, credential, guest_manifest)
    bottle = None
    if profile['platform'] == 'crossover':
        arguments = {} if bottle_runner is None else {'runner': bottle_runner}
        bottle = create_bottle(root, **arguments)
    resources = prepare_resources(root, minecraft_jar) if minecraft_jar else None
    atomic_json(owned_path(root, '.palcraft/player-launch-plan.json'), after)
    return {'ok': True, 'installation': result, 'credential': imported,
            'bottle': bottle, 'resources': resources, 'launch': after, 'game_or_services_started': []}
