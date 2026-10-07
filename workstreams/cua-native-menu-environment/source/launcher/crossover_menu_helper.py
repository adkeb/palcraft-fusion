#!/usr/bin/env python3
"""Owned CrossOver Windows menu bridge; run only as the normal session client.

No game is launched by plan(), bundle extraction, or the shortcut setup script.
run() replaces this process with the genuine native vendor Menu Helper after
the supervisor and session checks.
"""
import argparse
import bz2
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shlex
import stat
import struct
import subprocess
import sys
import time

REQUIREMENT = 'windows-menu-helper-v1'
TEMPLATE_SHA256 = '3eebe821f070f66307ff21e4298bea4f0fb2eba57f8b43394cdd8916e59bed9e'
HELPER_SHA256 = 'bed23023e0af7e61b2a781728541dc2517ba8a888359aa5a1ee2158546a2d1ba'
WRITER_SHA256 = 'c4169b4276a1f4478917d169ebe63878074d17b889d135326ff87bb8bc96fa07'
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


class MenuError(RuntimeError):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def windows(root, relative=''):
    return root.replace('/', '\\').rstrip('\\') + ('\\' + relative.replace('/', '\\') if relative else '')


def menu_script_name(menu):
    # CXMenuWindows.pm::remove_spaces, in that order.
    return menu.replace('^', '^5E').replace('+', '^2B').replace(' ', '+')


def archive_entries(compressed):
    if sha(compressed) != TEMPLATE_SHA256:
        raise MenuError('Installed vendor Menu Helper template differs from the reviewed version')
    data = bz2.decompress(compressed)
    offset = 0
    while offset + 76 <= len(data):
        header = data[offset:offset + 76]
        if header[:6] != b'070707':
            raise MenuError('Invalid vendor odc archive')
        mode = int(header[18:24], 8)
        name_size = int(header[59:65], 8)
        size = int(header[65:76], 8)
        end = offset + 76 + name_size + size
        if name_size < 1 or end > len(data):
            raise MenuError('Truncated vendor archive')
        name = data[offset + 76:offset + 76 + name_size - 1].decode('utf-8')
        payload = data[offset + 76 + name_size:end]
        offset = end
        if name == 'TRAILER!!!':
            return
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
            raise MenuError('Unsupported archive member')
        yield path, mode, payload
    raise MenuError('Missing archive trailer')


def checked_path(path, anchor):
    path, anchor = Path(path), Path(anchor)
    if not path.is_relative_to(anchor):
        raise MenuError('Path is outside the owned namespace')
    for item in (path, *path.parents):
        if item == anchor.parent:
            break
        if item.is_symlink():
            raise MenuError('Symlink in owned namespace')
    return path


