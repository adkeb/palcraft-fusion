"""Freeze the complete material source/assets handoff, with exact owner guards."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INC = ROOT / 'material-pipeline/runtime-increment'
OUTPUT = Path('/Users/PLAYER/Documents/Codex/2026-10-06/palcraft-hud-stream/outputs')
SCRIPTS = 'D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
BRIDGE = 'D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
MODEL = 'models-v4-761ddea057ce'
PROXY = ROOT / 'player-install-evidence/next-material-query-auth-dd3b6b861e8b'
BASE = ROOT / 'runtime-package/next9_2/manifest.json'
sha = lambda b: hashlib.sha256(b).hexdigest()
baseline_sha = sha(BASE.read_bytes())
files = {}
targets = {}

def add(logical, path, target=None, kind='material_owned'):
    files[logical] = Path(path).read_bytes()
    if target:
        targets[logical] = dict(target=target, kind=kind)

names = ['material_profiles.lua', 'texture_timeline.lua', 'biome_tint_consumer.lua',
    'widget_surface_materials.lua', 'actual_material_consumers.lua', 'material_runtime_binding.lua',
    'material_scene_driver.lua', 'material_live_wiring.lua']
for name in names:
    add('client/' + name, ROOT / 'palcraft/client' / name, SCRIPTS + name)
add('native/PalCraftMaterial-v1.dll', ROOT / 'material-pipeline/PalCraftMaterial-v1.dll',
    'D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/PalCraftMaterial-v1.dll')
add('source/material_bake_v1.cpp', ROOT / 'material-pipeline/material_bake_v1.cpp')
add('source/material_profiles_v1.hpp', ROOT / 'palcraft/native/material_profiles_v1.hpp')
add('tools/prepare_material_pixels.py', ROOT / 'material-pipeline/prepare_material_pixels.py')
add('tests/test_material_runtime.lua', ROOT / 'material-pipeline/tests/test_material_runtime.lua')
add('tests/test_material_consumers.lua', ROOT / 'material-pipeline/tests/test_material_consumers.lua')
add('validation/pixel-preparation.json', INC / 'pixel-preparation.json')
for path in sorted((INC / 'private-pixels').rglob('*')):
    if path.is_file():
        relative = path.relative_to(INC / 'private-pixels').as_posix()
        add('private-pixels/' + relative, path, BRIDGE + relative, 'private_exact_rgba')
for path in sorted((INC / 'proposals').rglob('*')):
    if path.is_file():
        add('proposals/' + path.relative_to(INC / 'proposals').as_posix(), path)
for path in sorted((INC / 'patches').glob('*.patch')):
    add('owner-patches/' + path.name, path)
patches = json.loads((INC / 'owner-patches.json').read_text())['patches']
for record in patches:
    assert sha(Path(record['base']).read_bytes()) == record['base_sha256']
    assert sha(Path(record['proposal']).read_bytes()) == record['proposal_sha256']

proxy_manifest = json.loads((PROXY / 'manifest.json').read_text())
assert sha((PROXY / 'launcher/session_proxy.py').read_bytes()) == proxy_manifest['candidate_sha256']
assert proxy_manifest['candidate_sha256'] == 'dd3b6b861e8b5bcc89d389f36b7d12a7ad3b5bda0f74ee30fd4d5a542783788a'
add('paired-dependency/launcher/session_proxy.py', PROXY / 'launcher/session_proxy.py',
    'fixed9_2 toolkit/launcher/session_proxy.py', 'installer_owned_next_delta')
add('paired-dependency/proxy-manifest.json', PROXY / 'manifest.json')
add('paired-dependency/session-proxy-material-query.patch', PROXY / 'session-proxy-material-query.patch')
for source, name in [('opaque-cutout-glass-actual.png', 'static-three-sample.png'),
    ('properties.json', 'static-three-properties.json'), ('cleanup.json', 'static-three-cleanup.json')]:
    add('existing-evidence/' + name, ROOT / 'native_renderer/evidence/material-three' / source,
        BRIDGE + 'material-evidence-v1/' + name, 'existing_static_parent_evidence')

config = dict(version=1, enabled=True, pixel_packages={BRIDGE + MODEL + '/': dict(namespace=MODEL,
    index_path='material-pixels-v1/' + MODEL + '/index.json')},
    bake_library='D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/PalCraftMaterial-v1.dll',
    widget_proof=dict(parent_asset='/Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent',
        static_uv0_alpha_clear=True, capture_evidence=BRIDGE + 'material-evidence-v1/static-three-sample.png',
        intermediate_alpha=False, overlap_sorting=False))
files['config/material-runtime-v1.json'] = (json.dumps(config, indent=2) + '\n').encode()
targets['config/material-runtime-v1.json'] = dict(target=BRIDGE + 'material-runtime-v1.json', kind='next_candidate_activation')
validation = dict(status='passed', runtime_fixture_checks=26, previous_consumer_regression_checks=13,
    lua_proposals_syntax='passed', real_client_world_factory_invoked=True,
    existing_command_queue_exercised=True, exact_current_scope_reply_and_same_scene_retry_exercised=True,
    waterlogged_foliage_and_water_roles_separated=True, tint_cache_includes_block_state=True,
    source_read_only_mc_dimension_api='actual26.3 dimension().identifier().toString()',
    proxy_check='one actual SessionProxy/TextSocket loopback using existing synthetic identity',
    actual_game_query_calls=0, engine_calls=0, services_started=0, GUI_calls=0, fixture_rgb_only=True,
    no_old_matrix_repeat=True, no_stress_benchmark=True)
files['validation/material-runtime-checks.json'] = (json.dumps(validation, indent=2) + '\n').encode()
handoff = '''Complete independent next material handoff; current 9.2 remains frozen.

Constructor and actual call path:
1. Install mapped material-owned modules, helper DLL, exact private pixel index/raws,
   material-runtime-v1.json and installer-owned next proxy delta. Select the SAME
   models-v4-761ddea057ce model-assets.json from the fixed9.2 baseline.
2. Apply/rebase only the guarded owner hunks, retaining Native6 capture hooks and
   any actual9.2 repair. The whole proposals are reviewable baselines, not a license
   to overwrite another owner's newer file. Owners return final merged hashes.
3. The actual client_world Worker:tick calls MaterialLiveWiring.attach BEFORE
   chunks capture Models.geometry. It binds bootstrap's current verified MC UUID,
   world_session, dimension and view on every existing worker tick.
4. Models.geometry copies per-block groups and retains authoritative coordinates,
   state and water/block tint role. The companion's original visual pipeline tick
   batches <=32 missing color rows into the SAME Records.commands command.json.
5. Native render's existing authenticated proxy/HostLink world.read round trip
   appends material_tint to the SAME native palcraft-events journal. The companion's
   original read loop dispatches it to pipeline.accept_material_tint.
6. Reply UUID/session/dim/view/request/state/source/index checks precede any cache
   update. A valid reply invokes companion.retry_material_block: existing section
   tile/revision invalidation or the original missing per-block visual spawn.
   It never inserts a synthetic world row, starts a second world reader, nor
   destroys/replaces the existing collider. The rebuilt groups carry actual RGB
   BEFORE merge, so separate biomes do not share one tint material.
7. The selected model root resolves its real namespaced raw RGBA index. The
   existing PalCraftMaterial-v1 helper multiplies RGB while preserving straight
   alpha and caches a PNG. Existing material providers bind that texture.
8. Normal Worker.stop removes the owned material handler/geometry decorator and
   resets requests; view rebind cannot resume a stale scene. No new timer/socket.

Necessary next Java compile (old Java10 JAR/source stays immutable):
MaterialTintFeature base3b316b -> proposal42951867 only permits read-only prepare
before ACK and requires actual client level dimension identifier to match the
trusted/request scope. All thread/identity/session/view/loaded-chunk/budget checks
remain. Visible commit and final ACK remain the existing WorldView transaction.

Acceptance: 26 directed offline runtime/factory/queue/retry checks +13 consumer
checks passed. Private pixels:38 selected tinted model sprites+water_flow,
126 exact RGBA sidecars; no original model package modified, no interpolated
intermediate frames precomputed. Existing three-sample capture proves static
UV0/alpha-clear parent sampling only. Actual tint image/query, intermediate alpha,
overlap sorting, shader vertex color, full animation/performance remain pending.
This handoff starts no game/process/service and claims no current runtime green.
'''
files['HANDOFF.txt'] = handoff.encode()
selection = sha(json.dumps([dict(path=p, sha256=sha(b), bytes=len(b)) for p, b in sorted(files.items())],
    sort_keys=True, separators=(',', ':')).encode())
snapshot = ROOT / 'material-pipeline/snapshots' / ('material-runtime-v1-' + selection[:12])
snapshot.mkdir(parents=True, exist_ok=True)
for logical, data in files.items():
    path = snapshot / logical
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == data, str(path)
    else:
        path.write_bytes(data)

guards = []
for row in patches:
    guard = dict(row)
    guard['proposal'] = str(snapshot / 'proposals' / row['logical'])
    guard['patch'] = str(snapshot / 'owner-patches' / Path(row['patch']).name)
    guards.append(guard)
install = dict(version=1, selection_sha256=selection, logical_windows_root='D:/PalworldServer-LAN',
    files=[dict(path=p, source=str(snapshot / p), sha256=sha(files[p]), bytes=len(files[p]), **t)
        for p, t in sorted(targets.items())],
    guarded_owner_proposals=guards, owner_proposals_require_final_merged_receipt=True,
    model_assets=dict(directory=MODEL, content_hash='761ddea057ce82e14e67278417769acc071d78ca0701e371cfc8e60cc89046d4',
        selected_by=BRIDGE + 'model-assets.json', current_fixed9_2_selection_unchanged=True))
manifest = dict(schema_version=1, candidate='material_runtime_v1', selection_sha256=selection,
    snapshot=str(snapshot), source_ready=True, owner_sources_modified=False, current9_2_modified=False,
    current9_2_manifest_sha256=baseline_sha, unicode_batch_required=False, runtime_deployed=False,
    runtime_accepted=False, actual_tint_green=False, required_owner_merges=[r['logical'] for r in guards if not r['logical'].startswith('mc/')],
    required_next_java_source_sha256='42951867a3701ae4b0350386a03b0066741f4253cec4dc42c1d3105460893052',
    next_java_compiled=False, old_java10_jar_unchanged=True, validation=validation,
    proxy_dependency_manifest_sha256=sha((PROXY / 'manifest.json').read_bytes()),
    proxy_dependency_source_sha256=proxy_manifest['candidate_sha256'],
    files=[dict(path=p, sha256=sha(b), bytes=len(b)) for p, b in sorted(files.items())])
for name, value in [('INSTALL-MAP.json', install), ('MANIFEST.json', manifest)]:
    data = (json.dumps(value, indent=2) + '\n').encode()
    p = snapshot / name
    if p.exists():
        assert p.read_bytes() == data
    else:
        p.write_bytes(data)
assert sha(BASE.read_bytes()) == baseline_sha
OUTPUT.mkdir(parents=True, exist_ok=True)
archive = OUTPUT / 'Actual-Material-Runtime-v1-bundle.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=3) as z:
    for path in sorted(snapshot.rglob('*')):
        if path.is_file():
            z.write(path, 'material-runtime-v1/' + path.relative_to(snapshot).as_posix())
shutil.copy2(snapshot / 'INSTALL-MAP.json', OUTPUT / 'ACTUAL-MATERIAL-RUNTIME-INSTALL-MAP.json')
status = dict(version=1, status='immutable_source_assets_handoff_ready_owner_merge_and_next_java_build_required',
    updated_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), snapshot=str(snapshot),
    manifest=str(snapshot / 'MANIFEST.json'), manifest_sha256=sha((snapshot / 'MANIFEST.json').read_bytes()),
    install_map=str(snapshot / 'INSTALL-MAP.json'), install_map_sha256=sha((snapshot / 'INSTALL-MAP.json').read_bytes()),
    bundle=str(archive), bundle_sha256=sha(archive.read_bytes()), bundle_bytes=archive.stat().st_size,
    selection_sha256=selection, pixel_preparation=json.loads(files['validation/pixel-preparation.json']),
    validation=validation, actual_tint_green=False, runtime_deployed=False, next_java_compiled=False,
    fixed9_2_unchanged=True, required_owner_merges=manifest['required_owner_merges'])
(ROOT / 'coordination/material_runtime_wiring.json').write_text(json.dumps(status, indent=2) + '\n')
(OUTPUT / 'ACTUAL-MATERIAL-RUNTIME-STATUS.json').write_text(json.dumps(status, indent=2) + '\n')
old_path = ROOT / 'coordination/actual_material_consumers.json'
old = json.loads(old_path.read_text())
old['next_material_runtime_handoff'] = dict(snapshot=str(snapshot), manifest_sha256=status['manifest_sha256'],
    install_map_sha256=status['install_map_sha256'], actual_tint_green=False, current_runtime_modified=False)
old_path.write_text(json.dumps(old, indent=2) + '\n')
print(json.dumps(dict(status=status['status'], snapshot=str(snapshot), selection_sha256=selection,
    manifest_sha256=status['manifest_sha256'], install_map_sha256=status['install_map_sha256'],
    source_files=len(files), install_files=len(targets), bundle_bytes=archive.stat().st_size)))
