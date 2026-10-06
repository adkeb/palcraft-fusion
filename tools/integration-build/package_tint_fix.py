"""Package the exact frozen10 tint qualification repair and verified Java outputs."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--snapshot', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
integration = root / 'integration-build'
snapshot, output = a.snapshot.resolve(), a.output.resolve()
assert not output.exists(), 'Refuse to alter a delivery'
checks = json.loads((snapshot / 'artifact-checks.json').read_text())
build = json.loads((snapshot / 'build-result.json').read_text(encoding='utf-8-sig'))
composition = json.loads((integration / 'staging/tint-prepare-10-1/composition.json').read_text())
assert build['exit_code'] == 0 and checks['jar_and_exact_source_hashes'] == 'PASS'
output.mkdir(parents=True)
for name in ['source.zip', 'source-manifest.json', 'build-result.json', 'gradle-build.log', 'artifact-checks.json', build['artifacts'][0]['name']]:
    shutil.copy2(snapshot / name, output / name)
for name in ['Build-Isolated.ps1', 'snapshot.py', 'verify_artifact.py', 'verify_composition.py', 'package_tint_fix.py', 'Generate-DLI-Metadata.init.gradle']:
    shutil.copy2(integration / name, output / name)
shutil.copy2(root / 'palcraft/LICENSE-upstream.txt', output / 'LICENSE-upstream.txt')
shutil.copytree(integration / 'inputs/tint-prepare-42951867a370', output / 'tint-qualification-input')
evidence = output / 'directed-checks-coherent9'
evidence.mkdir()
for name in ['source-manifest.json', 'gradle-build.log', 'targeted-checks.json']:
    shutil.copy2(integration / 'snapshots/coherent-9-f74fed4a87ce' / name, evidence / name)
material = root / 'material-pipeline/snapshots/material-runtime-v1-e8785b9db7ee/MANIFEST.json'
assert hashlib.sha256(material.read_bytes()).hexdigest() == '017db58d4fbd3dd04a471af14d0270dae188f7d8357ddab03060ea00bdc63b1c'
shutil.copy2(material, output / 'owner-material-runtime-MANIFEST.json')
shutil.copy2(root / 'entity-visuals/READY-capture-hook-v2.json', output / 'owner-READY-capture-hook-v2.json')
capture = json.loads((root / 'entity-visuals/READY-capture-hook-v2.json').read_text())
shutil.copy2(Path(capture['directory']) / 'HANDOFF-capture-hook-v2.md', output / 'HANDOFF-capture-hook-v2.md')
composition.update(built=True, artifact_verified=True, runtime_verified=False)
(output / 'composition.json').write_text(json.dumps(composition, ensure_ascii=False, indent=2) + '\n')
remote = build['source_root']
handoff = {'schema': 1, 'candidate': checks['mod_version'], 'snapshot': build['snapshot'], 'source_revision': checks['source_hash'],
    'jar': build['artifacts'][0], 'base_candidate': '0.2.0-integration.10', 'compiled': True, 'integration_deployed': False,
    'runtime_accepted': False, 'frozen10_modified': False, 'frozen9_2_modified': False,
    'matching_dli_paths': {key: remote + suffix for key, suffix in {'source_root': '', 'main_classes': '/build/classes/java/main',
        'client_classes': '/build/classes/java/client', 'main_resources': '/build/resources/main', 'client_resources': '/build/resources/client'}.items()},
    'material_qualification_fix': {'source_sha256': composition['material_source_sha256'], 'waiting_ack_readonly_prepare_allowed': True,
        'actual_level_dimension_id_required': True, 'visible_commit_gate_changed': False, 'auth_scope_and_loaded_chunk_required': True},
    'capture_java_unchanged_from_frozen10': True, 'capture_waiting_gate_retained': True,
    'entity_visual_view_interface': 'actual HostLink execute/bind/respond with existing lease; SessionPolicy world.read in frozen10 and this exact candidate',
    'owner_material_runtime_manifest': str(material), 'owner_material_runtime_manifest_sha256': '017db58d4fbd3dd04a471af14d0270dae188f7d8357ddab03060ea00bdc63b1c',
    'paired_next_proxy': {
        'source': str(root / 'player-install-evidence/next-capture-material-auth-36c5b1ff8415/launcher/session_proxy.py'),
        'sha256': '36c5b1ff841501c813beea6de35877cc01e49fd0116724eacbab83ac50c5dcbd',
        'outbound_ops': ['material_tint_query', 'entity_visual_view'],
        'incoming_capture_events': ['entity_visual_asset', 'entity_visual_cache', 'entity_visual_cache_chunk'],
        'original_host_envelope_preserved': True, 'new_socket': False,
        'combination_receipt_updates_dependency_without_mutating_owner_manifest': True},
    'requires': ['native6/models6 72-byte RGBA consumer and existing authenticated event/tick/lifecycle composition',
        'proxy paired whitelist includes material_tint_query and entity_visual_view', 'package/runtime merge owner-frozen Lua/native/material files',
        'DLI uses matching classes/resources; distribution JAR stays outside original empty shared/guest mods folders'],
    'runtime_operator': 'runtime_integration only; no automatic service restart or deployment',
    'validation': {'class_major': 69, 'mixins': checks['mixins'], 'exact_source_and_jar_hashes': 'PASS',
        'directed_tests': checks['directed_tests'], 'old_matrices_repeated': False, 'actual_game_tint_query': False,
        'actual_native_visual_acceptance': False, 'standard_player_Java_Fabric_normal_directory_acceptance': False}}
(output / 'component-startup-handoff.json').write_text(json.dumps(handoff, ensure_ascii=False, indent=2) + '\n')
if (snapshot / 'launch-metadata').is_dir():
    shutil.copytree(snapshot / 'launch-metadata', output / 'launch-metadata')
(output / 'README.md').write_text('''# PalCraft 0.2.0-integration.10.1 取色准备修复

以不可变 `.10` 为基线，仅修改 MaterialTintFeature 和版本号。真实修复允许已认证、当前 tuple 与实际 MC 维度匹配、区块已加载的只读取色在 waiting ACK 阶段执行，解除 hidden material readiness 与 ACK 的循环。实际维度使用 `dimension().identifier().toString()`。客户端线程、UUID/session/dim/view、预算、可见提交及实体 capture waiting gate 均保留。旧 `.10` 的 a645 JAR 不含此修复；`.9.2` 运行与所有旧冻结包未修改。

一次 Java25/MC26.3/Gradle9.7.1 assemble 使用 BelowNormal、单 worker、1GB、离线模式通过。产物/源码哈希、class major69、165类与41Mixin注册及实际目标签名已核验；HostLink entity_visual_view 和 SessionPolicy world.read 已在真实 frozen10源码及本候选确认。旧 rebase19/scope12/V3 import-export2 仅在生产代码、测试和输入SHA相同时复用，无重跑旧矩阵。

JAR、精确源码、日志、owner最小补丁、成套材质manifest及当前capture Java合同随包提供。Lua/native6接线与RGBA资源由package依据owner最终来源组合，运行、真实MC取色和可见材质/实体验收仍待runtime。没有自动部署、服务重启、GUI/RPC或压力测试。DLI只使用同snapshot的classes/resources，分发JAR保存至独立artifact，两个原空mods目录保持为空。具体Windows路径与组件依赖见component-startup-handoff.json。

后续成对代理使用已冻结36c5b1...，同时放行material_tint_query/entity_visual_view与三个原HOST封装的capture事件；组合协调记录更新此依赖，owner旧manifest保持不可变。Lab DLI配置便于受控加载，标准玩家Java/Fabric/正常游戏目录的安装验收仍未完成。
''')
files = sorted(path for path in output.rglob('*') if path.is_file())
(output / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.relative_to(output).as_posix() + '\n' for path in files))
archive = output.parent / (output.name + '.zip')
assert not archive.exists()
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as zipped:
    for path in sorted(output.rglob('*')):
        if path.is_file(): zipped.write(path, path.relative_to(output.parent))
record = {'candidate': str(output), 'archive': str(archive), 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'jar_sha256': checks['jar_sha256'], 'jar_bytes': checks['jar_bytes'], 'source_revision': checks['source_hash'],
    'build_running': False, 'runtime_accepted': False}
(integration / 'tint-prepare10_1-handoff.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(record, ensure_ascii=False))