def plan(root, profile, original_command, host_target):
    """Pure source plan. No processes, registrations, or file mutations."""
    root = Path(root).absolute()
    if root.is_symlink() or root.resolve() != root:
        raise MenuError('Player root must be the original physical owned root')
    if profile.get('platform') != 'crossover' or profile.get('bottle_mode') != 'existing-selected':
        raise MenuError('This bridge requires the selected existing CrossOver bottle')
    if profile.get('pal_entry_mode') != 'singleplayer':
        raise MenuError('This component is scoped to the owned singleplayer client')
    vendor = Path(profile['crossover_app']) / 'Contents'
    bottle = Path(profile['bottle_root'])
    wine = vendor / 'SharedSupport/CrossOver/bin/wine'
    prefix = [str(wine), '--bottle', profile['bottle_name'], '--enable-alt-loader', '1',
              '--debugmsg', '-all', '--dll', 'dwmapi=n,b', '--env', 'SteamAppId=1623730',
              '--workdir', windows(profile['windows_root'], 'PalCraft-Client')]
    target = windows(profile['windows_root'], host_target)
    if original_command[:len(prefix)] != prefix or original_command[len(prefix):len(prefix)+1] != [target]:
        raise MenuError('Original normal host command does not match this installation')
    arguments = original_command[len(prefix)+1:]
    expected = ['--root', windows(profile['windows_root']), '--control',
                windows(profile['windows_root'], '.palcraft/control'), '--token']
    if arguments[:5] != expected or len(arguments) < 8:
        raise MenuError('Normal host root/control/token arguments differ')
    token = arguments[5]
    tail = ['--fps', str(profile['fps'])]
    if profile.get('launch_shipping') is True:
        tail.append('--shipping')
    if profile['mute']:
        tail.append('--mute')
    if not re.fullmatch('[a-f0-9]{32}', token) or arguments[6:] != tail:
        raise MenuError('Normal host argument set differs')
    owner = sha(str(root).encode('utf-8'))[:24]
    menu = 'StartMenu/PalCraft/' + owner + '/PalCraft Game.lnk'
    home = root / '.palcraft/native-menu'
    bundle = home / 'PalCraft Game.app'
    description = 'PalCraft Game ' + owner[:8]
    menu_script = bottle / 'desktopdata/cxmenu' / menu_script_name(menu)
    cxmenu = vendor / 'SharedSupport/CrossOver/bin/cxmenu'
    # The observed winewrapper ignores --enable-alt-loader. Start the genuine
    # native Menu Helper, whose vendor Wine controller supplies its loader.
    launch = [str(bundle / 'Contents/MacOS/Menu Helper')]
    # The vendor helper resolves MenuPath through the official menu registry.
    # Its generated Windows menu command does not carry extra Wine options.
    return dict(root=root, vendor=vendor, bottle=bottle, home=home, bundle=bundle,
                wine=wine, cxmenu=cxmenu, menu=menu, owner=owner, description=description,
                link=bottle / 'drive_c/windows/Start Menu/PalCraft' / owner / 'PalCraft Game.lnk',
                link_windows='C:\\windows\\Start Menu\\PalCraft\\' + owner + '\\PalCraft Game.lnk',
                menu_script=menu_script, target=target, arguments=arguments, token=token,
                workdir=prefix[-1], launch=launch,
                bundle_id='com.codeweavers.CrossOverHelper.' +
                    hashlib.md5(profile['bottle_name'].encode('utf-8')).hexdigest().upper() + '.' +
                    hashlib.md5(menu.encode('utf-8')).hexdigest().upper())


def native_environment(environment):
    """Carry the validated normal Wine options through the vendor CX_ENV path."""
    result = dict(environment)
    try:
        inherited = shlex.split(result.get('CX_ENV', ''))
    except ValueError as exc:
        raise MenuError('The inherited CX_ENV cannot be parsed') from exc
    assignments = []
    for field in inherited:
        key, separator, _ = field.partition('=')
        if not separator or not key or '\0' in field or '\r' in field or '\n' in field:
            raise MenuError('The inherited CX_ENV contains an unsupported assignment')
        if key not in ('SteamAppId', 'WINEDLLOVERRIDES'):
            assignments.append(field)
    # bin/wine clears WINEDLLOVERRIDES before applying its CX_ENV assignments.
    assignments += ['SteamAppId=1623730', 'WINEDLLOVERRIDES=dwmapi=n,b']
    result['CX_ENV'] = shlex.join(assignments)
    result['CX_DEBUGMSG'] = '-all'
    return result


def native_shortcut_request(spec):
    fields = [spec['link_windows'], spec['target'],
              subprocess.list2cmdline(spec['arguments']), spec['workdir'], spec['description']]
    result = bytearray(b'PCSLNK01' + struct.pack('<I', len(fields)))
    for value in fields:
        if '\0' in value or '\r' in value or '\n' in value:
            raise MenuError('Unsupported ShellLink field')
        encoded = value.encode('utf-16-le')
        units = len(encoded) // 2
        if units > 32767:
            raise MenuError('ShellLink field exceeds the Windows Unicode limit')
        result.extend(struct.pack('<I', units))
        result.extend(encoded)
    if len(result) > 262144:
        raise MenuError('ShellLink request exceeds the file tool limit')
    return bytes(result)


