#!/usr/bin/env python3
"""Validate an untouched public two-box preview and emit existing apply fields. No RPC or plan mutation."""
import argparse, json, uuid
from pathlib import Path
BASE="00000000-0000-4000-8000-000000000031"
GUILD="00000000-0000-4000-8000-00000000001b"
CIDS=["00000000-0000-4000-8000-000000000025","00000000-0000-4000-8000-00000000001e"]
def require(value, message):
    if not value:
        raise ValueError(message)
def integer(v):
    return isinstance(v, int) and not isinstance(v, bool)
def validate(plan):
    require(plan.get("base_id")==BASE and plan.get("group_id")==GUILD, "Current selected base/guild mismatch")
    require(plan.get("cross_base") is False and plan.get("ownership_verified_live") is True, "Native ownership/same-base proof missing")
    require(plan.get("scope")=="fixed_snapshot_allowlist", "Original public preview scope missing")
    containers=plan.get("containers")
    require(isinstance(containers,list) and len(containers)==2 and sorted(c.get("id") for c in containers)==sorted(CIDS),
            "The sealed preview must contain exactly the two selected ordinary containers")
    capacities={}
    for c in containers:
        require(c.get("type") in ("ItemChest","ItemChest_02") and integer(c.get("capacity")) and c["capacity"]>0,
                "Actual ordinary type/capacity missing")
        capacities[c["id"]]=c["capacity"]
    def ref(row):
        require(isinstance(row,dict) and row.get("container_id") in capacities
                and integer(row.get("index")) and 0<=row["index"]<capacities[row["container_id"]],
                "A preview slot reference leaves the selected two-box scope")
    operations=plan.get("operations")
    require(isinstance(operations,list) and len(operations)>0 and plan.get("operation_count")==len(operations),
            "A genuine nonempty public operation list is required for this mutation boundary")
    for n,op in enumerate(operations,1):
        require(op.get("sequence")==n, "Operation order differs from server preview")
        ref(op.get("from"));ref(op.get("to"))
        require(integer(op.get("count")) and op["count"]>0, "Actual positive native move quantity missing")
        source=op.get("expected_source")
        require(isinstance(source,dict) and isinstance(source.get("item"),str)
                and integer(source.get("count")) and 0<op["count"]<=source["count"], "Original source preimage missing")
        if op.get("kind")=="merge":
            target=op.get("expected_target")
            require(isinstance(target,dict) and target.get("item")==source["item"]
                    and target.get("dynamicGuid")==source.get("dynamicGuid")
                    and target.get("dynamicWorldGuid")==source.get("dynamicWorldGuid"),
                    "Server merge preimages differ in full item identity")
        else:
            require(op.get("expected_target_empty") is True and op["count"]==source["count"],
                    "Original full-stack-to-empty semantics missing")
    for row in plan.get("stacks",[]):ref(row["origin"])
    for row in plan.get("initial_slots",[]):ref(row)
    for row in plan.get("assignments",[]):
        if "from" in row:ref(row["from"])
        if "to" in row:ref(row["to"])
    for key in ("plan_id","expected_revision","server_instance_id"):uuid.UUID(plan[key])
    return {"base_id":BASE,"group_id":GUILD,"container_ids":CIDS,"operation_count":len(operations),
            "merge_operation_count":plan.get("merge_operation_count"),
            "all_endpoints_inside_two_boxes":True,
            "moves":[{"sequence":op["sequence"],"kind":op.get("kind","full_stack"),
                      "item":op["expected_source"]["item"],"count":op["count"],
                      "from":op["from"],"to":op["to"]} for op in operations],
            "public_apply_fields":{"plan_id":plan["plan_id"],"expected_revision":plan["expected_revision"]},
            "native_baseline_expiry_instance_reserved_and_readback_checks_still_required":True}
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("preview")
    p.add_argument("--summary",required=True)
    p.add_argument("--apply-payload",required=True)
    args=p.parse_args()
    data=json.loads(Path(args.preview).read_text(encoding="utf-8-sig"))
    plan=data.get("result",data)
    summary=validate(plan)
    apply={**summary["public_apply_fields"],"idempotency_key":str(uuid.uuid4())}
    for filename,value in ((args.summary,summary),(args.apply_payload,apply)):
        path=Path(filename)
        require(not path.exists(),"Preserve the already prepared apply identity; do not overwrite: "+filename)
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(summary,ensure_ascii=False,indent=2))
if __name__=="__main__":main()

