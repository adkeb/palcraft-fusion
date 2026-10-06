#!/usr/bin/env python3
"""Bind a consumed normal-load observation to this owned live client process."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--root', type=Path, required=True)
p.add_argument('--observation', type=Path, required=True)
p.add_argument('--normal-load', type=Path, required=True)
p.add_argument('--receipt', type=Path, required=True)
a = p.parse_args()
r = a.root.resolve()
scope = json.loads((r / '.palcraft/standalone/scope.json').read_text())
session = json.loads((r / '.palcraft/session.json').read_text())
assert session['phase'] == 'bootstrap'
record = a.observation.resolve()
receipt = json.loads(record.read_text())
assert receipt['ok']
v = receipt['result']
assert v['read_only'] and len(v['players']) == 1
assert v['observed_unix'] >= session['started_unix']
pc, np = v['players'][0], v['native_process']
assert np['kind'] == 'palworld_client_process_identity'
assert np['read_only'] and np['native_code_matched']
assert np['executable_sha256'] == scope['executable_sha256']
assert pc['uid'] == scope['pal_uid'] and pc['initialized'] and pc['authority']
assert pc['loaded'] and pc['failed_dir'] == '' and pc['world_id'] == scope['world_directory']
assert len(v['game_instances']) == 1
assert v['game_instances'][0]['selected_world'] == scope['world_directory']
normalize = lambda z: z.replace('\\', '/').rstrip('/').lower()
assert normalize(v['native_user_dir']) == normalize(scope['private_user_dir_windows'])
for comp in ['GetPlayer', 'GetItem', 'GetWorkProgress']:
    assert pc['components'][comp]['owner']['address'] == pc['transmitter']['address']
assert pc['transmitter_owner']['address'] == pc['controller']['address']
client = session['components']['client']
actual = subprocess.run(['ps', '-p', str(client['pid']), '-o', 'lstart='], capture_output=True, text=True).stdout.strip()
assert actual == client['identity']
level = Path(scope['installed_level_path_host'])
assert level.is_file()
assert (level.parent / 'Players' / (pc['uid'].replace('-', '').upper() + '.sav')).is_file()
load = a.normal_load.resolve()
load_receipt = json.loads(load.read_text())
assert load_receipt['ok'] and load_receipt['result']['normal_existing_world_selected']
assert load_receipt['unix'] >= session['started_unix']
permission = {
    'schema': 1, 'source': 'runtime_owned_normal_load_observation',
    'process_epoch': str(np['pid']) + ':' + np['process_created_filetime'],
    'world_save_root': scope['installed_level_path_windows'].rsplit('/', 1)[0],
    'observation_record_sha256': hashlib.sha256(record.read_bytes()).hexdigest(),
    'normal_load_request_sha256': hashlib.sha256(load.read_bytes()).hexdigest(),
    'owned_supervisor_and_client_process_alive_checked': True,
    'actual_native_commandline_UserDir_physically_mapped': True,
    'native_context': {
        'world_address': pc['world']['address'], 'save_manager_address': pc['save_manager']['address'],
        'controller_address': pc['controller']['address'], 'game_state_address': pc['game_state']['address'],
        'world_id': pc['world_id'], 'host_uid': pc['uid'],
    },
    'published_unix': time.time(), 'observation_file': str(record), 'game_ready_claimed': False,
}
target = r / '.palcraft/standalone/owned-loaded-save-permission.json'
temp = target.with_suffix('.pending')
temp.write_text(json.dumps(permission, ensure_ascii=False, indent=2) + '\n')
os.chmod(temp, 0o600)
os.replace(temp, target)
a.receipt.write_text(json.dumps(permission, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'published_actual_permission': True, 'process_epoch': permission['process_epoch'],
                  'normal_observation_sha256': permission['observation_record_sha256'], 'game_ready': False}))
