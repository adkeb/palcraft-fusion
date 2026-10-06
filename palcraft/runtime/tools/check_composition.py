#!/usr/bin/env python3
"""Freeze/check the Overworld source composition. Read-only unless --freeze is requested.

This is a source and packaging assertion, never a claim of native/game acceptance.
"""
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

PALCRAFT = Path(__file__).resolve().parents[2]
FUSION = PALCRAFT.parent
MANIFEST = PALCRAFT / 'runtime/composition.json'
CLIENT = 'PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
SERVER = 'BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'

def selected_source(name):
    overrides = PALCRAFT / 'runtime/pins/overrides.json'
    values = json.loads(overrides.read_text()) if overrides.exists() else {}
    return Path(values.get(name, str(PALCRAFT / name)))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(manifest=None):
    def text_for(relative, role, scope):
        if manifest:
            entry = next(f for f in manifest['files'] if f['role'] == role and f['scope'] == scope)
            return Path(entry['source']).read_text()
        return (PALCRAFT / relative).read_text()
    client = text_for('client/main.lua', 'client_entrypoint', 'client')
    server = text_for('server/bridge-main.lua', 'full_ai_dispatcher', 'server')
    companion = text_for('server/main.lua', 'collision_companion', 'server')
    checks = {
        'client_features_require': "dofile(dir..'features.lua').new" in client,
        'client_features_tick_once': client.count('features:tick(') == 1,
        'client_features_reset_and_status': ('features:reset(' in client or 'features.reset,' in client) and 'features=features:status()' in client,
        'client_personal_identity_config': "runtime-config.json" in client and 'identity=runtime_config.identity' in client,
        'server_full_ai_entry_requires_features': "dofile(dir..'features.lua').new" in server,
        'server_runtime_tick_once': server.count('feature_api():tick(') == 1,
        'server_dispatcher_routes_once': server.count('feature_api():dispatch(') == 1,
        'no_parallel_exchange_tick': 'exchange_api().tick()' not in server,
        'collision_companion_keeps_world_reader': "local World=dofile(dir..'world_compat.lua')" in companion,
        'collision_companion_does_not_spawn_second_entity_worker': "entities.lua" not in companion and 'PalCraftEntityAuthority' not in companion,
        'single_world_observer_hook_available': 'function M.set_world_observer' in companion,
    }
    backup = PALCRAFT / 'runtime/evidence/bridge-main.before.features.lua'
    old = backup.read_text()
    before_methods = set(re.findall(r"method=='([^']+)'", old))
    after_methods = set(re.findall(r"method=='([^']+)'", server))
    runtime = text_for('server/features.lua', 'runtime_features', 'server')
    checks['all_old_ai_operations_preserved'] = all(m in after_methods or m == 'palcraft_exchange' and m in runtime for m in before_methods)
    return checks


