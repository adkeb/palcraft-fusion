"""Bounded source tests with temporary synthetic files, never an actual game receipt."""
import ast
import copy
import hashlib
import json
import os
import tempfile
from pathlib import Path

source = Path(__file__).resolve().parents[1] / 'source/launcher/journal_lifecycle.py'
tree = ast.parse(source.read_text())
names = {'file_identity', '_normal_late_receipt_matches', '_late_normal_saved_level'}
nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
assert len(nodes) == 3


class Rejected(Exception):
    pass


def fail(code, message):
    raise Rejected(code)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text())


def owned_path(root, name):
    path = root / name
    assert path.resolve().is_relative_to(root.resolve()) and not path.is_symlink()
    return path


with tempfile.TemporaryDirectory(prefix='palcraft-normal-late-source-') as directory:
    root = Path(directory)
    token = 'a' * 32
    level = root / 'User/Saved/world/Level.sav'
    player = level.parent / 'Players/SYNTHETICUID.sav'
    level.parent.mkdir(parents=True)
    player.parent.mkdir()
    level.write_bytes(b'synthetic final level')
    player.write_bytes(b'synthetic player')
    os.utime(level, ns=(4_000_000_000, 4_000_000_000))
    native = {'pid': 42, 'world_id': 'synthetic-world', 'pal_uid': 'synthetic-uid'}
    host = {'primary_pid': 42, 'primary_alive': False, 'job_active_processes': 0,
            'phase': 'stopped', 'exit_code': 0}
    hostpath = root / ('.palcraft/control/' + token + '.host.json')
    hostpath.parent.mkdir(parents=True)
    hostpath.write_text(json.dumps(host))
    os.utime(hostpath, ns=(5_000_000_000, 5_000_000_000))
    selected = root / '.palcraft/standalone/scope.json'
    selected.parent.mkdir(parents=True)
    selected.write_text(json.dumps({'installed_level_path_host': str(level)}))
    scope = {'token': token, 'native_scope': native, 'normal_title_observed': {'action': 'observe_title'}}
    session = {'phase': 'stopped', 'normal_stop_stage': 'await_native_exit'}
    witness = {'normal_save_id': 'synthetic-save', 'normal_save_completed': True, 'level_mtime': 2}
    save = {'submitted_unix': 1}
    calls = []
    environment = {'Path': Path, 'file_identity': None, 'owned_path': owned_path,
                   'read_json': read_json, 'digest': digest, 'fail': fail,
                   'get_state': lambda root: {'profile': {'fixture': True}},
                   'time': type('Clock', (), {'time': staticmethod(lambda: 6)})}

    def codec(root, facts):
        calls.append(facts)
        return {'kind': 'existing-owned-Level-codec-observation-v1', **native,
                'files': {str(path.relative_to(root)): {'identity': environment['file_identity'](path),
                          'sha256': digest(path)} for path in (level, player)},
                'standard_codec': 'palworld_save_tools decompress_sav_to_gvas + GvasFile.read PALWORLD_TYPE_HINTS',
                'codec_python_executable': '/synthetic/python', 'standard_codec_reparsed': True,
                'level_and_player_parsed': True, 'owned_UID_in_Level': True,
                'normal_save_completed': False, 'this_boot_mutation_persistence_verified': False}

    environment['_existing_level_codec'] = codec
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(source), 'exec'), environment)
    observe = environment['_late_normal_saved_level']
    matches = environment['_normal_late_receipt_matches']
    preserved = copy.deepcopy(witness)
    result = observe(root, token, scope, session, save, witness, level)
    assert witness == preserved and result['original_early_witness_preserved']
    assert result['kind'] == 'palcraft-final-normal-game-save-observation-v1'
    assert 'normal_save_completed' not in result['final_level_codec_observation']
    assert len(calls) == 1
    print('PASS normal late game save uses separate final codec observation, early witness unchanged')

    for changed_host, stamp in [({**host, 'exit_code': 3, 'phase': 'failed'}, 4),
                                ({**host, 'job_active_processes': 1}, 4),
                                (host, 6), (host, 2)]:
        hostpath.write_text(json.dumps(changed_host))
        os.utime(hostpath, ns=(5_000_000_000, 5_000_000_000))
        os.utime(level, ns=(stamp * 1_000_000_000, stamp * 1_000_000_000))
        try:
            observe(root, token, scope, session, save, witness, level)
        except Rejected as error:
            assert str(error) == 'JOURNAL_SAVE_CHANGED'
        else:
            raise AssertionError('Boundary accepted')
    assert len(calls) == 1
    print('PASS failed host, live job, external post-exit write and old write rejected before codec')

    hostpath.write_text(json.dumps(host))
    os.utime(hostpath, ns=(5_000_000_000, 5_000_000_000))
    os.utime(level, ns=(4_000_000_000, 4_000_000_000))
    result = observe(root, token, scope, session, save, witness, level)
    receipt = {'normal_save_witness': witness, 'final_post_exit_level_witness': result}
    assert matches(root, scope, receipt) and matches(root, scope, {})
    tampered = copy.deepcopy(receipt)
    tampered['final_post_exit_level_witness']['normal_save_id'] = 'another'
    assert not matches(root, scope, tampered)
    player.write_bytes(b'changed synthetic player')
    assert not matches(root, scope, receipt)
    print('PASS existing unchanged receipts retained, new receipt binds original save and final Level/Player')

print('RESULT 3 bounded source cases PASS; codec fixture synthetic; no actual Game/Save/receipt mutation')
