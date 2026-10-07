"""Use the original standalone launcher with one frozen managed backend prepare module."""
import argparse,hashlib,importlib.util,runpy,sys
from pathlib import Path
sys.dont_write_bytecode=True
parser=argparse.ArgumentParser(add_help=False);parser.add_argument('--tool-source',type=Path,required=True)
args,remaining=parser.parse_known_args();sys.path.insert(0,str(args.tool_source.resolve()))
p=Path(__file__).resolve().parent/'source/installer/standalone.py'
assert hashlib.sha256(p.read_bytes()).hexdigest()=='63a020738189c0b9560336fff25bafde4bef9915fa54d60a522698669f09275e'
import installer.core
spec=importlib.util.spec_from_file_location('installer.standalone',p)
module=importlib.util.module_from_spec(spec);sys.modules['installer.standalone']=module;spec.loader.exec_module(module)
sys.argv=[str(args.tool_source/'launcher/install_standalone.py')]+remaining
runpy.run_path(sys.argv[0],run_name='__main__')
