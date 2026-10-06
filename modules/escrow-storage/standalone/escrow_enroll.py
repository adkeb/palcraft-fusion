#!/usr/bin/env python3
"""Enroll only a really paid, complete empty ordinary box from live setup WAL + installed Level.

No grants, removals, world edits, RPCs or service calls. Writes the missing config
only after actual build/cost/ownership/geometry/save checks; never fabricates a witness.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import uuid
from escrow_bootstrap import lab_config, normalized
from escrow_io import read_and_force
from escrow_witness import decode_save, ZERO
from exchange_recovery import atomic_write


def read_record(path):
    return json.loads(read_and_force(path, 4 * 1024 * 1024))


def enroll(root, server_root, level, setup_id, durable_dll, credit_dll, vendor=None, lab_candidate=False, standalone_scope=None):
    scope = None
    if standalone_scope:
        import escrow_standalone
        scope = escrow_standalone.load_scope(standalone_scope)
        escrow_standalone.validate_level(scope, level)
        if Path(root).resolve() != Path(scope['exchange_root_host']):
            raise ValueError('Actual standalone exchange root differs')
    else:
        lab_config(server_root, level)
    root, level = Path(root), Path(level)
    setup_id = str(uuid.UUID(setup_id))
    prefix = f'escrow-setup-{setup_id}'
    rows = sorted(path for path in root.glob(prefix + '.r*.json') if re.fullmatch(re.escape(prefix) + r'\.r\d{6}\.json', path.name))
    if not rows:
        raise ValueError('Actual paid setup WAL is missing; do not invent paid evidence')
    op = None
    for revision, path in enumerate(rows, 1):
        row = read_record(path)
        if row.get('revision') != revision or row.get('id') != setup_id or row.get('kind') != 'normal_paid_escrow_setup':
            raise ValueError('Setup WAL identity/revision differs')
        receipt = path.with_name(path.name[:-5] + '.durable.json')
        if not receipt.exists() or read_record(receipt) != row:
            raise ValueError('Setup revision has no actual matching durable receipt')
        op = row
    if (op.get('status') != 'ready_for_saved_enrollment' or op.get('request_returned') is not True or
            op.get('attempted') is not True or op.get('bNotConsumeMaterials') is not False):
        raise ValueError('Actual normal consuming build has not completed')
    before, after = op['before'], op['after']
    if scope:
        if not all(escrow_standalone.authority_matches(scope, v) for v in (before, after)) or before.get('recipe_work') != 1000:
            raise ValueError('Actual singleplayer host/world/normal work differs from this paid WAL')
        if Path(durable_dll).resolve() != Path(scope['durable_dll_host']) or Path(credit_dll).resolve() != Path(scope['credit_dll_host']):
            raise ValueError('Standalone native files differ from the configured Mac/Wine pair')
    if before.get('recipe') != {'Wood': 15, 'Stone': 5} or before.get('wood', 0) < 15 or before.get('stone', 0) < 5:
        raise ValueError('Actual unlocked recipe/carried resource prerequisite differs')
    if before.get('technology_unlocked') is not True or before.get('player_uid') != after.get('player_uid') or before.get('guild_id') != after.get('guild_id'):
        raise ValueError('Real owner/guild/technology differs')
    carried = {'Wood': after['wood'] - before['wood'], 'Stone': after['stone'] - before['stone']}
    immediate = op.get('native_after', {}).get('world_totals', {})
    world_before = before.get('world_totals', {})
    world = {key: immediate.get(key, 0) - world_before.get(key, 0) for key in ('Wood', 'Stone')}
    if carried != {'Wood': -15, 'Stone': -5} and world != {'Wood': -15, 'Stone': -5}:
        raise ValueError('Observed real resource delta is not -15 Wood/-5 Stone')
    c = op['candidate']
    if c['model_id'] in {x['model_id'] for x in before['chests']} or c.get('build_player_uid') != before['player_uid']:
        raise ValueError('This is not the actual newly built paid owner box')
    if c.get('type') != 'ItemChest' or c.get('base_id') != ZERO or not c.get('empty') or not c.get('completed') or c.get('hp', 0) <= 0:
        raise ValueError('Actual empty completed outside-base ordinary box required')
    for base in after['bases']:
        if base.get('ok') is not True or not base.get('position') or type(base.get('range')) not in (int, float):
            raise ValueError('Actual complete base-range census required')
        dx, dy = c['position']['x'] - base['position']['x'], c['position']['y'] - base['position']['y']
        if dx * dx + dy * dy <= (base['range'] + 1000) ** 2:
            raise ValueError('Actual base transport/crafting radius overlaps this box')
    before_stat = level.stat()
    if before_stat.st_mtime_ns < after['observed_unix'] * 1_000_000_000:
        raise ValueError('Installed Level predates completed paid-box observation; wait for normal actual save')
    data = read_and_force(level)
    saved = decode_save(data, vendor)
    model = saved['models'][c['model_id']]
    for key in ('model_id', 'concrete_id', 'container_id', 'base_id', 'guild_id', 'type', 'position', 'build_player_uid'):
        if model.get(key) != c.get(key):
            raise ValueError('Actual installed saved model binding differs: ' + key)
    box = saved['containers'][c['container_id']]
    if model.get('hp', 0) <= 0 or model.get('completed') is not True or box['capacity'] != c['capacity'] or any(v['count'] for v in box['slots'].values()):
        raise ValueError('Actual installed save box is incomplete, rebound, nonempty or destroyed')
    current_stat = level.stat()
    if (before_stat.st_mtime_ns, before_stat.st_size, before_stat.st_ino) != (current_stat.st_mtime_ns, current_stat.st_size, current_stat.st_ino) or level.read_bytes() != data:
        raise ValueError('Actual installed Level changed during paid enrollment verification')
    if read_record(rows[-1]) != op or (root / f'{prefix}.r{op["revision"] + 1:06d}.json').exists():
        raise ValueError('Setup observation advanced during enrollment')
    output = root / 'escrow-config.json'
    if output.exists():
        raise ValueError('Existing enrollment must not be replaced by this one-time setup')
    current = root / 'escrow-leases-current.json'
    if current.exists() and any(x.get('status') != 'released' for x in read_record(current).get('leases', {}).values()):
        raise ValueError('An in-flight escrow lease exists; do not enroll another box')
    for dll in (durable_dll, credit_dll):
        if not Path(dll).is_file():
            raise ValueError('Actual configured native dependency is not deployed: ' + str(dll))
    candidate = {key: c[key] for key in ('model_id', 'concrete_id', 'container_id', 'base_id', 'guild_id', 'type', 'position', 'capacity', 'source_base_id')}
    candidate['enrollment_save_sha256'] = hashlib.sha256(data).hexdigest()
    config = {'protocol': 3, 'candidate': candidate, 'durable_dll': scope['durable_dll_windows'] if scope else str(durable_dll), 'credit_dll': scope['credit_dll_windows'] if scope else str(credit_dll),
              'level_path': str(level.resolve()), 'lab_candidate': lab_candidate, 'credit_verified': False,
              'isolation_evidence': {'runtime_verified': False, 'model_id': c['model_id'], 'container_id': c['container_id']},
              'enrollment': {'setup_id': setup_id, 'setup_revision': op['revision'], 'player_uid': before['player_uid'],
                             'cost': {'Wood': 15, 'Stone': 5}, 'carried_delta': carried, 'same_thread_world_delta': world,
                             'installed_level_sha256': candidate['enrollment_save_sha256'], 'ordinary_paid_build_observed': True,
                             'runtime_isolation_verified': False}}
    if scope: config['runtime_scope'] = escrow_standalone.lua_scope(scope)
    atomic_write(root / f'escrow-enrollment-{setup_id}.json', config['enrollment'])
    atomic_write(output, config)
    return {'config': str(output), 'model_id': c['model_id'], 'container_id': c['container_id'], 'save_sha256': candidate['enrollment_save_sha256'],
            'paid_cost': {'Wood': 15, 'Stone': 5}, 'runtime_verified': False, 'lab_candidate': lab_candidate}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('root', 'level', 'durable-dll', 'credit-dll'):
        p.add_argument('--' + key, type=Path, required=True)
    p.add_argument('--server-root', type=Path, help='Required only by the preserved network/Lab branch')
    p.add_argument('--setup-id', required=True);p.add_argument('--parser-vendor', type=Path)
    p.add_argument('--standalone-scope', type=Path, help='Actual configured private Mac singleplayer runtime profile')
    p.add_argument('--lab-candidate', action='store_true', help='Explicit already-authorized BridgeLab pilot; never claims daily runtime verification')
    a = p.parse_args()
    if not a.standalone_scope and not a.server_root: p.error('--server-root is required for the network/Lab branch')
    print(json.dumps(enroll(a.root, a.server_root, a.level, a.setup_id, a.durable_dll, a.credit_dll, a.parser_vendor, a.lab_candidate, a.standalone_scope), ensure_ascii=False))


if __name__ == '__main__':
    main()
