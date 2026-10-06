"""Release assembly from an explicit approved file list, never a whole workspace."""
import json
import os
import shutil
import tempfile
import zipfile
from pathlib import Path

from installer.core import Bundle, TOOLS, digest, fail, target_allowed


def build_release(spec_path, output, include_tools=True):
    spec_path = Path(spec_path).resolve()
    spec = json.loads(spec_path.read_text(encoding='utf-8'))
    output = Path(output).absolute()
    if output.exists():
        fail('OUTPUT_EXISTS', '输出文件已存在，不能覆盖：' + str(output), '使用带新版本号的输出文件名。')
    files = []
    sources = {}
    for item in spec.get('files', []):
        target = item.get('target', '')
        if not target_allowed(target):
            fail('PACKAGE_PATH', '发行清单不接受此路径：' + target)
        path = Path(item['source'])
        if not path.is_absolute():
            path = spec_path.parent / path
        if path.is_symlink() or not path.is_file():
            fail('PACKAGE_SOURCE', '源文件不存在或是链接：' + str(path))
        path = path.resolve()
        if item.get('expected_sha256') and digest(path) != item['expected_sha256']:
            fail('PACKAGE_SOURCE_CHANGED', '审批后文件已改变：' + str(path))
        sources[target] = path
        files.append({'target': target, 'bytes': path.stat().st_size, 'sha256': digest(path),
                      'role': item.get('role', 'dependency'), 'executable': item.get('executable', False)})
    if include_tools:
        base = Path(__file__).resolve().parents[1]
        for folder in ('installer', 'launcher'):
            for path in sorted((base / folder).rglob('*')):
                if not path.is_file() or path.is_symlink() or 'tests' in path.parts or '__pycache__' in path.parts:
                    continue
                if path.suffix not in ('.py', '.cpp', '.hpp', '.command', '.cmd', '.txt') and not path.name.endswith('.example.json'):
                    continue
                relative = path.relative_to(base).as_posix()
                target = TOOLS + '/' + relative
                if target in sources:
                    fail('PACKAGE_DUPLICATE', '工具目录不能由 payload 清单覆盖：' + target)
                sources[target] = path
                files.append({'target': target, 'bytes': path.stat().st_size, 'sha256': digest(path),
                              'role': 'player_tool', 'executable': path.suffix == '.command'})
    manifest = {'schema': 1, 'kind': 'palcraft-player-release', 'version': spec['version'],
                'platform': spec['platform'], 'source_revision': spec['source_revision'],
                'requirements': spec['requirements'], 'licenses': spec['licenses'],
                'files': sorted(files, key=lambda x: x['target'])}
    for key in ('classification', 'public_distribution_review_complete', 'runtime_composition_source_id', 'java_source_revision'):
        if key in spec:
            manifest[key] = spec[key]
    if len(sources) != len(files):
        fail('PACKAGE_DUPLICATE', '发行清单包含重复目的路径。')
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, filename = tempfile.mkstemp(prefix='palcraft-release-', suffix='.zip', dir=output.parent)
    os.close(handle)
    temporary = Path(filename)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2))
            for item in manifest['files']:
                archive.write(sources[item['target']], 'payload/' + item['target'])
        validated = Bundle(temporary)
        os.replace(temporary, output)
        return {'ok': True, 'release': str(output), 'sha256': validated.sha256, 'version': manifest['version'],
                'files': len(manifest['files']), 'game_bodies_packaged': False, 'personal_data_packaged': False}
    finally:
        temporary.unlink(missing_ok=True)


def build_distribution(spec_path, output):
    output = Path(output).absolute()
    if output.exists():
        fail('OUTPUT_EXISTS', '发布 ZIP 已存在，拒绝覆盖。')
    output.parent.mkdir(parents=True, exist_ok=True)
    base = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='palcraft-package-') as directory:
        release = Path(directory) / 'release.zip'
        result = build_release(spec_path, release)
        temp = output.with_name(output.name + '.partial')
        try:
            with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED) as archive:
                archive.write(release, 'PalCraft-Player/release.zip')
                for folder in ('installer', 'launcher'):
                    for path in sorted((base / folder).rglob('*')):
                        if path.is_file() and not path.is_symlink() and 'tests' not in path.parts and '__pycache__' not in path.parts and (path.suffix in ('.py', '.cpp', '.hpp', '.command', '.cmd', '.txt') or path.name.endswith('.example.json')):
                            archive.write(path, 'PalCraft-Player/' + path.relative_to(base).as_posix())
            os.replace(temp, output)
        finally:
            temp.unlink(missing_ok=True)
    return {**result, 'distribution': str(output), 'distribution_sha256': digest(output)}
