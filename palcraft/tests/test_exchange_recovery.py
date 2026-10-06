#!/usr/bin/env python3
"""Exercise actual Lua recovery in separate killed processes and the real save witness parser."""
import copy
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

BASE = Path(__file__).resolve().parents[4]
FUSION = BASE / "work/minecraft-fusion"
SOURCE = FUSION / "palcraft/server/exchange.lua"
CODEC = BASE / "work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua"
READERS = CODEC.with_name("readers.lua")
LUA = BASE / "work/palworld-live/research/lua-5.4.8/src/lua"
WORKER = Path(__file__).with_name("exchange_lua_worker.lua")
spec = importlib.util.spec_from_file_location("recovery", FUSION / "palcraft/mcp/exchange_recovery.py")
recovery = importlib.util.module_from_spec(spec); spec.loader.exec_module(recovery)
ZERO = "00000000-0000-0000-0000-000000000000"
MC = "11111111-1111-1111-1111-111111111111"
PAL = "00000000-0000-0000-0000-000000000001"
VENDOR = BASE / "work/palworld-save-toolkit/python/vendor"


def write(path, value):
    recovery.atomic_write(path, value)


def fixture(root, action="debit", count=16):
    root.mkdir(parents=True, exist_ok=True)
    q = {"protocol": 2, "id": str(uuid.uuid4()), "mc_uid": MC, "player_uid": PAL, "mc_world": "fixture-world",
         "item": "Wood", "count": count, "action": action}
    q["fingerprint"] = hashlib.sha256(json.dumps([q[k] for k in recovery.IDENTITY[:-1]], separators=(",", ":")).encode()).hexdigest()
    write(root / "players.json", {MC: PAL}); write(root / "request.json", q)
    write(root / f'mc-{q["id"]}.json', {**q, "state": "waiting_pal", "to_mc": action == "debit", "mc_debit_durable": action == "credit"})
    state = {"calls": {}, "containers": [
        {"id": "11111111-1111-1111-1111-111111111111", "slots": [{"item": "Wood", "count": 10}, {"item": "None", "count": 0}]},
        {"id": "22222222-2222-2222-2222-222222222222", "slots": [{"item": "Wood", "count": 10}, {"item": "None", "count": 0}]}]}
    write(root / "fixture-inventory.json", state)
    return q


def child(root, point="none", expected=0):
    run = subprocess.run([str(LUA), str(WORKER), str(root) + os.sep, str(SOURCE), str(CODEC), str(READERS), point], capture_output=True, text=True)
    if run.returncode != expected:
        raise AssertionError(f"Lua exited {run.returncode}, expected {expected}: {run.stderr} {run.stdout[-500:]}")
    return recovery.read(root / "fixture-result.json") if expected == 0 else None


def latest(root, q):
    return recovery.pal_records(root)[q["id"]][0]


def fake_witness(root, q):
    row = latest(root, q)
    state = recovery.read(root / "fixture-saved.json")
    saved = {}
    for container in state["containers"]:
        slots = {}
        for i, slot in enumerate(container["slots"]):
            ref = {"container_id": container["id"], "slot": i, "count": slot["count"], "item": slot["item"] if slot["count"] else ""}
            if slot["count"]:
                ref.update(dynamic_guid=ZERO, dynamic_world=ZERO)
            slots[i] = ref
        saved[container["id"]] = (len(slots), slots)
    recovery.verify_after(row, saved)
    write(root / f'witness-{q["id"]}.json', {"protocol": 2, "id": q["id"], "fingerprint": q["fingerprint"],
          "pal_revision": row["revision"], "durable": True, "expected_after": row["expected_after"], "save_sha256": "f" * 64})


