#!/usr/bin/env python3
"""PalCraft evidence runner. Reads files only; never controls a game or backend.

All writes are confined to qa/ or an explicitly supplied evidence run directory.
No RPC, socket, SSH, input, deployment, service or inventory mutation is present.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import fnmatch
import json
import math
from pathlib import Path
import sys
import time
import uuid
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
FUSION = HERE.parent.parent
WORKSPACE = FUSION.parent.parent
MATRIX = HERE / "matrix.json"
JSON_SOURCES = (
    "client-status.json", "input-state.json", "feedback.json", "render-status.json",
    "mac-hud-status.json", "palcraft-collision-status.json", "mac-fps-result.json",
    "lab-identity.json", "world-origin.json", "world-backend.json", "drops.json",
    "model-result.json", "move-probe.json", "world-compat-status.json",
    "entity-combat-status.json", "session-status.json",
    "client-performance.json", "render-performance.json", "controls-performance.json",
)
STREAM_SOURCES = ("connection-history.ndjson", "acceptance-probe.ndjson")
FRESHNESS = {"client-status.json": 6.0, "input-state.json": 3.0,
             "feedback.json": 3.0, "render-status.json": 3.0,
             "mac-hud-status.json": 3.0, "palcraft-collision-status.json": 3.0,
             "acceptance-probe.ndjson": 3.0}
STATIC_SOURCES = {"lab-identity.json", "world-origin.json", "world-backend.json"}
ARTIFACT_KINDS = {"screenshot", "video", "mc_inspection", "block_inspection",
                  "pal_inventory", "runtime", "ledger", "test_report", "build_manifest",
                  "probe", "log", "install_receipt"}
SHA = lambda b: hashlib.sha256(b).hexdigest()


def utc(ts=None):
    return datetime.fromtimestamp(time.time() if ts is None else ts, timezone.utc).isoformat()


def epoch(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def read_json(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def write_json(p, value):
    p = Path(p); p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".pending")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(p)


def append(p, value):
    with Path(p).open("a", encoding="utf-8") as f:
        f.write(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")


def rows(p):
    p = Path(p)
    if not p.exists(): return []
    result = []
    for line in p.read_text(encoding="utf-8").splitlines():
        try: result.append(json.loads(line))
        except json.JSONDecodeError: pass  # a currently appending last line is not evidence
    return result


def source_manifest(fusion):
    """Hash actual sources; old output ZIP names and STATE are not build identities."""
    base = Path(fusion) / "palcraft"
    candidates = []
    for part in ("client", "server", "native", "render", "mc/src", "installer", "launcher", "deploy", "runtime", "chunks"):
        p = base / part
        if p.exists():
            candidates += [f for f in p.rglob("*") if f.is_file() and
                           f.suffix in {".lua", ".py", ".cpp", ".h", ".java", ".json", ".ps1", ".swift", ".sh", ".c", ".cs", ".fx", ".fxh", ".kt", ".gradle", ".toml"}
                           and "qa" not in f.parts]
    candidates += [p for p in (base / "mc/build.gradle", Path(fusion) / "mac/hud_overlay.swift") if p.exists()]
    data = {}
    for p in sorted(set(candidates)):
        rel = str(p.relative_to(fusion)); data[rel] = SHA(p.read_bytes())
        if p.name == "fabric.mod.json":
            descriptor = read_json(p); descriptor.pop("version", None)
            data[rel+"#semantic"] = SHA(json.dumps(descriptor, sort_keys=True).encode())
    return {"digest": SHA(json.dumps(data, sort_keys=True).encode()), "files": data}


def deployed_manifest(bridge):
    """Observe the isolated local client payload, including the referenced native DLLs."""
    bridge = Path(bridge)
    lan = bridge.parent.parent
    win = lan / "PalCraft-Client/Pal/Binaries/Win64"
    script = win / "ue4ss/Mods/PalCraftClient/Scripts"
    result = {}
    if script.exists():
        for p in script.glob("*.lua"):
            result[str(p)] = SHA(p.read_bytes())
    for p in win.glob("PalCraft*.dll") if win.exists() else []:
        result[str(p)] = SHA(p.read_bytes())
    return {"digest": SHA(json.dumps(result, sort_keys=True).encode()), "files": result,
            "loaded_version_verified": False,
            "note": "Disk hashes do not prove the running process loaded them. Attach a cold-load build receipt."}


def matrix(): return read_json(MATRIX)


def active_profile():
    p = HERE / "active-profile.json"
    profile = read_json(p) if p.exists() else matrix().get("active_profile", {"profile_id": "unspecified", "performance_qualification_allowed": False})
    if profile.get("night_snapshot_expires_at_day_boundary"):
        local = datetime.now(ZoneInfo(profile.get("daily_schedule", {}).get("timezone", "Asia/Shanghai")))
        if local.hour >= 10 and profile.get("profile_id") == "night_low_power":
            # Requested day authorization, not a claim that hardware was switched.
            day = profile.get("day_policy", {})
            profile = {**profile, "profile_id": "day_authorized_readback_pending", "scheduled_mode": "day",
                "pal_fps_cap": day.get("pal_fps", 60), "mc_fps_cap": day.get("mc_fps", 60),
                "mc_fps_requested": day.get("mc_fps", 60), "hud_fps_cap": day.get("hud_fps", 30),
                "remote_cpu_max_percent": day.get("remote_cpu_max_percent", 100),
                "remote_gpu_power_limit_w": day.get("remote_gpu_power_limit_w", 575),
                "mac_low_power": False, "mac_fan_max_rpm": None, "remote_turbo_enabled": True,
                "functional_capture_seconds_max": 900, "functional_capture_interval_min_s": .25,
                "requested_day_restore_authorized": True, "actual_day_settings_verified": False,
                "scope_note": "Day request only; retain dated night telemetry as historical. Wait owner applied-state readback before performance qualification."}
    return profile


def collection_plan(profile, requested_seconds, requested_interval):
    """Functional permission is independent of benchmark/repeat permission."""
    allowed = profile.get("functional_evidence_collection_allowed", profile.get("repeated_verification_allowed", True))
    if allowed is False:
        raise ValueError("Current profile pauses functional evidence collection")
    if requested_seconds <= 0 or requested_interval < .05:
        raise ValueError("Positive duration and interval >= .05s required")
    functional_only = profile.get("performance_qualification_allowed") is False
    limit = profile.get("functional_capture_seconds_max", 180) if functional_only else requested_seconds
    interval_min = profile.get("functional_capture_interval_min_s", .5) if functional_only else .05
    return {"profile_id": profile["profile_id"], "seconds": min(requested_seconds, limit),
            "interval_s": max(requested_interval, interval_min), "functional_only": functional_only,
            "performance_qualification_allowed": not functional_only,
            "baseline_comparison_allowed": profile.get("baseline_comparison_allowed", True)}


def case_contract(case):
    # A power-profile update or a JAR version label does not change every criterion.
    return SHA(json.dumps({k: case.get(k) for k in ("required_checks", "visual_checks", "check_sources", "phases")}, sort_keys=True).encode())


def case_dependency_changes(case, before, after):
    config = read_json(HERE/"case-dependencies.json") if (HERE/"case-dependencies.json").exists() else {}
    patterns = config.get("cases", {}).get(case["id"], ["*"])
    selected = {p for p in set(before) | set(after) if any(fnmatch.fnmatchcase(p, g) for g in patterns)}
    return sorted(p for p in selected if before.get(p) != after.get(p))


def verify_reuse(review, fusion):
    """Explicit, hash-backed retention of unchanged component evidence only."""
    fusion = Path(fusion).resolve(); problems = []
    if review.get("proof_boundary") not in {"offline_component", "unchanged_component"}:
        problems.append("Fresh auth/HP/connection boundaries cannot be inherited")
    if not review.get("dependency_review") or not review.get("equivalence_reason"):
        problems.append("Owner dependency review and equivalence reason required")
    dependencies = review.get("dependency_hashes", {})
    if not isinstance(dependencies, dict) or not dependencies: problems.append("Frozen dependency hashes required")
    observed = {}
    for rel, expected in dependencies.items() if isinstance(dependencies, dict) else []:
        p = (fusion/rel).resolve()
        if not p.is_relative_to(fusion) or any(x.lower() in {"saved", "savegames"} for x in p.parts):
            problems.append("Dependency outside safe evidence scope: "+rel); continue
        actual = SHA(p.read_bytes()) if p.is_file() else None
        observed[rel] = actual
        if not expected or actual != expected: problems.append("Dependency changed/missing: "+rel)
    witnesses = []
    for a in review.get("artifacts", []):
        p = Path(a["path"]); p = p if p.is_absolute() else fusion/p; p=p.resolve()
        if not p.is_relative_to(fusion) or any(x.lower() in {"saved", "savegames"} for x in p.parts):
            problems.append("Artifact outside safe evidence scope"); continue
        actual = SHA(p.read_bytes()) if p.is_file() else None
        witnesses.append({"path": str(p), "sha256": actual})
        if not a.get("sha256") or actual != a["sha256"]: problems.append("Artifact hash changed/missing")
    if not witnesses: problems.append("Existing exact evidence required")
    return {"equivalent_component_evidence": not problems, "problems": problems,
            "dependency_hashes_observed": observed, "artifacts_observed": witnesses,
            "runtime_boundary_passed": False, "full_case_passed": False}


def retain_evidence(args):
    review = read_json(args.review)
    result = verify_reuse(review, Path(args.workspace)/"work/minecraft-fusion")
    target = Path(args.out).resolve()
    if not target.is_relative_to(HERE): raise ValueError("Retention record must be under qa/")
    record = {"reviewed_utc": utc(), "component": review.get("component"), "case_criteria": review.get("case_criteria", {}),
              "review": review, "result": result, "scope": "component evidence retained; no replay or blanket runtime pass"}
    write_json(target, record)
    print(json.dumps({"out": str(target), **result}, ensure_ascii=False))
    return 0 if result["equivalent_component_evidence"] else 2


def referenced_evidence(value, fusion):
    """Resolve reported files without following untrusted paths into production or saves."""
    observed = []; seen = set(); fusion = Path(fusion).resolve()
    def visit(v):
        if isinstance(v, dict):
            path = v.get("path")
            if isinstance(path, str): inspect(path, v.get("sha256"))
            for k, child in v.items():
                if isinstance(child, str) and len(child) == 64 and all(x in "0123456789abcdefABCDEF" for x in child) and ("/" in k or "\\" in k):
                    inspect(k, child); continue
                if isinstance(child, str) and ("log" in k or "report" in k or "screenshot" in k): inspect(child)
                else: visit(child)
        elif isinstance(v, list):
            for child in v: visit(child)
        elif isinstance(v, str) and (v.startswith("/") or v.startswith("work/minecraft-fusion/") or
              "/" in v and v.endswith((".log", ".json", ".ndjson", ".png", ".lua", ".cpp", ".java", ".py", ".zip", ".md"))):
            inspect(v)
    def inspect(s, expected=None):
        if s in seen: return
        seen.add(s)
        if ":/" in s or ":\\" in s:
            observed.append({"path": s, "verification": "remote_path_unobserved", "claimed_sha256": expected}); return
        p = Path(s)
        if not p.is_absolute():
            p = fusion.parent.parent / p if s.startswith("work/") else fusion / p
            if not p.exists() and not s.startswith("work/") and (fusion / "palcraft" / s).exists():
                p = fusion / "palcraft" / s
        p = p.resolve()
        if not p.is_relative_to(fusion) or any(part.lower() in {"savegames", "saved"} for part in p.parts):
            observed.append({"path": s, "verification": "outside_read_scope"}); return
        if not p.exists(): observed.append({"path": s, "verification": "missing"}); return
        if p.is_dir(): observed.append({"path": s, "verification": "directory_exists; contents_not_certified"}); return
        if p.stat().st_size > 100 * 1024 * 1024:
            observed.append({"path": s, "verification": "large_file_not_hashed"}); return
        actual = SHA(p.read_bytes())
        observed.append({"path": s, "verification": "hash_matches" if expected == actual else "hash_changed_since_capture" if expected else "file_observed",
                         "sha256": actual, "claimed_sha256": expected, "modified_utc": utc(p.stat().st_mtime)})
    visit(value); return observed


def native_partial_findings(evidence):
    """Validate reusable survival data even when a collector was initialized later."""
    findings = []
    placement = evidence.get("button_place", {})
    mining = evidence.get("button_mine", {})
    pickup = evidence.get("button_pickup", {})
    uid = placement.get("before", {}).get("uuid")
    if uid and placement.get("after_place"):
        try:
            result = inventory_delta(placement["before"], placement["after_place"], uid, {"minecraft:oak_button": -1})
            findings.append({"case": "I02", "criterion": "placement_delta", "result": result,
                             "classification": "reported_v3_run_arithmetic_verified; native visibility separate"})
        except ValueError as e: findings.append({"case": "I02", "error": str(e)})
    if uid and mining.get("after_mine") and pickup:
        try:
            result = inventory_delta(mining["after_mine"], pickup, uid, {"minecraft:oak_button": 1})
            before_drops = mining["after_mine"].get("server", {}).get("dropped_items", [])
            after_drops = pickup.get("server", {}).get("dropped_items", [])
            drop_before = sum(d["count"] for d in before_drops if d.get("item") == "minecraft:oak_button")
            drop_after = sum(d["count"] for d in after_drops if d.get("item") == "minecraft:oak_button")
            findings.append({"case": "I04", "criterion": "pickup_delta_and_drop_removed", "result": result,
                             "button_drops_before": drop_before, "button_drops_after": drop_after,
                             "drop_conserved": result["passed"] and drop_before == 1 and drop_after == 0,
                             "classification": "reported_v3_run_arithmetic_verified; second-pickup and current build unproven"})
        except ValueError as e: findings.append({"case": "I04", "error": str(e)})
    stress_end = evidence.get("v3_stress", {}).get("final", {})
    final = evidence.get("final_runtime", {})
    if "pending" in stress_end and "pending" in final:
        findings.append({"case": "R04", "criterion": "queue_endpoint_interpretation",
                         "stress_end_pending": stress_end["pending"], "later_final_pending": final["pending"],
                         "later_final_blocks": final.get("blocks"), "later_final_models": final.get("models"),
                         "classification": "later_final_zero_is_settlement_evidence; no inference of a timeout from one earlier nonzero endpoint"})
    return findings


def run_meta(run):
    run = Path(run).resolve()
    if not run.is_relative_to(HERE): raise ValueError("Evidence runs must be under qa/")
    return run, read_json(run / "run.json")


def current_phase(run):
    phases = rows(Path(run) / "phases.ndjson")
    return phases[-1]["phase"] if phases else "unmarked"


def init(args):
    run = Path(args.run).resolve()
    if not run.is_relative_to(HERE): raise ValueError("Evidence runs must be under qa/")
    if (run / "run.json").exists(): raise ValueError("Run already exists; use a new run directory")
    fusion = Path(args.workspace).resolve() / "work/minecraft-fusion"
    bridge = Path(args.bridge).resolve()
    if not bridge.is_dir(): raise ValueError("Existing isolated bridge directory required")
    fixture = getattr(args, "fixture", False)
    expected_root = fusion / "mac/drive_d/PalworldServer-LAN/PalCraft-Dev"
    if fixture:
        if not bridge.is_relative_to(HERE): raise ValueError("Offline fixtures must live under qa/")
    elif not bridge.is_relative_to(expected_root) or "bridge" not in bridge.parts:
        raise ValueError("Collector scope is the isolated PalCraft-Dev bridge; use --fixture only for qa/ fixtures")
    run.mkdir(parents=True, exist_ok=True); (run / "artifacts").mkdir()
    meta = {"schema_version": 1, "run_id": str(uuid.uuid4()), "started_utc": utc(),
            "operator": args.operator, "workspace": str(Path(args.workspace).resolve()),
            "bridge": str(bridge), "environment": "offline_fixture" if fixture else "BridgeLab", "graphics_bottle": "PalCraftLab",
            "source_manifest": source_manifest(fusion), "deployed_manifest": deployed_manifest(bridge),
            "matrix_sha256": SHA(MATRIX.read_bytes()), "policy": matrix()["policy"],
            "case_contracts": {c["id"]: case_contract(c) for c in matrix()["cases"]},
            "environment_contract": matrix().get("environment_contract", {}),
            "active_profile": active_profile(),
            "scope": "passive_files_only", "full_goal_complete": False}
    write_json(run / "run.json", meta)
    print(json.dumps({"run": str(run), "run_id": meta["run_id"], "source_digest": meta["source_manifest"]["digest"]}))


def mark(args):
    run, meta = run_meta(args.run)
    if args.phase not in {p["id"] for p in matrix()["phases"]}: raise ValueError("Unknown phase")
    params = json.loads(args.params) if args.params else {}
    if not isinstance(params, dict): raise ValueError("Phase parameters must be an object")
    row = {"run_id": meta["run_id"], "phase": args.phase, "observed_utc": utc(), "params": params}
    append(run / "phases.ndjson", row); print(json.dumps(row, ensure_ascii=False))


class Collector:
    def __init__(self, run, meta):
        self.run, self.meta = Path(run), meta
        self.bridge = Path(meta["bridge"])
        self.last_hash = {}; self.offsets = {}; self.pending = {}
        # Existing journal history is not evidence of an action in this run.
        for n in STREAM_SOURCES:
            p = self.bridge / n
            self.offsets[n] = p.stat().st_size if p.exists() else 0

    def poll(self, now=None):
        now = time.time() if now is None else now
        phase = current_phase(self.run)
        profile = active_profile(); profile_id = profile["profile_id"]
        caps = {k: profile.get(k) for k in ("pal_fps_cap", "mc_fps_cap", "hud_fps_cap", "mac_fan_max_rpm", "mac_low_power", "remote_cpu_max_percent", "remote_turbo_enabled", "remote_gpu_power_limit_w")}
        caps["mc_fps_cap"] = profile.get("mc_fps_requested", caps["mc_fps_cap"])
        reported_actual = profile.get("reported_actual_environment", {})
        for n in JSON_SOURCES:
            p = self.bridge / n
            if not p.exists(): continue
            try:
                st = p.stat(); content = p.read_bytes(); h = SHA(content)
                if self.last_hash.get(n) == h: continue
                payload = json.loads(content.decode("utf-8-sig"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                continue  # live writers are allowed to be caught between writes
            self.last_hash[n] = h
            append(self.run / "samples.ndjson", {"run_id": self.meta["run_id"], "phase": phase,
                "source": n, "sha256": h, "captured_utc": utc(now), "source_modified_utc": utc(st.st_mtime),
                "age_s": round(now - st.st_mtime, 6), "static": n in STATIC_SOURCES, "profile_id": profile_id,
                "profile_effective_utc": profile.get("effective_utc"), "requested_environment_caps": caps,
                "reported_actual_environment_snapshot": reported_actual, "payload": payload})
        for n in STREAM_SOURCES:
            p = self.bridge / n
            if not p.exists(): continue
            try:
                st = p.stat(); off = self.offsets.get(n, 0)
                if st.st_size < off: off = 0; self.pending[n] = b""
                with p.open("rb") as f:
                    f.seek(off); content = f.read(4 * 1024 * 1024); self.offsets[n] = f.tell()
                content = self.pending.get(n, b"") + content
                lines = content.split(b"\n"); self.pending[n] = lines.pop()
                for line in lines:
                    if not line.strip(): continue
                    try: payload = json.loads(line)
                    except (UnicodeDecodeError, json.JSONDecodeError): continue
                    # Probe rows have their own time. Journal rows without it are observational only.
                    event_time = payload.get("unix")
                    age = now - float(event_time) if isinstance(event_time, (float, int)) else now - st.st_mtime
                    append(self.run / "samples.ndjson", {"run_id": self.meta["run_id"], "phase": phase,
                        "source": n, "sha256": SHA(line), "captured_utc": utc(now),
                        "source_modified_utc": utc(st.st_mtime), "age_s": round(age, 6), "profile_id": profile_id,
                        "profile_effective_utc": profile.get("effective_utc"), "requested_environment_caps": caps,
                        "reported_actual_environment_snapshot": reported_actual, "payload": payload})
            except OSError: continue


def collect(args):
    run, meta = run_meta(args.run); c = Collector(run, meta)
    profile = active_profile(); plan = collection_plan(profile, args.seconds, args.interval)
    start = time.monotonic(); started = utc(); end = start + plan["seconds"]
    record = {"run_id": meta["run_id"], "operator": meta["operator"], "lease_id": getattr(args, "lease_id", None),
              "started_utc": started, "requested_seconds": args.seconds, "plan": plan,
              "profile": profile, "scope": "passive_files_only; gameplay performed by lead-assigned lease owner"}
    append(run/"collections.ndjson", record)
    print(json.dumps({"collecting": str(run), "mode": "read_only", "plan": plan}), flush=True)
    still_allowed = True
    try:
        while time.monotonic() < end:
            try: current = collection_plan(active_profile(), args.seconds, args.interval)
            except ValueError: still_allowed = False; break
            end = min(end, start + current["seconds"])
            if time.monotonic() >= end: break
            c.poll(); time.sleep(current["interval_s"])
    except KeyboardInterrupt: pass
    if still_allowed: c.poll()
    append(run/"collections.ndjson", {"run_id": meta["run_id"], "started_utc": started,
           "finished_utc": utc(), "elapsed_s": time.monotonic()-start, "profile_id": active_profile()["profile_id"],
           "functional_only": plan["functional_only"], "stopped_by_profile": not still_allowed})
    print(json.dumps({"captured_samples": len(rows(run / "samples.ndjson")), "functional_only": plan["functional_only"]}), flush=True)


def attach(args):
    run, meta = run_meta(args.run); source = Path(args.file).resolve()
    if args.kind not in ARTIFACT_KINDS: raise ValueError("Unknown evidence kind")
    if args.phase not in {p["id"] for p in matrix()["phases"]}: raise ValueError("Unknown phase")
    observed = epoch(args.observed_utc)
    pre_run = observed < epoch(meta["started_utc"]) - 2
    if pre_run and not args.historical: raise ValueError("Artifact predates this run; use --historical to retain it without current-run promotion")
    if observed > time.time() + 2: raise ValueError("Artifact timestamp is in the future")
    artifact_id = str(uuid.uuid4()); data = source.read_bytes()
    target = run / "artifacts" / (artifact_id + source.suffix)
    target.write_bytes(data)
    row = {"id": artifact_id, "run_id": meta["run_id"], "phase": args.phase,
           "kind": args.kind, "role": args.role, "observed_utc": utc(observed),
           "attached_utc": utc(), "source_path": str(source), "path": str(target.relative_to(run)),
           "sha256": SHA(data), "build_digest": meta["source_manifest"]["digest"]}
    row["historical"] = bool(args.historical or pre_run)
    append(run / "artifacts.ndjson", row); print(json.dumps(row, ensure_ascii=False))


def observe(args):
    run, meta = run_meta(args.run)
    case = next((c for c in matrix()["cases"] if c["id"] == args.case), None)
    if not case or args.criterion not in case["required_checks"]: raise ValueError("Unknown case/criterion")
    if args.criterion in case.get("check_sources", {}):
        raise ValueError("This criterion requires its machine checker; an observation cannot replace it")
    if args.phase not in case["phases"]: raise ValueError("Phase is not part of this case")
    evidence = args.evidence or []
    known = {a["id"] for a in rows(run / "artifacts.ndjson")}
    if any(i not in known for i in evidence): raise ValueError("Evidence ID not attached to this run")
    if args.verdict == "pass" and not evidence: raise ValueError("Pass observations require artifact IDs")
    row = {"run_id": meta["run_id"], "case": args.case, "phase": args.phase,
           "criterion": args.criterion, "verdict": args.verdict, "evidence": evidence,
           "note": args.note, "observed_utc": utc(), "source": "operator_observation"}
    append(run / "checks.ndjson", row); print(json.dumps(row, ensure_ascii=False))


def unwrap(value):
    if isinstance(value, dict) and "result" in value and isinstance(value["result"], dict): return value["result"]
    return value


def inventory(snapshot, player):
    snapshot = unwrap(snapshot)
    if not isinstance(snapshot, dict): raise ValueError("Inventory inspection must be an object")
    server = snapshot.get("server", snapshot)
    if not isinstance(server, dict): raise ValueError("Authoritative server inspection missing")
    players = server.get("players", [])
    if not players and snapshot.get("uuid") == player: players = [snapshot]
    hits = [p for p in players if p.get("uuid") == player]
    if len(hits) != 1: raise ValueError("Exactly one authoritative player UUID required; names are insufficient")
    counts = Counter()
    for row in hits[0].get("inventory", []):
        count = row.get("count")
        if isinstance(count, bool) or not isinstance(count, int) or count < 0: raise ValueError("Invalid inventory count")
        counts[row["item"]] += count
    return counts


def inventory_delta(before, after, player, expected):
    if not isinstance(expected, dict) or any(isinstance(v, bool) or not isinstance(v, int) for v in expected.values()):
        raise ValueError("Expected inventory delta must be an item -> integer object")
    a, b = inventory(before, player), inventory(after, player)
    actual = {k: b[k] - a[k] for k in set(a) | set(b) if b[k] != a[k]}
    wanted = {k: v for k, v in expected.items() if v != 0}
    return {"passed": actual == wanted, "actual": actual, "expected": wanted}


def check_delta(args):
    run, meta = run_meta(args.run)
    artifacts = {a["id"]: a for a in rows(run / "artifacts.ndjson")}
    before, after = artifacts[args.before], artifacts[args.after]
    for a in (before, after):
        if a["kind"] != "mc_inspection" or a["phase"] != args.phase: raise ValueError("Same-phase MC inspections required")
    result = inventory_delta(read_json(run / before["path"]), read_json(run / after["path"]),
                             args.player, json.loads(args.expected))
    case = next(c for c in matrix()["cases"] if c["id"] == args.case)
    if "inventory_arithmetic" not in case.get("check_sources", {}).get(args.criterion, []):
        raise ValueError("This criterion is not an inventory arithmetic check")
    if args.phase not in case["phases"]: raise ValueError("Phase is not part of this case")
    if epoch(before["observed_utc"]) >= epoch(after["observed_utc"]):
        raise ValueError("Before must be observed before after")
    row = {"run_id": meta["run_id"], "case": args.case, "phase": args.phase,
           "criterion": args.criterion, "verdict": "pass" if result["passed"] else "fail",
           "evidence": [args.before, args.after], "note": result, "observed_utc": utc(),
           "source": "inventory_arithmetic", "player_uuid": args.player}
    append(run / "checks.ndjson", row); print(json.dumps(row, ensure_ascii=False))


def exchange_invariants(row):
    """A completed v1 row proves amounts only; it never proves durable recovery."""
    problems = []
    pal = row.get("pal", {})
    if row.get("state") != "completed" or row.get("ok") is not True: problems.append("MC transaction not completed")
    if pal.get("status") != "completed" or pal.get("ok") is not True: problems.append("Pal transaction not completed")
    for key in ("id", "player_uid", "item", "count", "action"):
        if row.get(key) != pal.get(key): problems.append("receipt mismatch: " + key)
    if not isinstance(row.get("to_mc"), bool): problems.append("transfer direction missing")
    elif row.get("action") != ("debit" if row["to_mc"] else "credit"): problems.append("transfer action/direction mismatch")
    amount = row.get("count")
    if not isinstance(amount, int) or not 1 <= amount <= 64:
        problems.append("invalid quantity")
    else:
        sign = 1 if row.get("to_mc") is True else -1
        mc_before = row.get("mc_before")
        if mc_before is None and isinstance(row.get("mc_initial"), list):
            mc_before = sum(s.get("count", 0) for s in row["mc_initial"] if s.get("item") == row.get("mc_item"))
        if not isinstance(mc_before, (int, float)) or not isinstance(row.get("mc_after"), (int, float)):
            problems.append("MC before/after missing")
        elif row["mc_after"] - mc_before != sign * amount: problems.append("MC delta mismatch")
        if not all(isinstance(pal.get(k), (int, float)) for k in ("before", "after")):
            problems.append("Pal before/after missing")
        elif pal["after"] - pal["before"] != -sign * amount: problems.append("Pal delta mismatch")
    durable_problems = []
    if row.get("protocol") != 2: durable_problems.append("no protocol-2 durable receipt")
    if pal.get("durable") is not True: durable_problems.append("Pal durability unconfirmed")
    for key in ("protocol", "mc_uid", "mc_world", "fingerprint"):
        if not row.get(key) or row.get(key) != pal.get(key): durable_problems.append("durable identity mismatch: " + key)
    if row.get("protocol") == 2:
        keys = ("protocol", "id", "mc_uid", "player_uid", "mc_world", "item", "count", "action")
        fingerprint = SHA(json.dumps([row.get(k) for k in keys], ensure_ascii=False, separators=(",", ":")).encode())
        if row.get("fingerprint") != fingerprint: durable_problems.append("transaction fingerprint does not match identity")
        witness = pal.get("save_witness", {})
        if (witness.get("durable") is not True or witness.get("id") != row.get("id") or
            witness.get("fingerprint") != row.get("fingerprint") or
            not isinstance(witness.get("save_sha256"), str) or len(witness["save_sha256"]) != 64 or
            witness.get("pal_revision") != pal.get("revision") or "expected_after" not in pal or
            witness.get("expected_after") != pal.get("expected_after")):
            durable_problems.append("matching Pal save witness missing")
    leg = "credit" if row.get("to_mc") is True else "debit"
    if row.get("mc_" + leg + "_durable") is not True: durable_problems.append("MC saved receipt missing")
    return {"amounts_passed": not problems, "durability_passed": not problems and not durable_problems,
            "problems": problems, "durability_gaps": durable_problems}


def check_exchange(args):
    run, meta = run_meta(args.run); a = next(a for a in rows(run / "artifacts.ndjson") if a["id"] == args.artifact)
    if a["kind"] != "ledger": raise ValueError("Ledger artifact required")
    result = exchange_invariants(read_json(run / a["path"]))
    key = "durability_passed" if args.durable else "amounts_passed"
    case = "R02" if args.durable else "I07"
    criterion = "durable_receipts" if args.durable else "exchange_conservation"
    append(run / "checks.ndjson", {"run_id": meta["run_id"], "case": case, "phase": a["phase"],
        "criterion": criterion, "verdict": "pass" if result[key] else "fail", "evidence": [a["id"]],
        "note": result, "source": "exchange_arithmetic", "observed_utc": utc()})
    print(json.dumps(result, ensure_ascii=False))


def fresh_samples(run, source, phase=None):
    run_id = read_json(Path(run)/"run.json")["run_id"]
    return [r for r in rows(Path(run) / "samples.ndjson") if r["source"] == source
            and r.get("run_id") == run_id
            and (phase is None or r["phase"] == phase) and not r.get("static")
            and -2 <= r.get("age_s", math.inf) <= FRESHNESS.get(source, 3.0)]


def health_invariants(vitals, now):
    """Compare fresh bound authoritative health, never fabricate missing Pal HP."""
    if not isinstance(vitals, dict) or vitals.get("ok") is not True:
        return {"available": False, "reason": "verified_vitals_unavailable"}
    pal, mc = vitals.get("pal", {}), vitals.get("mc", {})
    if not isinstance(pal, dict) or not isinstance(mc, dict): return {"available": False, "reason": "authority_snapshot_missing"}
    if not vitals.get("player_uid") or not vitals.get("server_session_id") or not mc.get("mc_uuid"):
        return {"available": False, "reason": "identity_binding_missing"}
    if vitals.get("player_health_authority") != "pal_server":
        return {"available": False, "reason": "authority_not_established"}
    for body in (pal, mc):
        if not body.get("epoch") or "revision" not in body or not isinstance(body.get("unix"), (int, float)) or not -2 <= now-body["unix"] <= 3:
            return {"available": False, "reason": "authority_snapshot_stale_or_unversioned"}
    numbers = [pal.get("hp"), pal.get("max_hp"), mc.get("hearts"), mc.get("max_hearts")]
    if not all(isinstance(v, (float, int)) and math.isfinite(v) for v in numbers) or pal["max_hp"] <= 0 or mc["max_hearts"] <= 0:
        return {"available": False, "reason": "invalid_health_values"}
    if not isinstance(pal.get("alive"), bool) or not isinstance(pal.get("dying"), bool):
        return {"available": False, "reason": "alive_dying_state_missing"}
    expected = pal["hp"] / pal["max_hp"] * mc["max_hearts"] if pal.get("alive") is True and pal.get("dying") is False else 0
    live_health = expected > 0
    return {"available": True, "passed": abs(mc["hearts"] - expected) <= .001 and (mc["hearts"] > 0) == live_health,
            "pal_hp": pal["hp"], "pal_max_hp": pal["max_hp"], "mc_health": mc["hearts"],
            "expected_mc_health": expected, "mc_uuid": mc["mc_uuid"], "player_uid": vitals["player_uid"]}


def machine_checks(run, meta):
    out = []
    def add(case, criterion, passed, note, evidence, phase=None):
        out.append({"case": case, "criterion": criterion, "verdict": "pass" if passed else "fail",
                    "note": note, "source": "passive_probe", "phase": phase, "evidence": evidence})
    probes = fresh_samples(run, "acceptance-probe.ndjson")
    probes = [r for r in probes if isinstance(r["payload"], dict) and isinstance(r["payload"].get("state"), dict) and r["payload"].get("session_id")
              and r["payload"].get("state", {}).get("status") == "in_bridgelab"]
    by_phase = {}
    for r in probes:
        if isinstance(r["payload"], dict) and isinstance(r["payload"].get("state"), dict): by_phase.setdefault(r["phase"], []).append(r)
    health = []
    for r in probes:
        if not isinstance(r["payload"], dict): continue
        check = health_invariants(r["payload"].get("state", {}).get("vitals"), epoch(r["captured_utc"]))
        if check["available"]: health.append((r, check))
    if len(health) >= 2:
        identities = {(c["player_uid"], c["mc_uuid"]) for _, c in health}
        add("F06", "health_same_player", len(identities) == 1 and all(c["passed"] for _, c in health),
            {"samples": len(health), "identities": sorted(identities), "failures": [c for _, c in health if not c["passed"]]}, [r["sha256"] for r, _ in health])
    baseline = by_phase.get("baseline", [])
    entered = by_phase.get("mc_enter", [])
    returned = by_phase.get("pal_return", [])
    if baseline and entered and baseline[-1]["payload"]["session_id"] == entered[-1]["payload"]["session_id"]:
        b, a = baseline[-1]["payload"]["state"], entered[-1]["payload"]["state"]
        add("F01", "one_f5_one_transition", a.get("form", {}).get("transitions", -10) - b.get("form", {}).get("transitions", 0) == 1,
            {"before": b.get("form"), "after": a.get("form")}, [baseline[-1]["sha256"], entered[-1]["sha256"]])
        add("F01", "exclusive_first_person", a.get("form", {}).get("active") is True and a.get("pawn_hidden") is True
            and a.get("ignore_move") is True and a.get("ignore_look") is True and a.get("view") == a.get("form", {}).get("camera"),
            "Pawn hidden, Pal move/look disabled, dedicated MC view target", [entered[-1]["sha256"]])
    if baseline and returned and baseline[-1]["payload"]["session_id"] == returned[-1]["payload"]["session_id"]:
        b, a = baseline[-1]["payload"]["state"], returned[-1]["payload"]["state"]
        fields = ("pawn_hidden", "ignore_move", "ignore_look", "view", "walk_speed", "jump_velocity")
        restored = a.get("form", {}).get("active") is False and all(k in b and k in a and b[k] == a[k] for k in fields)
        add("F02", "pal_state_restored", restored, {"fields": fields, "before": b, "after": a}, [baseline[-1]["sha256"], returned[-1]["sha256"]])
    contact = by_phase.get("solid_contact", [])
    if len(contact) >= 3:
        states = [r["payload"]["state"] for r in contact]
        add("W03", "solid_does_not_swim", all(s.get("swimming") is False and s.get("movement_mode") != 4 for s in states),
            {"samples": len(states), "modes": sorted(set(s.get("movement_mode", -1) for s in states))}, [contact[0]["sha256"], contact[-1]["sha256"]])
    movement = by_phase.get("locomotion", [])
    speeds = [r["payload"]["state"].get("speed_cm_s") for r in movement]
    speeds = [s for s in speeds if isinstance(s, (int, float))]
    if len(speeds) >= 3:
        peak = max(speeds); low, high = meta["policy"]["walk_speed_cm_s"]
        add("F03", "walk_speed", low <= peak <= high, {"peak_cm_s": peak, "policy_cm_s": [low, high]}, [movement[0]["sha256"], movement[-1]["sha256"]])
    anchor = by_phase.get("world_anchor", [])
    actor_states = [r["payload"]["state"] for r in anchor if r["payload"]["state"].get("actors")]
    if len(actor_states) >= 3:
        keys = set(actor_states[0]["actors"])
        for s in actor_states: keys &= set(s["actors"])
        drift = 0.0
        for k in keys:
            positions = [s["actors"][k]["position"] for s in actor_states]
            p0 = positions[0]
            drift = max(drift, max(math.dist(p0, p) for p in positions))
        yaws = [s.get("camera_yaw", 0) for s in actor_states]
        turning = sum(abs((b - a + 180) % 360 - 180) for a, b in zip(yaws, yaws[1:]))
        add("W01", "actors_fixed_during_turn", bool(keys) and drift <= meta["policy"]["actor_drift_cm"] and turning >= 240,
            {"stable_actors": len(keys), "max_drift_cm": drift, "sampled_turn_degrees": turning}, [r["sha256"] for r in anchor])
    performance = [r for r in probes if r["phase"] in {"locomotion", "survival_mine", "sustain"} and r["payload"].get("frame_ms")]
    frame_ms = [v for r in performance for v in r["payload"]["frame_ms"] if isinstance(v, (int, float)) and v > 0]
    if active_profile().get("performance_qualification_allowed") is not False and len(frame_ms) >= meta["policy"]["minimum_frame_samples"]:
        frame_ms.sort(); mean_fps = 1000 * len(frame_ms) / sum(frame_ms)
        p95 = frame_ms[min(len(frame_ms) - 1, math.ceil(.95 * len(frame_ms)) - 1)]; maximum = frame_ms[-1]
        passed = mean_fps >= meta["policy"]["mean_fps_min"] and p95 <= meta["policy"]["frame_p95_ms_max"] and maximum <= meta["policy"]["frame_max_ms"]
        add("P01", "frame_budget", passed, {"samples": len(frame_ms), "mean_engine_fps": mean_fps, "p95_ms": p95, "max_ms": maximum,
            "method": "UE game-thread DeltaSeconds; separate visual/input latency witness still required"}, [performance[0]["sha256"], performance[-1]["sha256"]])
    for a in rows(Path(run) / "artifacts.ndjson"):
        if a["kind"] == "runtime":
            d = unwrap(read_json(Path(run) / a["path"]))
            if isinstance(d.get("production_running"), bool):
                add("S01", "production_off", d["production_running"] is False and d.get("production_ports_checked") is True,
                    d, [a["id"]])
    return out


def evaluate(args):
    run, meta = run_meta(args.run)
    artifacts = {a["id"]: a for a in rows(run / "artifacts.ndjson")}
    valid_artifacts = {}
    invalid = []
    for aid, a in artifacts.items():
        p = run / a["path"]
        if not p.exists() or SHA(p.read_bytes()) != a["sha256"] or a.get("run_id") != meta["run_id"]:
            invalid.append(aid)
        elif not a.get("historical"): valid_artifacts[aid] = a
    samples = rows(run / "samples.ndjson")
    sample_ids = {s["sha256"] for s in samples if -2 <= s.get("age_s", math.inf) <= FRESHNESS.get(s["source"], 3.0)}
    checks = rows(run / "checks.ndjson") + machine_checks(run, meta)
    profile = active_profile()
    blockers = read_json(HERE/"runtime-blockers.json").get("blockers", []) if (HERE/"runtime-blockers.json").exists() else []
    source_now = source_manifest(Path(meta["workspace"]) / "work/minecraft-fusion")
    stable = source_now["digest"] == meta["source_manifest"]["digest"]
    contract_stable = meta.get("matrix_sha256") == SHA(MATRIX.read_bytes())
    results = []
    for c in matrix()["cases"]:
        affected = case_dependency_changes(c, meta["source_manifest"]["files"], source_now["files"])
        criterion_contract_stable = meta.get("case_contracts", {}).get(c["id"]) == case_contract(c) if meta.get("case_contracts") else contract_stable
        case_blockers = [b for b in blockers if not b.get("resolved") and c["id"] in b.get("affected_cases", [])]
        passed = set(); failures = []; invalid_checks = []; deferred = []
        for check in [x for x in checks if x.get("case") == c["id"]]:
            if c["id"] in {"P01", "P02"} and profile.get("performance_qualification_allowed") is False:
                deferred.append(check); continue
            if any(b.get("category") == "input_environment" for b in case_blockers):
                # An undelivered key on a locked desktop is not a game-logic failure.
                deferred.append({**check, "defer_reason": "locked_or_unfocused_input_environment"}); continue
            if check["verdict"] == "fail": failures.append(check); continue
            refs = check.get("evidence", [])
            accepted = refs and all(i in valid_artifacts or i in sample_ids for i in refs)
            if check["criterion"] not in c["required_checks"]:
                accepted = False
            allowed = c.get("check_sources", {}).get(check["criterion"])
            if allowed and check.get("source") not in allowed:
                accepted = False
            if accepted and check.get("source") == "operator_observation":
                accepted = check.get("phase") in c["phases"]
                accepted = accepted and all(valid_artifacts[i]["phase"] == check["phase"] for i in refs if i in valid_artifacts)
                if check["criterion"] in c.get("visual_checks", []):
                    accepted = accepted and any(valid_artifacts.get(i, {}).get("kind") in {"screenshot", "video"} for i in refs)
            if accepted: passed.add(check["criterion"])
            else: invalid_checks.append(check)
        missing = [k for k in c["required_checks"] if k not in passed]
        observed_status = "contradictory" if failures else "proven" if not missing and criterion_contract_stable else "unproven"
        status = "contradictory" if failures else "proven" if not missing and not affected and criterion_contract_stable and not case_blockers else "unproven"
        results.append({"id": c["id"], "requirement": c["requirement"], "owner": c["owner"], "status": status,
                        "observed_run_status": observed_status, "affected_dependencies": affected,
                        "current_runtime_blockers": case_blockers,
                        "criterion_contract_stable": criterion_contract_stable,
                        "next_validation": "Review affected boundary and use one combined functional flow; unaffected component proof retained" if affected else "No source-change replay required",
                        "passed_checks": sorted(passed), "missing_checks": missing, "failures": failures,
                        "invalid_checks": invalid_checks, "deferred_checks": deferred,
                        "profile_id": profile["profile_id"],
                        "qualification_deferred": c["id"] in {"P01", "P02"} and profile.get("performance_qualification_allowed") is False})
    # An offline report, a historical screenshot, or a partial tier cannot complete the full migration.
    report = {"schema_version": 1, "run_id": meta["run_id"], "evaluated_utc": utc(),
              "source_stable": stable, "contract_stable": contract_stable,
              "environment_contract": meta.get("environment_contract", {}),
              "current_profile": profile, "performance_baseline_comparison_allowed": profile.get("baseline_comparison_allowed", True),
              "source_changed_paths": [k for k in set(source_now["files"]) | set(meta["source_manifest"]["files"])
                if meta["source_manifest"]["files"].get(k) != source_now["files"].get(k)],
              "invalid_artifacts": invalid, "summary": dict(Counter(c["status"] for c in results)),
              "cases": results, "full_goal_complete": meta["environment"] == "BridgeLab" and not invalid and all(c["status"] == "proven" for c in results)}
    write_json(run / "report.json", report)
    print(json.dumps({k: v for k, v in report.items() if k != "cases"}, ensure_ascii=False, indent=2))
    return 0 if report["full_goal_complete"] else 2


def audit(args):
    if not Path(args.out).resolve().is_relative_to(HERE): raise ValueError("Audit output must be under qa/")
    fusion = Path(args.workspace).resolve() / "work/minecraft-fusion"
    spec = matrix(); branches = []
    for p in sorted((fusion / "coordination").glob("*.json")):
        if p.name in {"team.json", "acceptance.json"}: continue
        try: d = read_json(p)
        except (OSError, ValueError) as e:
            branches.append({"file": str(p), "invalid": str(e)}); continue
        refs = d.get("evidence", [])
        # Keep owner reports as claims. Only referenced files and their hashes are observed facts.
        branches.append({"file": str(p), "sha256": SHA(p.read_bytes()), "modified_utc": utc(p.stat().st_mtime),
                         "task": d.get("task", p.stem), "claimed_status": d.get("status", d.get("state")),
                         "claims": refs, "unfinished": d.get("unfinished", d.get("remaining", d.get("incomplete", []))),
                         "interfaces": d.get("interfaces", {}), "referenced_files": referenced_evidence(d, fusion),
                         "verified_partial_findings": native_partial_findings(refs) if p.stem == "native_renderer" and isinstance(refs, dict) else []})
    current_bridge = Path(args.bridge).resolve() if args.bridge else fusion / "mac/drive_d/PalworldServer-LAN/PalCraft-Dev/bridge"
    passive = []; now = time.time()
    for name in JSON_SOURCES:
        p = current_bridge / name
        if not p.exists(): passive.append({"source": name, "exists": False}); continue
        try: d = read_json(p)
        except (OSError, ValueError) as e: passive.append({"source": name, "valid": False, "error": str(e)}); continue
        passive.append({"source": name, "exists": True, "sha256": SHA(p.read_bytes()), "age_s": round(now-p.stat().st_mtime, 3),
                        "fresh": -2 <= now-p.stat().st_mtime <= FRESHNESS.get(name, 3.0), "payload": d})
    cases = []
    observations = read_json(HERE / "observed-findings.json") if (HERE / "observed-findings.json").exists() else {"findings": []}
    scoped_acceptances = read_json(HERE / "accepted-case-evidence.json").get("cases", {}) if (HERE / "accepted-case-evidence.json").exists() else {}
    partial_acceptances = read_json(HERE / "case-check-evidence.json").get("cases", {}) if (HERE / "case-check-evidence.json").exists() else {}
    for c in spec["cases"]:
        findings = []; existing = []
        for evidence in c.get("source_evidence", []):
            p = fusion / evidence["path"]
            found = p.exists(); marker = evidence.get("contains")
            if found and marker: found = marker in p.read_text(encoding="utf-8", errors="replace")
            findings.append({"path": evidence["path"], "marker": marker, "present": found,
                             "sha256": SHA(p.read_bytes()) if p.exists() else None})
        for rel in c.get("historical_evidence", []):
            p = fusion / rel
            if p.exists(): existing.append({"path": rel, "modified_utc": utc(p.stat().st_mtime), "sha256": SHA(p.read_bytes()),
                                           "classification": "historical_partial; no current-build acceptance"})
        status = c.get("initial_status", "unproven")
        implementation_paths = []
        if c["owner"] == "player_install":
            implementation_paths = [str(p.relative_to(fusion)) for name in ("installer", "launcher") for p in (fusion/"palcraft"/name).glob("*.py")]
        owner_branch = next((b for b in branches if b.get("task") == c["owner"] and b.get("claimed_status")), None)
        if owner_branch:
            for ref in owner_branch.get("referenced_files", []):
                if ref["verification"] in {"file_observed", "hash_matches", "hash_changed_since_capture"} and ref["path"].endswith((".lua", ".py", ".java", ".cpp", ".h", ".cs")):
                    implementation_paths.append(ref["path"])
        if status == "unimplemented" and (implementation_paths or c["id"] == "X04" and any(f["present"] for f in findings)):
            status = "unproven"  # implementation work is visible; completion still requires the full contract
        observed = [f for f in observations.get("findings", []) if f.get("case") == c["id"] and not f.get("resolved")]
        if any(f.get("verdict") == "fail" for f in observed): status = "contradictory"
        decision = scoped_acceptances.get(c["id"])
        decision_intact = False
        if decision and decision.get("status") == "proven" and not decision.get("reopened"):
            decision_intact = all((fusion/a["path"]).is_file() and SHA((fusion/a["path"]).read_bytes()) == a["sha256"] for a in decision.get("evidence", []))
            if decision_intact and decision.get("evidence"): status = "proven"
        cases.append({"id": c["id"], "requirement": c["requirement"], "owner": c["owner"],
                      "status": status, "gap": c["current_gap"], "implementation_paths_observed": implementation_paths,
                      "observed_findings": observed,
                      "accepted_scope": decision.get("scope") if decision_intact else None,
                      "accepted_case_evidence": "palcraft/qa/accepted-case-evidence.json#"+c["id"] if decision_intact else None,
                      "checks_proven": partial_acceptances.get(c["id"], {}).get("checks_proven", []),
                      "checks_partially_proven": partial_acceptances.get(c["id"], {}).get("checks_partially_proven", []),
                      "scope_status": partial_acceptances.get(c["id"], {}).get("scope_status"),
                      "owner_unfinished": owner_branch.get("unfinished", []) if owner_branch else [],
                      "qualification_deferred": c["id"] in {"P01", "P02"} and active_profile().get("performance_qualification_allowed") is False,
                      "source_findings": findings, "historical_evidence": existing,
                      "required_checks": c["required_checks"], "acceptance_phases": c["phases"]})
    stale_state = read_json(fusion / "STATE.json") if (fusion / "STATE.json").exists() else {}
    contradictions = [
        {"type": "historical_state", "claim": "STATE.mac_test.remaining says GUI/hand not connected",
         "observed": "Current PlayFeedback, HUD source and mac-hud-status exist; this is not proof of visible correct GUI",
         "action": "Use current phase screenshots + fresh feedback, not the stale remaining list"},
        {"type": "performance", "claim": "STATE.mac_test.measured_fps is 22.07",
         "observed": "A five-second historical probe cannot establish this build's sustained performance",
         "action": "Use probe frame distribution during the same marked gameplay run"},
        {"type": "geometry_scope", "claim": "MC geometry oracle checks passed",
         "observed": "Algorithm evidence does not verify native engine materials, collisions, crash safety or actual in-game appearance",
         "action": "Accept algorithm independently; keep in-game visual and cold-load cases open"},
    ]
    report = {"schema_version": 1, "audited_utc": utc(now), "scope": "read_only_files",
              "source_manifest": source_manifest(fusion), "branch_reports": branches, "passive_snapshot": passive,
              "state_file_updated_utc": stale_state.get("updated_utc"), "contradictions": contradictions,
              "environment_contract": spec.get("environment_contract", {}),
              "current_profile": active_profile(),
              "observed_environment_snapshot": read_json(HERE/"runtime-readonly-current.json") if (HERE/"runtime-readonly-current.json").exists() else None,
              "observed_hardware_snapshot": read_json(HERE/"hardware-readonly-current.json") if (HERE/"hardware-readonly-current.json").exists() else None,
              "cases": cases, "summary": dict(Counter(c["status"] for c in cases)), "full_goal_complete": False,
              "limits": ["No graphical lease used", "No backend/RPC or production save access", "Owner completion claims are not promoted to player-facing proof"]}
    write_json(args.out, report)
    print(json.dumps({"out": str(Path(args.out).resolve()), "summary": report["summary"], "branch_reports": len(branches), "full_goal_complete": False}, ensure_ascii=False))


def show_matrix(args):
    d = matrix()
    if args.json: print(json.dumps(d, ensure_ascii=False, indent=2)); return
    for c in d["cases"]: print(f'{c["id"]}\t{c["owner"]}\t{c["requirement"]}\t{",".join(c["phases"])}')


def cli():
    p = argparse.ArgumentParser(description=__doc__); sub = p.add_subparsers(dest="command", required=True)
    a = sub.add_parser("audit"); a.add_argument("--workspace", default=str(WORKSPACE)); a.add_argument("--bridge"); a.add_argument("--out", default=str(HERE/"audit-current.json")); a.set_defaults(func=audit)
    a = sub.add_parser("matrix"); a.add_argument("--json", action="store_true"); a.set_defaults(func=show_matrix)
    a = sub.add_parser("retain-evidence"); a.add_argument("--review", required=True); a.add_argument("--workspace", default=str(WORKSPACE)); a.add_argument("--out", required=True); a.set_defaults(func=retain_evidence)
    a = sub.add_parser("init"); a.add_argument("--run", required=True); a.add_argument("--workspace", default=str(WORKSPACE)); a.add_argument("--bridge", required=True); a.add_argument("--operator", required=True); a.add_argument("--fixture", action="store_true"); a.set_defaults(func=init)
    a = sub.add_parser("mark"); a.add_argument("--run", required=True); a.add_argument("phase"); a.add_argument("--params"); a.set_defaults(func=mark)
    a = sub.add_parser("collect"); a.add_argument("--run", required=True); a.add_argument("--seconds", type=float, default=900); a.add_argument("--interval", type=float, default=.25); a.add_argument("--lease-id"); a.set_defaults(func=collect)
    a = sub.add_parser("attach"); a.add_argument("--run", required=True); a.add_argument("--phase", required=True); a.add_argument("--kind", choices=sorted(ARTIFACT_KINDS), required=True); a.add_argument("--role", default="witness"); a.add_argument("--file", required=True); a.add_argument("--observed-utc", required=True); a.add_argument("--historical", action="store_true"); a.set_defaults(func=attach)
    a = sub.add_parser("observe"); a.add_argument("--run", required=True); a.add_argument("--case", required=True); a.add_argument("--phase", required=True); a.add_argument("--criterion", required=True); a.add_argument("--verdict", choices=["pass", "fail"], required=True); a.add_argument("--evidence", nargs="*"); a.add_argument("--note", required=True); a.set_defaults(func=observe)
    a = sub.add_parser("check-delta"); a.add_argument("--run", required=True); a.add_argument("--case", required=True); a.add_argument("--criterion", required=True); a.add_argument("--phase", required=True); a.add_argument("--before", required=True); a.add_argument("--after", required=True); a.add_argument("--player", required=True); a.add_argument("--expected", required=True); a.set_defaults(func=check_delta)
    a = sub.add_parser("check-exchange"); a.add_argument("--run", required=True); a.add_argument("--artifact", required=True); a.add_argument("--durable", action="store_true"); a.set_defaults(func=check_exchange)
    a = sub.add_parser("evaluate"); a.add_argument("--run", required=True); a.set_defaults(func=evaluate)
    args = p.parse_args()
    if args.command == "collect" and (args.seconds <= 0 or args.interval < .05): p.error("Positive duration and interval >= .05s required")
    try: return args.func(args) or 0
    except (ValueError, OSError, KeyError, StopIteration) as e: p.exit(1, f"acceptance: {e}\n")


if __name__ == "__main__": sys.exit(cli())
