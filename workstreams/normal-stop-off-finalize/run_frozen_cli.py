#!/usr/bin/env python3
"""Execute the original revised CLI from frozen source, never copy over installed modules."""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
from pathlib import Path

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('--tool-source', required=True, type=Path)
args, command = parser.parse_known_args()
base = args.tool_source.resolve()
required = {'installer/core.py': '9880d8dd8d4e672cf13836e4ca10e4d553a5fdf5886a73b40bd5418ce81fbcee',
            'launcher/runtime.py': '5bbfefec5387d596101a869a44c2e2407eeedf5326d062faae12d490a1f3684e'}
for relative, sha in required.items():
    if hashlib.sha256((base / relative).read_bytes()).hexdigest() != sha:
        raise SystemExit('Frozen base source differs: ' + relative)
source = Path(__file__).resolve().parent / 'source'
sys.path.insert(0, str(base))
import installer, launcher
installer.__path__.insert(0, str(source / 'installer'))
launcher.__path__.insert(0, str(source / 'launcher'))
from installer.cli import main
raise SystemExit(main(command))
