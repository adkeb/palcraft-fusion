"""One directed original temporary-root bootstrap fixture; no game/lease/process runs."""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
DELTA = HERE.parent
BASE = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(BASE))
from launcher import runtime as original_runtime
spec = importlib.util.spec_from_file_location('launcher.runtime', DELTA / 'source/launcher/runtime.py')
runtime = importlib.util.module_from_spec(spec);sys.modules[spec.name] = runtime;spec.loader.exec_module(runtime)
from installer.core import PlayerError, atomic_json
fixture_source = Path(sys.argv[2]).resolve()
spec = importlib.util.spec_from_file_location('existing_singleplayer_bootstrap_check', fixture_source)
fixture_module = importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture_module)
temporary = HERE / 'temporary';temporary.mkdir(exist_ok=True)
tempfile.tempdir = str(temporary)
case = fixture_module.SingleplayerBootstrapTests();case.setUp()
try:
    root = case.root
    source = root / 'BridgeLab/rpc/palcraft-events.ndjson'
    source.parent.mkdir(parents=True, exist_ok=True)
    volume = b'old original event volume\n\x00complete bytes retained\n'
    source.write_bytes(volume)
    wal = root / 'PalCraft-Dev/bridge/exchange/witness.log'
    wal.parent.mkdir(parents=True, exist_ok=True);wal.write_bytes(b'stable WAL sentinel')
    saved = root / 'PalCraft-Client-User/Saved/Level.sav'
    saved.parent.mkdir(parents=True, exist_ok=True);saved.write_bytes(b'stable Saved sentinel')
    bad = root / 'personal-stop.json'
    atomic_json(bad, {'phase': 'stopped', 'graceful': True})
    try:
        runtime.start(root, dry_run=True, boot_singleplayer=True, normal_stop_receipt=bad)
        raise AssertionError('Personal stop intention cannot be a full witness')
    except PlayerError as exc:
        assert exc.code == 'JOURNAL_STOP'
    assert source.read_bytes() == volume
    full = root / 'full-normal-stop-fixture.json'
    atomic_json(full, {'root': str(root), 'root_id': 'bootstrap-fixture',
        'normal_save_completed': True, 'all_owned_producers_and_consumers_stopped': True})
    with patch.object(runtime, 'require_release_paths'):
        plan = runtime.start(root, dry_run=True, boot_singleplayer=True, normal_stop_receipt=full)
    assert plan['journal_maintenance']['dry_run'] is True and source.read_bytes() == volume
    # Stop at the existing health boundary before token creation/Popen; the rotator itself is real.
    boundary = {'ok': False, 'checks': [{'code': 'SOURCE_CHECK_BOUNDARY', 'ok': False,
        'message': 'No new process is launched by this source check', 'action': ''}]}
    with patch.object(runtime, 'health', return_value=boundary), patch.object(runtime.subprocess, 'Popen', side_effect=AssertionError('Process forbidden')):
        try:
            runtime.start(root, boot_singleplayer=True, normal_stop_receipt=full)
            raise AssertionError('Source check must stop before process startup')
        except PlayerError as exc:
            assert exc.code == 'SOURCE_CHECK_BOUNDARY'
    assert not source.exists(), 'The original writer must create the next volume'
    archives = list((root / 'BridgeLab/rpc/journal-archives').glob('*/palcraft-events.ndjson'))
    assert len(archives) == 1 and archives[0].read_bytes() == volume
    receipt = json.loads((archives[0].parent / 'rotation-receipt.json').read_text())
    assert receipt['archived_sha256'] == hashlib.sha256(volume).hexdigest()
    assert receipt['archived_bytes'] == len(volume)
    assert wal.read_bytes() == b'stable WAL sentinel' and saved.read_bytes() == b'stable Saved sentinel'
    assert not (root / '.palcraft/session.json').exists()
    try:
        runtime.start(root, dry_run=True, normal_stop_receipt=full)
        raise AssertionError('Full/promotion cannot rotate a live lifecycle')
    except PlayerError as exc:
        assert exc.code == 'JOURNAL_SCOPE'
    result = {'schema': 1, 'passed': True, 'actual_original_rotator': True,
        'existing_temporary_bootstrap_fixture': str(fixture_source),
        'personal_stop_intention_rejected': True, 'dry_run_preserves_full_volume': True,
        'completed_witness_fixture_archives_complete_bytes_before_start': True,
        'new_volume_not_prefilled': True, 'Saved_and_WAL_unchanged': True,
        'promotion_path_rejected': True, 'source_check_health_boundary_never_starts_process': True,
        'production_stop_witness_created': False, 'runtime_or_live_lease_operations': False}
    (HERE / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
finally:
    case.tearDown()
