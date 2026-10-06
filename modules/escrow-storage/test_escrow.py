import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock
import uuid

BASE = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BASE / 'work/minecraft-fusion/palcraft/mcp'))
import escrow_credit as credit
import escrow_witness as witness
import escrow_rehydrate as rehydrate
import escrow_io as durable_io

CID = '00000000-0000-4000-8000-000000000016'
MID = '00000000-0000-4000-8000-00000000000c'
MC = '77777777-7777-4777-8777-777777777777'
PAL = '33333333-3333-4333-8333-333333333333'
TX = '44444444-4444-4444-8444-444444444444'
SOURCE = '11111111-1111-4111-8111-111111111111'
BAG = '22222222-2222-4222-8222-222222222222'


def fixture(stage='full', direction='debit'):
    tx = {'protocol': 3, 'id': TX, 'mc_uid': MC, 'player_uid': PAL, 'mc_world': 'fixture',
          'action': direction, 'item': 'Wood', 'count': 16, 'fingerprint': 'b' * 64}
    c = {'container_id': CID, 'model_id': MID, 'concrete_id': '00000000-0000-4000-8000-000000000028',
         'base_id': witness.ZERO, 'guild_id': '00000000-0000-4000-8000-00000000001b',
         'type': 'ItemChest', 'capacity': 10, 'position': {'x': 100000., 'y': 0., 'z': 100.}}
    empty = {'container_id': CID, 'slot': 0, 'count': 0, 'item': ''}
    full = {**empty, 'count': 16, 'item': 'Wood', 'dynamic_world': witness.ZERO, 'dynamic_guid': witness.ZERO}
    expected = full if stage == 'full' else empty
    op = 'moveIn' if direction == 'debit' else 'credit'
    operations = {op: {'observed': True, 'expected_after': full,
                      'details': [{'before': {'container_id': SOURCE}}] if op == 'moveIn' else {}}}
    if stage == 'empty':
        operations['deliver' if direction == 'credit' else 'dispose'] = {'observed': True, 'expected_after': empty}
    lease = {'protocol': 3, 'owner_tx': TX, 'tx': tx, 'candidate': c, 'container_id': CID, 'slot': 0,
             'generation': 2, 'revision': 4, 'status': stage, 'expected_after': expected,
             'save_after_unix': 1, 'operations': operations, 'recipient_container_id': BAG}
    save = {'containers': {CID: {'capacity': 10, 'slots': {0: expected}},
                           SOURCE: {'capacity': 10, 'slots': {}}, BAG: {'capacity': 42, 'slots': {}}},
            'models': {MID: {**c, 'hp': 4000, 'completed': True}}}
    return lease, save


def nbt_string(text):
    raw = text.encode('utf-8')
    return struct.pack('>H', len(raw)) + raw


def saved_player(tx, marker=None):
    u = uuid.UUID(tx['mc_uid']).bytes
    uuid_field = b'\x0b' + nbt_string('UUID') + struct.pack('>i', 4) + u
    marker = marker if marker is not None else 'palcraft.exchange.v3:' + tx['id'] + ':debit'
    tags = b'\x09' + nbt_string('Tags') + b'\x08' + struct.pack('>i', 1) + nbt_string(marker)
    return gzip.compress(b'\x0a\0\0' + uuid_field + tags + b'\0', mtime=0)


def mc_fixture(root):
    lease, _ = fixture(direction='credit')
    lease['status'] = 'claimed'
    world = root / 'fixture-world'
    (world / 'playerdata').mkdir(parents=True)
    lease['tx']['mc_world'] = str(world.resolve())
    mc = {**lease['tx'], 'state': 'waiting_pal', 'mc_debit_durable': True}
    player = world / 'playerdata' / (MC + '.dat')
    player.write_bytes(saved_player(lease['tx']))
    return lease, mc, player


