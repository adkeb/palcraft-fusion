#!/usr/bin/env python3
"""Verify a pre-attempt installed checkpoint against a TRUSTED new-Pal-boot certificate.

This module reads a save and constructs proof; it does not restart, rearm, create
permits or modify inventory. verify_boot is required from the lifecycle owner:
it must attest the real new process and that the whole world loaded this exact
checkpoint before admitting effects. A mod-reload UUID / REST save / empty slot
cannot attest this. No CLI auto-manufactures a certificate from its own flags.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import uuid

from escrow_witness import decode_save, verify_chest_binding
from escrow_io import read_and_force


def sha(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def canonical_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def saved_slot(saved, ref):
    box = saved['containers'][ref['container_id']]
    if not 0 <= ref['slot'] < box['capacity']:
        raise ValueError('Saved counterpart slot outside its container')
    return box['slots'].get(ref['slot'], {'container_id': ref['container_id'], 'slot': ref['slot'], 'count': 0, 'item': ''})


def make_rearm_proof(lease, operation, level, boot_certificate, verify_boot, vendor=None, decoder=decode_save, proof_id=None):
    if not callable(verify_boot) or verify_boot(boot_certificate) is not True:
        raise ValueError('Trusted lifecycle verification of the actual new Pal process and whole-world loaded checkpoint is required')
    tx, op = lease['tx'], lease['operations'][operation]
    if operation not in {'moveIn', 'credit', 'dispose', 'deliver'} or tx.get('protocol') != 3 or op.get('attempted') is not True:
        raise ValueError('Recorded v3 native intent required')
    durable_after = lease.get('full_witness') if operation in {'moveIn', 'credit'} else lease.get('empty_witness')
    if durable_after:
        raise ValueError('A witnessed native effect cannot be rearmed or rolled back')
    allowed = {'needs_recovery', 'moving_in', 'crediting', 'disposing', 'delivering'} | ({'full'} if operation in {'moveIn', 'credit'} else {'empty'})
    if lease.get('status') not in allowed:
        raise ValueError('Rearm phase is out of order')
    certificate = boot_certificate
    new_boot = str(uuid.UUID(certificate['boot_id']))
    old_boot = str(uuid.UUID(op['boot_id']))
    if new_boot == old_boot or certificate.get('epoch') == op['epoch']:
        raise ValueError('Same Pal boot/mod reload cannot rearm')
    if certificate.get('protocol') != 3 or certificate.get('kind') != 'palworld_full_world_rehydration' or certificate.get('full_world_rehydrated') is not True:
        raise ValueError('Full-world loader certificate required')
    if type(certificate.get('pid')) is not int or certificate['pid'] <= 0:
        raise ValueError('Actual Pal PID required')
    created = certificate.get('process_created_unix')
    loaded = certificate.get('loaded_unix')
    if type(created) not in {int, float} or type(loaded) not in {int, float} or not op['attempted_unix'] < created <= loaded:
        raise ValueError('New process creation/load must follow the old native attempt')
    installed = Path(level)
    if Path(certificate['installed_level_path']).resolve() != installed.resolve():
        raise ValueError('Certificate refers to another installed world checkpoint')
    # A verified normal-startup receipt retains the exact stopped installed blob.
    # Subsequent normal autosaves must not erase that actual boot evidence.
    sealed = certificate.get('checkpoint_is_sealed_prelaunch') is True
    path = Path(certificate['checkpoint_path']) if sealed else installed
    before = path.stat()
    if type(certificate.get('checkpoint_mtime_ns')) is not int or certificate['checkpoint_mtime_ns'] != before.st_mtime_ns or before.st_mtime_ns > op['attempted_unix'] * 1_000_000_000:
        raise ValueError('Restored checkpoint must be the installed file and predate the attempted effect')
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if not sha(certificate.get('loaded_level_sha256')) or certificate['loaded_level_sha256'] != digest:
        raise ValueError('Installed checkpoint is not the exact file loaded by the new Pal process')
    saved = decoder(data, vendor)
    verify_chest_binding(lease, saved)
    if saved_slot(saved, op['before']) != op['before']:
        raise ValueError('The saved escrow contains a persisted/partial effect rather than its exact beforeimage')
    counterparts = []
    if operation == 'moveIn':
        counterparts = [step['before'] for step in op['details']]
    elif operation == 'deliver':
        counterparts = [op['details']['to']]
    for ref in counterparts:
        if saved_slot(saved, ref) != ref:
            raise ValueError('The installed source/bag beforeimage differs; preserve audit instead of replaying')
    current = read_and_force(path)
    after = path.stat()
    if current != data or (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
        raise ValueError('Installed checkpoint changed during rehydration verification')
    return {'protocol': 3, 'kind': 'escrow_rearm_after_world_rehydrate', 'proof_id': str(uuid.UUID(proof_id)) if proof_id else str(uuid.uuid4()),
            'id': lease['owner_tx'], 'fingerprint': tx['fingerprint'], 'container_id': lease['container_id'], 'slot': lease['slot'],
            'lease_generation': lease['generation'], 'lease_revision': lease['revision'], 'operation': operation,
            'previous_attempt': op.get('attempt', 1), 'previous_request_id': op['request_id'], 'previous_observed': op.get('observed') is True,
            'from_epoch': op['epoch'], 'to_epoch': certificate['epoch'], 'from_boot_id': old_boot, 'to_boot_id': new_boot,
            'full_world_rehydrated': True, 'loaded_level_sha256': digest, 'installed_level_sha256': digest,
            'boot_certificate_sha256': canonical_sha(certificate), 'checkpoint_mtime_ns': before.st_mtime_ns,
            'saved_before': op['before'], 'counterpart_before': counterparts}