def output_text(data, token):
    if isinstance(data, bytes):
        if data[:2] in (b'\xff\xfe', b'\xfe\xff'):
            data = data.decode('utf-16', errors='replace')
        elif data and data.count(b'\0') > len(data) // 5:
            data = data.decode('utf-16-le', errors='replace')
        else:
            data = data.decode('utf-8', errors='replace')
    data = str(data or '').replace(token, '<redacted-token>')
    return re.sub(r'(?i)\b[0-9a-f]{32}\b', '<redacted-token>', data)[-2500:]


def step_receipt(spec, stage, completed):
    exists = spec['link'].is_file()
    report = dict(schema=1, stage=stage, returncode=completed.returncode,
                  stdout=output_text(completed.stdout, spec['token']),
                  stderr=output_text(completed.stderr, spec['token']),
                  expected_link=spec['link_windows'], link_exists=exists,
                  link_bytes=spec['link'].stat().st_size if exists else None,
                  target_executed=False)
    path = checked_path(spec['home'] / 'setup-diagnostic.json', spec['root'])
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    path.chmod(0o600)
    return json.dumps(report, ensure_ascii=False, separators=(',', ':'))


def native_readback(completed, spec):
    for line in output_text(completed.stdout, spec['token']).splitlines():
        if line.startswith('{'):
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if value.get('backend') == 'IShellLinkW' and value.get('stage') == 'verified':
                required = ('readback_target', 'readback_arguments', 'readback_workdir', 'readback_description')
                if value.get('target_executed') is False and value.get('same_original_file') is True and all(value.get(name) is True for name in required):
                    return value
    return None


def bundle_info(spec, profile, template_info, bottle_id):
    result = dict(template_info)
    result.update(CFBundleIdentifier=spec['bundle_id'], CFBundleName=spec['description'],
                  CFBundleDisplayName=spec['description'], CXHelperAppVersion=43,
                  CXHelperAppBottleName=profile['bottle_name'],
                  CXHelperAppBottleTag='CrossOver-' + bottle_id + '/',
                  CXOriginalMenuName=spec['description'],
                  CrossOverHelperMenuPath=spec['menu'])
    result['CFBundleDocumentTypes'] = [{'CFBundleTypeRole': 'Viewer',
        'LSItemContentTypes': ['com.codeweavers.CrossOverHelper.MenuDummyType']}]
    result['UTImportedTypeDeclarations'] = [{'UTTypeIdentifier': 'com.codeweavers.CrossOverHelper.MenuDummyType'}]
    # This private game helper does not own Steam URL schemes.
    result.pop('CFBundleURLTypes', None)
    return result


def write_bundle(spec, profile, bottle_id):
    compressed = (spec['vendor'] / 'Resources/Menu Helper.cpbz2').read_bytes()
    entries = list(archive_entries(compressed))
    helper = next(payload for path, _, payload in entries if str(path) == 'Contents/MacOS/Menu Helper')
    if sha(helper) != HELPER_SHA256:
        raise MenuError('Vendor executable differs')
    bundle = checked_path(spec['bundle'], spec['root'])
    bundle.mkdir(parents=True, exist_ok=True)
    for path, mode, payload in entries:
        target = checked_path(bundle / str(path), spec['root'])
        if stat.S_ISDIR(mode):
            target.mkdir(parents=True, exist_ok=True)
        else:
            if str(path) == 'Contents/Info.plist':
                payload = plistlib.dumps(bundle_info(spec, profile, plistlib.loads(payload), bottle_id))
            target.write_bytes(payload)
            target.chmod(stat.S_IMODE(mode))
    icon = spec['vendor'] / 'Resources/CrossOverHelper.icns'
    if icon.is_file():
        (bundle / 'Contents/Resources/CrossOverHelper.icns').write_bytes(icon.read_bytes())