class LuaRecovery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="palcraft-exchange-")
        self.root = Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()

    def test_safe_boundaries_resume_without_repeating_native_calls(self):
        cases = [("debit", 16, "wal:begin"), ("debit", 16, "wal:prepared"), ("debit", 16, "observed:debit:1"),
                 ("debit", 16, "observed:debit:2"), ("debit", 16, "wal:awaiting_pal_save"),
                 ("credit", 8, "wal:prepared"), ("credit", 8, "wal:awaiting_pal_save")]
        for index, (action, count, point) in enumerate(cases):
            with self.subTest(action=action, point=point):
                root = self.root / str(index); q = fixture(root, action, count)
                child(root, point, 91); out = child(root)
                self.assertEqual(out["status"], "awaiting_pal_save")
                self.assertFalse(out["ok"])
                fake_witness(root, q); self.assertEqual(child(root)["status"], "completed")
                for _ in range(4): self.assertEqual(child(root)["status"], "completed")
                state = recovery.read(root / "fixture-inventory.json")
                self.assertEqual(state["calls"].get(action), 2 if action == "debit" else 1)
                total = sum(s["count"] for c in state["containers"] for s in c["slots"])
                self.assertEqual(total, 20 - count if action == "debit" else 20 + count)

    def test_ambiguous_native_intents_are_visible_and_never_replayed(self):
        cases = [("debit", 16, "wal:applying", 0), ("debit", 16, "native:debit:1", 1), ("debit", 16, "native:debit:2", 2),
                 ("credit", 8, "wal:applying", 0), ("credit", 8, "native:credit", 1)]
        for index, (action, count, point, calls) in enumerate(cases):
            with self.subTest(point=point, action=action):
                root = self.root / str(index); q = fixture(root, action, count)
                child(root, point, 91)
                for _ in range(5):
                    out = child(root); self.assertEqual(out["status"], "needs_recovery"); self.assertIn("error", out)
                state = recovery.read(root / "fixture-inventory.json")
                self.assertEqual(state["calls"].get(action, 0), calls)
                self.assertTrue(latest(root, q)["effect_attempted"])
                self.assertTrue(recovery.status(root)["transactions"][0]["manual_audit_required"])
                with self.assertRaises(ValueError): recovery.verify_after(latest(root, q), {})

    def test_completed_wal_before_lock_release_is_recovered(self):
        q = fixture(self.root); child(self.root); fake_witness(self.root, q)
        child(self.root, "wal:completed", 91)
        # Same completed ID remains idempotent after a fresh Lua process.
        self.assertEqual(child(self.root)["status"], "completed")
        active = sorted(self.root.glob("pal-active.r*.json"))
        self.assertEqual(recovery.read(active[-1])["event"], "end")

    def test_wrong_witness_identity_or_revision_does_not_release_items(self):
        q = fixture(self.root); child(self.root); fake_witness(self.root, q)
        path = self.root / f'witness-{q["id"]}.json'; witness = recovery.read(path)
        for key, wrong in [("id", str(uuid.uuid4())), ("fingerprint", "0" * 64), ("pal_revision", 999), ("expected_after", [])]:
            bad = copy.deepcopy(witness); bad[key] = wrong; write(path, bad)
            self.assertEqual(child(self.root)["status"], "awaiting_pal_save")
        write(path, witness); self.assertTrue(child(self.root)["ok"])
        self.assertEqual(recovery.read(self.root / "fixture-inventory.json")["calls"]["debit"], 2)

    def test_payload_reuse_and_missing_mc_source_intent_are_refused(self):
        q = fixture(self.root); child(self.root)
        changed = {**q, "count": 1}; write(self.root / "request.json", changed); child(self.root, expected=2)
        self.assertEqual(recovery.read(self.root / "fixture-inventory.json")["calls"]["debit"], 2)
        other = self.root / "other"; q2 = fixture(other, "credit", 8)
        (other / f'mc-{q2["id"]}.json').unlink(); child(other, expected=2)
        self.assertEqual(recovery.read(other / "fixture-inventory.json")["calls"], {})

    def test_truncated_revision_fails_closed(self):
        q = fixture(self.root); child(self.root)
        last = sorted(self.root.glob(f'pal-{q["id"]}.r*.json'))[-1]; last.write_text("{partial", encoding="utf-8")
        child(self.root, expected=2)
        self.assertEqual(recovery.read(self.root / "fixture-inventory.json")["calls"]["debit"], 2)
        with self.assertRaises(json.JSONDecodeError): recovery.pal_records(self.root)

    def test_concurrent_production_and_bag_moves_hold_then_normal_moves_recover(self):
        for action, count in [("debit", 16), ("credit", 8)]:
            with self.subTest(action=action):
                root = self.root / action; q = fixture(root, action, count); child(root)
                state = recovery.read(root / "fixture-inventory.json")
                if action == "debit":
                    state["containers"][1]["slots"][0]["count"] += 3  # Legitimate production into the affected base slot.
                else:
                    bag = state["containers"][0]["slots"]
                    bag[0]["count"] -= 4; bag[1] = {"count": 4, "item": "Wood"}  # Normal bag move.
                write(root / "fixture-inventory.json", state); write(root / "fixture-saved.json", state)
                total = sum(s["count"] for c in state["containers"] for s in c["slots"])
                with self.assertRaises(ValueError): fake_witness(root, q)
                for _ in range(3): self.assertEqual(child(root)["status"], "awaiting_pal_save")
                row = latest(root, q)
                write(root / f'witness-blocked-{q["id"]}.json', {"pal_revision": row["revision"], "fingerprint": row["fingerprint"], "needs_inventory_audit": True})
                out = child(root); self.assertTrue(out["recovery_required"])
                # Restore affected slots by moving existing material; preserve every extra/credited item.
                if action == "debit":
                    chest = state["containers"][1]["slots"]
                    chest[0]["count"] -= 3; chest[1] = {"count": 3, "item": "Wood"}
                else:
                    bag = state["containers"][0]["slots"]
                    bag[0]["count"] += bag[1]["count"]; bag[1] = {"count": 0, "item": "None"}
                self.assertEqual(sum(s["count"] for c in state["containers"] for s in c["slots"]), total)
                write(root / "fixture-inventory.json", state); write(root / "fixture-saved.json", state)
                fake_witness(root, q); self.assertEqual(child(root)["status"], "completed")
                self.assertEqual(recovery.read(root / "fixture-inventory.json")["calls"].get(action), 2 if action == "debit" else 1)