class EscrowWitness(unittest.TestCase):
    def test_lease_record_contains_only_the_exact_selected_row(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, save = fixture()
            other = copy.deepcopy(lease); other.update(owner_tx='88888888-8888-4888-8888-888888888888', container_id=BAG, status='claimed'); other['tx']['id'] = other['owner_tx']
            export = {'protocol': 3, 'revision': 11, 'leases': {CID: lease, BAG: other}}
            path, level = root / 'escrow-leases-current.json', root / 'Level.sav'
            path.write_text(json.dumps(export)); level.write_bytes(b'fixture-save')
            w = witness.write_witness(root, path, level, decoder=lambda *_: save, tx_id=TX)
            self.assertEqual(w['lease_record'], lease)
            self.assertNotIn('leases', w['lease_record'])
            lease['save_after_unix'] += 3
            self.assertNotEqual(w['lease_record'], lease)

    def test_combined_current_export_selects_one_transaction(self):
        lease, _ = fixture()
        other = copy.deepcopy(lease)
        other.update(owner_tx='88888888-8888-4888-8888-888888888888', container_id=BAG, status='claimed')
        other['tx']['id'] = other['owner_tx']
        export = {'protocol': 3, 'revision': 5, 'leases': {CID: lease, BAG: other}}
        self.assertEqual(witness.select_current(export, TX), lease)
        self.assertEqual(witness.select_current(export), lease)
        export['leases'][BAG]['status'] = 'full'
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            witness.select_current(export)

    def test_unrelated_current_lease_advancing_does_not_block_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, save = fixture()
            other = copy.deepcopy(lease)
            other.update(owner_tx='88888888-8888-4888-8888-888888888888', container_id=BAG, status='claimed')
            other['tx']['id'] = other['owner_tx']
            export = {'protocol': 3, 'revision': 5, 'leases': {CID: lease, BAG: other}}
            path, level = root / 'escrow-leases-current.json', root / 'Level.sav'
            path.write_text(json.dumps(export)); level.write_bytes(b'fixture-save')
            def unrelated(*_):
                export['revision'] += 1
                export['leases'][BAG]['revision'] += 1
                path.write_text(json.dumps(export))
                return save
            w = witness.write_witness(root, path, level, decoder=unrelated, tx_id=TX)
            self.assertTrue(witness.accept_witness(lease, w))
            self.assertEqual(w['lease_sha256'], witness.lease_digest(lease))

    def test_combined_export_duplicate_or_wrong_container_identity_refused(self):
        lease, _ = fixture()
        with self.assertRaises(ValueError):
            witness.select_current({'protocol': 3, 'revision': 1, 'leases': {BAG: lease}}, TX)
        duplicate = copy.deepcopy(lease); duplicate['container_id'] = BAG
        with self.assertRaises(ValueError):
            witness.select_current({'protocol': 3, 'revision': 1, 'leases': {CID: lease, BAG: duplicate}}, TX)

    def test_source_production_does_not_block_escrow_full_receipt(self):
        lease, save = fixture()
        save['containers'][SOURCE]['slots'][0] = {'count': 999, 'item': 'Wood'}
        self.assertEqual(witness.verify_snapshot(lease, save, 'full')['actual']['count'], 16)

    def test_normal_recipient_moves_allow_empty_same_level_receipt(self):
        lease, save = fixture('empty', 'credit')
        save['containers'][BAG]['slots'][31] = {'count': 44, 'item': 'Coal'}
        self.assertEqual(witness.verify_snapshot(lease, save, 'empty')['actual']['count'], 0)

    def test_missing_source_or_bag_requires_additional_atomicity_proof(self):
        for stage, direction, cid in [('full', 'debit', SOURCE), ('empty', 'credit', BAG)]:
            lease, save = fixture(stage, direction)
            del save['containers'][cid]
            with self.assertRaises(ValueError):
                witness.verify_snapshot(lease, save, stage)

    def test_damage_destroy_rebind_move_and_foreign_item_refused(self):
        cases = ['destroy', 'hp', 'complete', 'rebind', 'position', 'count', 'item', 'dynamic', 'other_slot', 'capacity']
        for case in cases:
            with self.subTest(case=case):
                lease, save = fixture()
                if case == 'destroy': del save['models'][MID]
                elif case == 'hp': save['models'][MID]['hp'] = 0
                elif case == 'complete': save['models'][MID]['completed'] = False
                elif case == 'rebind': save['models'][MID]['container_id'] = SOURCE
                elif case == 'position': save['models'][MID]['position'] = {'x': 100001., 'y': 0., 'z': 100.}
                elif case == 'capacity': save['containers'][CID]['capacity'] = 24
                elif case == 'other_slot': save['containers'][CID]['slots'][1] = {'count': 1}
                else:
                    save['containers'][CID]['slots'][0] = copy.deepcopy(lease['expected_after'])
                    key = {'count': 'count', 'item': 'item', 'dynamic': 'dynamic_guid'}[case]
                    save['containers'][CID]['slots'][0][key] = 17 if case == 'count' else SOURCE
                with self.assertRaises((ValueError, KeyError)):
                    witness.verify_snapshot(lease, save, 'full')

    def test_v2_or_unobserved_effect_cannot_receive_witness(self):
        lease, save = fixture()
        lease['tx']['protocol'] = 2
        with self.assertRaises(ValueError): witness.verify_snapshot(lease, save, 'full')
        lease, save = fixture()
        lease['operations']['moveIn']['observed'] = False
        with self.assertRaises(ValueError): witness.verify_snapshot(lease, save, 'full')

    def test_late_witness_rejects_released_new_stage_and_new_generation(self):
        lease, _ = fixture()
        w = {**witness.binding(lease, 'full'), 'durable': True, 'same_level_counterpart': True, 'save_sha256': 'c' * 64}
        self.assertTrue(witness.accept_witness(lease, w))
        for change in [('generation', 3), ('status', 'empty'), ('status', 'released'), ('revision', 5)]:
            current = copy.deepcopy(lease)
            current[change[0]] = change[1]
            self.assertFalse(witness.accept_witness(current, w))

    def test_installed_save_witness_and_current_lease_race(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lease, save = fixture()
            lease_path, level = root / 'lease-current.json', root / 'Level.sav'
            lease_path.write_text(json.dumps(lease)); level.write_bytes(b'fixture-save')
            w = witness.write_witness(root, lease_path, level, decoder=lambda *_: save)
            self.assertEqual(w['save_sha256'], hashlib.sha256(b'fixture-save').hexdigest())
            self.assertTrue(witness.accept_witness(lease, w))
            def changed(*_):
                lease_path.write_text(json.dumps({**lease, 'status': 'released'}))
                return save
            with self.assertRaisesRegex(ValueError, 'advanced/released'):
                witness.write_witness(root, lease_path, level, decoder=changed)

    def test_save_replaced_during_parse_and_predating_barrier_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, save = fixture()
            lease_path, level = root / 'lease-current.json', root / 'Level.sav'
            lease_path.write_text(json.dumps(lease)); level.write_bytes(b'old')
            def replaced(*_):
                level.write_bytes(b'new'); return save
            with self.assertRaisesRegex(ValueError, 'changed during'):
                witness.write_witness(root, lease_path, level, decoder=replaced)
            lease['save_after_unix'] = level.stat().st_mtime + 100
            lease_path.write_text(json.dumps(lease))
            with self.assertRaisesRegex(ValueError, 'predates'):
                witness.write_witness(root, lease_path, level, decoder=lambda *_: save)

    def test_real_historical_serial_chest_model_container_identity(self):
        path = BASE / 'work/palworld-live/lab/serial-chest-after-Level.sav'
        save = witness.decode_save(path.read_bytes(), BASE / 'work/palworld-save-toolkit/python/vendor')
        self.assertEqual(save['models'][MID]['container_id'], CID)
        self.assertEqual(save['containers'][CID]['capacity'], 10)
        self.assertEqual(save['containers'][CID]['slots'][0]['count'], 17)
        self.assertEqual(save['models'][MID]['build_player_uid'], '22222222-0000-0000-0000-000000000000')
        # These historical contents prove the chest is real, never prove isolation.
        self.assertEqual(len(save['containers']), 1404)


class EscrowPermit(unittest.TestCase):
    def test_real_nbt_tag_creates_one_bound_permit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, mc, player = mc_fixture(root)
            request = credit.native_request_id(lease, 'credit')
            out = credit.prepare_permit(root, lease, mc, player, request)
            path = Path(out['permit_path'])
            self.assertEqual(len(path.read_bytes()), 128)
            self.assertEqual(path.read_bytes()[:16], credit.guid(request))
            self.assertEqual(credit.prepare_permit(root, lease, mc, player, request), out)
            path.rename(path.with_name(path.name.replace('.permit.bin', '.claimed.bin')))
            with self.assertRaisesRegex(ValueError, 'already claimed'):
                credit.prepare_permit(root, lease, mc, player, request)

    def test_flags_without_actual_saved_debit_tag_do_not_authorize_credit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, mc, player = mc_fixture(root)
            player.write_bytes(saved_player(lease['tx'], 'palcraft.exchange.v2:' + TX + ':debit'))
            with self.assertRaisesRegex(ValueError, 'Actual atomic'):
                credit.prepare_permit(root, lease, mc, player, credit.native_request_id(lease, 'credit'))
            self.assertFalse(list(root.glob('*.permit.bin')))

    def test_identity_changed_and_v2_terminal_never_create_v3_permit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, mc, player = mc_fixture(root)
            for key, value in [('protocol', 2), ('count', 17), ('player_uid', BAG), ('mc_debit_durable', False), ('state', 'completed')]:
                changed = {**mc, key: value}
                with self.assertRaises(ValueError):
                    credit.prepare_permit(root, lease, changed, player, credit.native_request_id(lease, 'credit'))

    def test_new_lease_generation_and_operation_use_distinct_request_ids(self):
        lease, _ = fixture()
        request = credit.native_request_id(lease, 'credit')
        self.assertNotEqual(credit.native_request_id(lease, 'dispose'), request)
        lease['generation'] += 1
        self.assertNotEqual(credit.native_request_id(lease, 'credit'), request)
        first_attempt = credit.native_request_id(lease, 'credit', 1)
        self.assertNotEqual(credit.native_request_id(lease, 'credit', 2), first_attempt)
        lease['next_attempt'] = {'credit': 2}
        self.assertEqual(credit.native_request_id(lease, 'credit'), credit.native_request_id(lease, 'credit', 2))

    def test_partial_existing_permit_is_held_and_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, mc, player = mc_fixture(root)
            request = credit.native_request_id(lease, 'credit')
            path = root / ('escrow-credit-' + request.replace('-', '') + '.permit.bin'); path.write_bytes(b'partial')
            with self.assertRaisesRegex(ValueError, 'differs'):
                credit.prepare_permit(root, lease, mc, player, request)
            self.assertEqual(path.read_bytes(), b'partial')

    def test_actual_tag_from_another_mc_world_does_not_authorize_credit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); lease, mc, player = mc_fixture(root)
            other = root / 'other-world/playerdata'; other.mkdir(parents=True)
            duplicate = other / player.name; duplicate.write_bytes(player.read_bytes())
            with self.assertRaisesRegex(ValueError, 'another world'):
                credit.prepare_permit(root, lease, mc, duplicate, credit.native_request_id(lease, 'credit'))


class EscrowRehydration(unittest.TestCase):
    def setup_checkpoint(self, root, operation='moveIn'):
        lease, save = fixture(direction='credit' if operation in {'credit', 'deliver'} else 'debit')
        empty = {'container_id': CID, 'slot': 0, 'count': 0, 'item': ''}
        before = empty if operation in {'moveIn', 'credit'} else copy.deepcopy(lease['expected_after'])
        source = {'container_id': SOURCE, 'slot': 0, 'count': 50, 'item': 'Wood', 'dynamic_world': witness.ZERO, 'dynamic_guid': witness.ZERO}
        target = {'container_id': BAG, 'slot': 0, 'count': 0, 'item': ''}
        lease['status'] = 'needs_recovery'
        lease['operations'] = {operation: {'attempted': True, 'observed': False, 'attempt': 1, 'attempted_unix': 1002,
             'request_id': '66666666-6666-4666-8666-000000000001', 'boot_id': 'aaaaaaaa-aaaa-4aaa-8aaa-000000000001', 'epoch': 'old',
             'before': before, 'expected_after': copy.deepcopy(lease['expected_after']),
             'details': [{'before': source, 'n': 16}] if operation == 'moveIn' else {'to': target, 'n': 16} if operation == 'deliver' else {}}}
        save['containers'][CID]['slots'][0] = copy.deepcopy(before)
        save['containers'][SOURCE]['slots'][0] = source
        level = root / 'Level.sav'; level.write_bytes(b'complete-world-checkpoint-before-attempt')
        os.utime(level, ns=(1000000000000, 1000000000000))
        certificate = {'protocol': 3, 'kind': 'palworld_full_world_rehydration', 'full_world_rehydrated': True,
          'boot_id': 'aaaaaaaa-aaaa-4aaa-8aaa-000000000002', 'epoch': 'new', 'pid': 9876,
          'process_created_unix': 1004, 'loaded_unix': 1005, 'installed_level_path': str(level.resolve()),
          'checkpoint_mtime_ns': level.stat().st_mtime_ns, 'loaded_level_sha256': hashlib.sha256(level.read_bytes()).hexdigest()}
        return lease, save, level, certificate

    def test_exact_installed_pre_attempt_checkpoint_and_trusted_new_boot_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            for op in ['moveIn', 'credit', 'dispose', 'deliver']:
                root = Path(directory) / op; root.mkdir()
                lease, save, level, cert = self.setup_checkpoint(root, op)
                proof = rehydrate.make_rearm_proof(lease, op, level, cert, lambda c: c == cert, decoder=lambda *_: save)
                self.assertEqual(proof['saved_before'], lease['operations'][op]['before'])
                self.assertEqual(proof['boot_certificate_sha256'], rehydrate.canonical_sha(cert))
                self.assertEqual(proof['previous_attempt'], 1)
                self.assertEqual(proof['lease_generation'], lease['generation'])

    def test_self_asserted_flags_without_lifecycle_verifier_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            lease, save, level, cert = self.setup_checkpoint(Path(directory))
            for verifier in [None, lambda _: False]:
                with self.assertRaisesRegex(ValueError, 'Trusted lifecycle'):
                    rehydrate.make_rearm_proof(lease, 'moveIn', level, cert, verifier, decoder=lambda *_: save)

    def test_observed_but_unwitnessed_effect_and_durable_witness_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            lease, save, level, cert = self.setup_checkpoint(Path(directory), 'credit')
            lease['status'] = 'full'; lease['operations']['credit']['observed'] = True
            proof = rehydrate.make_rearm_proof(lease, 'credit', level, cert, lambda _: True, decoder=lambda *_: save)
            self.assertTrue(proof['previous_observed'])
            lease['full_witness'] = {'durable': True}
            with self.assertRaisesRegex(ValueError, 'witnessed native'):
                rehydrate.make_rearm_proof(lease, 'credit', level, cert, lambda _: True, decoder=lambda *_: save)

    def test_same_boot_wrong_epoch_hash_path_or_process_age_cannot_rearm(self):
        with tempfile.TemporaryDirectory() as directory:
            lease, save, level, cert = self.setup_checkpoint(Path(directory))
            for key, value in [('boot_id', lease['operations']['moveIn']['boot_id']), ('epoch', 'old'),
                               ('loaded_level_sha256', 'c' * 64), ('installed_level_path', str(level.with_name('backup.sav'))),
                               ('process_created_unix', 1001), ('full_world_rehydrated', False), ('checkpoint_mtime_ns', 1001000000000)]:
                with self.subTest(key=key), self.assertRaises(ValueError):
                    rehydrate.make_rearm_proof(lease, 'moveIn', level, {**cert, key: value}, lambda _: True, decoder=lambda *_: save)

    def test_persisted_afterimage_partial_effect_or_saved_source_difference_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            lease, save, level, cert = self.setup_checkpoint(Path(directory))
            for slot_id, count in [(CID, 16), (CID, 8), (SOURCE, 34), (SOURCE, 51)]:
                changed = copy.deepcopy(save)
                if slot_id == CID:
                    changed['containers'][CID]['slots'][0] = {**lease['expected_after'], 'count': count}
                else:
                    changed['containers'][SOURCE]['slots'][0]['count'] = count
                with self.subTest(cid=slot_id, count=count), self.assertRaises(ValueError):
                    rehydrate.make_rearm_proof(lease, 'moveIn', level, cert, lambda _: True, decoder=lambda *_: changed)

    def test_save_replaced_during_proof_decode_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            lease, save, level, cert = self.setup_checkpoint(Path(directory))
            def changed(*_):
                level.write_bytes(b'post-restart-save'); return save
            with self.assertRaisesRegex(ValueError, 'changed during'):
                rehydrate.make_rearm_proof(lease, 'moveIn', level, cert, lambda _: True, decoder=changed)


class EscrowDurableIO(unittest.TestCase):
    def test_posix_force_reads_identical_bytes_and_enforces_explicit_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source'; path.write_bytes(b'unchanged')
            before = path.stat().st_mtime_ns
            self.assertEqual(durable_io.read_and_force(path), b'unchanged')
            with self.assertRaises(ValueError): durable_io.read_and_force(path, 2)
            self.assertEqual(path.read_bytes(), b'unchanged')
            self.assertEqual(path.stat().st_mtime_ns, before)

    def test_windows_existing_shared_handle_has_write_right_and_never_writes_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source'; path.write_bytes(b'windows-snapshot')
            before = path.stat().st_mtime_ns
            calls = []
            class Function:
                def __init__(self, fn): self.fn = fn
                def __call__(self, *args): return self.fn(*args)
            def create(name, access, share, _, disposition, flags, template):
                calls.append((access, share, disposition, flags))
                return os.open(name, os.O_RDWR)
            class API:
                CreateFileW = Function(create)
                CloseHandle = Function(lambda fd: os.close(fd))
            class CRT:
                @staticmethod
                def open_osfhandle(handle, flags):
                    self.assertEqual(flags & os.O_RDWR, os.O_RDWR)
                    return handle
            fd = durable_io._windows_fd(path, API(), CRT())
            with mock.patch.object(durable_io, '_windows_fd', return_value=fd):
                self.assertEqual(durable_io.read_and_force(path, system='nt'), b'windows-snapshot')
            self.assertEqual(calls, [(0xc0000000, 7, 3, 0x80)])
            self.assertEqual(path.read_bytes(), b'windows-snapshot')
            self.assertEqual(path.stat().st_mtime_ns, before)


if __name__ == '__main__':
    unittest.main()
