#!/usr/bin/env python3
"""Offline-only parser for a captured Lab workers.list response. No network/game writes."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

BASE = '00000000-0000-4000-8000-000000000031'
GUILD = '00000000-0000-4000-8000-00000000001b'
INDIVIDUAL = '00000000-0000-4000-8000-00000000002e'
WORK = '00000000-0000-4000-8000-000000000020'
MODEL = '00000000-0000-4000-8000-000000000012'
ZERO = '00000000-0000-0000-0000-000000000000'


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('UTC timestamp missing')
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Timestamp must include timezone')
    return parsed.astimezone(dt.timezone.utc)


def unwrap(value):
    for _ in range(6):
        if not isinstance(value, dict):
            raise ValueError('Response must be an object')
        if value.get('isError') is True or value.get('error'):
            raise ValueError('Captured tool returned an error')
        if 'bases' in value:
            return value
        if isinstance(value.get('structuredContent'), dict):
            value = value['structuredContent']
        elif isinstance(value.get('result'), dict):
            value = value['result']
        elif isinstance(value.get('content'), list):
            parts = [x['text'] for x in value['content'] if x.get('type') == 'text' and isinstance(x.get('text'), str)]
            if len(parts) != 1:
                raise ValueError('Expected one JSON text response')
            value = json.loads(parts[0])
        else:
            raise ValueError('No workers.list result found')
    raise ValueError('Too many response wrappers')


def verify(captured, saved, after_utc, expected_instance=None):
    r = {'lab_only': True, 'read_only': True, 'requested_individual_id': INDIVIDUAL,
         'expected_work_id': WORK, 'expected_model_id': MODEL,
         'native_assignment_called': False, 'actor_force_load_called': False,
         'runtime_fixed_association': False, 'saved_work_model_binding': False,
         'live_model_binding_verified': False, 'live_reverse_work_binding_verified': False,
         'restart_retention_evidence': False, 'errors': [],
         'limitation': 'workers.list exposes character-side assignment only. Model binding comes from the named save snapshot; it is not a fresh reverse/model check. This parser does not prove process restart; its after_utc checkpoint must be supplied from the known Lab recovery.'}
    try:
        snap = unwrap(captured)
        assert snap.get('ok') is True and snap.get('reader_verified') is True, 'Worker reader did not return a verified successful snapshot'
        assert snap.get('candidate_unvalidated') is False, 'Reader remains candidate/unverified'
        assert snap.get('native_assignment_called') is False and snap.get('source') == 'runtime_read_only', 'Expected read-only worker result'
        assert not snap.get('errors'), 'Snapshot contains errors'
        observed, after = timestamp(snap.get('observed_utc')), timestamp(after_utc)
        assert observed >= after, 'Snapshot predates the recovery checkpoint'
        instance = snap.get('server_instance_id')
        assert isinstance(instance, str) and len(instance) == 36, 'Server instance identity missing'
        if expected_instance:
            assert instance == expected_instance, 'Snapshot came from another bridge instance'
        r.update(observed_utc=snap['observed_utc'], recovery_checkpoint_utc=after_utc, server_instance_id=instance,
                 fresh_after_checkpoint=True)
        bases = [b for b in snap['bases'] if b.get('id') == BASE]
        assert len(bases) == 1, 'Target base missing or duplicated'
        base = bases[0]
        assert base.get('ok') is True and base.get('available') is True and base.get('group_id') == GUILD, 'Base unavailable or ownership differs'
        assert not base.get('errors'), 'Base reader contains errors'
        rows = [w for w in base.get('workers', []) if w.get('individual_id', {}).get('instance_id') == INDIVIDUAL]
        assert len(rows) == 1, 'Target individual missing or duplicated'
        row = rows[0]
        r['worker'] = {k: row.get(k) for k in ['nickname', 'character_id', 'slot_index', 'individual_id', 'base_id', 'group_id', 'actor_loaded', 'sleeping', 'dead', 'warnings', 'task']}
        assert row.get('ok') is True and row.get('empty') is False, 'Target worker read failed'
        assert row['individual_id'].get('player_uid') == ZERO, 'Worker compound identity changed'
        assert row.get('ownership_verified_live') is True and row.get('base_id') == BASE and row.get('group_id') == GUILD, 'Worker membership not verified'
        m = row.get('membership', {})
        assert all(m.get(k) is True for k in ['director_slot_present', 'base_matches', 'group_matches']), 'Director/parameter membership incomplete'
        assert m.get('director_base_id') == BASE and m.get('parameter_base_id') == BASE and m.get('director_group_id') == GUILD and m.get('parameter_group_id') == GUILD, 'Membership chain differs'
        assert not any(w.get('stage') == 'current_task' for w in row.get('warnings', [])), 'Current-task reader failed'
        if row.get('actor_loaded') is not True:
            r['status'] = 'waiting_for_loaded_actor'
            r['note'] = 'Ask the connected tester to approach this base; re-read later without forcing actor creation.'
        elif row.get('task', {}).get('known') is not True:
            r['status'] = 'current_task_unknown'
        else:
            t = row['task']
            r['runtime_fixed_association'] = t.get('assigned') is True and t.get('fixed') is True and t.get('work_id') == WORK
            r['status'] = 'expected_fixed_association_observed' if r['runtime_fixed_association'] else 'expected_fixed_association_not_observed'
            r['production_work_observed'] = t.get('working') is True
            r['note'] = 'Fixed association and actual production are separate; Working=false does not invalidate a fixed idle workstation.'
        assert saved.get('lab_only') is True and saved.get('read_only') is True, 'Expected Lab offline save report'
        matches = [w for w in saved.get('workers', []) if w.get('individual_id') == INDIVIDUAL]
        assert len(matches) == 1, 'Saved worker report missing or duplicated'
        sw = matches[0]
        r['saved_work_model_binding'] = (sw.get('ok') is True and sw.get('fixedWorkSaved') is True and
            sw.get('saved_fixed_matches') == 1 and sw.get('guild_id') == GUILD and
            sw.get('work', {}).get('id') == WORK and sw['work'].get('model_id') == MODEL and sw['work'].get('base_id') == BASE)
        r['save_input_sha256'] = saved.get('input', {}).get('sha256')
        assert isinstance(r['save_input_sha256'], str) and len(r['save_input_sha256']) == 64, 'Saved evidence SHA missing'
        assert r['saved_work_model_binding'], 'Saved fixed-work/model binding not verified'
        r['restart_retention_evidence'] = r['runtime_fixed_association'] and r['saved_work_model_binding']
        r['ok'] = r['restart_retention_evidence']
    except (AssertionError, ValueError, TypeError, KeyError) as exc:
        r['ok'] = False
        r['status'] = 'insufficient_or_invalid_evidence'
        r['errors'].append(str(exc))
    return r


def load(path):
    data = Path(path).read_bytes()
    if len(data) > 8*1024*1024:
        raise ValueError('Input JSON too large')
    return json.loads(data), hashlib.sha256(data).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workers', required=True)
    p.add_argument('--saved', required=True)
    p.add_argument('--after-utc', required=True, help='Known post-recovery checkpoint, not inferred from file mtime')
    p.add_argument('--server-instance-id')
    p.add_argument('--output')
    a = p.parse_args()
    workers, whash = load(a.workers)
    saved, shash = load(a.saved)
    result = verify(workers, saved, a.after_utc, a.server_instance_id)
    result['evidence_files'] = {'workers_sha256': whash, 'saved_report_sha256': shash}
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if a.output:
        dest = Path(a.output)
        if dest.suffix != '.json' or dest.resolve() in [Path(a.workers).resolve(), Path(a.saved).resolve()]:
            raise ValueError('Output must be a new JSON report, never an input')
        with dest.open('x', encoding='utf-8') as f:
            f.write(text)
    print(text, end='')
    return 0 if result['ok'] else 2

if __name__ == '__main__':
    raise SystemExit(main())
