#!/usr/bin/env python3
"""构建完整普通目录客户端 proposal；不安装、启动或部署。"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.core import PlayerError
from installer.proposal import proposal

parser = argparse.ArgumentParser(description=__doc__)
for name in ('staging', 'baseline-manifest', 'baseline-zip', 'client-map', 'output', 'version'):
    parser.add_argument('--' + name, required=True)
args = parser.parse_args()
try:
    result = proposal(args.staging, args.baseline_manifest, args.baseline_zip, args.client_map, args.output, args.version)
except PlayerError as exc:
    print(json.dumps(exc.as_dict(), ensure_ascii=False))
    raise SystemExit(2)
print(json.dumps(result, ensure_ascii=False, indent=2))
