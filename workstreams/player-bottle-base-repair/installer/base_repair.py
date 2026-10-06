"""Repair approved missing base files only; never reapply a player release."""
import copy
import shutil
import uuid
from pathlib import Path

from installer.core import (CLIENT, _clone_file, _source_files, atomic_json, digest, ensure_no_session,
                            fail, get_state, operation_lock, owned_path)


def repair_plugins(root, source, dry_run=False):
    root = Path(root).absolute()
    state = get_state(root)
    source, selected = _source_files(source)
    if digest(source / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe') != state['game_sha256']:
        fail('BASE_REPAIR_VERSION', '合法源游戏与本安装 Shipping 版本不一致。')
    files = [(path, relative) for path, relative in selected if relative.startswith('Pal/Plugins/')]
    plan = []
    for path, relative in files:
        target = owned_path(root, CLIENT + '/' + relative)
        expected = digest(path)
        if target.exists() and (not target.is_file() or digest(target) != expected):
            fail('BASE_REPAIR_CONFLICT', '插件目标已有不同文件，未覆盖：' + relative)
        plan.append({'relative': relative, 'sha256': expected, 'bytes': path.stat().st_size,
                     'copy': not target.exists()})
    if dry_run:
        return {'ok': True, 'dry_run': True, 'plugins': plan, 'files': len(plan),
                'source_changed': False, 'Game_or_services_started': []}
    with operation_lock(root):
        ensure_no_session(root)
        state = get_state(root)
        before = copy.deepcopy(state)
        created = []
        journal = owned_path(root, '.palcraft/base-repair-' + uuid.uuid4().hex + '.json')
        atomic_json(journal, {'kind': 'missing-approved-plugins', 'before_state': before, 'files': plan, 'phase': 'copying'})
        try:
            for (path, relative), entry in zip(files, plan):
                target = owned_path(root, CLIENT + '/' + relative)
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():
                    if state['profile'].get('game_copy_mode') == 'apfs-clone':
                        _clone_file(path, target)
                    else:
                        shutil.copy2(path, target)
                    created.append(target)
                if digest(target) != entry['sha256']:
                    fail('BASE_REPAIR_HASH', '插件复制后摘要不符。')
                info = target.stat()
                state.setdefault('base_files', {})[CLIENT + '/' + relative] = {
                    'bytes': info.st_size, 'mtime_ns': info.st_mtime_ns, 'sha256': entry['sha256']}
            atomic_json(owned_path(root, '.palcraft/state.json'), state)
            atomic_json(journal, {'kind': 'missing-approved-plugins', 'files': plan, 'phase': 'committed'})
        except Exception:
            for path in created:
                if path.is_file() and digest(path) == next(x['sha256'] for x in plan if path.relative_to(root / CLIENT).as_posix() == x['relative']):
                    path.unlink()
            raise
    return {'ok': True, 'files': len(plan), 'copied': len(created), 'source_changed': False,
            'release_or_UserDir_changed': False, 'Game_or_services_started': []}
