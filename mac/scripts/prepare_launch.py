"""Prepare local native-Mac MC/HUD arguments only; never starts a service."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', type=Path, required=True)
args = parser.parse_args()
cfg = json.loads(args.config.read_text())
root = Path(cfg['software_root'])
plan = json.loads((root / 'setup/mac-dependency-plan.json').read_text())
uuid = cfg['guest_mc_uuid']
if uuid != '11111111-1111-1111-1111-111111111111' or cfg['guest_mc_name'] != 'PalCraft':
    raise ValueError('This migration preserves the existing enrolled identity')
out = root / 'launch'
out.mkdir(exist_ok=True)
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
for role, values, cwd, executable, main in [
    ('server', server, cfg['server_game_dir'], str(java), 'FabricServerLauncher'),
    ('guest', guest, cfg['guest_game_dir'], str(java), 'KnotClient'),
    ('hud', hud, cfg['guest_bridge_dir'], 'python3', str(root / 'hud/hud_relay.py'))]:
    if any('fabric.dli' in value or 'devlaunchinjector' in value or '.gradle' in value for value in values):
        raise ValueError('Development route refused')
    if role != 'hud':
        (out / (role + '.args')).write_text('\n'.join(json.dumps(value, ensure_ascii=False) for value in values) + '\n')
    metadata = {'schema': 1, 'role': role, 'executable': executable, 'main': main, 'cwd': cwd, 'arguments': values,
        'config': str(args.config.resolve()), 'configured_for_actual_boot': cfg['configured_for_actual_boot'],
        'mod_filename': cfg['mod_filename'], 'mod_sha256': cfg['mod_sha256'], 'same_original_uuid': uuid,
        'frame_file': cfg['frame_file'], 'world_started': False, 'actual_runtime_accepted': False}
    (out / (role + '.json')).write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
environment = {'PALCRAFT_BRIDGE_DIR': cfg['guest_bridge_dir'], 'PALCRAFT_HUD_PORT': '25603',
    'PALCRAFT_FRAME_NAME': 'Local\\MCPassthroughFrame-' + uuid, 'PALCRAFT_TITLEBAR_HEIGHT': '28',
    'PALCRAFT_WINDOW_PID': '<actual standalone Wine Pal process PID set by runtime>'}
(out / 'hud-overlay-env.json').write_text(json.dumps(environment, indent=2) + '\n')
print(json.dumps({'prepared_only': True, 'launch_dir': str(out), 'guest_classpath_files': len(libraries),
                  'server_port': 25567, 'guest_ws_port': 25599, 'hud_port': 25603, 'same_framefile_all': True}))
