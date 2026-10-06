"""Numerical sidecar checks only. No scene render or candidate image delivered."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util, json, hashlib
from PIL import Image

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("pixels", ROOT / "prepare_material_pixels.py")
pixels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixels)

with TemporaryDirectory(dir=ROOT) as tmp:
    tmp = Path(tmp)
    source, output = tmp / "models-v4-fixture", tmp / "sidecars"
    path = source / "textures/minecraft/block/oak_leaves.png"
    path.parent.mkdir(parents=True)
    raw = bytes([255,128,32,0, 12,24,48,255, 8,16,32,127, 100,80,60,255])
    Image.frombytes("RGBA", (2,2), raw).save(path)
    original_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    index = pixels.prepare(source, output, ["minecraft:block/oak_leaves"], nearest_min_size=4)
    row = index["textures"]["textures/minecraft/block/oak_leaves.png"]
    assert row["width"] == row["height"] == 4 and row["nearest_scale"] == 2
    made = (output / row["path"]).read_bytes()
    for y in range(4):
        for x in range(4):
            a, b = (y*4+x)*4, ((y//2)*2+x//2)*4
            assert made[a:a+4] == raw[b:b+4]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == original_hash
    assert index["source_modified"] is False and row["alpha"] == "straight"
    assert row["source_width"] == row["source_height"] == 2
print(json.dumps({"ok":True,"nearest_every_RGBA_texel_repeated_exactly":True,
    "source_PNG_unchanged":True,"alpha_unchanged":True,"scene_or_engine_called":False}))