def bottle_configuration(spec):
    text = (spec['bottle'] / 'cxbottle.conf').read_text(encoding='utf-8')
    def field(section, name, source=text):
        match = re.search(r'(?ms)^\[' + re.escape(section) + r'\]\s*(.*?)(?=^\[|\Z)', source)
        value = re.search(r'(?m)^\s*"?' + re.escape(name) + r'"?\s*=\s*"([^"\r\n]*)"\s*$', match[1] if match else '')
        return value[1] if value else None
    bottle_id = field('Bottle', 'BottleID')
    if not bottle_id or not re.fullmatch('[A-Za-z0-9-]+', bottle_id):
        raise MenuError('Selected bottle has no valid BottleID')
    # cxmenu may otherwise update the entire bottle before working on the menu.
    vendor_conf = spec['vendor'] / 'SharedSupport/CrossOver/etc/CrossOver.conf'
    build = field('CrossOver', 'BuildTimestamp') or field('CrossOver', 'BuildTimestamp', vendor_conf.read_text(encoding='utf-8'))
    if not build or build != field('Bottle', 'Timestamp'):
        raise MenuError('Vendor would upgrade the selected bottle; use its normal maintenance lane first')
    if field('Bottle', 'MenuMode') == 'frozen':
        raise MenuError('Selected bottle menus are frozen')
    return bottle_id, sha((spec['bottle'] / 'cxbottle.conf').read_bytes())


def session_guard(spec, require_parent=True):
    """Re-read the original session, stop marker and supervisor identity."""
    from launcher.runtime import process_matches
    session = json.loads((spec['root'] / '.palcraft/session.json').read_text(encoding='utf-8'))
    if session.get('token') != spec['token'] or session.get('phase') not in ('starting', 'bootstrap', 'running'):
        raise MenuError('The original normal session is not alive')
    if (spec['root'] / '.palcraft/control' / (spec['token'] + '.stop')).exists():
        raise MenuError('The original session requested stop')
    supervisor = session.get('supervisor', {})
    if not process_matches(supervisor) or (require_parent and supervisor.get('pid') != os.getppid()):
        raise MenuError('The original supervisor identity is not alive')
    client = session.get('components', {}).get('client', {})
    if client.get('pid') != os.getpid() or not process_matches(client):
        raise MenuError('This bridge is not the one original supervisor client')


