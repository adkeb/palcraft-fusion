#!/usr/bin/env python3
"""A01: four existing read-only AI methods; run only in the runtime owner's ready window."""
import argparse
import importlib.util
import json
import time
import uuid
from pathlib import Path

METHODS = ("status", "bases", "catalog", "storage")
SCOPE_FIELDS = ("world_id", "server_session_id", "player_uid", "guild_id", "base_id", "container_id")
class CheckFailed(RuntimeError):
    pass

def check(condition, message):
    if not condition:
        raise CheckFailed(message)

def integer(value):
    return isinstance(value, int) and not isinstance(value, bool)

def context_load(path):
    context = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    for field in SCOPE_FIELDS:
        value = context.get(field)
        check(isinstance(value, str) and value and "REPLACE" not in value and "<" not in value,
              "Current runtime context required: " + field)
    for field in ("player_uid", "guild_id", "base_id", "container_id"):
        uuid.UUID(context[field])
    check(len(context["world_id"]) == 32 and all(c in "0123456789abcdefABCDEF" for c in context["world_id"]),
          "Use the actual Pal world directory ID from the existing runtime context")
    check(isinstance(context.get("context_evidence"), str) and context["context_evidence"] and "REPLACE" not in context["context_evidence"],
          "Reference the runtime owner's existing current-world/owner receipt")
    return context

def requests_for(context):
    return [
        ("status", {}),
        ("bases", {}),
        ("catalog", {"player_uid": context["player_uid"], "filter": "ItemChest"}),
        ("storage", {"base_id": context["base_id"], "container_ids": [context["container_id"]]}),
    ]

