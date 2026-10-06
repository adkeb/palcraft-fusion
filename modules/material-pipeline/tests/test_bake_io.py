"""Small standalone bake/file-boundary test. Never loads Unreal or a game process."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from PIL import Image

exe=Path(os.sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='palcraft-material-',dir=str(Path('work/minecraft-fusion/material-pipeline').resolve()))as temporary:
 root=Path(temporary)
 source=root/'material-pixels-v1/textures/minecraft/block/test.png.rgba'
 source.parent.mkdir(parents=True)
 source.write_bytes(bytes([255,128,0,0,0,255,128,255]))
 input_path=source.relative_to(root).as_posix()
 output_path='material-cache-v1/test_804020.png'
 wire=struct.pack('<8s6I',b'PALCMAT1',2,1,0x804020,len(input_path),len(output_path),0)+input_path.encode()+output_path.encode()
 (root/'material-bake-request.bin').write_bytes(wire)
 env=dict(os.environ,PALCRAFT_BRIDGE_DIR=str(root))
 subprocess.run([str(exe)],check=True,env=env,stdout=subprocess.DEVNULL)
 assert json.loads((root/'material-bake-result.json').read_text())['ok']
 with Image.open(root/output_path)as image:
  assert image.getpixel((0,0))==(128,32,0,0) and image.getpixel((1,0))==(0,64,16,255)
 outside='../bad.png'
 (root/'material-bake-request.bin').write_bytes(struct.pack('<8s6I',b'PALCMAT1',2,1,0x804020,len(input_path),len(outside),0)+input_path.encode()+outside.encode())
 subprocess.run([str(exe)],check=True,env=env,stdout=subprocess.DEVNULL)
 assert not json.loads((root/'material-bake-result.json').read_text())['ok']
 assert not(root/'../bad.png').exists()
 print('{"status":"passed","png_roundtrip_and_path_boundary":true,"engine_calls":0,"mode":"night_low_power_small_io_contract"}')
