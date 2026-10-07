"""Run the complete original CLI with one frozen journal source overlay."""
import argparse,hashlib,importlib.util,sys
from pathlib import Path
sys.dont_write_bytecode=True
parser=argparse.ArgumentParser(add_help=False)
parser.add_argument('--tool-source',type=Path,required=True)
args,remaining=parser.parse_known_args()
source=Path(__file__).resolve().parent/'source/launcher/journal_lifecycle.py'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='1b310fc8067b6a92c209722d40c6c6c7679b119ce9f9894570435fadb0797448'
sys.path.insert(0,str(args.tool_source.resolve()))
import installer.core
spec=importlib.util.spec_from_file_location('launcher.journal_lifecycle',source)
module=importlib.util.module_from_spec(spec);sys.modules['launcher.journal_lifecycle']=module;spec.loader.exec_module(module)
from installer.cli import main
raise SystemExit(main(remaining))
