"""Load one frozen core overlay and its already-approved normal data producer into the original complete CLI."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import sys
sys.dont_write_bytecode = True

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-source', type=Path, required=True)
    args, original_args = parser.parse_known_args(argv)
    if not original_args:
        parser.error('Pass an original CLI command after --tool-source')
    root = Path(__file__).resolve().parent
    sys.path.insert(0, str(args.tool_source.resolve()))
    for name, relative in (('installer.core', 'source/installer/core.py'),
                           ('installer.standalone', 'dependencies/installer/standalone.py')):
        path = root / relative
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    from installer.cli import main as original_main
    return original_main(original_args)

if __name__ == '__main__':
    raise SystemExit(main())
