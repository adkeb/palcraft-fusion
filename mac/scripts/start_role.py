"""Runtime-owned final local startup; requires immutable sync and new host auth."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--launch', type=Path, required=True)
parser.add_argument('--sync-receipt', type=Path, required=True)
args = parser.parse_args()
launch = json.loads(args.launch.read_text())
prepared_java_args = args.launch.with_suffix('.args').resolve()
sync = json.loads(args.sync_receipt.read_text())
cfg = json.loads(Path(launch['config']).read_text())
if not launch['configured_for_actual_boot']:
    raise RuntimeError('Runtime must set exact actual Mac paths/current host public options first')
if not sync.get('previous_world_producers_stopped') or not sync.get('immutable_snapshot_synced') or not sync.get('same_mc_uuid_preserved'):
    raise RuntimeError('Final runtime-owned save/stop and immutable sync receipt required')
root = Path(cfg['software_root'])
if cfg['guest_mc_uuid'] != sync.get('mc_uuid'):
    raise RuntimeError('Snapshot belongs to another player identity')
mod = Path(launch['cwd']) / 'mods' / launch['mod_filename'] if launch['role'] != 'hud' else root / 'mods' / launch['mod_filename']
if hashlib.sha256(mod.read_bytes()).hexdigest() != launch['mod_sha256']:
    raise RuntimeError('Mac transport JAR guard failed')
if launch['role'] in ('server', 'guest'):
    if not (root / 'server/world/level.dat').is_file():
        raise RuntimeError('Original Minecraft world missing; refuse creating a new world')
    if not sync.get('ledger_configuration_preserved'):
        raise RuntimeError('Existing ledger/exchange configuration receipt required')
    if not sync.get('actual_standalone_host_identity_enrolled'):
        raise RuntimeError('Fresh actual Standalone Pal host session/UID enrollment required')
    # Reference only: never parse private credential contents in launcher.
    if launch['role'] == 'guest' and not Path(cfg['credential_file']).is_file():
        raise RuntimeError('Actual enrolled credential file missing')
port = {'server': 25567, 'guest': 25599, 'hud': 25603}[launch['role']]
test = socket.socket()
try: test.bind(('127.0.0.1', port))
except OSError: raise RuntimeError('Port already in use; no stop or replacement is performed')
finally: test.close()
os.chdir(launch['cwd'])
if launch['role'] == 'hud':
    os.execvp('python3', ['python3', launch['main']] + launch['arguments'])
else:
    os.execv(launch['executable'], [launch['executable'], '@' + str(prepared_java_args)])
