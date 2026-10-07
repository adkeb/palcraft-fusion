"""Use the original complete player CLI with exactly three frozen source overlays."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
PINS = {
    'installer.core': ('source/installer/core.py', 'f2cfa4048da10ad3b2b5813bc7b2bf37b40b866a0dc3b8a5355726dec46a34fb'),
    'launcher.journal_lifecycle': ('source/launcher/journal_lifecycle.py', 'bab797abf0ba93f7ce63528d8539c0598107a42f995e7a5c184bcc7ee4b2ba07'),
    'installer.cli': ('source/installer/cli.py', '0ce1116ec34d8706131b1e6f36084631ed1c8309b42028d25a09112fd2f95acf'),
}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser.add_argument('--tool-source', type=Path, required=True)
    args, original_args = parser.parse_known_args(argv)
    if not original_args:
        parser.error('Pass an original CLI command after --tool-source')
    folder = Path(__file__).resolve().parent
    sys.path.insert(0, str(args.tool_source.resolve()))
    for name, (relative, expected) in PINS.items():
        path = folder / relative
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit('Frozen source pin differs: ' + relative)
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    return sys.modules['installer.cli'].main(original_args)


if __name__ == '__main__':
    raise SystemExit(main())