class SavedWitness(unittest.TestCase):
    def test_actual_plm_save_sparse_slots_and_cached_decode(self):
        existing = BASE / "work/palworld-live/lab/wood-move-saved.sav"
        data = existing.read_bytes(); started = time.perf_counter(); cpu = time.process_time()
        saved = recovery.load_saved_slots(data, VENDOR)
        print(json.dumps({"real_save": existing.name, "containers": len(saved), "wall_seconds": round(time.perf_counter() - started, 4),
                          "cpu_seconds": round(time.process_time() - cpu, 4), "peak_rss_bytes": recovery.peak_rss_bytes(), "save_bytes": len(data)}))
        self.assertGreater(len(saved), 1000)
        ref = next(ref for _, slots in saved.values() for ref in slots.values() if ref["count"] > 0 and ref["item"] == "Wood")
        with tempfile.TemporaryDirectory(prefix="palcraft-witness-") as temp:
            root = Path(temp); q = fixture(root)
            row = {**q, "status": "awaiting_pal_save", "effect_observed": True, "revision": 1,
                   "updated_unix": int(time.time()) - 2, "save_after_unix": int(time.time()) - 1, "expected_after": [ref]}
            journal = root / f'pal-{q["id"]}.r000001.json'; write(journal, row)
            level = root / "Level.sav"; level.write_bytes(data)
            runner = recovery.WitnessRunner(root, level, VENDOR)
            self.assertEqual(runner.tick()["written"], [q["id"]]); self.assertEqual(runner.decode_count, 1)
            for _ in range(5): self.assertEqual(runner.tick()["written"], [q["id"]])
            self.assertEqual(runner.decode_count, 1, "Unchanged save was decoded every poll")
            witness = root / f'witness-{q["id"]}.json'; witness.unlink()
            self.assertEqual(runner.tick()["written"], [q["id"]]); self.assertEqual(runner.decode_count, 1)
            bad = copy.deepcopy(row); bad["expected_after"][0]["count"] += 1; write(journal, bad); witness.unlink()
            self.assertFalse(runner.tick()["written"]); self.assertEqual(runner.decode_count, 1)
            bad["effect_observed"] = False
            with self.assertRaises(ValueError): recovery.verify_after(bad, saved)
            bad["effect_observed"] = True; bad["save_after_unix"] = int(time.time()) + 30; write(journal, bad)
            calls = []; runner.save = lambda: calls.append(True)
            runner.tick(); self.assertFalse(calls, "Save requested before material barrier")



