"""Bounded HUD-only transport and the compatible MCPT v1 shared-memory reader."""
from dataclasses import dataclass
import struct
import time
import zlib

MAX_WIDTH, MAX_HEIGHT = 3840, 2160
MAX_PIXELS = MAX_WIDTH * MAX_HEIGHT
MAX_AGE_MS = 250
MC_HEADER, MC_DESC, MC_DESC_SIZE = 4096, 256, 128
V2 = struct.Struct("!4sHHIIIIIIQQQQ")
V1 = struct.Struct("!III")
BOTTOM_UP, PREMULTIPLIED, HUD_ONLY, BUILD_MODE, SCREEN_OPEN = 1, 2, 4, 8, 16


@dataclass(frozen=True)
class Frame:
    width: int
    height: int
    pixels: bytes
    producer: int
    publication: int
    frame: int
    host_frame: int
    capture_ms: int
    publish_ms: int
    flags: int

    def stale(self, now_ms=None):
        return (now_ms if now_ms is not None else time.time_ns() // 1_000_000) - self.capture_ms > MAX_AGE_MS


@dataclass(frozen=True)
class EncodedFrame:
    frame: Frame
    payload: bytes

    def packet(self, version=2):
        f = self.frame
        if version == 1:
            return V1.pack(f.width, f.height, len(self.payload)) + self.payload
        return V2.pack(
            b"PHUD", 2, V2.size, f.width, f.height, len(self.payload), f.flags,
            f.producer, 0, f.frame, f.host_frame, f.capture_ms, f.publish_ms,
        ) + self.payload


def encode(frame):
    if len(frame.pixels) != frame.width * frame.height * 4:
        raise ValueError("incorrect RGBA size")
    return EncodedFrame(frame, zlib.compress(frame.pixels, 1))


class Encoder:
    """Reuse compressed bytes for identical pixels, while refreshing all frame metadata."""
    def __init__(self):
        self.previous = None
        self.compressions = self.reused = 0

    def encode(self, frame):
        old = self.previous
        if old and frame.width == old.frame.width and frame.height == old.frame.height and frame.pixels == old.frame.pixels:
            value = EncodedFrame(frame, old.payload)
            self.reused += 1
        else:
            value = encode(frame)
            self.compressions += 1
        self.previous = value
        return value


class SnapshotReader:
    """read(offset, count) must copy bytes. Both header and slot must remain stable."""

    def __init__(self, read):
        self.read = read
        self.last = None
        self.rejected = 0

    def poll(self, now_ms=None):
        now_ms = now_ms if now_ms is not None else time.time_ns() // 1_000_000
        header = self.read(0, 48)
        if len(header) != 48 or header[:4] != b"MCPT":
            return None
        version, header_size, slots = struct.unpack_from("<III", header, 4)
        stride, max_w, max_h, publication, slot, producer = struct.unpack_from("<qiiqii", header, 16)
        if version != 1 or header_size != MC_HEADER or not 1 <= slots <= 8:
            raise ValueError("unsupported MCPT header")
        if not 1 <= max_w <= MAX_WIDTH or not 1 <= max_h <= MAX_HEIGHT or not 0 < stride <= MAX_PIXELS * 12:
            raise ValueError("invalid MCPT dimensions/stride")
        token = (producer, publication)
        if not 0 <= slot < slots or token == self.last:
            return None
        desc_offset = MC_DESC + MC_DESC_SIZE * slot
        desc = self.read(desc_offset, MC_DESC_SIZE)
        seq, frame, host_frame, w, h = struct.unpack_from("<qqqii", desc)
        if seq <= 0 or seq & 1:
            self.rejected += 1
            return None
        if not 1 <= w <= max_w or not 1 <= h <= max_h or w * h * 12 > stride:
            raise ValueError("invalid MCPT slot dimensions")
        size = w * h * 4
        # Keep the legacy third-plane offset. Never read colour or depth.
        pixels = self.read(MC_HEADER + stride * slot + 2 * size, size)
        if len(pixels) != size or self.read(desc_offset, 8) != desc[:8] or self.read(32, 16) != header[32:48]:
            self.rejected += 1
            return None
        self.last = token
        mc_flags = struct.unpack_from("<I", desc, 44)[0]
        flags = PREMULTIPLIED | HUD_ONLY | (BOTTOM_UP if mc_flags & 2 else 0)
        if mc_flags & 8:
            capture_ms, publish_ms, state = struct.unpack_from("<qqI", desc, 104)
            if not 0 < capture_ms <= publish_ms <= now_ms + 1000:
                raise ValueError("invalid MCPT epoch timestamps")
            flags |= (BUILD_MODE if state & 1 else 0) | (SCREEN_OPEN if state & 2 else 0)
        else:
            # Existing exporters contain only monotonic timestamps. Liveness is
            # bounded separately by producer exit and unchanged publications.
            capture_ms = publish_ms = now_ms
            flags |= BUILD_MODE
        return Frame(w, h, pixels, producer, publication, frame, host_frame, capture_ms, publish_ms, flags)
