"""Package a verified source increment, its owner handoffs and build evidence."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--snapshot', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
integration = root / 'integration-build'
snapshot, output = args.snapshot.resolve(), args.output.resolve()
assert not (output / 'SHA256SUMS.txt').exists(), 'Refuse to alter a finished delivery'
output.mkdir(parents=True, exist_ok=True)
checks = json.loads((snapshot / 'artifact-checks.json').read_text())
build = json.loads((snapshot / 'build-result.json').read_text(encoding='utf-8-sig'))
ready = json.loads((root / 'entity-visuals/READY-capture-hook-v2.json').read_text())
capture = Path(ready['directory'])
material = json.loads((root / 'coordination/actual_material_consumers.json').read_text())
composition = json.loads((integration / 'staging/material-capture-10/composition.json').read_text())
assert build['exit_code'] == 0 and checks['jar_and_exact_source_hashes'] == 'PASS'

for name in ['source.zip', 'source-manifest.json', 'build-result.json', 'gradle-build.log', 'artifact-checks.json', build['artifacts'][0]['name']]:
    shutil.copy2(snapshot / name, output / name)
for name in ['Build-Isolated.ps1', 'snapshot.py', 'verify_artifact.py', 'verify_composition.py', 'package_composition.py']:
    shutil.copy2(integration / name, output / name)
shutil.copy2(root / 'palcraft/LICENSE-upstream.txt', output / 'LICENSE-upstream.txt')
composition.update(built=True, artifact_verified=True, runtime_verified=False)
(output / 'composition.json').write_text(json.dumps(composition, ensure_ascii=False, indent=2) + '\n')
shutil.copytree(capture, output / 'capture-hook-v2', dirs_exist_ok=True)
shutil.copy2(root / 'entity-visuals/READY-capture-hook-v2.json', output / 'capture-hook-v2/READY-capture-hook-v2.json')
proof = root / 'entity-visuals/verification-capture.json'
if proof.exists():
    shutil.copy2(proof, output / 'capture-hook-v2/owner-narrow-capture-proof.json')
materials = output / 'material-consumers'
materials.mkdir(exist_ok=True)
for row in material['files']:
    if row['path'].startswith('palcraft/client/'):
        source = Path(row['absolute'])
        assert hashlib.sha256(source.read_bytes()).hexdigest() == row['sha256']
        shutil.copy2(source, materials / source.name)
shutil.copy2(root / 'coordination/actual_material_consumers.json', materials / 'actual_material_consumers.json')
shutil.copy2(integration / 'inputs/material-tint-34e1e99979ab/selected-inputs.json', materials / 'selected-java-inputs.json')
evidence = output / 'directed-checks-coherent9'
evidence.mkdir(exist_ok=True)
for name in ['source-manifest.json', 'gradle-build.log', 'targeted-checks.json']:
    shutil.copy2(integration / 'snapshots/coherent-9-f74fed4a87ce' / name, evidence / name)
base_delivery = output.parent / 'PalCraft-Coherent-Candidate-0.2.0-integration.9.2'
shutil.copy2(base_delivery / 'Bind-Existing-Shared-World.init.gradle', output / 'Bind-Existing-Shared-World.init.gradle')

remote = build['source_root']
handoff = {
    'schema': 1, 'candidate': build['artifacts'][0]['name'], 'snapshot': build['snapshot'],
    'role': 'independent material and actual entity renderer capture source increment after frozen 9.2',
    'source_revision': checks['source_hash'], 'jar': build['artifacts'][0],
    'matching_dli_paths': {key: remote + suffix for key, suffix in {
        'source_root': '', 'main_classes': '/build/classes/java/main', 'client_classes': '/build/classes/java/client',
        'main_resources': '/build/resources/main', 'client_resources': '/build/resources/client'}.items()},
    'compiled': True, 'runtime_accepted': False, 'integration_deployed': False, 'frozen9_2_modified': False,
    'power': {'environment': 'night_low_power', 'build_priority': 'BelowNormal/Gradle low', 'workers': 1, 'heap': '1G'},
    'base_candidate': '0.2.0-integration.9.2', 'changed_files': composition['changed_files_relative_to_frozen9_2'],
    'material': {'source_sha256': '3b316b09e4499f836d70a5d035f179ea9ff51bc8e8bf5982a6f509f983da3cfe',
        'route': 'material_tint_query -> world.read -> client thread -> trusted current view -> same host lease response',
        'live_color_verified': False, 'consumer_manifest': 'material-consumers/actual_material_consumers.json'},
    'capture': {'owner_content_sha256': ready['source_content_sha256'], 'render_and_resource_reload_hook_compiled': True,
        'derived_events': ['entity_visual_asset', 'entity_visual_cache', 'entity_visual_cache_chunk'],
        'native_vertex_bytes': 72, 'composition_document': 'capture-hook-v2/HANDOFF-capture-hook-v2.md',
        'requires': ['existing current view and authenticated host-session verifier', 'exact native entity Actor verifier',
            'models version 6 and captured_native_consumer using read_visual/verify_visual',
            '72-byte RGBA native vertex format and actually supported material callbacks',
            'same existing event dispatcher, tick and lifecycle composition'],
        'bound_host_only': True, 'runtime_graphics_verified': False},
    'verification': {'new_classes': 'PASS', 'registered_mixins': checks['mixins'],
        'actual_new_target_descriptors': 'PASS; runtime Mixin application pending',
        'directed_checks': 'reused exact SHA inputs from coherent9: rebase19, scope12, V3 import/export2',
        'old_matrices_repeated': False},
    'runtime_operator': 'runtime_integration is sole deployment/service/RPC operator; this candidate does not authorize replacing the accepted runtime batch',
    'excluded': ['new portable drops/projectiles field adapters', 'UE4SS Unicode full rebuild', 'native DLL replacement or automatic feature enablement'],
    'pending': ['cold-load matching classes/resources/JAR', 'wire capture and material consumers in existing runtime composition',
        'one scoped read-only tint query and controlled <=3 rendering samples under runtime window', 'actual material and entity visual acceptance']}
(output / 'component-startup-handoff.json').write_text(json.dumps(handoff, ensure_ascii=False, indent=2) + '\n')
(output / 'README.md').write_text('''# PalCraft 0.2.0-integration.10 独立候选

本包以冻结 `.9.2` 为基础，仅组合只读材质查询与实体 renderer capture v2，共 11 个文件变化。现有 `.9.2`、服务、客户端、存档和性能设置未改动。

Java 25.0.1 / MC 26.3 / Gradle 9.7.1 的一次离线 assemble 已通过，使用 BelowNormal、单 worker、1GB heap。JAR、源码 ZIP、字节码、165 个类及 41 个 Mixin 注册已核验。render 与 resource reload 两个新增目标的完整签名均对实际 MC JAR 核对；这不代替实际 Mixin 加载验证。

材质查询使用当前已加载区块、可信玩家与 world tuple；水色来自实际 BiomeColors。实体捕获使用现有 render thread、认证 HostLink、实际 renderer/model 输出，资源重载清理缓存。PNG 和 manifest 使用 48KiB 原始块、8MiB 预算和 SHA256；无游戏纹理或游戏 JAR 随包分发。

rebase19、scope12、V3 import/export2 复用 coherent9 的实际通过日志，相关生产代码、测试和配置 SHA 完全一致；没有重跑旧矩阵。模型 owner 的小型 direct/chunk cache fixture 与 Creeper/Dragon CPU proof 记录随包附上，没有扩展成图形验收。

运行与视觉验收仍未完成。capture 的 Lua 事件、tick、生命周期及 native 72-byte RGBA consumer 依赖见 `capture-hook-v2/HANDOFF-capture-hook-v2.md`；材质 consumer 见对应 manifest。不要混合旧 DLI classes/resources；同一 snapshot 的真实 Windows 路径列在 `component-startup-handoff.json`。runtime_integration 统一控制后续加载、RPC、临时样本与清理。本包没有启用 travel、exchange、scoped camera 或任何新 runtime 功能。

新 portable drops/projectiles 字段适配及 UE4SS Unicode 完整重编译不在这次 Java 增量范围。
''')
files = sorted(path for path in output.rglob('*') if path.is_file())
(output / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.relative_to(output).as_posix() + '\n' for path in files))
archive = output.parent / (output.name + '.zip')
assert not archive.exists(), 'Refuse to replace finished archive'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as zipped:
    for path in sorted(output.rglob('*')):
        if path.is_file():
            zipped.write(path, path.relative_to(output.parent))
record = {'candidate': str(output), 'archive': str(archive), 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'jar_sha256': checks['jar_sha256'], 'source_revision': checks['source_hash'], 'build_running': False, 'runtime_accepted': False}
(integration / 'material-capture10-handoff.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(record, ensure_ascii=False))
