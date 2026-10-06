"""Freeze ready source files and prove the archive matches the recorded bytes."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MC = ROOT / 'palcraft/mc'
CORE = [
    'build.gradle', 'gradle.properties',
    'src/main/java/dev/rehan/passthrough/Passthrough.java',
    'src/main/java/dev/rehan/passthrough/BridgeNetwork.java',
    'src/main/java/dev/rehan/passthrough/BridgePayload.java',
    'src/main/java/dev/rehan/passthrough/BridgeServerFeatures.java',
    'src/main/java/dev/rehan/passthrough/FeatureRegistry.java',
    'src/client/java/dev/rehan/passthrough/client/ClientBridge.java',
    'src/client/java/dev/rehan/passthrough/client/ClientInput.java',
    'src/client/java/dev/rehan/passthrough/client/PassthroughClient.java',
    'src/main/resources/passthrough.mixins.json',
    'src/client/resources/passthrough.client.mixins.json',
    'src/contractTest/java/dev/rehan/passthrough/FeatureRegistryContract.java',
]

def digest(data):
    return hashlib.sha256(data).hexdigest()

def eligible(path, source_root=MC):
    rel = path.relative_to(source_root)
    return rel.parts[0] in ('src', 'gradle') or rel.as_posix() in ('build.gradle', 'gradle.properties', 'settings.gradle', 'gradlew', 'gradlew.bat', '.gitignore')

def freeze(label, baseline=None, extra=(), source_root=MC):
    source_root = Path(source_root).resolve()
    if baseline:
        with zipfile.ZipFile(baseline) as archive:
            data = {name: archive.read(name) for name in archive.namelist() if not name.endswith('/')}
        captured = [source_root / name for name in CORE + list(extra)]
        for path in captured:
            data[path.relative_to(source_root).as_posix()] = path.read_bytes()
    else:
        captured = sorted(path for path in source_root.rglob('*') if path.is_file() and eligible(path, source_root))
        data = {path.relative_to(source_root).as_posix(): path.read_bytes() for path in captured}
    for path in captured:
        name = path.relative_to(source_root).as_posix()
        if digest(path.read_bytes()) != digest(data[name]):
            raise RuntimeError('Source changed during snapshot: ' + name)
    files = {name: digest(content) for name, content in sorted(data.items())}
    source_hash = digest(json.dumps(files, sort_keys=True, separators=(',', ':')).encode())
    snapshot = label + '-' + source_hash[:12]
    output = ROOT / 'integration-build/snapshots' / snapshot
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / 'source.zip'
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, content in sorted(data.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, content)
    record = {
        'schema_version': 1, 'kind': label, 'snapshot': snapshot,
        'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_hash': source_hash, 'archive_sha256': digest(archive_path.read_bytes()),
        'baseline': str(baseline) if baseline else None,
        'captured_current_files': [path.relative_to(source_root).as_posix() for path in captured],
        'captured_source_root': str(source_root),
        'remote_root': 'D:/PalworldServer-LAN/PalCraft-Dev/workstreams/integration/' + snapshot,
        'files': files,
    }
    (output / 'source-manifest.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in record.items() if key not in ('files', 'captured_current_files')}, ensure_ascii=False))
    return record

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--label', required=True)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--extra', action='append', default=[])
    parser.add_argument('--source-root', type=Path, default=MC)
    args = parser.parse_args()
    freeze(args.label, args.baseline, args.extra, args.source_root)
