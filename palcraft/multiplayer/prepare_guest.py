"""Generate a per-player guest plan from a server-enrolled credential and already assigned ports. Never starts a process."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path, PureWindowsPath
from session_client import inspect_grant, load_credential


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2); stream.write('\n')
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


@contextmanager
def plan_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as stream:
        if os.name == 'nt':
            import msvcrt
            stream.seek(0); stream.write(b'0'); stream.flush(); stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try: yield
        finally:
            if os.name == 'nt':
                stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else: fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def prepare(credential_file: str, *, remote_root: str, mc_ws_port: int, hud_port: int,
            mc_server_address: str, allocation_file: Path, output: Path, remote_host: str = '5090',
            world_origin: dict | None = None, now: int | None = None, max_fps: int = 15) -> dict:
    credential = load_credential(credential_file); public = inspect_grant(credential['grant'])
    instant = int(time.time()) if now is None else now
    if instant >= public['expires_at']: raise ValueError('Credential expired; renew the same binding before launch')
    if not (1024 <= mc_ws_port <= 65535 and 1024 <= hud_port <= 65535) or mc_ws_port == hud_port:
        raise ValueError('MC WS and HUD require two distinct assigned TCP ports')
    if type(max_fps) is not int or not 1 <= max_fps <= 60: raise ValueError('Guest max FPS must be an integer from 1 to 60')
    address, sep, port = mc_server_address.rpartition(':')
    if not sep or not address or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError('MC server address must include its port')
    if int(port) in (mc_ws_port, hud_port): raise ValueError('Guest ports collide with shared MC server')
    identity = public['identity']; base = PureWindowsPath(remote_root) / 'sessions' / identity['mc_uuid']
    bridge = str(base / 'bridge'); run = str(base / 'minecraft'); remote_credential = str(base / 'credential.json')
    mapping = 'Local\\MCPassthroughFrame-' + identity['mc_uuid']
    guest = {'mc_ws_port': mc_ws_port, 'hud_port': hud_port, 'frame_mapping': mapping, 'bridge_dir': bridge,
             'run_dir': run, 'credential_file': remote_credential, 'mc_server_address': mc_server_address,
             'mc_server_port': int(port), 'max_fps': max_fps, 'mc_args': ['--username', identity['mc_name'], '--uuid', identity['mc_uuid']],
             'jvm_args': ['--enable-native-access=ALL-UNNAMED', '-Dpalcraft.sessions.mode=strict',
                          '-Dpalcraft.session.credential=' + remote_credential, '-Dpalcraft.bridgeDir=' + bridge,
                          '-Dpalcraft.frameName=' + mapping, '-Dpassthrough.port=' + str(mc_ws_port),
                          '-Dpalcraft.server=' + mc_server_address, '-Dpalcraft.hidden=true', '-Dpalcraft.maxFps=' + str(max_fps)]}
    manifest = {'schema': 1, 'kind': 'palcraft_guest', 'environment': 'BridgeLab', 'remote_host': remote_host,
                'identity': identity, 'server_session_id': public['server_session_id'], 'expires_at': public['expires_at'],
                'guest': guest, 'world_origin': world_origin, 'mute': True, 'power_profile': 'night_low_power' if max_fps <= 15 else 'explicit_guest_fps',
                'credential_sha256': hashlib.sha256(Path(credential_file).read_bytes()).hexdigest(),
                'credential_source': 'server_admin_enrollment', 'grant_verification': 'MC login authority before entry',
                'prepared_only': True, 'starts_processes': False}
    with plan_lock(allocation_file.with_suffix(allocation_file.suffix + '.lock')):
        allocations = json.loads(allocation_file.read_text(encoding='utf-8')) if allocation_file.exists() else {'schema': 1, 'guests': []}
        for row in allocations['guests']:
            if row['remote_host'] != remote_host: continue
            if row['identity']['mc_uuid'] == identity['mc_uuid']:
                if row['identity'] != identity: raise ValueError('Another Pal UID already owns this MC avatar')
                continue
            used = {row['guest']['mc_ws_port'], row['guest']['hud_port']}
            if used.intersection({mc_ws_port, hud_port}): raise ValueError('Assigned port is already allocated to another guest')
            if row['guest']['bridge_dir'].lower() == bridge.lower() or row['guest']['frame_mapping'] == mapping:
                raise ValueError('Guests would share bridge files or frame memory')
        rows = [r for r in allocations['guests'] if not (r['remote_host'] == remote_host and r['identity']['mc_uuid'] == identity['mc_uuid'])]
        rows.append(manifest); allocations['guests'] = rows
        atomic_json(output, manifest); atomic_json(allocation_file, allocations)
    return manifest


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--credential', required=True); p.add_argument('--output', type=Path, required=True)
    p.add_argument('--allocations', type=Path, required=True); p.add_argument('--remote-root', default='D:/PalworldServer-LAN/PalCraft-Dev')
    p.add_argument('--mc-ws-port', type=int, required=True); p.add_argument('--hud-port', type=int, required=True)
    p.add_argument('--mc-server-address', default='127.0.0.1:25567'); p.add_argument('--remote-host', default='5090')
    p.add_argument('--max-fps', type=int, default=15)
    p.add_argument('--world-origin', type=Path)
    a = p.parse_args(); origin = json.loads(a.world_origin.read_text(encoding='utf-8')) if a.world_origin else None
    result = prepare(a.credential, remote_root=a.remote_root, mc_ws_port=a.mc_ws_port, hud_port=a.hud_port,
                     mc_server_address=a.mc_server_address, allocation_file=a.allocations, output=a.output,
                     remote_host=a.remote_host, world_origin=origin, max_fps=a.max_fps)
    print(json.dumps({'ok': True, 'manifest': str(a.output.resolve()), 'identity': result['identity'],
                      'guest': result['guest'], 'prepared_only': True}, ensure_ascii=False))


if __name__ == '__main__': main()