def validate(method, result, context):
    check(isinstance(result, dict), method + ": result object required")
    if method == "status":
        check(result.get("offline_building") is True, "Original offline building status is unavailable")
        check(result.get("adapter") == "saved_owner_server_spawn", "Original saved-owner adapter is unavailable")
        modes = result.get("modes")
        check(isinstance(modes, list) and "survival" in modes and "creative" in modes, "Original AI modes missing")
        check(integer(result.get("online_controllers")) and result["online_controllers"] >= 0,
              "Actual controller count missing")
        return {"adapter": result["adapter"], "online_controllers": result["online_controllers"]}
    if method == "bases":
        check(result.get("ok") is True and isinstance(result.get("bases"), list), "Live base reader failed")
        rows = [row for row in result["bases"] if row.get("id") == context["base_id"]]
        check(len(rows) == 1, "Selected current base missing or ambiguous")
        row = rows[0]
        check(row.get("ok") is True and row.get("available") is True, "Selected base is unavailable")
        check(row.get("group_id") == context["guild_id"], "Selected base differs from the operator's current guild")
        return {"base_id": row["id"], "guild_id": row["group_id"], "building_count": row.get("building_count")}
    if method == "catalog":
        check(isinstance(result.get("builds"), list), "Actual recipe/technology list missing")
        rows = [row for row in result["builds"] if row.get("id") == "ItemChest"]
        check(len(rows) == 1, "Original ItemChest recipe missing or ambiguous")
        row = rows[0]
        check(isinstance(row.get("unlocked"), bool), "Actual saved-account technology state missing")
        check(isinstance(row.get("materials"), list), "Actual native recipe materials missing")
        for material in row["materials"]:
            check(isinstance(material.get("item"), str) and integer(material.get("count")) and material["count"] > 0,
                  "Malformed native recipe material")
        # A locked state is a real current technology result, not a bypass or a failed reader.
        return {"build_id": row["id"], "unlocked": row["unlocked"], "materials": row["materials"], "work": row.get("work")}
    check(method == "storage", "Read-only method allowlist violated")
    check(result.get("ok") is True and result.get("includes_items") is True, "Live ordinary storage reader failed")
    check(isinstance(result.get("chests"), list), "Ordinary storage rows missing")
    check(len(result["chests"]) == 1,
          "Selected ordinary chest absent/filtered/ambiguous; an empty result does not prove an empty escrow chest")
    row = result["chests"][0]
    check(row.get("id") == context["container_id"] and row.get("actual_id") == context["container_id"],
          "Actual container identity mismatch")
    for field in ("ok", "verified_live", "ownership_verified_live", "eligible_for_snapshot_plan"):
        check(row.get(field) is True, "Actual ordinary container check failed: " + field)
    check(row.get("base_id_live") == context["base_id"] and row.get("group_id_live") == context["guild_id"],
          "Actual container base/guild mismatch")
    check(result.get("force_concrete_requested") is False, "A read-only no-force lookup is required")
    slots = row.get("slots")
    check(integer(row.get("capacity")) and isinstance(slots, list) and len(slots) == row["capacity"],
          "The actual full slot list is required")
    check({slot.get("index") for slot in slots} == set(range(row["capacity"])), "Slot coverage is incomplete")
    totals = {}
    for slot in slots:
        check(integer(slot.get("count")) and slot["count"] >= 0, "Actual slot count invalid")
        if slot["count"] > 0:
            check(isinstance(slot.get("item"), str), "Actual item ID missing")
            totals[slot["item"]] = totals.get(slot["item"], 0) + slot["count"]
    return {"container_id": row["id"], "base_id": row["base_id_live"], "guild_id": row["group_id_live"],
            "capacity": row["capacity"], "item_totals": dict(sorted(totals.items())),
            "owner_permission_claimed": False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, help="Current operator-selected context; this is not a new certificate")
    parser.add_argument("--output", required=True)
    parser.add_argument("--ai-client", help="Existing ai_client.py; imported only for an explicitly requested execution")
    parser.add_argument("--execute", action="store_true", help="Runtime owner only, after the new root is ready")
    parser.add_argument("--reuse", help="Reuse the same ready-window base-food receipts; make zero additional RPC calls")
    args = parser.parse_args()
    check(not (args.execute and args.reuse), "Choose execution or existing-receipt reuse")
    context = context_load(args.context)
    requests = requests_for(context)
    report = {
        "schema": 1, "case": "A01", "scope": {key: context[key] for key in SCOPE_FIELDS},
        "context_evidence": context["context_evidence"],
        "scope_origin": "runtime owner supplied actual world/owner context; legacy AI replies do not attest a world tuple",
        "started_unix": time.time(), "responses": [], "rpc_calls": 0,
        "construction_calls": 0, "storage_move_calls": 0, "materials_consumed_by_this_chain": 0,
        "new_paid_build_verified": False, "overall_A01_accepted": False,
        "historical_paid_evidence_reused_separately": True,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if not args.execute and not args.reuse:
        report.update(status="prepared_not_executed", requests=[{"method": m, "params": p} for m, p in requests])
        save()
        return
    collected = None
    call = None
    if args.reuse:
        collected = json.loads(Path(args.reuse).read_text(encoding="utf-8-sig"))
        check(all(collected.get("scope", {}).get(key) == context[key] for key in SCOPE_FIELDS),
              "Reused inventory receipts must belong to this same runtime-selected world/owner/container context")
        check(isinstance(collected.get("responses"), list), "Existing response records missing")
    else:
        check(args.ai_client is not None, "An existing AI client path is required")
        spec = importlib.util.spec_from_file_location("a01_existing_ai_client", args.ai_client)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        call = module.call
    try:
        seen = set()
        for method, params in requests:
            if collected is not None:
                rows = [row for row in collected["responses"] if row.get("method") == method and row.get("params") == params]
                check(len(rows) == 1, "Missing or ambiguous same-flow receipt: " + method)
                row = rows[0]
                request_id = row["request_id"]
                uuid.UUID(request_id)
                result = row["result"]
                source = "same_ready_window_base_food_receipt"
            else:
                request_id = str(uuid.uuid4())
                report["attempting"] = {"method": method, "params": params, "request_id": request_id}
                save()
                report["rpc_calls"] += 1
                # The existing transport retains this same UUID across its internal retries.
                result = call(method, params, request_id)
                source = "existing_AI_file_queue"
            check(request_id not in seen, "Each read needs its own request UUID")
            seen.add(request_id)
            summary = validate(method, result, context)
            report["responses"].append({"request_id": request_id, "method": method, "params": params,
                                       "result": result, "checks": summary, "source": source,
                                       "backend_receipt": "D:/PalworldServer-LAN/BridgeLab/rpc/agent-result-" + request_id + ".json"})
            report.pop("attempting", None)
            save()
        report.update(status="passed_current_read_chain", finished_unix=time.time(),
                      acceptance_boundary="Only the new bootstrap/factory/legacy-dispatch/current-reader connection; no new build, transfer, or full A01 acceptance")
        save()
    except Exception as exc:
        report.update(status="failed_current_read_chain", error=str(exc), finished_unix=time.time())
        save()
        raise

if __name__ == "__main__":
    main()