def files():
    result = []

    def add(source, target, role, scope):
        source = Path(source)
        try:
            name = source.relative_to(PALCRAFT).as_posix()
            source = selected_source(name)
        except ValueError:
            pass
        if not source.is_file():
            raise FileNotFoundError(source)
        result.append({'source': str(source), 'target': target, 'role': role, 'scope': scope,
                       'sha256': digest(source), 'bytes': source.stat().st_size})

    for side, target in [('client', CLIENT), ('server', SERVER)]:
        add(PALCRAFT / side / 'features.lua', target + 'features.lua', 'runtime_features', side)
        for name in ('compose', 'io', 'session'):
            add(PALCRAFT / 'runtime' / (name + '.lua'), target + 'runtime/' + name + '.lua', 'runtime_lua', side)
        add(PALCRAFT / side / 'entities.lua', target + 'entities.lua', 'entity_worker', side)
        add(PALCRAFT / 'server/world_compat.lua', target + 'world_compat.lua', 'world_reducer', side)
        add(FUSION / 'native_renderer/stable-v3/json.lua', target + 'json.lua', 'json_codec', side)
    add(PALCRAFT / 'client/main.lua', CLIENT + 'main.lua', 'client_entrypoint', 'client')
    add(PALCRAFT / 'client/form.lua', CLIENT + 'form.lua', 'client_form', 'client')
    add(PALCRAFT / 'server/main.lua', CLIENT + 'palcraft-collisions.lua', 'collision_companion', 'client')
    add(FUSION / 'native_renderer/stable-v3/models.lua', CLIENT + 'models.lua', 'model_renderer_stable_v3', 'client')
    add(PALCRAFT / 'client/model_geometry_v2.lua', CLIENT + 'model_geometry_v2.lua', 'model_geometry_v2', 'client')
    add(PALCRAFT / 'native/PalCraftModel-v3.dll', 'PalCraft-Client/Pal/Binaries/Win64/PalCraftModel-v3.dll', 'model_dll_stable_v3', 'client')
    add(PALCRAFT / 'native/PalCraftMesh-v6.dll', 'PalCraft-Client/Pal/Binaries/Win64/PalCraftMesh-v6.dll', 'collision_dll_v6', 'client')
    add(FUSION / 'input-performance/PalCraftRender-v15.dll', 'PalCraft-Client/Pal/Binaries/Win64/PalCraftRender-v15.dll', 'camera_input_dll_v15', 'client')
    add(PALCRAFT / 'server/bridge-main.lua', SERVER + 'main.lua', 'full_ai_dispatcher', 'server')
    add(PALCRAFT / 'server/main.lua', SERVER + 'palcraft-server.lua', 'collision_companion', 'server')
    add(PALCRAFT / 'server/entity_protocol.lua', SERVER + 'entity_protocol.lua', 'entity_protocol', 'server')
    add(PALCRAFT / 'server/session-auth.lua', SERVER + 'session-auth.lua', 'authority_presence', 'server')
    add(PALCRAFT / 'native/PalCraftMesh-v6.dll', 'BridgeLab/Pal/Binaries/Win64/PalCraftMesh-v6.dll', 'collision_dll_v6', 'server')
    return result


def gaps():
    rules = [
        ('model_geometry_v3', '../native_renderer/stable-v3/models.lua', "local Geometry=dofile(dir..'model_geometry_v2.lua')", 'the selected stable-v3 renderer loads geometry v2; the newer configurable renderer is a separate pending native candidate'),
        ('fluid_geometry_v2', 'client/fluid_geometry_v2.lua', 'function M.geometry', 'no verified translucent native fluid surface renderer in the first profile'),
        ('chunks', 'runtime/chunks.lua', 'function M.new', 'compound collision has offline tests; native engine acceptance and exclusive consumer switch are pending'),
        ('travel', 'server/features.lua', "C:register('travel'", 'first profile disables travel; view verifier and complete mailbox transport must be present before enabling'),
        ('exchange', 'server/features.lua', "C:register('exchange'", 'first profile disables exchange; persistent escrow and supervised durable save witness are pending'),
        ('fluid_physics', 'server/features.lua', "C:register('fluid_physics'", 'first profile disables native fluid bodies and movement until engine acceptance'),
    ]
    result = []
    for feature, relative, needle, reason in rules:
        path = (PALCRAFT / relative).resolve()
        line = next((i for i, value in enumerate(path.read_text().splitlines(), 1) if needle in value), None)
        result.append({'feature': feature, 'file': str(path), 'line': line, 'enabled': False, 'reason': reason})
    return result


