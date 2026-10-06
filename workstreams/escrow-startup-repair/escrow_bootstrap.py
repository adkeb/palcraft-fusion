#!/usr/bin/env python3
"""Actual BridgeLab startup checkpoint/process/loaded-world receipt entrypoints.

prepare runs only after the existing normal stop has really completed. bind and
finalize do not start/stop games or submit RPCs. The normal server game-thread
bootstrap module emits the loaded-world observation. No fixed-true verifier.
"""
import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

from escrow_io import read_and_force
from escrow_witness import decode_save, select_current
from escrow_rehydrate import canonical_sha

LAB = 'd:/palworldserver-lan/bridgelab'
EXE_REL = 'Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe'


def normalized(path):
    return str(path).replace('\\', '/').rstrip('/').lower()


def read(path):
    return json.loads(Path(path).read_bytes())


def atomic(path, value):
    from exchange_recovery import atomic_write
    atomic_write(path, value)


def immutable_bytes(path, data):
    path = Path(path)
    temporary = path.with_name(path.name + '.' + str(uuid.uuid4()) + '.tmp')
    try:
        with temporary.open('xb') as f:
            f.write(data); f.flush(); os.fsync(f.fileno())
        os.link(temporary, path)  # atomic, no replacement, same filesystem
        if os.name != 'nt':
            fd = os.open(path.parent, os.O_RDONLY)
            try: os.fsync(fd)
            finally: os.close(fd)
    finally:
        temporary.unlink(missing_ok=True)


def lab_config(server_root, level):
    if normalized(server_root) != LAB:
        raise ValueError('Bootstrap is limited to the existing BridgeLab root')
    p = Path(level)
    if normalized(p.name) != 'level.sav' or '/pal/saved/savegames/0/' not in normalized(p) or not normalized(p).startswith(LAB + '/'):
        raise ValueError('Actual installed BridgeLab Level.sav required')
    world = p.parent.name.upper()
    if len(world) != 32 or any(c not in '0123456789ABCDEF' for c in world):
        raise ValueError('Canonical installed world directory required')
    return world


def windows_lab_processes(server_root):
    if os.name != 'nt':
        raise RuntimeError('Real startup lifecycle requires the Windows backend')
    exe = str(Path(server_root) / EXE_REL)
    # WMI filter checks only this existing Lab exe; credentials/command lines are
    # neither read nor printed. It never reads production settings/saves.
    wql = "ExecutablePath='" + exe.replace('\\', '\\\\').replace("'", "\\'") + "'"
    quoted = "'" + wql.replace("'", "''") + "'"
    script = "$ErrorActionPreference='Stop';$p=@(Get-CimInstance Win32_Process -Filter " + quoted + ");ConvertTo-Json -Compress -InputObject @($p|Select-Object -ExpandProperty ProcessId)"
    encoded = base64.b64encode(script.encode('utf-16le')).decode()
    raw = subprocess.check_output(['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded], text=True).strip()
    ids = json.loads(raw) if raw else []
    return ids if isinstance(ids, list) else [ids]


def windows_process(pid):
    if os.name != 'nt':
        raise RuntimeError('Real process verification requires the Windows backend')
    from ctypes import wintypes
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]; api.OpenProcess.restype = wintypes.HANDLE
    api.CloseHandle.argtypes = [wintypes.HANDLE]; api.CloseHandle.restype = wintypes.BOOL
    api.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4; api.GetProcessTimes.restype = wintypes.BOOL
    api.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]; api.QueryFullProcessImageNameW.restype = wintypes.BOOL
    api.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]; api.GetExitCodeProcess.restype = wintypes.BOOL
    handle = api.OpenProcess(0x1000, False, int(pid))
    if not handle: raise ctypes.WinError(ctypes.get_last_error())
    try:
        created, exited, kernel, user = (wintypes.FILETIME() for _ in range(4))
        name = ctypes.create_unicode_buffer(32768); count = wintypes.DWORD(len(name)); code = wintypes.DWORD()
        if not api.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(kernel), ctypes.byref(user)) or not api.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(count)) or not api.GetExitCodeProcess(handle, ctypes.byref(code)):
            raise ctypes.WinError(ctypes.get_last_error())
        if code.value != 259: raise ValueError('Bound Pal process has exited')
        ticks = (created.dwHighDateTime << 32) | created.dwLowDateTime
        return {'pid': int(pid), 'executable': name.value, 'process_created_filetime': str(ticks),
                'process_created_unix': (ticks - 116444736000000000) / 10_000_000}
    finally:
        api.CloseHandle(handle)


