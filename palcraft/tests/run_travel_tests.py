"""Small source/fault checks only; no server, game, RPC, GUI, or scale workload."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua", required=True)
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--evidence", type=pathlib.Path, required=True)
    parser.add_argument("--scratch", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    args.scratch.mkdir(parents=True, exist_ok=True)
    suites = []
    for suite in ("travel_contract", "travel_actor", "travel_journal"):
        script = args.root / "tests" / f"{suite}.lua"
        result = subprocess.run(
            [args.lua, str(script), str(args.root), str(args.scratch)],
            text=True, capture_output=True, check=False,
        )
        if result.returncode:
            print(result.stderr or result.stdout, file=sys.stderr)
            return result.returncode
        report = json.loads(result.stdout)
        report["source_sha256"] = hashlib.sha256(script.read_bytes()).hexdigest()
        report["mode"] = "night_low_power"
        suites.append(report)
        (args.evidence / f"{suite}.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    summary = {
        "task": "dimension_travel", "mode": "night_low_power",
        "passed": sum(suite["passed"] for suite in suites), "suites": suites,
        "live_pal_trip_verified": False, "engine_compound_collision_verified": False,
        "power_loss_durability_verified": False, "scale_benchmark_executed": False,
        "timings_are_performance_baseline": False,
    }
    (args.evidence / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"passed": summary["passed"], "mode": "night_low_power", "live_pal_trip_verified": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