def prepare(spec, profile, env, runner=subprocess.run, guard=session_guard):
    """Future normal boot only. All calls are synchronous setup, never game starts."""
    guard(spec)
    bottle_id, before = bottle_configuration(spec)
    checked_path(spec['home'], spec['root']).mkdir(parents=True, exist_ok=True)
    spec['home'].chmod(0o700)
    link_anchor = spec['bottle'] / 'drive_c/windows/Start Menu/PalCraft' / spec['owner']
    checked_path(spec['link'], spec['bottle'])
    link_anchor.mkdir(parents=True, exist_ok=True)
    link_anchor.chmod(0o700)
    writer = checked_path(spec['writer'], spec['root'])
    if not writer.is_file() or sha(writer.read_bytes()) != WRITER_SHA256:
        raise MenuError('The release lacks the exact native Windows ShellLink file tool')
    request = checked_path(spec['home'] / 'create-shortcut.bin', spec['root'])
    try:
        request.write_bytes(native_shortcut_request(spec))
        request.chmod(0o600)
        setup = [str(spec['wine']), '--bottle', profile['bottle_name'], '--no-update',
                 '--debugmsg', '-all', '--wait-children', spec['writer_windows'],
                 windows(profile['windows_root'], '.palcraft/native-menu/create-shortcut.bin')]
        completed = runner(setup, env=env, timeout=30, capture_output=True)
        detail = step_receipt(spec, 'native_IShellLinkW_create_and_readback', completed)
        if completed.returncode != 0 or not spec['link'].is_file() or native_readback(completed, spec) is None:
            raise MenuError('The owned Windows ShellLink could not be created: ' + detail)
    finally:
        request.unlink(missing_ok=True)
    spec['link'].chmod(0o600)
    guard(spec)
    create = [str(spec['cxmenu']), '--bottle', profile['bottle_name'], '--create', spec['menu'],
              '--type', 'windows', '--description', spec['description'], '--mode', 'install', '--install']
    completed = runner(create, env=env, timeout=30, capture_output=True)
    if completed.returncode != 0 or not spec['menu_script'].is_file():
        raise MenuError('The vendor did not install the owned Windows menu: ' + step_receipt(spec, 'cxmenu_create_install', completed))
    if sha((spec['bottle'] / 'cxbottle.conf').read_bytes()) != before:
        raise MenuError('Vendor changed bottle configuration; refuse to launch')
    write_bundle(spec, profile, bottle_id)
    guard(spec)
    registered = runner([LSREGISTER, '-f', str(spec['bundle'])], env=env, timeout=10, capture_output=True)
    if registered.returncode != 0:
        raise MenuError('The owned native helper could not be registered: ' + step_receipt(spec, 'lsregister_owned_native_bundle', registered))
    receipt = dict(schema=1, requirement=REQUIREMENT, menu=spec['menu'],
                   native_bundle=str(spec['bundle']), bundle_identifier=spec['bundle_id'],
                   target=spec['target'], helper_sha256=HELPER_SHA256,
                   template_sha256=TEMPLATE_SHA256, bottle_configuration_unchanged=True,
                   shelllink_producer='native_IShellLinkW_IPersistFile', writer_sha256=WRITER_SHA256,
                   shelllink_fields_read_back=True,
                   launch_route='genuine_vendor_Menu_Helper_executable',
                   actual_game_app_registered=None, actual_window_owner_proven=False,
                   physical_f5_proven=False)
    receipt_path = spec['home'] / 'prepared.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    receipt_path.chmod(0o600)


def parse_cli(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('action', choices=['run'])
    parser.add_argument('original', nargs=argparse.REMAINDER)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_cli(argv)
    if sys.platform != 'darwin':
        raise MenuError('This component is only for the Mac normal boot')
    # Same package imports as the original palcraft.py launcher entry point.
    sys.path.insert(0, str(Path(__file__).absolute().parent.parent))
    from installer.core import get_state, validate_profile, owned_path
    root = Path(args.root).absolute()
    state = get_state(root)
    if state['manifest'].get('requirements', {}).get('crossover_native_menu') != REQUIREMENT:
        raise MenuError('This release did not explicitly enable the owned menu bridge')
    profile = validate_profile(state['profile'], root)
    hosts = [entry for entry in state['manifest']['files'] if entry.get('role') == 'client_host']
    if len(hosts) != 1:
        raise MenuError('Client host manifest role is not unique')
    owned_path(root, hosts[0]['target'])
    original = args.original[1:] if args.original[:1] == ['--'] else args.original
    spec = plan(root, profile, original, hosts[0]['target'])
    writers = [entry for entry in state['manifest']['files'] if entry.get('role') == 'crossover_shelllink_writer']
    if len(writers) != 1 or writers[0].get('sha256') != WRITER_SHA256:
        raise MenuError('The release has no unique exact native ShellLink writer role')
    spec['writer'] = owned_path(root, writers[0]['target'])
    spec['writer_windows'] = windows(profile['windows_root'], writers[0]['target'])
    # spawn() persists its supervisor identity immediately after Popen.
    deadline = time.monotonic() + 3
    while True:
        try:
            session_guard(spec)
            break
        except MenuError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(.05)
    setup_environment = os.environ.copy()
    launch_environment = native_environment(setup_environment)
    prepare(spec, profile, setup_environment)
    session_guard(spec)
    # One native vendor app replacement; never also run the shortcut/cxmenu here.
    os.execve(spec['launch'][0], spec['launch'], launch_environment)


if __name__ == '__main__':
    try:
        main()
    except (MenuError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print('PALCRAFT_NATIVE_MENU_SETUP: ' + str(exc), file=sys.stderr)
        sys.exit(1)
