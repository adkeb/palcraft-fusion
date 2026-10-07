#!/usr/bin/env python3
"""Bounded source checks; never starts a game, Wine, cxmenu, or native helper."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


BASE = Path(__file__).resolve().parent
ROOT = BASE.resolve()
INSTALLED = BASE / 'base/launcher/crossover_menu_helper.py'
CROSSOVER_APP = Path(os.environ.get('PALCRAFT_CROSSOVER_APP', '/Applications/CrossOver.app'))
VENDOR = CROSSOVER_APP / 'Contents/SharedSupport/CrossOver/bin/wine'
sys.dont_write_bytecode = True


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


old = module('menu_environment_original', INSTALLED)
new = module('menu_environment_candidate', BASE / 'source/launcher/crossover_menu_helper.py')
checks = []


def check(name, predicate):
    assert predicate, name
    checks.append({'name': name, 'passed': True})


source = json.loads((BASE / 'SOURCE.json').read_text())
check('original_installed_source_unchanged', hashlib.sha256(INSTALLED.read_bytes()).hexdigest() == source['base_sha256'])
check('source_compiles_without_running_main', compile((BASE / 'source/launcher/crossover_menu_helper.py').read_text(), 'staged_menu.py', 'exec') is not None)

environment = {
    'CX_ENV': "EXAMPLE_OPTION='value with spaces' SteamAppId=0 WINEDLLOVERRIDES=example=b EXAMPLE_FLAG=unchanged",
    'CX_DEBUGMSG': '+all',
    'PALCRAFT_WINDOWS_ROOT': 'Z:/example/owned root',
    'PALCRAFT_PROXY_PORT': '18340',
    'CX_BOTTLE': 'PalCraftLab',
    'CX_BOTTLE_PATH': '/example/bottles',
    'UNRELATED_SETTING': 'preserved',
}
before = dict(environment)
final = new.native_environment(environment)
fields = shlex.split(final['CX_ENV'])
parsed = dict(field.split('=', 1) for field in fields)
check('caller_environment_not_mutated', environment == before)
check('owned_normal_dll_override_last_and_unique', fields.count('WINEDLLOVERRIDES=dwmapi=n,b') == 1 and sum(x.startswith('WINEDLLOVERRIDES=') for x in fields) == 1 and fields[-1] == 'WINEDLLOVERRIDES=dwmapi=n,b')
check('normal_SteamAppId_unique', parsed['SteamAppId'] == '1623730' and sum(x.startswith('SteamAppId=') for x in fields) == 1)
check('unrelated_CX_ENV_assignments_preserved', parsed['EXAMPLE_OPTION'] == 'value with spaces' and parsed['EXAMPLE_FLAG'] == 'unchanged')
check('root_bottle_proxy_and_unrelated_environment_preserved', all(final[k] == value for k, value in before.items() if k not in ('CX_ENV', 'CX_DEBUGMSG')))
check('normal_debugmsg_preserved', final['CX_DEBUGMSG'] == '-all')
check('absent_CX_ENV_supported', shlex.split(new.native_environment({})['CX_ENV']) == ['SteamAppId=1623730', 'WINEDLLOVERRIDES=dwmapi=n,b'])
for invalid in ["UNFINISHED='quote", 'invalid-assignment', '=missing-name', 'VALUE=bad\nline', 'VALUE=bad\x00value']:
    try:
        new.native_environment({'CX_ENV': invalid})
    except new.MenuError:
        continue
    raise AssertionError('malformed inherited CX_ENV accepted')
check('malformed_inherited_CX_ENV_fails_before_native_exec', True)

# Use only synthetic argument values. plan() and ShellLink serialization are pure.
profile = {
    'platform': 'crossover', 'bottle_mode': 'existing-selected', 'pal_entry_mode': 'singleplayer',
    'crossover_app': str(CROSSOVER_APP),
    'bottle_root': '/example/bottles/PalCraftLab', 'bottle_name': 'PalCraftLab',
    'windows_root': 'Z:/example/owned root', 'fps': 15, 'launch_shipping': True, 'mute': True,
}
host = 'PalCraft-Dev/player-tools/bin/PalCraftClientHost-v1.exe'
wine = Path(profile['crossover_app']) / 'Contents/SharedSupport/CrossOver/bin/wine'
original_command = [str(wine), '--bottle', profile['bottle_name'], '--enable-alt-loader', '1',
    '--debugmsg', '-all', '--dll', 'dwmapi=n,b', '--env', 'SteamAppId=1623730',
    '--workdir', old.windows(profile['windows_root'], 'PalCraft-Client'),
    old.windows(profile['windows_root'], host), '--root', old.windows(profile['windows_root']),
    '--control', old.windows(profile['windows_root'], '.palcraft/control'), '--token', 'f' * 32,
    '--fps', '15', '--shipping', '--mute']
old_plan = old.plan(ROOT, profile, original_command, host)
new_plan = new.plan(ROOT, profile, original_command, host)
check('same_native_helper_and_owned_menu_route', old_plan['launch'] == new_plan['launch'] and old_plan['menu'] == new_plan['menu'] and old_plan['bundle_id'] == new_plan['bundle_id'])
check('same_all_ShellLink_fields_and_host_arguments', old.native_shortcut_request(old_plan) == new.native_shortcut_request(new_plan))
info = new.bundle_info(new_plan, profile, {'CFBundleExecutable': 'Menu Helper'}, 'example-bottle-id')
check('unsupported_Info_Command_key_removed', 'CrossOverHelperCommand' not in info and info['CrossOverHelperMenuPath'] == new_plan['menu'])

# Exercise the exact official pure parser after the vendor's explicit deletion.
# This invokes Perl only; it does not execute the vendor wine command.
vendor_source = VENDOR.read_text()
function = re.search(r'(?ms)^sub read_env_from_string\(\$\)\n\{.*?^\}\n', vendor_source).group(0)
check('official_vendor_order_verified', vendor_source.index('delete $ENV{WINEDLLOVERRIDES};') < vendor_source.index('read_env_from_string($opt_env) if (defined $opt_env);'))
perl = "use strict; use warnings; use Text::ParseWords qw(shellwords); use JSON::PP; sub cxlog {}\n" + function + "\n"
perl += "$ENV{WINEDLLOVERRIDES}='discarded'; delete $ENV{WINEDLLOVERRIDES}; read_env_from_string($ARGV[0]); print encode_json({SteamAppId=>$ENV{SteamAppId},WINEDLLOVERRIDES=>$ENV{WINEDLLOVERRIDES},EXAMPLE_OPTION=>$ENV{EXAMPLE_OPTION},EXAMPLE_FLAG=>$ENV{EXAMPLE_FLAG}});"
completed = subprocess.run(['/usr/bin/perl', '-e', perl, final['CX_ENV']], capture_output=True, text=True, check=True)
official = json.loads(completed.stdout)
check('official_parser_restores_override_after_delete', official['WINEDLLOVERRIDES'] == 'dwmapi=n,b' and official['SteamAppId'] == '1623730')
check('official_parser_preserves_quoted_unknown_assignments', official['EXAMPLE_OPTION'] == 'value with spaces' and official['EXAMPLE_FLAG'] == 'unchanged')

receipt = {
    'schema': 1, 'source_only': True, 'passed': True, 'checks': checks,
    'official_vendor_parser_sha256': hashlib.sha256(function.encode()).hexdigest(),
    'source_sha256': hashlib.sha256((BASE / 'source/launcher/crossover_menu_helper.py').read_bytes()).hexdigest(),
    'actual_game_Wine_cxmenu_or_helper_started': False,
    'installed_source_session_vendor_or_Saved_modified': False,
    'actual_native_helper_inheritance_verified': False,
    'actual_gameplay_or_42_cases_pass_claimed': False,
}
(BASE / 'verification.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'passed': True, 'checks': len(checks), 'receipt': str(BASE / 'verification.json'), 'native_helper_inheritance_pending': True}))