def container_signature(saved):
    rows = []
    for cid, box in sorted(saved['containers'].items()):
        slots = [box['slots'][i] for i in sorted(box['slots']) if box['slots'][i]['count'] > 0]
        rows.append({'container_id': cid, 'capacity': box['capacity'], 'slots': slots})
    return rows


def pending_targets(export, saved):
    targets, refs = {}, {}
    for cid, lease in export.get('leases', {}).items():
        if lease.get('status') == 'released': continue
        select_current(export, lease['owner_tx'])
        targets[cid] = lease['candidate']
        refs[(cid, lease['slot'])] = {'container_id': cid, 'slot': lease['slot']}
        for key, op in lease.get('operations', {}).items():
            if key == 'moveIn':
                for step in op['details']:
                    ref = step['before']; refs[(ref['container_id'], ref['slot'])] = ref
            elif key == 'deliver':
                ref = op['details']['to']; refs[(ref['container_id'], ref['slot'])] = ref
    observed = []
    for cid, index in sorted(refs):
        box = saved['containers'][cid]
        if not 0 <= index < box['capacity']: raise ValueError('Pending saved slot outside its real container')
        observed.append(box['slots'].get(index, {'container_id': cid, 'slot': index, 'count': 0, 'item': ''}))
    return {'candidates': list(targets.values()), 'slot_refs': [{'container_id': r['container_id'], 'slot': r['slot']} for r in observed],
            'checkpoint_slots': observed}