# v3 focused contract cases reuse the existing child process fixture. They prove
# coordinator/escrow wiring, not live native produce or Windows power-loss safety.
sys.path.insert(0, str(FUSION / "palcraft/mcp"))
import escrow_witness
import exchange_v3


def fixture_v3(root, action="debit", count=8):
    q = fixture(root, action, count)
    q["protocol"] = 3
    q["fingerprint"] = hashlib.sha256(json.dumps([q[k] for k in recovery.IDENTITY[:-1]], separators=(",", ":")).encode()).hexdigest()
    write(root / "request.json", q)
    mc = {**q, "state": "waiting_pal", "to_mc": action == "debit", "mc_debit_durable": action == "credit"}
    c = {"container_id": "33333333-3333-3333-3333-333333333333", "model_id": "44444444-4444-4444-4444-444444444444",
         "concrete_id": "00000000-0000-4000-8000-00000000001b", "guild_id": "66666666-6666-6666-6666-666666666666",
         "base_id": ZERO, "source_base_id": "77777777-7777-7777-7777-777777777777", "type": "ItemChest", "capacity": 3,
         "position": {"x": 20000, "y": 20000, "z": 0}, "enrollment_save_sha256": "1" * 64}
    state = recovery.read(root / "fixture-inventory.json")
    state["candidate"] = c
    state["containers"].append({"id": c["container_id"], "slots": [{"item": "", "count": 0} for _ in range(3)]})
    write(root / "fixture-inventory.json", state)
    if action == "credit":
        mc["mc_debit_receipt"] = mock_mc_receipt(q, "debit")
    write(root / f'mc-{q["id"]}.json', mc)
    return q


def mock_mc_receipt(q, leg):
    return {**{k: q[k] for k in ("protocol", "id", "fingerprint", "mc_uid", "mc_world")}, "leg": leg,
            "marker": f'palcraft.exchange.v3:{q["id"]}:{leg}', "player_data": "fixture-only", "saved_player_sha256": "9" * 64}


def v3_lease(root):
    export = recovery.read(root / 'escrow-leases-current.json')
    return next(iter(export['leases'].values()))


def mock_mc_proof(root, q, leg):
    lease = v3_lease(root)
    mc = recovery.read(root / f'mc-{q["id"]}.json')
    mc[f'mc_{leg}_durable'] = True
    mc[f'mc_{leg}_receipt'] = mock_mc_receipt(q, leg)
    mc['state'] = 'waiting_pal_cleanup' if leg == 'credit' else 'waiting_pal'
    write(root / f'mc-{q["id"]}.json', mc)
    proof = {"protocol": 3, "id": q['id'], "fingerprint": q['fingerprint'], "lease_generation": lease['generation'],
             "leg": leg, "durable": True, "mc_receipt": mc[f'mc_{leg}_receipt']}
    write(root / f'escrow-mc-{leg}-proof-{q["id"]}-g{lease["generation"]}.json', proof)
    if leg == 'debit':
        write(root / f'escrow-credit-proof-{q["id"]}-g{lease["generation"]}-a1.json',
              {"native_request_id": exchange_v3.native_request_id(lease, 'credit'), "lease_generation": lease['generation'], "mc_receipt_sha256": 'a' * 64})


