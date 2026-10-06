"""Prepare exact RGBA sidecars for runtime tinting; never edits the frozen model package."""
import argparse
import hashlib
import json
from pathlib import Path


def prepare(asset_root, output_root, sprites):
    from PIL import Image
    asset_root, output_root = Path(asset_root), Path(output_root)
    if asset_root.resolve() == output_root.resolve():
        raise ValueError("pixel sidecars require a separate output directory")
    output_root.mkdir(parents=True, exist_ok=True)
    records = {}
    for sprite in sprites:
        if ":" in sprite:
            sprite = sprite.replace(":", "/", 1)
        if ".." in sprite or sprite.startswith("/") or not sprite:
            raise ValueError("invalid sprite")
        relative = Path("textures") / (sprite + ".png")
        meta = asset_root / "textures" / (sprite + ".json")
        paths = [relative]
        if meta.is_file():
            info = json.loads(meta.read_text())
            animation = info.get("animation")
            if isinstance(animation, dict):
                frames_dir = animation.get("frames_dir")
                if frames_dir and ".." not in frames_dir and not frames_dir.startswith("/"):
                    paths += [Path(frames_dir) / f"{f['index']:04d}.png" for f in animation["frames"]]
        for path in dict.fromkeys(paths):
            image = Image.open(asset_root / path).convert("RGBA")
            width, height = image.size
            if not 0 < width <= 1024 or not 0 < height <= 1024:
                raise ValueError(f"pixel sidecar dimensions too large: {path}")
            raw = image.tobytes()
            destination = Path(str(path) + ".rgba")
            full = output_root / destination
            full.parent.mkdir(parents=True, exist_ok=True)
            full.write_bytes(raw)
            records[path.as_posix()] = dict(path=destination.as_posix(), width=width, height=height,
                sha256=hashlib.sha256(raw).hexdigest(), alpha="straight", tint="caller BlockColors RGB, byte multiply")
    index = dict(version=1, source_root=asset_root.name, source_modified=False, textures=records)
    (output_root / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    return index


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset_root")
    parser.add_argument("output_root", help="Separate bridge/material-pixels-v1 directory")
    parser.add_argument("sprites", nargs="+", help="Only the actual tinted sprites needed by this world; avoids processing every animated texture.")
    args = parser.parse_args()
    index = prepare(args.asset_root, args.output_root, args.sprites)
    print(json.dumps(dict(status="ready",textures=len(index["textures"]),source_modified=False)))
