#!/usr/bin/env python3
"""Build a player release from a reviewed payload spec; no deployment or downloads."""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.core import PlayerError
from installer.packaging import build_distribution, build_release
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--spec', required=True, help='已审批的 payload JSON，逐文件列source/target/role与版本兼容性')
parser.add_argument('--output', required=True)
parser.add_argument('--release-only', action='store_true')
args = parser.parse_args()
try:
    result = (build_release if args.release_only else build_distribution)(args.spec, args.output)
except PlayerError as exc:
    print(json.dumps(exc.as_dict(), ensure_ascii=False))
    raise SystemExit(2)
print(json.dumps(result, ensure_ascii=False, indent=2))