def prepare(root, server_root, level, vendor=None, stopped_check=windows_lab_processes, decoder=decode_save):
    world = lab_config(server_root, level)
    if stopped_check(server_root): raise ValueError('Normal Pal stop has not completed; no checkpoint may be captured')
    root, level = Path(root), Path(level); root.mkdir(parents=True, exist_ok=True)
    before = level.stat(); data = read_and_force(level); after = level.stat()
    if (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
        raise ValueError('Installed checkpoint changed during stopped capture')
    saved = decoder(data, vendor)
    if stopped_check(server_root): raise ValueError('Pal restarted during checkpoint capture')
    boot_id = str(uuid.uuid4()); directory = root / 'bootstrap' / boot_id; directory.mkdir(parents=True)
    seal = directory / 'Level.sav'; immutable_bytes(seal, data)
    os.utime(seal, ns=(before.st_atime_ns, before.st_mtime_ns)); read_and_force(seal)
    export = read(root / 'escrow-leases-current.json') if (root / 'escrow-leases-current.json').exists() else {'protocol': 3, 'revision': 0, 'leases': {}}
    if export.get('protocol') != 3 or not isinstance(export.get('leases'), dict): raise ValueError('Current lease export schema differs')
    targets = pending_targets(export, saved)
    # FDateTime reflected getters expose millisecond components. Pair those with
    # exact saved GameTime ticks and the complete loaded inventory signature.
    header = {k: v for k, v in saved['header'].items() if k != 'timestamp_ticks'}
    expected = {'header': header, 'containers': container_signature(saved), 'transaction_slots': targets['checkpoint_slots']}
    immutable_bytes(directory / 'expected.json', json.dumps(expected, ensure_ascii=False, separators=(',', ':')).encode())
    envelope = {'protocol': 3, 'kind': 'palworld_prelaunch_checkpoint', 'boot_id': boot_id, 'epoch': 'pal-boot:' + boot_id,
                'server_root': str(server_root), 'installed_level_path': str(level.resolve()), 'world_directory': world,
                'checkpoint_path': str(seal.resolve()), 'checkpoint_sha256': hashlib.sha256(data).hexdigest(),
                'checkpoint_mtime_ns': before.st_mtime_ns, 'checkpoint_bytes': len(data), 'captured_unix': time.time(),
                'stopped_observation': 'no_exact_BridgeLab_exe_process_before_and_after_capture',
                'expected_path': str((directory / 'expected.json').resolve()), 'expected_sha256': canonical_sha(expected),
                'lease_export': export, 'targets': targets}
    immutable_bytes(directory / 'prelaunch.json', json.dumps(envelope, ensure_ascii=False, separators=(',', ':')).encode())
    atomic(root / 'escrow-boot-prelaunch.json', envelope)
    return envelope


def bind(root, server_root, level, pid, process_reader=windows_process, process_list=windows_lab_processes):
    lab_config(server_root, level); root = Path(root); envelope = read(root / 'escrow-boot-prelaunch.json')
    proc = process_reader(pid)
    if process_list(server_root) != [int(pid)] or normalized(proc['executable']) != normalized(Path(server_root) / EXE_REL):
        raise ValueError('The actual singleton Lab process/exe differs')
    if proc['process_created_unix'] <= envelope['captured_unix']: raise ValueError('Process predates completed stopped checkpoint capture')
    if normalized(envelope['installed_level_path']) != normalized(Path(level).resolve()): raise ValueError('Boot envelope belongs to another Level')
    value = {**proc, 'protocol': 3, 'boot_id': envelope['boot_id'], 'epoch': envelope['epoch'], 'bound_unix': time.time(),
             'prelaunch_sha256': canonical_sha(envelope)}
    path = root / 'bootstrap' / envelope['boot_id'] / 'execution.json'
    if path.exists():
        if read(path) != value and any(read(path).get(k) != value[k] for k in ['pid', 'boot_id', 'process_created_filetime', 'executable', 'prelaunch_sha256']): raise ValueError('Boot was already bound to another process')
        value = read(path)
    else: immutable_bytes(path, json.dumps(value, separators=(',', ':')).encode())
    atomic(root / 'escrow-boot-execution.json', value)
    return value


def finalize(root, server_root, level, pid, rpc_root, process_reader=windows_process, process_list=windows_lab_processes):
    root = Path(root); lab_config(server_root, level)
    envelope = read(root / 'escrow-boot-prelaunch.json'); directory = root / 'bootstrap' / envelope['boot_id']
    execution = read(directory / 'execution.json'); expected = read(envelope['expected_path'])
    if canonical_sha(expected) != envelope['expected_sha256'] or hashlib.sha256(read_and_force(envelope['checkpoint_path'])).hexdigest() != envelope['checkpoint_sha256']:
        raise ValueError('The actual stopped installed checkpoint seal was altered')
    process = process_reader(pid)
    if process_list(server_root) != [int(pid)] or any(process[k] != execution[k] for k in ['pid', 'process_created_filetime', 'executable']): raise ValueError('Bound Pal process changed or exited')
    native = read(Path(rpc_root) / ('escrow-boot-process-' + envelope['boot_id'].replace('-', '') + '.json'))
    observation_path = directory / 'loaded.json'; observation = read(observation_path)
    if native.get('pid') != int(pid) or native.get('process_created_filetime') != execution['process_created_filetime'] or native.get('boot_hex') != envelope['boot_id'].replace('-', ''):
        raise ValueError('In-process identity differs from actual OS process')
    if observation.get('boot_id') != envelope['boot_id'] or observation.get('process_identity') != native or observation.get('epoch') != envelope['epoch']:
        raise ValueError('Loaded observation belongs to a stale boot/mod reload')
    if observation.get('world_directory', '').upper() != envelope['world_directory'] or not observation.get('server_session_id'):
        raise ValueError('Actual loaded Pal world/session differs')
    # The backup flag's engine semantics are unverified. Keep its actual value
    # as a diagnostic; require the restored content to match the seal below.
    if observation.get('loaded_world_data') is not True or observation.get('all_levels_loaded') is not True or observation.get('load_failed_directory') != '':
        raise ValueError('Actual world loader is incomplete or reports a failed directory')
    if observation.get('header') != expected['header'] or observation.get('containers') != expected['containers']:
        raise ValueError('Actual loaded world-save data differs from sealed installed checkpoint')
    if observation.get('transaction_slots') != expected['transaction_slots']:
        raise ValueError('Actual manager transaction containers/beforeimages differ from loaded checkpoint')
    if canonical_sha(read(root / 'escrow-leases-current.json') if (root / 'escrow-leases-current.json').exists() else {'protocol': 3, 'revision': 0, 'leases': {}}) != canonical_sha(envelope['lease_export']):
        raise ValueError('Transactions changed while boot checkpoint was being established')
    certificate = {'protocol': 3, 'kind': 'palworld_full_world_rehydration', 'runtime_verified': True,
                   'boot_id': envelope['boot_id'], 'epoch': envelope['epoch'], 'pid': int(pid),
                   'process_created_unix': execution['process_created_unix'], 'process_created_filetime': execution['process_created_filetime'],
                   'loaded_unix': time.time(), 'loader_observed_unix': observation['observed_unix'], 'full_world_rehydrated': True,
                   'installed_level_path': envelope['installed_level_path'], 'checkpoint_path': envelope['checkpoint_path'],
                   'checkpoint_is_sealed_prelaunch': True, 'checkpoint_mtime_ns': envelope['checkpoint_mtime_ns'],
                   'loaded_level_sha256': envelope['checkpoint_sha256'], 'world_directory': envelope['world_directory'],
                   'server_session_id': observation['server_session_id'], 'prelaunch_sha256': canonical_sha(envelope),
                   'execution_sha256': canonical_sha(execution), 'observation_sha256': canonical_sha(observation),
                   'expected_sha256': envelope['expected_sha256'], 'issued_unix': time.time()}
    cert_path = directory / 'certificate.json'
    if cert_path.exists():
        prior = read(cert_path)
        if any(prior[k] != certificate[k] for k in certificate if k not in {'issued_unix', 'loaded_unix'}):
            raise ValueError('This actual boot already has another certificate')
        certificate = prior
    else:
        immutable_bytes(cert_path, json.dumps(certificate, separators=(',', ':')).encode())
    atomic(root / 'escrow-boot-certificate.json', certificate)
    return certificate


def verifier(root, server_root, level, rpc_root=None, process_reader=windows_process, process_list=windows_lab_processes):
    root = Path(root)
    def verify(certificate):
        try:
            lab_config(server_root, level)
            directory = root / 'bootstrap' / str(uuid.UUID(certificate['boot_id']))
            if read(root / 'escrow-boot-certificate.json') != certificate or read(directory / 'certificate.json') != certificate: return False
            proc = process_reader(certificate['pid']); execution = read(directory / 'execution.json'); envelope = read(directory / 'prelaunch.json')
            observation = read(directory / 'loaded.json'); expected = read(directory / 'expected.json')
            if process_list(server_root) != [certificate['pid']] or any(proc[k] != execution[k] for k in ['pid', 'process_created_filetime', 'executable']): return False
            if normalized(proc['executable']) != normalized(Path(server_root) / EXE_REL) or proc['process_created_unix'] <= envelope['captured_unix']: return False
            if normalized(certificate['installed_level_path']) != normalized(Path(level).resolve()): return False
            if any(certificate[key] != canonical_sha(obj) for key, obj in [('prelaunch_sha256', envelope), ('execution_sha256', execution), ('observation_sha256', observation), ('expected_sha256', expected)]): return False
            if hashlib.sha256(read_and_force(certificate['checkpoint_path'])).hexdigest() != certificate['loaded_level_sha256']: return False
            if observation['header'] != expected['header'] or observation['containers'] != expected['containers'] or observation['transaction_slots'] != expected['transaction_slots']: return False
            native = observation['process_identity']
            return (certificate.get('runtime_verified') is True and observation['loaded_world_data'] is True and observation['all_levels_loaded'] is True and
                    observation['load_failed_directory'] == '' and native['pid'] == proc['pid'] and native['process_created_filetime'] == proc['process_created_filetime'] and
                    native['boot_hex'] == certificate['boot_id'].replace('-', '') and observation['world_directory'].upper() == certificate['world_directory'])
        except (ValueError, KeyError, OSError, RuntimeError):
            return False
    return verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'bind', 'finalize', 'complete'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--server-root', type=Path, required=True)
    parser.add_argument('--level', type=Path, required=True); parser.add_argument('--parser-vendor', type=Path)
    parser.add_argument('--pid', type=int); parser.add_argument('--rpc-root', type=Path)
    parser.add_argument('--timeout-seconds', type=float, default=60)
    args = parser.parse_args()
    if args.mode == 'prepare': value = prepare(args.root, args.server_root, args.level, args.parser_vendor)
    elif args.mode == 'bind': value = bind(args.root, args.server_root, args.level, args.pid)
    elif args.mode == 'finalize': value = finalize(args.root, args.server_root, args.level, args.pid, args.rpc_root)
    else:
        bind(args.root, args.server_root, args.level, args.pid)
        deadline = time.monotonic() + args.timeout_seconds
        while True:
            try:
                value = finalize(args.root, args.server_root, args.level, args.pid, args.rpc_root)
                break
            except FileNotFoundError:
                if time.monotonic() >= deadline: raise RuntimeError('Actual game-thread loaded observation did not arrive; bootstrap remains held')
                time.sleep(.25)
    print(json.dumps({k: value[k] for k in ['protocol', 'boot_id', 'epoch'] if k in value}))


if __name__ == '__main__': main()