def freeze():
    checks = audit()
    if not all(checks.values()):
        raise RuntimeError('Source hooks are not ready: ' + str(checks))
    entries = files()
    tests = json.loads((PALCRAFT / 'runtime/evidence/offline-tests.json').read_text())
    assert tests['passed'] and tests['game_engine_validated'] is False
    for name, expected in tests['source_sha256'].items():
        assert digest(selected_source(name)) == expected, 'Tested source changed: ' + name
    source_id = hashlib.sha256(json.dumps([(f['scope'], f['target'], f['sha256']) for f in entries], separators=(',', ':')).encode()).hexdigest()
    snapshot = PALCRAFT / 'runtime/frozen' / ('lab-overworld-v1-' + source_id[:12])
    for entry in entries:
        original = Path(entry['source'])
        target = snapshot / entry['target']
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.is_file() or digest(target) != entry['sha256']:
            shutil.copy2(original, target)
        assert digest(target) == entry['sha256'], 'Source changed while freezing: ' + str(original)
        entry['source_original'] = str(original)
        entry['source'] = str(target)
    manifest = {
        'schema_version': 1, 'profile': 'lab-overworld-v1', 'source_id': source_id,
        'frozen_utc': datetime.now(timezone.utc).isoformat(), 'source_ready': True, 'deployed': False,
        'runtime_accepted': False, 'requires_lead_deployment_lease': True, 'operating_mode': 'night_low_power',
        'flags': {'strict_sessions': True, 'entities_enabled': True, 'world_overworld': True, 'travel_enabled': False,
                  'exchange_enabled': False, 'chunk_enabled': False, 'fluid_physics_enabled': False},
        'jvm_properties': {'palcraft.sessions.mode': 'strict', 'palcraft.sessions.authority': 'D:/PalworldServer-LAN/BridgeLab/rpc/session-auth/authority-public.json',
                           'palcraft.travel.enabled': 'false', 'palcraft.exchange.enabled': 'false'},
        'files': entries, 'immutable_payload_root': str(snapshot), 'source_assertions': checks, 'offline_evidence': tests,
        'generated_configuration': {'target': 'PalCraft-Dev/bridge/runtime-config.json', 'source': 'personal installer profile.connection.identity',
                                    'example_only': str(PALCRAFT / 'runtime/config-lab-overworld.json'), 'contains_private_credential': False},
        'required_directories': ['BridgeLab/rpc/session-auth', 'PalCraft-Dev/bridge/entities', 'BridgeLab/rpc/travel'],
        'preserved_ai_dependencies': ['readers.lua', 'discovery.lua', 'targets.lua', 'storage-runtime-fast.lua', 'storage-readers-fast.lua',
                                      'organize.lua', 'merge.lua', 'offline-build-main.lua', 'read-actual-geometry-main.lua', 'read-materials-main.lua'],
        'external_dependencies': {'java': 'integration_build frozen unified jar, strict SessionEnrollment preserving existing MC UUID/inventory',
                                  'proxy': 'player_install launcher/session_proxy.py + multiplayer/session_client.py, one listener',
                                  'hud': 'hud_stream final relay/overlay candidate, 10 FPS',
                                  'model_assets': 'frozen v2 7342e9820b46, private MC resource extraction; geometry v3 not selected',
                                  'exchange_witness': 'disabled dependency; never start a save watcher as a side effect of this checker'},
        'load_order': ['full PalLiveBridge dispatcher', 'server features: presence -> sessions -> existing world observer -> entity authority',
                       'server-owned actual UID enrollment and strict MC guest login', 'single local HMAC proxy and personal frame mapping',
                       'client main/form -> collision companion + stable models/v2 reducer -> features host/world/entity observer',
                       'authenticated snapshot mirror -> exact 1/2370 HP observer and Java HUD vitals'],
        'startup_steps': ['Lead deploys the verified backend/client payload together; production stays OFF; no automatic service changes.',
                          'Full server dispatcher must be loaded in the approved Lab window; wait for fresh pal-presence and verify exact Pal UID.',
                          'Enroll/import PalCraft with MC UUID 11111111-1111-1111-1111-111111111111 against the current Pal boot; never guess the first controller.',
                          'Start or reconnect the one registered guest using its personal directory, credential, WS port and frame mapping.',
                          'Launch the single local proxy, SSH25598, HUD10FPS and the owned client at 15FPS; refresh lab-identity and runtime-config.',
                          'palcraft_start loads collision companion; query palcraft_features_status and client-status.features for binding/worker evidence.',
                          'Verify HP against the Pal authority, a non-solid button, and HUD in one low-FPS acceptance window; no item grants.'],
        'known_gaps': gaps(), 'claims': {'fps_measured_by_this_workstream': False, 'actual_combat_verified': False, 'full_migration_complete': False},
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    return manifest


def check():
    m = json.loads(MANIFEST.read_text())
    changed = [{'target': f['target'], 'source': f['source']} for f in m['files'] if not Path(f['source']).is_file() or digest(Path(f['source'])) != f['sha256']]
    checks = audit(m)
    head_drift = [f['source_original'] for f in m['files'] if digest(Path(f['source_original'])) != f['sha256']]
    return {'schema_version': 1, 'source_id': m['source_id'], 'passed': not changed and all(checks.values()),
            'changed_sources': changed, 'working_source_head_changed': head_drift, 'assertions': checks,
            'runtime_accepted': False, 'deployed_by_checker': False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--freeze', action='store_true')
    args = p.parse_args()
    if args.freeze:
        m = freeze()
        print(json.dumps({'source_ready': m['source_ready'], 'source_id': m['source_id'], 'files': len(m['files']), 'manifest': str(MANIFEST)}))
    else:
        result = check()
        print(json.dumps(result))
        if not result['passed']:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
