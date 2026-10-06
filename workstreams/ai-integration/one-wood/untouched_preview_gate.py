#!/usr/bin/env python3
"""Read-only gate for an untouched server storage preview. Never sends a request or edits a plan."""
import argparse, json, uuid
from pathlib import Path
BASE = "00000000-0000-4000-8000-000000000031"
CIDS = ["00000000-0000-4000-8000-000000000025","00000000-0000-4000-8000-00000000001e"]
ZERO = "00000000-0000-0000-0000-000000000000"
def assess(plan):
    ops = plan.get("operations")
    if plan.get("base_id") != BASE or not isinstance(ops, list) or len(ops) != 1 or plan.get("operation_count") != 1:
        return {"eligible": False, "reason": "server plan is not exactly one operation in the selected base", "operation_count": plan.get("operation_count")}
    op = ops[0]
    src, dst = op.get("from", {}), op.get("to", {})
    expected = op.get("expected_source", {})
    if sorted([src.get("container_id"), dst.get("container_id")]) != sorted(CIDS):
        return {"eligible": False, "reason": "operation does not connect exactly the two selected ordinary containers"}
    if op.get("count") != 1 or expected.get("item") != "Wood":
        return {"eligible": False, "reason": "server-generated operation is not Wood count1", "actual_count": op.get("count"), "actual_item": expected.get("item")}
    if expected.get("dynamicGuid") != ZERO or expected.get("dynamicWorldGuid") != ZERO:
        return {"eligible": False, "reason": "ordinary static Wood identity required"}
    for key in ("plan_id", "expected_revision"):
        uuid.UUID(plan[key])
    # This only emits the existing public apply fields; the runtime must still execute native guards.
    return {"eligible": True, "apply_fields": {"plan_id": plan["plan_id"], "expected_revision": plan["expected_revision"]},
            "runtime_still_selects_fresh_idempotency_key": True,
            "native_guards_or_world_ownership_not_bypassed": True,
            "request_executed": False}
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("preview")
    args = p.parse_args()
    data = json.loads(Path(args.preview).read_text(encoding="utf-8-sig"))
    plan = data.get("result", data)
    print(json.dumps(assess(plan), ensure_ascii=False, indent=2))
if __name__ == "__main__":
    main()