def fixture_saved_v3(root):
    lease = v3_lease(root)
    state = recovery.read(root / 'fixture-inventory.json')
    saved = {'containers': {}, 'models': {lease['candidate']['model_id']: {**lease['candidate'], 'hp': 100, 'completed': True}}}
    for container in state['containers']:
        slots = {}
        for index, slot in enumerate(container['slots']):
            ref = {'container_id': container['id'], 'slot': index, 'count': slot['count'], 'item': slot['item'] if slot['count'] else ''}
            if slot['count']:
                ref.update(dynamic_world=ZERO, dynamic_guid=ZERO)
            slots[index] = ref
        saved['containers'][container['id']] = {'capacity': len(slots), 'slots': slots}
    return saved


def fixture_witness_v3(root):
    lease = v3_lease(root)
    saved = fixture_saved_v3(root)
    level = root / 'Level.sav'
    level.write_bytes(json.dumps(recovery.read(root / 'fixture-inventory.json')).encode())
    os.utime(level, (time.time() + 3, time.time() + 3))
    w = escrow_witness.write_witness(root, root / 'escrow-leases-current.json', level,
                                   decoder=lambda data, vendor: saved, tx_id=lease['owner_tx'])
    return exchange_v3.publish_bound_witness(root, root / 'escrow-leases-current.json', lease, w)


def complete_mc_v3(root, q):
    mc = recovery.read(root / f'mc-{q["id"]}.json')
    mc.update(state='completed', escrow_empty_durable=True, lease_generation=v3_lease(root)['generation'])
    write(root / f'mc-{q["id"]}.json', mc)


