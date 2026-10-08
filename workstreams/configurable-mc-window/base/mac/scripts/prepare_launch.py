"""Prepare local native-Mac MC/HUD arguments only; never starts a service."""
import argparse
import json
from pathlib import Path

def with_role_fps(values, fps, guest=False):
    result = list(values)
    if guest:
        indexes = [i for i, value in enumerate(result) if value.startswith('-Dpalcraft.maxFps=')]
    else:
        indexes = [i for i, value in enumerate(result) if value == '--fps']
    if len(indexes) != 1 or (not guest and indexes[0] + 1 == len(result)):
        raise ValueError('Performance override requires one original FPS argument per guest/HUD role')
    index = indexes[0]
    if guest:
        result[index] = '-Dpalcraft.maxFps=' + str(fps)
    else:
        result[index + 1] = str(fps)
    return result


def prepare_launch(config_path, performance_override=None):
    if performance_override is not None:
        if (not isinstance(performance_override, dict)
                or set(performance_override) != {'mc_fps', 'hud_fps'}
                or any(type(performance_override[key]) is not int or not 1 <= performance_override[key] <= maximum
                       for key, maximum in (('mc_fps', 60), ('hud_fps', 120)))):
            raise ValueError('Performance override requires only integer mc_fps (1..60) and hud_fps (1..120)')
    cfg = json.loads(Path(config_path).read_text())
    root = Path(cfg['software_root'])
    plan = json.loads((root / 'setup/mac-dependency-plan.json').read_text())
    uuid = cfg['guest_mc_uuid']
    out = Path(cfg.get('launch_dir', root / 'launch'))
    out.mkdir(parents=True, exist_ok=True)
    java = Path(cfg['java_home']) / 'bin/java'
    features = ['-D' + key + '=' + value for key, value in cfg['feature_jvm_public'].items()]
    common = ['-Dfabric.development=false', '--enable-native-access=ALL-UNNAMED', '--sun-misc-unsafe-memory-access=allow']
    server = common + ['-Xmx2G', '-Dpalcraft.shared=true', '-Dpalcraft.sessions.mode=strict',
        '-Dpalcraft.sessions.authority=' + cfg['authority_public'], '-Dpalcraft.bridgeDir=' + cfg['server_bridge_dir'],
        '-Dpalcraft.entityDir=' + cfg['entity_dir'], '-Dpalcraft.exchangeDir=' + cfg['exchange_dir'],
        '-Dpalcraft.serverJournal=' + str(Path(cfg['rpc_root']) / 'authoritative-events.ndjson'),
        '-Dpalcraft.travelAckJournal=' + str(Path(cfg['rpc_root']) / 'travel/travel-acks.ndjson')] + features + [
        '-jar', str(root / 'server/fabric-server-launch.jar'), 'nogui']
    libraries = [root / 'client/libraries' / row['path'] for row in plan['libraries']]
    libraries.append(root / 'client/versions/26.3/26.3.jar')
    if not all(path.is_file() for path in libraries):
        raise FileNotFoundError('Expected hash-verified native-Mac libraries')
    game = Path(cfg['guest_game_dir'])
    profile = json.loads((root / 'client/versions/fabric-loader-0.19.5-26.3/fabric-loader-0.19.5-26.3.json').read_text())
    guest = ['-XstartOnFirstThread'] + common + ['-Xms256M', '-Xmx1G', '--add-exports', 'java.base/jdk.internal.misc=ALL-UNNAMED',
        '-XX:StackShadowPages=32', '-Dpalcraft.sessions.mode=strict', '-Dpalcraft.session.credential=' + cfg['credential_file'],
        '-Dpalcraft.bridgeDir=' + cfg['guest_bridge_dir'], '-Dpalcraft.frameFile=' + cfg['frame_file'],
        '-Dpalcraft.frameName=Local\\MCPassthroughFrame-' + uuid, '-Dpassthrough.port=' + str(cfg['guest_ws']),
        '-Dpalcraft.server=' + cfg['minecraft_server'], '-Dpalcraft.hidden=true',
        '-Dpalcraft.maxFps=' + str(cfg['performance']['mc_fps']),
        '-Dpalcraft.renderDistance=' + str(cfg['performance']['render_distance']),
        '-Dpalcraft.simulationDistance=' + str(cfg['performance']['simulation_distance']),
        '-Dpalcraft.exchangeDir=' + cfg['exchange_dir'], '-Djava.library.path=' + str(game / 'natives/java'),
        '-Djna.tmpdir=' + str(game / 'natives/jna'), '-Dorg.lwjgl.system.SharedLibraryExtractPath=' + str(game / 'natives/lwjgl'),
        '-Dio.netty.native.workdir=' + str(game / 'natives/netty'), '-Dminecraft.launcher.brand=PalMac',
        '-Dminecraft.launcher.version=1'] + features + profile['arguments']['jvm'] + ['-classpath', ':'.join(str(path) for path in libraries),
        'net.fabricmc.loader.impl.launch.knot.KnotClient', '--username', cfg['guest_mc_name'], '--version', profile['id'],
        '--gameDir', str(game), '--assetsDir', cfg.get('assets_dir', str(root / 'client/assets')), '--assetIndex', '34', '--uuid', uuid,
        '--accessToken', '0', '--clientId', '00000000-0000-0000-0000-000000000000', '--xuid', '', '--versionType', 'release',
        '--width', '1920', '--height', '1080']
    hud = ['--frame-file', cfg['frame_file'], '--fps', str(cfg['performance']['hud_fps']), '--port', '25603',
           '--status-file', str(Path(cfg['guest_bridge_dir']) / 'hud-relay-status.json')]
    template = json.loads(Path(cfg['preserve_launch_template']).read_text()) if cfg.get('preserve_launch_template') else None
    overrides = {}
    if performance_override is not None:
        # Validate both positions before publishing any role file. Original template bytes stay untouched.
        originals = {'guest': guest, 'hud': hud} if template is None else {
            role: template['roles'][role]['arguments'] for role in ('guest', 'hud')}
        overrides = {'guest': with_role_fps(originals['guest'], performance_override['mc_fps'], guest=True),
                     'hud': with_role_fps(originals['hud'], performance_override['hud_fps'])}
    for role, values, cwd, executable, main in [
        ('server', server, cfg['server_game_dir'], str(java), 'FabricServerLauncher'),
        ('guest', guest, cfg['guest_game_dir'], str(java), 'KnotClient'),
        ('hud', hud, cfg['guest_bridge_dir'], 'python3', cfg.get('hud_relay_script', str(root / 'hud/hud_relay.py')))]:
        if template is not None:
            before = template['roles'][role]
            if (Path(before['cwd']).resolve() != Path(cwd).resolve()
                    or before['same_original_uuid'] != uuid or before['frame_file'] != cfg['frame_file']):
                raise ValueError('Existing launch template belongs to another world/player/frame root')
            values, executable, main = before['arguments'], before['executable'], before['main']
        if role == 'hud' and cfg.get('hud_relay_script'):
            main = cfg['hud_relay_script']
        if role in overrides:
            values = overrides[role]
        if any('fabric.dli' in value or 'devlaunchinjector' in value or '.gradle' in value for value in values):
            raise ValueError('Development route refused')
        if role != 'hud':
            (out / (role + '.args')).write_text('\n'.join(json.dumps(value, ensure_ascii=False) for value in values) + '\n')
        metadata = {'schema': 1, 'role': role, 'executable': executable, 'main': main, 'cwd': cwd, 'arguments': values,
            'config': str(Path(config_path).resolve()), 'configured_for_actual_boot': cfg['configured_for_actual_boot'],
            'mod_filename': cfg['mod_filename'], 'mod_sha256': cfg['mod_sha256'], 'same_original_uuid': uuid,
            'frame_file': cfg['frame_file'], 'world_started': False, 'actual_runtime_accepted': False}
        (out / (role + '.json')).write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    environment = {'PALCRAFT_BRIDGE_DIR': cfg['guest_bridge_dir'], 'PALCRAFT_HUD_PORT': '25603',
        'PALCRAFT_FRAME_NAME': 'Local\\MCPassthroughFrame-' + uuid, 'PALCRAFT_TITLEBAR_HEIGHT': '28',
        'PALCRAFT_WINDOW_PID': '<actual standalone Wine Pal process PID set by runtime>'}
    (out / 'hud-overlay-env.json').write_text(json.dumps(environment, indent=2) + '\n')
    return {'prepared_only': True, 'launch_dir': str(out), 'guest_classpath_files': len(libraries),
                      'server_port': 25567, 'guest_ws_port': 25599, 'hud_port': 25603, 'same_framefile_all': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--performance-override', type=Path,
                        help='Explicit JSON containing only mc_fps and hud_fps; changes only their original role arguments')
    args = parser.parse_args()
    override = json.loads(args.performance_override.read_text()) if args.performance_override else None
    print(json.dumps(prepare_launch(args.config, performance_override=override)))


if __name__ == '__main__':
    main()
