"""Private sign glyph sink for the already-authenticated player WS proxy.

No socket, subprocess, thread, loop, remote filesystem or generic asset endpoint.
Call receive only after existing HostSession.receive verified the host_session.
The trusted native sign_text_view request is the sole view/mapping provenance.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import tempfile
import time
import zlib

TYPES = frozenset(("sign_text_asset", "sign_text_snapshot"))
FENCE = ("world_session", "dim", "view", "mapping", "mc_uuid")
MAX_PNG = 16 * 1024 * 1024
MAX_CHUNK = 48 * 1024
MAX_SNAPSHOT = 4 * 1024 * 1024
SHA = re.compile(r"[a-f0-9]{64}\Z")


def integer(value, minimum=0, maximum=2**53 - 1):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or int(value) != value or not minimum <= value <= maximum:
        raise ValueError("SIGN_WIRE_INTEGER")
    return int(value)


def png_dimensions(data):
    if not 45 <= len(data) <= MAX_PNG or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("SIGN_PNG_FORMAT")
    offset, dimensions, image_data, ended = 8, None, False, False
    while offset + 12 <= len(data):
        size, kind = struct.unpack_from(">I4s", data, offset)
        if size > MAX_PNG or offset + size + 12 > len(data):
            raise ValueError("SIGN_PNG_CHUNK")
        body = data[offset + 8:offset + 8 + size]
        crc, = struct.unpack_from(">I", data, offset + 8 + size)
        if (zlib.crc32(kind + body) & 0xffffffff) != crc:
            raise ValueError("SIGN_PNG_CRC")
        if offset == 8:
            if kind != b"IHDR" or size != 13:
                raise ValueError("SIGN_PNG_HEADER")
            width, height, depth, colour, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            if not 1 <= width <= 2048 or not 1 <= height <= 1024 or (depth, colour, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("SIGN_PNG_DIMENSIONS")
            dimensions = (width, height)
        elif kind == b"IHDR":
            raise ValueError("SIGN_PNG_DUPLICATE_HEADER")
        if kind == b"IDAT":
            image_data = True
        offset += size + 12
        if kind == b"IEND":
            if size or offset != len(data):
                raise ValueError("SIGN_PNG_END")
            ended = True
            break
    if not ended or not image_data:
        raise ValueError("SIGN_PNG_INCOMPLETE")
    return dimensions


class SignTextReceiver:
    def __init__(self, root, authenticated_identity, *, now_ms=None):
        self.root = Path(root)
        self.identity = dict(authenticated_identity)
        if not isinstance(self.identity.get("mc_uuid"), str) or not self.identity["mc_uuid"]:
            raise ValueError("SIGN_RECEIVER_IDENTITY")
        self.now = now_ms or (lambda: int(time.time() * 1000))
        self.fence = self.request = self.partial = self.pending_snapshot = None
        self.producer = None
        self.epoch = self.last_seq = -1
        self.retired = []
        self.verified = {}
        self.error = None
        self.retry_at = 0
        self.stats = {"assets": 0, "bytes": 0, "snapshots": 0, "rejected": 0}

    def bind(self, native_request):
        """Pass the real native sign_text_view request before lease.stamp/send.
        No ACK reconstruction/origin proof is accepted or required here."""
        if native_request.get("t") != "sign_text_view":
            raise ValueError("SIGN_NATIVE_REQUEST")
        if native_request.get("op") == "unbind":
            self.unbind()
            return
        fence = {key: native_request.get(key) for key in FENCE}
        fence["view"] = integer(fence["view"])
        for key in FENCE:
            if key != "view" and (not isinstance(fence[key], str) or not 0 < len(fence[key]) <= 1024):
                raise ValueError("SIGN_NATIVE_FENCE")
        if fence["mc_uuid"] != self.identity["mc_uuid"]:
            raise ValueError("SIGN_NATIVE_PLAYER")
        bounds = native_request.get("bounds")
        if not isinstance(bounds, list) or len(bounds) != 6:
            raise ValueError("SIGN_NATIVE_BOUNDS")
        bounds = [integer(n, -30000000, 30000000) for n in bounds]
        if any(bounds[i] >= bounds[i + 3] for i in range(3)):
            raise ValueError("SIGN_NATIVE_BOUNDS")
        if self.fence != fence:
            self.unbind()
            self.fence = fence
        self.request = {"t": "sign_text_view", "op": "bind", **fence, "bounds": bounds}
        self.error = None

    def _clear_partial(self):
        if self.partial is not None:
            self.partial["file"].close()
            self.partial["path"].unlink(missing_ok=True)
            self.partial = None

    def unbind(self):
        self._clear_partial()
        self.fence = self.request = self.pending_snapshot = None
        self.producer = None
        self.epoch = self.last_seq = -1
        self.retired = []
        # No synthetic producer/epoch is invented. The native host feature reset
        # clears actors immediately; a missed reset also expires within5seconds.
        (self.root / "snapshot.json").unlink(missing_ok=True)

    reset = unbind
    close = unbind

    def _header(self, message):
        if self.fence is None or message.get("schema") != 1 or any(message.get(key) != self.fence[key] for key in FENCE):
            raise ValueError("SIGN_WIRE_FENCE")
        producer = message.get("producer")
        if not isinstance(producer, str) or not 0 < len(producer) <= 128 or producer in self.retired:
            raise ValueError("SIGN_WIRE_PRODUCER")
        epoch = integer(message.get("epoch"))
        seq = integer(message.get("seq"))
        if producer == self.producer and (epoch < self.epoch or epoch == self.epoch and seq <= self.last_seq):
            raise ValueError("SIGN_WIRE_STALE")
        if producer != self.producer or epoch != self.epoch:
            if self.producer and producer != self.producer:
                self.retired = (self.retired + [self.producer])[-32:]
            self._clear_partial()
            self.pending_snapshot = None
            self.producer, self.epoch, self.last_seq = producer, epoch, -1
        return producer, epoch, seq

    def _image(self, sha, dimensions=None):
        if not isinstance(sha, str) or not SHA.fullmatch(sha):
            raise ValueError("SIGN_WIRE_SHA")
        path = self.root / "textures" / (sha + ".png")
        if not path.is_file() or path.is_symlink():
            return False
        stat = path.stat()
        marker = (stat.st_size, stat.st_mtime_ns)
        cached = self.verified.get(sha)
        if not cached or cached[0] != marker:
            if not 1 <= stat.st_size <= MAX_PNG:
                raise ValueError("SIGN_PNG_SIZE")
            raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != sha:
                raise ValueError("SIGN_PNG_SHA")
            cached = (marker, png_dimensions(raw))
            if len(self.verified) >= 8192:
                self.verified.clear()
            self.verified[sha] = cached
        if dimensions is not None and cached[1] != dimensions:
            raise ValueError("SIGN_PNG_METADATA")
        return True

    def _asset(self, message, context):
        sha = message.get("sha256")
        if not isinstance(sha, str) or not SHA.fullmatch(sha):
            raise ValueError("SIGN_WIRE_SHA")
        total = integer(message.get("bytes"), 1, MAX_PNG)
        offset = integer(message.get("offset"), 0, total - 1)
        dimensions = (integer(message.get("width"), 1, 2048), integer(message.get("height"), 1, 1024))
        if self._image(sha, dimensions):
            self._publish_pending()
            return
        encoded = message.get("data")
        if not isinstance(encoded, str) or not 0 < len(encoded) <= 65536:
            raise ValueError("SIGN_WIRE_CHUNK")
        data = base64.b64decode(encoded, validate=True)
        if not 0 < len(data) <= MAX_CHUNK or offset + len(data) > total or type(message.get("final")) is not bool or message["final"] != (offset + len(data) == total):
            raise ValueError("SIGN_WIRE_CHUNK")
        key = (context[0], context[1], context[2], sha)
        if offset == 0:
            self._clear_partial()
            directory = self.root / ".receiving"
            directory.mkdir(parents=True, exist_ok=True)
            if directory.is_symlink():
                raise ValueError("SIGN_PRIVATE_DIRECTORY")
            file = tempfile.NamedTemporaryFile(mode="w+b", prefix=sha + "-", suffix=".part", dir=directory, delete=False)
            self.partial = {"key": key, "total": total, "offset": 0, "dimensions": dimensions,
                            "path": Path(file.name), "file": file, "hash": hashlib.sha256()}
        part = self.partial
        if not part or part["key"] != key or part["total"] != total or part["offset"] != offset or part["dimensions"] != dimensions:
            raise ValueError("SIGN_WIRE_ORDER")
        part["file"].write(data)
        part["hash"].update(data)
        part["offset"] += len(data)
        self.stats["bytes"] += len(data)
        if message["final"]:
            if part["hash"].hexdigest() != sha:
                raise ValueError("SIGN_PNG_SHA")
            part["file"].flush()
            part["file"].seek(0)
            if png_dimensions(part["file"].read()) != dimensions:
                raise ValueError("SIGN_PNG_METADATA")
            part["file"].close()
            directory = self.root / "textures"
            directory.mkdir(parents=True, exist_ok=True)
            if directory.is_symlink():
                raise ValueError("SIGN_PRIVATE_DIRECTORY")
            destination = directory / (sha + ".png")
            if destination.is_symlink():
                raise ValueError("SIGN_PRIVATE_FILE")
            os.replace(part["path"], destination)
            self.partial = None
            self.stats["assets"] += 1
            self._image(sha, dimensions)
            self._publish_pending()

    def _snapshot(self, message, context):
        snapshot = message.get("snapshot")
        if not isinstance(snapshot, dict) or snapshot.get("schema") != 1 or snapshot.get("t") != "sign_text":
            raise ValueError("SIGN_SNAPSHOT_SCHEMA")
        if any(snapshot.get(key) != message.get(key) for key in (*FENCE, "producer", "epoch", "seq", "created_ms")):
            raise ValueError("SIGN_SNAPSHOT_ENVELOPE")
        created = integer(snapshot.get("created_ms"))
        if not -5000 <= self.now() - created <= 5000:
            raise ValueError("SIGN_SNAPSHOT_AGE")
        rows = snapshot.get("rows")
        if not isinstance(rows, list) or len(rows) > 1024 or type(snapshot.get("complete")) is not bool or type(snapshot.get("available")) is not bool:
            raise ValueError("SIGN_SNAPSHOT_ROWS")
        images, positions = {}, set()
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("at"), list) or len(row["at"]) != 3:
                raise ValueError("SIGN_SNAPSHOT_BLOCK")
            at = tuple(integer(n, -30000000, 30000000) for n in row["at"])
            if at in positions or not all(self.request["bounds"][i] <= at[i] < self.request["bounds"][i + 3] for i in range(3)):
                raise ValueError("SIGN_SNAPSHOT_SCOPE")
            positions.add(at)
            for side in ("front", "back"):
                face = row.get(side)
                image = face.get("image") if isinstance(face, dict) else None
                if not isinstance(image, dict) or not isinstance(image.get("sha256"), str) or not SHA.fullmatch(image["sha256"]) or image.get("path") != "textures/" + image["sha256"] + ".png":
                    raise ValueError("SIGN_SNAPSHOT_IMAGE")
                dimensions = (integer(image.get("width"), 1, 2048), integer(image.get("height"), 1, 1024))
                if image["sha256"] in images and images[image["sha256"]] != dimensions:
                    raise ValueError("SIGN_SNAPSHOT_IMAGE")
                images[image["sha256"]] = dimensions
        raw = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(raw) > MAX_SNAPSHOT:
            raise ValueError("SIGN_SNAPSHOT_BYTES")
        self.pending_snapshot = (context, raw, images, created)
        self._publish_pending()

    def _publish_pending(self):
        pending = self.pending_snapshot
        if pending is None:
            return False
        context, raw, images, created = pending
        if context[:2] != (self.producer, self.epoch) or not -5000 <= self.now() - created <= 5000:
            self.pending_snapshot = None
            return False
        if not all(self._image(sha, dimensions) for sha, dimensions in images.items()):
            return False
        self.root.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="wb", prefix="snapshot-", suffix=".pending", dir=self.root, delete=False) as file:
            file.write(raw)
            temporary = Path(file.name)
        try:
            os.replace(temporary, self.root / "snapshot.json")
        finally:
            temporary.unlink(missing_ok=True)
        self.last_seq = context[2]
        self.pending_snapshot = None
        self.error = None
        self.stats["snapshots"] += 1
        self._prune(images)
        return True

    def _prune(self, images):
        cutoff = time.time() - 10
        for path in (self.root / "textures").glob("*.png"):
            if SHA.fullmatch(path.stem) and path.stem not in images and not path.is_symlink() and path.stat().st_mtime < cutoff:
                path.unlink(missing_ok=True)
                self.verified.pop(path.stem, None)

    def receive(self, already_authenticated_message):
        """Return True for consumed glyph messages, including rejected frames.
        Input must be the clean dict returned by the existing lease.receive.
        Errors affect this display stream, not the game's authenticated input."""
        if not isinstance(already_authenticated_message, dict) or already_authenticated_message.get("t") not in TYPES:
            return False
        try:
            context = self._header(already_authenticated_message)
            if already_authenticated_message["t"] == "sign_text_asset":
                self._asset(already_authenticated_message, context)
            else:
                self._snapshot(already_authenticated_message, context)
        except (ValueError, TypeError, KeyError, OSError, binascii.Error, struct.error) as error:
            if isinstance(error, ValueError) and str(error) == "SIGN_WIRE_STALE":
                self.stats["rejected"] += 1
                return True # reliable stream duplicates do not trigger a rebind
            self._clear_partial()
            self.stats["rejected"] += 1
            # Never log the PNG bytes or user text. Retry reuses sign_text_view.
            self.error = str(error) if isinstance(error, ValueError) and str(error).startswith("SIGN_") else "SIGN_RECEIVER_IO_OR_FORMAT"
        return True

    def retry_request(self):
        """If cached PNGs were evicted/missing, resend the same genuine native
        request through existing send_scoped at most once per second. Java's
        setTransport then resends assets; no new operation/handshake is needed."""
        if self.request and self.now() >= self.retry_at and (self.error or self.pending_snapshot):
            self.retry_at = self.now() + 1000
            return dict(self.request)
        return None

    def status(self):
        return {"schema": 1, "bound": self.fence is not None, "epoch": self.epoch, "seq": self.last_seq,
                "receiving": self.partial is not None, "awaiting_assets": self.pending_snapshot is not None,
                "stats": dict(self.stats), "error": self.error, "runtime_verified": False}