class V3Wiring(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-v3-')
        self.root = Path(self.temp.name)
    def tearDown(self):
        self.temp.cleanup()

    def test_import_two_saved_phases_allow_source_production(self):
        q = fixture_v3(self.root)
        self.assertEqual(child(self.root)['status'], 'full')
        state = recovery.read(self.root / 'fixture-inventory.json')
        state['containers'][1]['slots'][0]['count'] += 3  # normal base production after Move
        write(self.root / 'fixture-inventory.json', state)
        fixture_witness_v3(self.root)
        self.assertEqual(child(self.root)['status'], 'full_saved')
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {'move': 1})
        mock_mc_proof(self.root, q, 'credit')
        self.assertEqual(child(self.root)['status'], 'empty')
        fixture_witness_v3(self.root)
        self.assertEqual(child(self.root)['status'], 'empty_saved')
        complete_mc_v3(self.root, q)
        self.assertEqual(child(self.root)['status'], 'completed')
        self.assertEqual(child(self.root)['status'], 'completed')
        state = recovery.read(self.root / 'fixture-inventory.json')
        self.assertEqual(state['calls'], {'move': 1, 'dispose': 1})
        self.assertEqual(sum(s['count'] for c in state['containers'] for s in c['slots']), 15)

    def test_export_saved_debit_and_empty_phase_allow_bag_moves(self):
        q = fixture_v3(self.root, 'credit')
        self.assertEqual(child(self.root)['status'], 'claimed')
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {})
        mock_mc_proof(self.root, q, 'debit')
        self.assertEqual(child(self.root)['status'], 'full')
        fixture_witness_v3(self.root)
        self.assertEqual(child(self.root)['status'], 'empty')
        state = recovery.read(self.root / 'fixture-inventory.json')
        state['containers'][0]['slots'][0], state['containers'][0]['slots'][1] = state['containers'][0]['slots'][1], state['containers'][0]['slots'][0]
        write(self.root / 'fixture-inventory.json', state)
        fixture_witness_v3(self.root)
        self.assertEqual(child(self.root)['status'], 'empty_saved')
        complete_mc_v3(self.root, q)
        self.assertEqual(child(self.root)['status'], 'completed')
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {'produce': 1, 'move': 1})

    def test_existing_worker_creates_permit_from_actual_saved_nbt(self):
        q = fixture_v3(self.root, 'credit')
        world = self.root / 'actual-fixture-world'; (world / 'playerdata').mkdir(parents=True)
        q['mc_world'] = str(world.resolve())
        q['fingerprint'] = hashlib.sha256(json.dumps([q[k] for k in recovery.IDENTITY[:-1]], separators=(",", ":")).encode()).hexdigest()
        write(self.root / 'request.json', q)
        spec = importlib.util.spec_from_file_location('escrow_fixture_helpers', FUSION / 'escrow-storage/test_escrow.py')
        helpers = importlib.util.module_from_spec(spec); spec.loader.exec_module(helpers)
        data = helpers.saved_player(q); player = world / 'playerdata' / (q['mc_uid'] + '.dat'); player.write_bytes(data)
        receipt = mock_mc_receipt(q, 'debit'); receipt.update(player_data=str(player), saved_player_sha256=hashlib.sha256(data).hexdigest())
        write(self.root / f'mc-{q["id"]}.json', {**q, 'state': 'waiting_pal', 'to_mc': False, 'mc_debit_durable': True, 'mc_debit_receipt': receipt})
        self.assertEqual(child(self.root)['status'], 'claimed')
        rpc = self.root / 'rpc'; rpc.mkdir()
        runner = recovery.WitnessRunner(self.root, self.root / 'Level.sav', rpc_root=rpc)
        result = runner.tick(); self.assertEqual(result['held'], [])
        permits = list(rpc.glob('*.permit.bin')); self.assertEqual(len(permits), 1); self.assertEqual(permits[0].stat().st_size, 128)
        proof = recovery.read(self.root / f'escrow-mc-debit-proof-{q["id"]}-g1.json')
        self.assertEqual(proof['mc_receipt_sha256'], hashlib.sha256(data).hexdigest())
        self.assertEqual(proof['mc_receipt'], receipt)
        self.assertEqual(child(self.root)['status'], 'full')
        self.assertEqual(recovery.status(self.root)['protocol'], 3)
        # The credit proof checks the actual UUID/world/credit tag as well.
        player.write_bytes(helpers.saved_player(q, f'palcraft.exchange.v3:{q["id"]}:credit'))
        with patch.object(exchange_v3, 'read_and_force', wraps=exchange_v3.read_and_force) as force:
            self.assertEqual(exchange_v3.read_saved_leg(player, q, 'credit')['saved_player_uid'], q['mc_uid'])
            force.assert_called_once_with(player, 16 * 1024 * 1024)
        with self.assertRaisesRegex(ValueError, 'receipt missing'):
            exchange_v3.read_saved_leg(player, q, 'refund')

    def test_lost_move_response_reconciles_exclusive_afterimage(self):
        fixture_v3(self.root)
        child(self.root, 'native:move', 91)
        self.assertEqual(child(self.root)['status'], 'full')
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {'move': 1})

    def test_real_rearm_interface_keeps_history_and_uses_new_request(self):
        fixture_v3(self.root)
        state = recovery.read(self.root / 'fixture-inventory.json')
        state.update(epoch='fixture-boot-1', boot_id='00000000-0000-0000-0000-000000000009')
        write(self.root / 'fixture-inventory.json', state)
        child(self.root, 'lease:moving_in', 91)
        lease = v3_lease(self.root); op = lease['operations']['moveIn']
        self.assertEqual(state['calls'], {})
        import escrow_rehydrate
        saved = fixture_saved_v3(self.root)
        level = self.root / 'Level.sav'; level.write_bytes(b'fixture-before-attempt-checkpoint')
        stamp = op['attempted_unix'] - 5; os.utime(level, (stamp, stamp))
        certificate = {'protocol': 3, 'kind': 'palworld_full_world_rehydration', 'runtime_verified': True,
                       'full_world_rehydrated': True, 'boot_id': '00000000-0000-0000-0000-00000000000a',
                       'epoch': 'fixture-boot-2', 'pid': 123, 'process_created_unix': op['attempted_unix'] + 1,
                       'loaded_unix': op['attempted_unix'] + 2, 'installed_level_path': str(level.resolve()),
                       'checkpoint_mtime_ns': level.stat().st_mtime_ns, 'loaded_level_sha256': hashlib.sha256(level.read_bytes()).hexdigest()}
        proof = escrow_rehydrate.make_rearm_proof(lease, 'moveIn', level, certificate,
            lambda value: value == certificate, decoder=lambda data, vendor: saved)
        proof['runtime_fixture'] = True  # fixture-only lifecycle authority injection
        write(self.root / 'escrow-boot-certificate.json', certificate)
        write(self.root / f'escrow-rearm-{lease["owner_tx"]}-g1-moveIn-a1.json', proof)
        state.update(epoch='fixture-boot-2', boot_id=certificate['boot_id']); write(self.root / 'fixture-inventory.json', state)
        self.assertEqual(child(self.root)['status'], 'claimed')
        self.assertEqual(child(self.root)['status'], 'full')
        now = v3_lease(self.root)
        self.assertEqual(now['operations']['moveIn']['attempt'], 2)
        self.assertNotEqual(now['operations']['moveIn']['request_id'], op['request_id'])
        self.assertEqual(now['operation_history']['moveIn'][0], op)
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {'move': 1})

    def test_unforced_cas_cannot_move_material(self):
        fixture_v3(self.root)
        state = recovery.read(self.root / 'fixture-inventory.json'); state['fail_commit'] = 'moving_in'
        write(self.root / 'fixture-inventory.json', state)
        run = subprocess.run([str(LUA), str(WORKER), str(self.root) + os.sep, str(SOURCE), str(CODEC), str(READERS), 'none'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn('durable commit pending', run.stderr)
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {})
        state.pop('fail_commit'); write(self.root / 'fixture-inventory.json', state)
        self.assertEqual(child(self.root)['status'], 'full')
        self.assertEqual(recovery.read(self.root / 'fixture-inventory.json')['calls'], {'move': 1})

    def test_observed_unwitnessed_restore_rearms_before_save(self):
        fixture_v3(self.root)
        state = recovery.read(self.root / 'fixture-inventory.json')
        state.update(epoch='fixture-boot-1', boot_id='00000000-0000-0000-0000-000000000009')
        before = copy.deepcopy(state)
        write(self.root / 'fixture-inventory.json', state)
        self.assertEqual(child(self.root)['status'], 'full')
        lease = v3_lease(self.root); op = lease['operations']['moveIn']
        self.assertTrue(op['observed'])
        self.assertNotIn('full_witness', lease)
        # Only this fixture's checkpoint is restored; the external call ledger
        # retains the one effect that ran and then disappeared on world reload.
        before['calls'] = {'move': 1}
        write(self.root / 'fixture-inventory.json', before)
        saved = fixture_saved_v3(self.root)
        level = self.root / 'Level.sav'; level.write_bytes(b'fixture-observed-before-save-checkpoint')
        stamp = op['attempted_unix'] - 5; os.utime(level, (stamp, stamp))
        certificate = {'protocol': 3, 'kind': 'palworld_full_world_rehydration', 'runtime_verified': True,
                       'full_world_rehydrated': True, 'boot_id': '00000000-0000-0000-0000-00000000000a',
                       'epoch': 'fixture-boot-2', 'pid': 123, 'process_created_unix': op['attempted_unix'] + 1,
                       'loaded_unix': op['attempted_unix'] + 2, 'installed_level_path': str(level.resolve()),
                       'checkpoint_mtime_ns': level.stat().st_mtime_ns, 'loaded_level_sha256': hashlib.sha256(level.read_bytes()).hexdigest()}
        write(self.root / 'escrow-boot-certificate.json', certificate)
        before.update(epoch=certificate['epoch'], boot_id=certificate['boot_id'])
        write(self.root / 'fixture-inventory.json', before)
        (self.root / 'save-request.json').unlink()
        self.assertEqual(child(self.root)['status'], 'full')
        self.assertFalse((self.root / 'save-request.json').exists())
        saves = []
        runner = exchange_v3.Runner(self.root, level, save=lambda: saves.append('save'),
                                   verify_boot=lambda value: value == certificate)
        runner.decoder = lambda data, vendor: saved  # explicitly mocked world loader
        result = runner.tick()
        self.assertTrue(result['held'][0]['rearm_pending'])
        self.assertEqual(saves, [])
        self.assertEqual(level.read_bytes(), b'fixture-observed-before-save-checkpoint')
        self.assertEqual(level.stat().st_mtime_ns, certificate['checkpoint_mtime_ns'])
        proof_path = self.root / f'escrow-rearm-{lease["owner_tx"]}-g1-moveIn-a1.json'
        proof = recovery.read(proof_path)
        self.assertTrue(proof['previous_observed'])
        proof['runtime_fixture'] = True  # fixture-only lifecycle authority injection
        write(proof_path, proof)
        self.assertEqual(child(self.root)['status'], 'claimed')
        self.assertEqual(child(self.root)['status'], 'full')
        now = v3_lease(self.root)
        self.assertEqual(now['operations']['moveIn']['attempt'], 2)
        self.assertNotEqual(now['operations']['moveIn']['request_id'], op['request_id'])
        self.assertEqual(now['operation_history']['moveIn'][0], op)
        state = recovery.read(self.root / 'fixture-inventory.json')
        self.assertEqual(state['calls'], {'move': 2})
        self.assertEqual(sum(slot['count'] for c in state['containers'] for slot in c['slots']), 20)

    def test_watch_cli_passes_real_bootstrap_verifier(self):
        import escrow_bootstrap
        write(self.root / 'request.json', {'protocol': 3, 'id': str(uuid.uuid4())})
        write(self.root / 'escrow-leases-current.json', {'protocol': 3, 'revision': 0, 'leases': {}})
        server_root = Path('D:/PalworldServer-LAN/BridgeLab')
        level = server_root / 'Pal/Saved/SaveGames/0/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/Level.sav'
        created = []
        runner_class = recovery.WitnessRunner
        def capture_runner(*args, **kwargs):
            runner = runner_class(*args, **kwargs)
            created.append(runner)
            return runner
        class WatchChecked(Exception):
            pass
        # Run the actual watch CLI for one idle iteration, using the real factory.
        # Only its timer is interrupted; no certificates, OS evidence or verifier
        # results are faked, and no save/network/game operation is invoked.
        argv = ['exchange_recovery.py', 'witness', '--watch', '--root', str(self.root),
                '--level', str(level), '--pal-server-root', str(server_root)]
        with patch.object(sys, 'argv', argv), \
             patch.object(recovery, 'WitnessRunner', side_effect=capture_runner), \
             patch.object(escrow_bootstrap, 'verifier', wraps=escrow_bootstrap.verifier) as factory, \
             patch.object(recovery.time, 'sleep', side_effect=WatchChecked), \
             patch.object(recovery, 'request_lab_save') as save, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(WatchChecked):
                recovery.main()
            factory.assert_called_once_with(self.root, server_root, level)
            save.assert_not_called()
        self.assertEqual(len(created), 1)
        verifier = created[0].v3.verify_boot
        self.assertIs(verifier, created[0].verify_boot)
        self.assertEqual(verifier.__module__, 'escrow_bootstrap')
        self.assertFalse(verifier({'protocol': 3, 'boot_id': str(uuid.uuid4()),
                                   'runtime_verified': True, 'full_world_rehydrated': True}))

if __name__ == "__main__":
    unittest.main(verbosity=2)
