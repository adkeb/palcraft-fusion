#!/usr/bin/env python3
import argparse
import datetime
import io
import json
import time
import unittest
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--report', required=True)
parser.add_argument('--log', required=True)
args = parser.parse_args()
suite = unittest.defaultTestLoader.discover(str(Path(__file__).parent), pattern='test_*.py')
started = time.monotonic()
stream = io.StringIO()
result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
Path(args.log).write_text(stream.getvalue(), encoding='utf-8')
report = {'schema': 1, 'task': 'player_install', 'ok': result.wasSuccessful(), 'tests_run': result.testsRun,
          'failures': [{'test': str(t), 'traceback': trace} for t, trace in result.failures],
          'errors': [{'test': str(t), 'traceback': trace} for t, trace in result.errors],
          'duration_seconds': round(time.monotonic() - started, 3),
          'tested_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'runtime': 'temporary fake game/bottle/processes and ephemeral loopback echo sockets only',
          'live_game_or_server_mutations': []}
Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: v for k, v in report.items() if k not in ('failures', 'errors')}, ensure_ascii=False))
raise SystemExit(0 if result.wasSuccessful() else 1)
