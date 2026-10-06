"""Offline regression of evidence integrity, conservation and conservative verdicts."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace as Args
import unittest

import acceptance as qa

PLAYER = "11111111-1111-1111-1111-111111111111"
PEER = "00000000-0000-4000-8000-000000000023"


def inspection(count, peer=3, other=2):
    return {"server": {"players": [
        {"uuid": PLAYER, "inventory": [{"slot": 0, "item": "minecraft:oak_button", "count": count},
                                        {"slot": 2, "item": "minecraft:coal", "count": other}]},
        {"uuid": PEER, "inventory": [{"slot": 0, "item": "minecraft:oak_button", "count": peer}]}]}}


def ledger(protocol=1):
    r = {"id": "00000000-0000-4000-8000-000000000023", "player_uid": "pal-uid", "mc_uid": PLAYER,
         "item": "Wood", "mc_item": "minecraft:oak_log", "action": "debit", "count": 8,
         "to_mc": True, "state": "completed", "ok": True, "mc_before": 0, "mc_after": 8}
    r["pal"] = {k: r[k] for k in ("id", "player_uid", "item", "action", "count")}
    r["pal"].update(status="completed", ok=True, before=40, after=32)
    if protocol == 2:
        r.update(protocol=2, mc_world="test-world", fingerprint="f"*64, mc_credit_durable=True)
        keys = ("protocol", "id", "mc_uid", "player_uid", "mc_world", "item", "count", "action")
        r["fingerprint"] = qa.SHA(json.dumps([r[k] for k in keys], separators=(",", ":")).encode())
        for k in ("protocol", "mc_uid", "mc_world", "fingerprint"): r["pal"][k] = r[k]
        r["pal"]["durable"] = True
        r["pal"].update(revision=5, expected_after=[{"slot": 0, "count": 32}])
        r["pal"]["save_witness"] = {"durable": True, "id": r["id"], "fingerprint": r["fingerprint"], "save_sha256": "a"*64,
                                      "pal_revision": 5, "expected_after": r["pal"]["expected_after"]}
    return r


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=qa.HERE)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name); self.bridge = self.base / "bridge"; self.bridge.mkdir()
        self.run = self.base / "run"
        with contextlib.redirect_stdout(io.StringIO()):
            qa.init(Args(run=str(self.run), workspace=str(qa.WORKSPACE), bridge=str(self.bridge), operator="offline_test", fixture=True))
        self.meta = qa.read_json(self.run / "run.json")

    def sample(self, phase, source, payload, age=0):
        if source == "acceptance-probe.ndjson":
            payload.setdefault("session_id", "fixture-session")
            payload.setdefault("state", {}).setdefault("status", "in_bridgelab")
        qa.append(self.run / "samples.ndjson", {"run_id": self.meta["run_id"], "phase": phase, "source": source,
            "payload": payload, "age_s": age, "sha256": qa.SHA(json.dumps(payload).encode()), "captured_utc": qa.utc()})

    def test_matrix_has_all_player_goals_and_no_missing_phase_or_check(self):
        m = qa.matrix(); phases = {p["id"] for p in m["phases"]}
        self.assertEqual(len(m["cases"]), len({c["id"] for c in m["cases"]}))
        self.assertGreaterEqual(len(m["cases"]), 42)
        for c in m["cases"]:
            self.assertTrue(set(c["phases"]) <= phases)
            self.assertTrue(set(c["visual_checks"]) <= set(c["required_checks"]))
            self.assertTrue(set(c["check_sources"]) <= set(c["required_checks"]))
        self.assertTrue({"F06", "P02", "X01", "X02", "X03", "X04", "X05", "R02", "D03"} <= {c["id"] for c in m["cases"]})

    def test_inventory_delta_is_uuid_scoped_and_exact(self):
        self.assertTrue(qa.inventory_delta(inspection(1), inspection(0, peer=4), PLAYER, {"minecraft:oak_button": -1})["passed"])
        self.assertFalse(qa.inventory_delta(inspection(1), inspection(0, other=100), PLAYER, {"minecraft:oak_button": -1})["passed"])
        self.assertFalse(qa.inventory_delta(inspection(1), inspection(1), PLAYER, {"minecraft:oak_button": -1})["passed"])

    def test_names_or_missing_uuid_do_not_authorize_inventory_owner(self):
        with self.assertRaises(ValueError): qa.inventory({"players": [{"name": "PalCraft", "inventory": []}]}, PLAYER)
        duplicate = inspection(1); duplicate["server"]["players"].append(duplicate["server"]["players"][0])
        with self.assertRaises(ValueError): qa.inventory(duplicate, PLAYER)

    def test_legacy_amounts_do_not_prove_durable_recovery(self):
        r = qa.exchange_invariants(ledger())
        self.assertTrue(r["amounts_passed"]); self.assertFalse(r["durability_passed"])

    def test_receipt_identity_mismatch_or_uncertain_pal_save_is_failure(self):
        r = ledger(2); r["pal"]["player_uid"] = "someone-else"
        self.assertFalse(qa.exchange_invariants(r)["amounts_passed"])
        r = ledger(2); r["pal"]["status"] = "awaiting_pal_save"; r["pal"]["durable"] = False
        self.assertFalse(qa.exchange_invariants(r)["durability_passed"])

    def test_protocol2_actual_schema_uses_mc_initial_snapshot(self):
        r = ledger(2); r.pop("mc_before"); r["mc_initial"] = [{"item": "minecraft:oak_log", "count": 0}]
        self.assertTrue(qa.exchange_invariants(r)["durability_passed"])
        r["mc_after"] = 16
        self.assertFalse(qa.exchange_invariants(r)["amounts_passed"])

    def test_collector_handles_partial_json_and_does_not_replay_old_stream(self):
        p = self.bridge / "feedback.json"; p.write_text('{"mode":')
        history = self.bridge / "connection-history.ndjson"; history.write_text('{"phase":"old"}\n')
        c = qa.Collector(self.run, self.meta); c.poll()
        self.assertEqual(qa.rows(self.run / "samples.ndjson"), [])
        p.write_text('{"mode":true}'); c.poll(); c.poll()
        self.assertEqual(len(qa.rows(self.run / "samples.ndjson")), 1)
        with history.open("a") as f: f.write('{"phase":"new"')
        c.poll(); self.assertEqual(len(qa.rows(self.run / "samples.ndjson")), 1)
        with history.open("a") as f: f.write('}\n')
        c.poll(); self.assertEqual(qa.rows(self.run / "samples.ndjson")[-1]["payload"]["phase"], "new")

    def test_stale_swimming_status_never_becomes_a_current_pass(self):
        for _ in range(3): self.sample("solid_contact", "acceptance-probe.ndjson", {"state": {"swimming": False, "movement_mode": 1}}, age=200)
        self.assertEqual(qa.machine_checks(self.run, self.meta), [])
        for mode in [1, 1, 4]: self.sample("solid_contact", "acceptance-probe.ndjson", {"state": {"swimming": mode == 4, "movement_mode": mode}})
        checks = qa.machine_checks(self.run, self.meta)
        self.assertEqual(checks[0]["verdict"], "fail")

    def test_world_anchor_requires_real_turn_and_stable_actor(self):
        for yaw in [0, 100, 200, 300]: self.sample("world_anchor", "acceptance-probe.ndjson", {"state": {"camera_yaw": yaw, "actors": {"0:64:0": {"position": [100, 200, 300]}}}})
        checks = qa.machine_checks(self.run, self.meta)
        self.assertEqual(next(c for c in checks if c["criterion"] == "actors_fixed_during_turn")["verdict"], "pass")
        self.sample("world_anchor", "acceptance-probe.ndjson", {"state": {"camera_yaw": 350, "actors": {"0:64:0": {"position": [103, 200, 300]}}}})
        checks = qa.machine_checks(self.run, self.meta)
        self.assertEqual(next(c for c in checks if c["criterion"] == "actors_fixed_during_turn")["verdict"], "fail")

    def test_observer_cannot_override_machine_criterion(self):
        args = Args(run=str(self.run), case="F01", phase="mc_enter", criterion="one_f5_one_transition", evidence=[], verdict="pass", note="looks okay")
        with self.assertRaises(ValueError): qa.observe(args)

    def test_health_is_one_authority_and_missing_or_stale_is_not_pass(self):
        now = time.time()
        v = {"ok": True, "player_uid": "pal", "server_session_id": "lab", "player_health_authority": "pal_server",
             "pal": {"hp": 1, "max_hp": 2370, "alive": True, "dying": False, "epoch": "p1", "revision": 2, "unix": now},
             "mc": {"hearts": 20, "max_hearts": 20, "mc_uuid": PLAYER, "epoch": "m1", "revision": 2, "unix": now}}
        self.assertFalse(qa.health_invariants(v, now)["passed"])
        v["mc"]["hearts"] = 20 / 2370
        self.assertTrue(qa.health_invariants(v, now)["passed"])
        v["mc"]["hearts"] = 0
        self.assertFalse(qa.health_invariants(v, now)["passed"])
        self.assertFalse(qa.health_invariants(v, now+10)["available"])
        self.assertFalse(qa.health_invariants({"ok": False}, now)["available"])

    def test_dead_pal_does_not_reappear_as_live_mc_hearts(self):
        now = time.time()
        v = {"ok": True, "player_uid": "pal", "server_session_id": "lab", "player_health_authority": "pal_server",
             "pal": {"hp": 100, "max_hp": 100, "alive": False, "dying": True, "epoch": "p1", "revision": 3, "unix": now},
             "mc": {"hearts": 20, "max_hearts": 20, "mc_uuid": PLAYER, "epoch": "m1", "revision": 3, "unix": now}}
        self.assertFalse(qa.health_invariants(v, now)["passed"])
        v["mc"]["hearts"] = 0
        self.assertTrue(qa.health_invariants(v, now)["passed"])

    def test_missing_case_evidence_never_completes_the_full_goal(self):
        with contextlib.redirect_stdout(io.StringIO()): code = qa.evaluate(Args(run=str(self.run)))
        r = qa.read_json(self.run / "report.json")
        self.assertEqual(code, 2); self.assertFalse(r["full_goal_complete"])
        self.assertEqual(r["summary"], {"unproven": len(qa.matrix()["cases"])})

    def test_historical_visual_and_tampered_artifact_cannot_promote_pass(self):
        p = self.base / "frame.png"; p.write_bytes(b"test screenshot fixture")
        with contextlib.redirect_stdout(io.StringIO()):
            qa.attach(Args(run=str(self.run), phase="mc_enter", kind="screenshot", role="witness", file=str(p), observed_utc=qa.utc(time.time()-100), historical=True))
        a = qa.rows(self.run / "artifacts.ndjson")[0]
        qa.append(self.run / "checks.ndjson", {"case": "F01", "phase": "mc_enter", "criterion": "first_person_visible", "verdict": "pass", "evidence": [a["id"]], "source": "operator_observation"})
        with contextlib.redirect_stdout(io.StringIO()): qa.evaluate(Args(run=str(self.run)))
        r = qa.read_json(self.run / "report.json")
        self.assertNotIn("first_person_visible", next(c for c in r["cases"] if c["id"] == "F01")["passed_checks"])
        (self.run / a["path"]).write_bytes(b"modified")
        with contextlib.redirect_stdout(io.StringIO()): qa.evaluate(Args(run=str(self.run)))
        self.assertIn(a["id"], qa.read_json(self.run / "report.json")["invalid_artifacts"])


if __name__ == "__main__": unittest.main()
