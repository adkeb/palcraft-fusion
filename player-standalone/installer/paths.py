"""One installation, two path domains; no drive mappings are created here."""
import re
from pathlib import Path

PATH_CONTRACT = 'windows-root-v1'
LEGACY_WINDOWS_ROOT = 'D:/PalworldServer-LAN'


def normalize_windows_root(value):
    if not isinstance(value, str):
        raise ValueError('Windows 运行目录必须是绝对盘符路径。')
    path = value.replace('\\', '/').rstrip('/')
    if not re.match(r'^[A-Za-z]:/[^/]', path):
        raise ValueError('Windows 运行目录必须是绝对盘符路径，不能填写 Mac 宿主路径。')
    parts = path[3:].split('/')
    if any(not p or p in ('.', '..') or p.rstrip(' .') != p or
           any(ord(c) < 32 or c in '<>:"|?*' for c in p) or
           p.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL',
               *('COM' + str(i) for i in range(1, 10)), *('LPT' + str(i) for i in range(1, 10))}
           for p in parts):
        raise ValueError('安装目录含 Windows 不支持的路径组件。')
    return path[0].upper() + path[1:]


def windows_root(root, profile):
    """Windows uses its own root; CrossOver uses the bottle's standard Z:\\ -> / view."""
    if profile['platform'] == 'windows':
        result = normalize_windows_root(str(root))
    else:
        host = Path(root).absolute()
        bottle = Path(profile['bottle_root']).absolute()
        if host == bottle or host.is_relative_to(bottle) or bottle.is_relative_to(host):
            raise ValueError('安装目录与专用 bottle 目录应彼此独立。')
        result = normalize_windows_root('Z:' + host.as_posix())
    supplied = profile.get('windows_root')
    if supplied is not None and normalize_windows_root(supplied).casefold() != result.casefold():
        raise ValueError('Windows 运行目录与实际安装目录不一致；请移除旧 windows_root 后重新配置。')
    return result


def windows_path(root, relative=''):
    root = normalize_windows_root(root)
    if relative:
        relative = relative.replace('\\', '/')
        if relative.startswith('/') or any(p in ('', '.', '..') for p in relative.split('/')) or ':' in relative:
            raise ValueError('运行文件路径必须位于安装目录内。')
        root += '/' + relative
    return root.replace('/', '\\')


def bottle_mapping_matches(bottle):
    mapping = Path(bottle) / 'dosdevices/z:'
    return mapping.is_symlink() and mapping.resolve() == Path('/')


def validate_release_paths(manifest, profile):
    """An old D-only binary must never be installed into an arbitrary directory."""
    if manifest.get('requirements', {}).get('path_contract') == PATH_CONTRACT:
        return
    if profile['windows_root'].casefold() != LEGACY_WINDOWS_ROOT.casefold():
        raise ValueError('此发布包仍依赖旧 D 盘目录；请选择支持自选目录的新版 PalCraft 发布包。')
