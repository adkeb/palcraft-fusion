"""Verify converted pixel data and all blockstate references against the jar."""
import io
import json
import zipfile
from pathlib import Path
from PIL import Image

root = Path("work/minecraft-fusion/model-compat/assets-v2")
jar = zipfile.ZipFile("work/minecraft-fusion/palcraft/mc/minecraft-client-26.3.jar")
reference_count = 0
missing = []
for path in (root / "states").rglob("*.json"):
    state = json.loads(path.read_text())
    specs = list(state.get("variants", {}).values()) + [part["apply"] for part in state.get("multipart", [])]
    for spec in specs:
        for value in spec if isinstance(spec, list) else [spec]:
            name = value["model"] if ":" in value["model"] else "minecraft:" + value["model"]
            namespace, name = name.split(":", 1)
            target = root / "models" / namespace / (name + ".json")
            if not target.exists():
                missing.append({"state": str(path), "model": name})
            else:
                data = json.loads(target.read_text())
                assert data.get("faces") or data.get("empty") or data.get("special_model_required"), str(target)
            reference_count += 1
assert not missing, missing

verified = animations = 0
for meta_path in (root / "textures").rglob("*.json"):
    info = json.loads(meta_path.read_text())
    local = meta_path.relative_to(root / "textures")
    source = Image.open(io.BytesIO(jar.read("assets/" + str(local.with_suffix(".png")).replace("/", "/textures/", 1)))).convert("RGBA")
    animation = info.get("animation")
    if animation:
        index = animation["frames"][0]["index"]
        w, h, columns = animation["width"], animation["height"], animation["columns"]
        x, y = index % columns * w, index // columns * h
        source = source.crop((x, y, x + w, y + h))
        animations += 1
    expected = source.resize(info["import_size"], Image.Resampling.NEAREST)
    actual = Image.open(meta_path.with_suffix(".png")).convert("RGBA")
    assert actual.size == expected.size and actual.tobytes() == expected.tobytes(), str(meta_path)
    verified += 1
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["issues"] == []
result = {"status": "passed", "blockstate_model_references": reference_count,
          "exact_pixel_textures": verified, "exact_animation_first_frames": animations,
          "remaining_special_models": len(manifest["special_models"]),
          "known_empty_models": len(manifest["empty_models"]), "missing_references": []}
(root.parent / "asset-verification.json").write_text(json.dumps(result, indent=2))
print(json.dumps(result))
