"""Focused glyph-stream checks. No server/game/socket or asset download."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import zlib

spec = importlib.util.spec_from_file_location("sign_receiver", Path(__file__).parents[1] / "python/receiver.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)


def png():
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + \
        chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff")) + chunk(b"IEND", b"")


clock = 100000
request = {"t": "sign_text_view", "op": "bind", "world_session": "test-world", "dim": "minecraft:overworld",
           "view": 7, "mapping": "actual-native-mapping", "mc_uuid": "test-bound-player", "bounds": [0, 0, -16, 16, 256, 0]}
raw = png()
sha = hashlib.sha256(raw).hexdigest()


def envelope(seq=1, epoch=1):
    return {"schema": 1, "producer": "test-mc-process", "epoch": epoch, "seq": seq, "created_ms": clock,
            **{key: request[key] for key in module.FENCE}}


def footer(seq=1, epoch=1):
    doc = {**envelope(seq, epoch), "t": "sign_text", "complete": True, "available": True,
           "rows": [{"at": [3, 64, -2], "id": "minecraft:oak_sign", "state_key": "test-state",
                     "front": {"image": {"sha256": sha, "path": f"textures/{sha}.png", "width": 1, "height": 1}},
                     "back": {"image": {"sha256": sha, "path": f"textures/{sha}.png", "width": 1, "height": 1}}}]}
    return {**envelope(seq, epoch), "t": "sign_text_snapshot", "snapshot": doc}


def packet(offset, data, final, seq=1, epoch=1):
    return {**envelope(seq, epoch), "t": "sign_text_asset", "sha256": sha, "bytes": len(raw),
            "offset": offset, "final": final, "width": 1, "height": 1, "data": base64.b64encode(data).decode()}


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory) / "private-signs"
    sink = module.SignTextReceiver(root, {"mc_uuid": request["mc_uuid"]}, now_ms=lambda: clock)
    sink.bind(request)
    assert sink.receive({"t": "player_vitals"}) is False
    assert sink.receive(footer()) is True and not (root / "snapshot.json").exists(), "footer published before referenced PNG"
    retry = sink.retry_request()
    assert retry == request and sink.retry_request() is None, "missing assets did not reuse bounded original native request"
    assert sink.receive(packet(0, raw[:20], False)) and not (root / "snapshot.json").exists()
    assert sink.receive(packet(20, raw[20:], True))
    destination = root / "textures" / (sha + ".png")
    assert destination.read_bytes() == raw
    published = json.loads((root / "snapshot.json").read_text())
    assert published == footer()["snapshot"] and sink.status()["seq"] == 1, "snapshot identity/bytes changed during transfer"
    assert not list((root / ".receiving").glob("*.part"))
    changed = footer(2)
    changed["mapping"] = "other-view"
    assert sink.receive(changed) and sink.status()["error"] == "SIGN_WIRE_FENCE"
    assert json.loads((root / "snapshot.json").read_text()) == published
    changed = footer(2)
    changed["snapshot"]["rows"][0]["front"]["image"]["path"] = "../../other"
    assert sink.receive(changed) and sink.status()["error"] == "SIGN_SNAPSHOT_IMAGE"
    assert sink.receive(footer(2)) and sink.status()["seq"] == 2, "verified cached PNG was not reused"
    destination.write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
    assert sink.receive(footer(3)) and sink.status()["error"] == "SIGN_PNG_SHA", "corrupt cache passed hash verification"
    destination.unlink()
    bad = packet(0, raw, True, 3)
    bad["data"] = base64.b64encode(raw[:-1] + bytes([raw[-1] ^ 1])).decode()
    assert sink.receive(bad) and sink.status()["error"] == "SIGN_PNG_SHA"
    assert not destination.exists() and not list((root / ".receiving").glob("*.part"))
    assert sink.receive(packet(0, raw, True, 3)) and sink.receive(footer(3))
    assert sink.status()["seq"] == 3 and sink.status()["runtime_verified"] is False
    assert sink.receive(footer(1, 2)) and sink.status()["epoch"] == 2
    old_stats=sink.status()["stats"]["rejected"]
    assert sink.receive(footer(4, 1)) and sink.status()["stats"]["rejected"]==old_stats+1 and sink.status()["seq"]==1
    new_request = {**request, "view": 8}
    sink.bind(new_request)
    assert not (root / "snapshot.json").exists(), "rebound view retained old snapshot"
    assert sink.receive(footer(5, 2)) and sink.status()["error"] == "SIGN_WIRE_FENCE"
    sink.close()
    assert sink.status()["bound"] is False and not (root / "snapshot.json").exists()

print("PASS: PNG before snapshot; streaming order/hash/CRC/dimensions; native fence; epoch; cache reuse; bounded same-request retry; unbind")
