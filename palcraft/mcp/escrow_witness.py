#!/usr/bin/env python3
"""v3 full/empty witnesses for an exclusive REAL ordinary chest in installed Level.sav.

Reads only saves; writes a receipt, never the save. Source production and normal
recipient bag changes do not invalidate a held escrow slot. Both containers must
belong to this same atomic world save; missing/destroyed/rebound escrow is refused.
"""
import contextlib
import copy
import hashlib
import io
import json
import os
import re
from pathlib import Path
import sys
import time
import uuid
import datetime
import struct
from escrow_io import read_and_force

ZERO = '00000000-0000-0000-0000-000000000000'


def uid(value):
    return str(uuid.UUID(str(value))).lower()


def values(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and isinstance(value.get('values'), list):
        return value['values']
    raise ValueError('Save array did not decode')


def decode_save(data, vendor=None):
    if vendor:
        sys.path.insert(0, str(vendor))
    from palworld_save_tools.gvas import GvasFile
    from palworld_save_tools.palsav import decompress_sav_to_gvas
    from palworld_save_tools.paltypes import PALWORLD_TYPE_HINTS
    from palworld_save_tools.archive import FArchiveReader
    raw, _ = decompress_sav_to_gvas(data)
    warnings = io.StringIO()
    with contextlib.redirect_stdout(warnings):
        gvas = GvasFile.read(raw, PALWORLD_TYPE_HINTS, {}, allow_nan=True)
    warning_text = warnings.getvalue()
    if any(name in warning_text for name in ('ItemContainerSaveData', 'MapObjectSaveData')):
        raise ValueError('Save schema could not be confirmed')
    world = gvas.properties['worldSaveData']['value']
    containers, models = {}, {}
    for entry in values(world['ItemContainerSaveData']['value']):
        cid, value = uid(entry['key']['ID']['value']), entry['value']
        capacity = value['SlotNum']['value']
        if cid in containers or type(capacity) is not int or not 0 <= capacity <= 1000:
            raise ValueError('Duplicate/invalid saved container')
        slots = {}
        for slot in values(value['Slots']['value']):
            r = FArchiveReader(bytes(slot['RawData']['value']['values']))
            index, count = r.i32(), r.i32()
            if index in slots or not 0 <= index < capacity or count < 0:
                raise ValueError('Duplicate/invalid saved slot')
            ref = {'container_id': cid, 'slot': index, 'count': count, 'item': ''}
            if count:
                ref.update(item=r.fstring(), dynamic_world=uid(r.guid()), dynamic_guid=uid(r.guid()))
            slots[index] = ref
        containers[cid] = {'capacity': capacity, 'slots': slots}
    for entry in values(world['MapObjectSaveData']['value']):
        if entry['MapObjectId']['value'] not in {'ItemChest', 'ItemChest_02'}:
            continue
        model, concrete = entry['Model']['value'], entry['ConcreteModel']['value']
        encoded = bytes(model['RawData']['value']['values'])
        if len(encoded) < 216:
            raise ValueError('Truncated ordinary chest model')
        r = FArchiveReader(encoded)
        row = dict(zip(('model_id', 'concrete_id', 'base_id', 'guild_id'), (uid(r.guid()) for _ in range(4))))
        row.update(type=entry['MapObjectId']['value'],hp=r.i32(),max_hp=r.i32())
        for _ in range(4):
            r.double()
        row['position'] = dict(zip(('x', 'y', 'z'), (r.double() for _ in range(3))))
        r.read(24 + 16 * 3)
        row['build_player_uid'] = uid(r.guid())
        cr = FArchiveReader(bytes(concrete['RawData']['value']['values']))
        if uid(cr.guid()) != row['concrete_id'] or uid(cr.guid()) != row['model_id']:
            raise ValueError('Saved model/concrete reverse binding differs')
        br = FArchiveReader(bytes(model['BuildProcess']['value']['RawData']['value']['values']))
        row['completed'] = br.byte() == 1
        modules = values(concrete['ModuleMap']['value'])
        item_modules = [x for x in modules if x['key'] == 'EPalMapObjectConcreteModelModuleType::ItemContainer']
        if len(item_modules) != 1:
            raise ValueError('Ordinary chest has ambiguous item-container module')
        row['container_id'] = uid(FArchiveReader(bytes(item_modules[0]['value']['RawData']['value']['values'])).guid())
        if row['model_id'] in models:
            raise ValueError('Duplicate ordinary chest model')
        models[row['model_id']] = row
    ticks = gvas.properties.get('Timestamp', {}).get('value')
    header = {'version': gvas.properties.get('Version', {}).get('value'),
              'revision': gvas.properties.get('Revision', {}).get('value')}
    if type(ticks) is int:
        date = datetime.datetime(1, 1, 1) + datetime.timedelta(microseconds=ticks // 10)
        header['timestamp'] = [date.year, date.month, date.day, date.hour, date.minute, date.second, date.microsecond // 1000]
        header['timestamp_ticks'] = str(ticks)
    game_time = world.get('GameTimeSaveData', {}).get('value', {})
    real_ticks = game_time.get('RealDateTimeTicks', {}).get('value') if isinstance(game_time, dict) else None
    if real_ticks is None and isinstance(game_time, dict):
        encoded_time = game_time.get('RawData', {}).get('value', {}).get('values', [])
        if len(encoded_time) >= 16:
            real_ticks = struct.unpack_from('<q', bytes(encoded_time), 8)[0]
    if type(real_ticks) is int:
        header['real_date_time_ticks'] = str(real_ticks)
    return {'containers': containers, 'models': models, 'header': header}


def verify_chest_binding(lease, saved):
    tx, c = lease['tx'], lease['candidate']
    if tx.get('protocol') != 3:
        raise ValueError('V3 lease required')
    if lease.get('owner_tx') != tx['id'] or type(lease.get('generation')) is not int or lease['generation'] < 1:
        raise ValueError('Escrow lease identity/generation invalid')
    model = saved['models'][c['model_id']]
    for name in ('model_id', 'concrete_id', 'container_id', 'base_id', 'guild_id', 'type', 'position'):
        if model.get(name) != c.get(name):
            raise ValueError('Saved escrow binding changed: ' + name)
    if model.get('hp', 0) <= 0 or model.get('completed') is not True:
        raise ValueError('Escrow is destroyed or incomplete in the actual save')
    box = saved['containers'][c['container_id']]
    if box['capacity'] != c['capacity'] or lease['container_id'] != c['container_id'] or lease['slot'] != 0:
        raise ValueError('Saved escrow capacity/slot differs')
    if any(i != lease['slot'] and ref['count'] for i, ref in box['slots'].items()):
        raise ValueError('Unrelated item entered another reserved chest slot')
    return box


def verify_snapshot(lease, saved, stage):
    tx, c = lease['tx'], lease['candidate']
    if tx.get('protocol') != 3 or stage not in {'full', 'empty'} or lease.get('status') != stage:
        raise ValueError('Only the v3 observed full/empty stage may receive a witness')
    box = verify_chest_binding(lease, saved)
    empty = {'container_id': c['container_id'], 'slot': lease['slot'], 'count': 0, 'item': ''}
    actual = box['slots'].get(lease['slot'], empty)
    expected = lease.get('expected_after')
    goal = empty if stage == 'empty' else {**empty, 'count': tx['count'], 'item': tx['item'],
                                        'dynamic_world': ZERO, 'dynamic_guid': ZERO}
    if expected != goal or actual != expected:
        raise ValueError('Saved exclusive escrow does not contain the observed stage')
    observed = [op for op in lease['operations'].values() if op.get('observed') is True and op.get('expected_after') == expected]
    if not observed:
        raise ValueError('No native effect was observed for this save stage')
    # Container presence confirms that a normal engine Move's two inventories
    # are serialized in the SAME Level file. Their contents are allowed to change.
    if tx['action'] == 'debit' and stage == 'full':
        op = lease['operations'].get('moveIn', {})
        for source in op.get('details', []):
            if source['before']['container_id'] not in saved['containers']:
                raise ValueError('Source container is not in the same atomic Level save')
    if tx['action'] == 'credit' and stage == 'empty':
        if lease.get('recipient_container_id') not in saved['containers']:
            raise ValueError('Recipient bag is not in the same atomic Level save; additional save proof is required')
    return {'container_id': c['container_id'], 'slot': lease['slot'], 'actual': actual,
            'model_id': c['model_id'], 'concrete_id': c['concrete_id'], 'same_level_counterpart': True}


def binding(lease, stage):
    return {'protocol': 3, 'id': lease['owner_tx'], 'fingerprint': lease['tx']['fingerprint'],
            'lease_generation': lease['generation'], 'lease_revision': lease['revision'],
            'container_id': lease['container_id'], 'slot': lease['slot'], 'stage': stage,
            'expected_after': lease['expected_after']}


def accept_witness(lease, witness):
    stage = lease.get('status')
    return (stage in {'full', 'empty'} and all(witness.get(k) == v for k, v in binding(lease, stage).items()) and
            witness.get('durable') is True and witness.get('same_level_counterpart') is True and
            isinstance(witness.get('save_sha256'), str) and re.fullmatch(r'[0-9a-f]{64}', witness['save_sha256']) is not None)


def select_current(export, tx_id=None):
    """Accept a single current lease or the owner's atomic multi-container export."""
    if not isinstance(export, dict):
        raise ValueError('Current lease export must be an object')
    if 'tx' in export and 'owner_tx' in export:
        rows = [export]
    elif export.get('protocol') == 3 and type(export.get('revision')) is int and export['revision'] >= 0 and isinstance(export.get('leases'), dict):
        rows = []
        owners = set()
        for key, row in export['leases'].items():
            if not isinstance(row, dict) or uid(key) != key or row.get('container_id') != key or uid(row['owner_tx']) in owners:
                raise ValueError('Duplicate or mismatched current container/transaction')
            owners.add(uid(row['owner_tx']))
            rows.append(row)
    else:
        raise ValueError('Current export schema must be {protocol:3,revision,leases:{containerId:lease}}')
    if tx_id is not None:
        target = uid(tx_id)
        rows = [row for row in rows if row.get('owner_tx') == target]
    else:
        rows = [row for row in rows if row.get('status') in {'full', 'empty'}]
    if len(rows) != 1:
        raise ValueError('Select exactly one current escrow transaction with --tx-id')
    row = rows[0]
    if row.get('protocol') != 3 or row['tx'].get('protocol') != 3 or row['tx'].get('id') != row['owner_tx']:
        raise ValueError('Current lease transaction identity differs')
    return row


def lease_digest(lease):
    return hashlib.sha256(json.dumps(lease, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def write_witness(root, lease_path, level, vendor=None, decoder=decode_save, tx_id=None):
    root, lease_path, level = Path(root), Path(lease_path), Path(level)
    lease_bytes = lease_path.read_bytes()
    lease = select_current(json.loads(lease_bytes), tx_id)
    stage = lease['status']
    stat = level.stat()
    if stat.st_mtime_ns < lease['save_after_unix'] * 1_000_000_000:
        raise ValueError('Installed Level save predates escrow save barrier')
    data = level.read_bytes()
    proof = verify_snapshot(lease, decoder(data, vendor), stage)
    current = read_and_force(level)
    after = level.stat()
    if current != data or (stat.st_mtime_ns, stat.st_size, stat.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
        raise ValueError('Installed Level save changed during verification')
    # The caller supplies get_current_lease(path) via an immutable current-row
    # export. Export must advance/revoke on release; comparing a stale immutable
    # revision file alone cannot prove that this generation remains current.
    if select_current(json.loads(lease_path.read_bytes()), lease['owner_tx']) != lease:
        raise ValueError('Escrow current lease advanced/released while verifying')
    witness = {**binding(lease, stage), **proof, 'durable': True,
               'save_sha256': hashlib.sha256(data).hexdigest(), 'save_path': str(level.resolve()),
               'lease_record': copy.deepcopy(lease), 'lease_sha256': lease_digest(lease),
               'current_export_sha256': hashlib.sha256(lease_bytes).hexdigest(), 'verified_unix': time.time()}
    # Delegate fsynced atomic receipt writing to the existing exchange utility.
    from exchange_recovery import atomic_write
    output = root / f'escrow-witness-{lease["owner_tx"]}-g{lease["generation"]}-{stage}.json'
    atomic_write(output, witness)
    return witness


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--lease-current', type=Path, required=True)
    parser.add_argument('--level', type=Path, required=True)
    parser.add_argument('--parser-vendor', type=Path)
    parser.add_argument('--tx-id', help='Transaction to select from escrow-leases-current.json')
    args = parser.parse_args()
    print(json.dumps(write_witness(args.root, args.lease_current, args.level, args.parser_vendor, tx_id=args.tx_id), ensure_ascii=False))
