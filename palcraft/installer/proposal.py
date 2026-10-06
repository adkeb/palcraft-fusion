"""Build the complete portable client from the sealed baseline and reviewed owner overlays."""
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

from installer.core import BIN, DEV, TOOLS, atomic_json, digest, fail, target_allowed
from installer.packaging import build_distribution


def proposal(root, baseline_manifest, baseline_zip, owner_map, output, version):
    root, output = Path(root).absolute(), Path(output).absolute()
    if root.exists() or output.exists():
        fail('OUTPUT_EXISTS', '组合目录或输出已存在，请使用新的 proposal 版本目录。')
    baseline = json.loads(Path(baseline_manifest).read_text())
    overlay = json.loads(Path(owner_map).read_text())
    if overlay.get('complete_client_source_ready') is not True:
        fail('PROPOSAL_INCOMPLETE', '完整客户端路径组合清单尚未就绪。')
    if overlay.get('baseline_zip_sha256') and digest(baseline_zip) != overlay['baseline_zip_sha256']:
        fail('PROPOSAL_BASE_HASH', '完整冻结基线 ZIP 的摘要不符。')
    changes = {f['target']: f for f in overlay['files']}
    root.mkdir(parents=True)
    payload = root / 'payload'
    sources = {}
    with zipfile.ZipFile(baseline_zip) as archive:
        names = archive.namelist()
        index = {}
        for member in names:
            if '/payload/' in member:
                key = 'payload/' + member.split('/payload/', 1)[1]
                index.setdefault(key, []).append(member)
        for entry in baseline['files']:
            target = entry['target']
            if not target_allowed(target) or target.startswith(TOOLS + '/') or target in changes:
                continue
            if Path(target).name.startswith('PalCraftRender-'):
                continue
            members = index.get(entry['staged_path'], [])
            if len(members) != 1:
                fail('PROPOSAL_MEMBER', '冻结包成员不唯一或缺失：' + target)
            data = archive.read(members[0])
            if hashlib.sha256(data).hexdigest() != entry['sha256']:
                fail('PROPOSAL_BASE_HASH', '冻结客户端成员摘要不符：' + target)
            path = payload / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            sources[target] = {'source': str(path), 'target': target, 'expected_sha256': entry['sha256'],
                               'role': entry.get('role', 'dependency'), 'executable': entry.get('executable', False)}
    for target, entry in changes.items():
        if not target_allowed(target):
            fail('PROPOSAL_PATH', '客户端组合包含非个人客户端目标：' + target)
        source = Path(entry['source'])
        expected = entry.get('expected_sha256', entry.get('sha256'))
        if not source.is_file() or source.is_symlink() or digest(source) != expected:
            fail('PROPOSAL_SOURCE', '组件源缺失或已改变：' + str(source))
        path = payload / target
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, path)
        sources[target] = {'source': str(path), 'target': target, 'expected_sha256': expected,
                           'role': entry.get('role', 'dependency'), 'executable': entry.get('executable', False)}
    aliases = {'main.lua': 'client_main', 'json.lua': 'json_lua', 'palcraft-collisions.lua': 'collisions_lua',
               'models_v6.lua': 'models_lua', 'UE4SS-settings.ini': 'ue4ss_settings', 'dwmapi.dll': 'proxy_dll'}
    for target, entry in sources.items():
        basename = Path(target).name
        if basename in aliases:
            entry['role'] = aliases[basename]
        if basename == 'UE4SS.dll':
            entry['role'] = 'ue4ss'
        elif basename == 'PalCraftUE4SSUtf8.dll':
            entry['role'] = 'ue4ss_utf8_shim'
        elif basename.startswith('PalCraftRender-') and basename.endswith('.dll'):
            entry['role'] = 'native_render'
        elif basename.startswith('PalCraftModel-') and basename.endswith('.dll'):
            entry['role'] = 'native_model'
        elif basename.startswith('PalCraftMesh-') and basename.endswith('.dll'):
            entry['role'] = 'native_mesh'
        elif basename == 'PalCraftClientHost-v1.exe':
            entry['role'] = 'client_host'
        elif target.endswith('/runtime/paths.lua'):
            entry['role'] = 'runtime_paths'
    requirements = dict(overlay['requirements'])
    spec = {'schema': 1, 'version': version, 'platform': 'both',
            'source_revision': overlay['source_revision'], 'requirements': requirements,
            'classification': 'internal-portable-complete-client-proposal',
            'public_distribution_review_complete': False,
            'licenses': overlay['licenses'], 'files': list(sources.values())}
    spec_path = root / 'player-payload-spec.json'
    atomic_json(spec_path, spec)
    result = build_distribution(spec_path, output)
    atomic_json(root / 'proposal-manifest.json', {'schema': 1, 'version': version,
                'spec': str(spec_path), 'files': len(sources), 'baseline_manifest_sha256': digest(baseline_manifest),
                'overlay_sha256': digest(owner_map), 'release_sha256': result['sha256'],
                'distribution_sha256': result['distribution_sha256'], 'single_install_entry': 'launcher/install_player.py',
                'source_ready': True, 'actual_Core_Game_or_Fabric_accepted': False,
                'same_identity_launch_plan': 'installer.setup.launch_plan', 'runtime_operations': []})
    return result
