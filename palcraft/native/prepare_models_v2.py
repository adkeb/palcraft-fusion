"""Convert installed Java Minecraft assets for PalCraft's native renderer.

Output is compatible with prepare_models.py's faces/vertices/normal/uv schema.
Additional metadata describes cutout/translucent materials, animation, culling,
lighting and models that need a block-entity/fluid renderer. Resource-pack zips
may override the client jar in the same order as Minecraft's resource stack.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import zipfile
from collections import Counter
from pathlib import Path

from PIL import Image

NORMALS = {
    "down": (0, -1, 0), "up": (0, 1, 0), "north": (0, 0, -1),
    "south": (0, 0, 1), "west": (-1, 0, 0), "east": (1, 0, 0),
}


def resource(name):
    return name if ":" in name else "minecraft:" + name


def resource_path(kind, name, suffix=".json"):
    namespace, path = resource(name).split(":", 1)
    return f"assets/{namespace}/{kind}/{path}{suffix}"


def rotate(vector, axis, degrees):
    p = list(vector)
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    i = "xyz".index(axis)
    j, k = (i + 1) % 3, (i + 2) % 3
    p[j], p[k] = c * p[j] - s * p[k], s * p[j] + c * p[k]
    return p


def element_transform(position, rotation):
    """26.3 CuboidRotation: Rz*Ry*Rx; rescale each matrix column first."""
    if not rotation:
        return list(position)
    rotations = ([(rotation["axis"], rotation["angle"])]
                 if "axis" in rotation else [(a, rotation.get(a, 0)) for a in "xyz"])
    columns = []
    for axis in range(3):
        column = [float(axis == i) for i in range(3)]
        for name, degrees in rotations:
            column = rotate(column, name, degrees)
        if rotation.get("rescale", False):
            scale = 1 / max(abs(value) for value in column)
            column = [value * scale for value in column]
        columns.append(column)
    origin = rotation.get("origin", [8, 8, 8])
    local = [position[i] - origin[i] for i in range(3)]
    return [origin[i] + sum(columns[j][i] * local[j] for j in range(3)) for i in range(3)]


def vertices(a, b):
    x, y, z = a
    X, Y, Z = b
    return {
        "down": [(x, y, Z), (x, y, z), (X, y, z), (X, y, Z)],
        "up": [(x, Y, z), (x, Y, Z), (X, Y, Z), (X, Y, z)],
        "north": [(X, Y, z), (X, y, z), (x, y, z), (x, Y, z)],
        "south": [(x, Y, Z), (x, y, Z), (X, y, Z), (X, Y, Z)],
        "west": [(x, Y, z), (x, y, z), (x, y, Z), (x, Y, Z)],
        "east": [(X, Y, Z), (X, y, Z), (X, y, z), (X, Y, z)],
    }


def default_uvs(a, b):
    x, y, z = a
    X, Y, Z = b
    return {
        "down": [x, 16 - Z, X, 16 - z], "up": [x, z, X, Z],
        "north": [16 - X, 16 - Y, 16 - x, 16 - y],
        "south": [x, 16 - Y, X, 16 - y],
        "west": [z, 16 - Y, Z, 16 - y],
        "east": [16 - Z, 16 - Y, 16 - z, 16 - y],
    }


def face_normal(points, fallback):
    a = [points[1][i] - points[0][i] for i in range(3)]
    b = [points[2][i] - points[0][i] for i in range(3)]
    n = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    length = math.sqrt(sum(value * value for value in n))
    return [value / length for value in n] if length > 1e-12 else list(fallback)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


class Converter:
    def __init__(self, jar, destination, resource_packs=(), texture_min_size=256, block_entity_models=None):
        self.sources = [zipfile.ZipFile(path) for path in [jar, *resource_packs]]
        self.paths = {path for source in self.sources for path in source.namelist()}
        self.out = Path(destination)
        self.texture_min_size = texture_min_size
        self.model_cache = {}
        self.texture_cache = {}
        self.issues = []
        self.counts = Counter()
        self.special = []
        self.empty = []
        self.jar = Path(jar)
        self.block_entity_models = Path(block_entity_models) if block_entity_models else None

    def read(self, path):
        for source in reversed(self.sources):
            try:
                return source.read(path)
            except KeyError:
                pass
        raise KeyError(path)

    def load_model(self, name, chain=()):
        name = resource(name)
        if name in self.model_cache:
            return self.model_cache[name]
        if name in chain:
            raise ValueError("cyclic model inheritance: " + " -> ".join((*chain, name)))
        own = json.loads(self.read(resource_path("models", name)))
        parent = self.load_model(own["parent"], (*chain, name)) if "parent" in own else {}
        result = {**parent, **own, "textures": {**parent.get("textures", {}), **own.get("textures", {})}}
        self.model_cache[name] = result
        return result

    def resolve_texture(self, texture, data):
        seen = set()
        # Heavy-core's shipped 26.3 model names the slot "all" without '#'.
        if isinstance(texture, str) and texture in data.get("textures", {}):
            texture = "#" + texture
        while isinstance(texture, str) and texture.startswith("#"):
            if texture in seen:
                raise ValueError("cyclic texture reference: " + texture)
            seen.add(texture)
            texture = data["textures"][texture[1:]]
        forced = isinstance(texture, dict) and texture.get("force_translucent", False)
        if isinstance(texture, dict):
            texture = texture["sprite"]
        return resource(texture), forced

    def export_texture(self, name):
        if name in self.texture_cache:
            return self.texture_cache[name]
        png = self.read(resource_path("textures", name, ".png"))
        image = Image.open(io.BytesIO(png)).convert("RGBA")
        try:
            meta = json.loads(self.read(resource_path("textures", name, ".png.mcmeta")))
        except KeyError:
            meta = {}
        animation = meta.get("animation")
        frame = image
        animation_info = None
        if animation is not None:
            # AnimationFrameSize.calculate (Java): unspecified dimensions use
            # min(width,height); either explicitly supplied dimension is honored.
            if "width" in animation:
                fw = animation["width"]
                fh = animation.get("height", image.height)
            elif "height" in animation:
                fw, fh = image.width, animation["height"]
            else:
                fw = fh = min(image.size)
            if fw <= 0 or fh <= 0 or image.width % fw or image.height % fh:
                raise ValueError(f"invalid animation dimensions: {name}")
            columns, rows = image.width // fw, image.height // fh
            sequence = animation.get("frames", list(range(columns * rows)))
            if not sequence:
                sequence = list(range(columns * rows))
            frames = [{"index": value, "time": animation.get("frametime", 1)} if isinstance(value, int)
                      else {"index": value["index"], "time": value.get("time", animation.get("frametime", 1))}
                      for value in sequence]
            if any(value["index"] < 0 or value["index"] >= columns * rows for value in frames):
                raise ValueError(f"invalid animation frame index: {name}")
            first = frames[0]["index"]
            x, y = first % columns * fw, first // columns * fh
            frame = image.crop((x, y, x + fw, y + fh))
            animation_info = {"width": fw, "height": fh, "columns": columns, "rows": rows,
                              "interpolate": animation.get("interpolate", False), "frames": frames}
            self.counts["animated_textures"] += 1
        alpha = set(frame.getchannel("A").tobytes())
        mode = "translucent" if any(0 < value < 255 for value in alpha) else "cutout" if 0 in alpha else "opaque"
        scale = max(1, math.ceil(self.texture_min_size / min(frame.size)))
        enlarged = frame.resize((frame.width * scale, frame.height * scale), Image.Resampling.NEAREST)
        namespace, path = name.split(":", 1)
        target = self.out / "textures" / namespace / (path + ".png")
        target.parent.mkdir(parents=True, exist_ok=True)
        enlarged.save(target)
        if animation_info:
            target.with_suffix(".sheet.png").write_bytes(png)
        info = {"source_sha256": hashlib.sha256(png).hexdigest(), "source_size": list(image.size),
                "frame_size": list(frame.size), "import_size": list(enlarged.size),
                "nearest_scale": scale, "alpha_mode": mode, "animation": animation_info}
        if meta.get("texture"):
            info["sampler"] = meta["texture"]
        write_json(target.with_suffix(".json"), info)
        self.texture_cache[name] = info
        self.counts["textures"] += 1
        self.counts["texture_" + mode] += 1
        return info

    def bake_model(self, name):
        data = self.load_model(name)
        faces = []
        for element in data.get("elements", []):
            points = vertices(element["from"], element["to"])
            defaults = default_uvs(element["from"], element["to"])
            for direction, face in element.get("faces", {}).items():
                texture, forced = self.resolve_texture(face["texture"], data)
                texinfo = self.export_texture(texture)
                positions = [element_transform(p, element.get("rotation")) for p in points[direction]]
                n = face_normal(positions, NORMALS[direction])
                u, v, U, V = face.get("uv", defaults[direction])
                uv = [(u, v), (u, V), (U, V), (U, v)]
                shift = face.get("rotation", 0) // 90 % 4
                uv = uv[shift:] + uv[:shift]
                faces.append({"texture": texture, "vertices": [[c / 16 for c in p] for p in positions],
                              "normal": n, "uv": [[c / 16 for c in p] for p in uv], "direction": direction,
                              "tint": face.get("tintindex", -1), "translucent": forced,
                              "alpha_mode": "translucent" if forced else texinfo["alpha_mode"],
                              "cull": face.get("cullface"), "shade": element.get("shade", True),
                              "light_emission": element.get("light_emission", 0)})
        result = {"schema": 2, "faces": faces, "ambient_occlusion": data.get("ambientocclusion", True)}
        if not faces:
            # Air and moving block entities intentionally have no cuboid JSON.
            # These cannot be silently replaced by a cube or a stone texture.
            result["special_model_required"] = True
            localname = name.split(":", 1)[1]
            if localname in {"block/air", "block/barrier", "block/structure_void"} or (
                localname.startswith("block/light_") and localname.removeprefix("block/light_").isdigit()
            ) or localname in {
                "block/pitcher_crop_top_stage_0", "block/pitcher_crop_top_stage_1", "block/pitcher_crop_top_stage_2"
            }:
                result["empty"] = True
                result.pop("special_model_required", None)
                self.empty.append(name)
            else:
                self.special.append(name)
        if "particle" in data.get("textures", {}):
            try:
                result["particle_texture"] = self.resolve_texture("#particle", data)[0]
                self.export_texture(result["particle_texture"])
            except (KeyError, ValueError):
                pass
        return result

    def export_chests(self):
        if not self.block_entity_models:
            return
        meta = json.loads(self.block_entity_models.with_suffix(".meta.json").read_text())
        source_hash = hashlib.sha256(self.jar.read_bytes()).hexdigest()
        if meta["minecraft_client_sha256"] != source_hash:
            raise ValueError("Block-entity model extraction is from a different Minecraft client jar")
        shapes = {}
        for line in self.block_entity_models.read_text().splitlines():
            row = json.loads(line)
            shapes.setdefault(row["variant"], []).append(row)
        kinds = {"chest": "normal", "trapped_chest": "trapped", "ender_chest": "ender"}
        for prefix, texture in [("", "copper"), ("exposed_", "copper_exposed"),
                                ("weathered_", "copper_weathered"), ("oxidized_", "copper_oxidized")]:
            kinds[prefix + "copper_chest"] = texture
            kinds["waxed_" + prefix + "copper_chest"] = texture
        for block, texture_base in kinds.items():
            original_path = resource_path("blockstates", "minecraft:" + block)
            if original_path not in self.paths:
                continue
            variants = {}
            for variant, rows in shapes.items():
                if block == "ender_chest" and variant != "single":
                    continue
                texture = "minecraft:entity/chest/" + texture_base + ("_" + variant if variant != "single" else "")
                texinfo = self.export_texture(texture)
                faces = []
                for row in rows:
                    normal = row["normal"]
                    direction = max(NORMALS, key=lambda name: sum(a * b for a, b in zip(NORMALS[name], normal)))
                    faces.append({"texture": texture, "vertices": [v[:3] for v in row["vertices"]],
                                  "normal": normal, "uv": [v[3:] for v in row["vertices"]],
                                  "direction": direction, "tint": -1, "translucent": False,
                                  "alpha_mode": texinfo["alpha_mode"], "shade": True, "light_emission": 0,
                                  "part": row["part"]})
                model_id = "minecraft:palcraft/block_entity/chest/" + block + "/" + variant
                target = self.out / "models/minecraft/palcraft/block_entity/chest" / block / (variant + ".json")
                write_json(target, {"schema": 2, "faces": faces, "block_entity": "chest", "closed": True,
                                    "lid_pivot": [0, 9 / 16, 1 / 16], "ambient_occlusion": False})
                self.counts["block_entity_models"] += 1
                for facing, angle in [("south", 0), ("west", 90), ("north", 180), ("east", 270)]:
                    key = "facing=" + facing + (",type=" + variant if block != "ender_chest" else "")
                    variants[key] = {"model": model_id, "y": angle}
            write_json(self.out / "states-original/minecraft" / (block + ".json"), json.loads(self.read(original_path)))
            write_json(self.out / "states/minecraft" / (block + ".json"), {"variants": variants})
            original = "minecraft:block/" + block
            if original in self.special:
                self.special.remove(original)
        self.counts["block_entity_blocks"] = len(kinds)

    def prepare(self):
        states = [p for p in self.paths if "/blockstates/" in p and p.endswith(".json") and p.startswith("assets/")]
        models = [p for p in self.paths if "/models/block/" in p and p.endswith(".json") and p.startswith("assets/")]
        referenced = set()
        def record_spec(spec):
            for value in spec if isinstance(spec, list) else [spec]:
                referenced.add(resource(value["model"]))
        for path in sorted(states):
            parts = path.split("/", 3)
            target = self.out / "states" / parts[1] / parts[3]
            data = json.loads(self.read(path))
            write_json(target, data)
            for spec in data.get("variants", {}).values():
                record_spec(spec)
            for part in data.get("multipart", []):
                record_spec(part["apply"])
            self.counts["blockstates"] += 1
        for path in sorted(models):
            _, namespace, _, modelpath = path.split("/", 3)
            name = namespace + ":" + modelpath.removesuffix(".json")
            try:
                data = self.bake_model(name)
                write_json(self.out / "models" / namespace / modelpath, data)
                self.counts["models"] += 1
                self.counts["faces"] += len(data["faces"])
            except (KeyError, ValueError) as exc:
                if name in referenced:
                    self.issues.append({"model": name, "error": str(exc)})
                else:
                    # Parent templates contain deliberately unbound #textures.
                    self.counts["abstract_templates"] += 1
        self.special = sorted(name for name in self.special if name in referenced)
        self.export_chests()
        manifest = {"schema": 2, **self.counts, "special_models": self.special,
                    "empty_models": sorted(name for name in self.empty if name in referenced), "issues": self.issues,
                    "texture_min_size": self.texture_min_size, "animation_rendered": False}
        write_json(self.out / "manifest.json", manifest)
        return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jar")
    parser.add_argument("destination")
    parser.add_argument("--resource-pack", action="append", default=[])
    parser.add_argument("--texture-min-size", type=int, default=256)
    parser.add_argument("--block-entity-models", help="ChestMeshOracle output from this exact client jar")
    args = parser.parse_args()
    converter = Converter(args.jar, args.destination, args.resource_pack, args.texture_min_size, args.block_entity_models)
    result = converter.prepare()
    print(json.dumps({key: value for key, value in result.items() if key != "special_models"}, ensure_ascii=False))
