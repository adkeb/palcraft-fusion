"""Fan out the latest Minecraft HUD. No world layers and no frame queue.

Legacy clients receive the original 12-byte header. New clients first send
HUD2\n, then receive PHUD v2 headers with source identity and capture time.
"""
import argparse
import ctypes as c
import json
import mmap
import os
from pathlib import Path
import socket
import select
import socketserver
import threading
import time
import struct
import stat

from hud_protocol import SnapshotReader, Encoder, MC_HEADER, MAX_PIXELS


class WindowsMapping:
    def __init__(self, name="Local\\MCPassthroughFrame"):
        if os.name != "nt":
            raise OSError("MCPT shared memory requires Windows")
        self.k = k = c.WinDLL("kernel32", use_last_error=True)
        self.name = name
        k.OpenFileMappingW.argtypes = [c.c_ulong, c.c_int, c.c_wchar_p]
        k.OpenFileMappingW.restype = c.c_void_p
        k.MapViewOfFile.argtypes = [c.c_void_p, c.c_ulong, c.c_ulong, c.c_ulong, c.c_size_t]
        k.MapViewOfFile.restype = c.c_void_p
        k.UnmapViewOfFile.argtypes = [c.c_void_p]
        k.CloseHandle.argtypes = [c.c_void_p]
        k.OpenProcess.argtypes = [c.c_ulong, c.c_int, c.c_ulong]
        k.OpenProcess.restype = c.c_void_p
        k.GetExitCodeProcess.argtypes = [c.c_void_p, c.POINTER(c.c_ulong)]
        self.handle = self.base = self.process = None
        self.producer = 0
        self.mapped_size = 0
        self.reader = SnapshotReader(self.read)

    def open(self):
        if self.base:
            return True
        self.handle = self.k.OpenFileMappingW(4, False, self.name)
        if not self.handle:
            return False
        self.base = self.k.MapViewOfFile(self.handle, 4, 0, 0, 0)
        if not self.base:
            self.close()
            return False
        class MemoryInfo(c.Structure):
            _fields_ = [("BaseAddress", c.c_void_p), ("AllocationBase", c.c_void_p),
                        ("AllocationProtect", c.c_ulong), ("PartitionId", c.c_ushort),
                        ("RegionSize", c.c_size_t), ("State", c.c_ulong),
                        ("Protect", c.c_ulong), ("Type", c.c_ulong)]
        info = MemoryInfo()
        self.k.VirtualQuery.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
        self.k.VirtualQuery.restype = c.c_size_t
        if not self.k.VirtualQuery(self.base, c.byref(info), c.sizeof(info)):
            self.close()
            return False
        self.mapped_size = info.RegionSize
        return True

    def read(self, offset, size):
        if not self.base or offset < 0 or size < 0 or offset + size > self.mapped_size:
            raise ValueError("MCPT read outside mapped view")
        return c.string_at(self.base + offset, size)

    def alive(self, producer):
        if producer != self.producer:
            if self.process:
                self.k.CloseHandle(self.process)
            self.producer = producer
            self.process = self.k.OpenProcess(0x1000, False, producer)
        code = c.c_ulong()
        return bool(self.process and self.k.GetExitCodeProcess(self.process, c.byref(code)) and code.value == 259)

    def close(self):
        if self.base:
            self.k.UnmapViewOfFile(self.base)
        for handle in (self.handle, self.process):
            if handle:
                self.k.CloseHandle(handle)
        self.handle = self.base = self.process = None
        self.producer = self.mapped_size = 0
        # Preserve the last publication across remaps. Otherwise a hung legacy
        # producer would replay its old frame every time we reopened the view.


class MacFileMapping:
    """Read the native Java MCPT file through the existing snapshot reader."""
    def __init__(self, path):
        if os.name == "nt":
            raise OSError("File-backed MCPT requires a native POSIX process")
        self.path = Path(path)
        self.file = self.mapping = None
        self.identity = None
        self.mapped_size = 0
        self.reader = SnapshotReader(self.read)

    def open(self):
        try:
            info = self.path.stat()
        except FileNotFoundError:
            self.close()
            return False
        if not stat.S_ISREG(info.st_mode) or not MC_HEADER <= info.st_size <= MC_HEADER + MAX_PIXELS * 12 * 8:
            self.close()
            return False
        identity = (info.st_dev, info.st_ino, info.st_size)
        if self.mapping is not None and identity == self.identity:
            return True
        self.close()
        file = self.path.open("rb")
        try:
            opened = os.fstat(file.fileno())
            if (opened.st_dev, opened.st_ino, opened.st_size) != identity:
                file.close()
                return False
            mapping = mmap.mmap(file.fileno(), opened.st_size, access=mmap.ACCESS_READ)
        except BaseException:
            file.close()
            raise
        self.file, self.mapping = file, mapping
        self.identity = identity
        self.mapped_size = opened.st_size
        return True

    def read(self, offset, size):
        if self.mapping is None or offset < 0 or size < 0 or offset + size > self.mapped_size:
            raise ValueError("MCPT read outside mapped file")
        return self.mapping[offset:offset + size]

    def alive(self, producer):
        if producer <= 0:
            return False
        try:
            os.kill(producer, 0)
            return True
        except (ProcessLookupError, PermissionError):
            return False

    def close(self):
        if self.mapping is not None:
            self.mapping.close()
        if self.file is not None:
            self.file.close()
        self.file = self.mapping = None
        self.identity = None
        self.mapped_size = 0
        # Preserve reader.last across reopen; never replay an old publication.


class Latest:
    """One encoded frame shared by all clients; slow clients never hold a FIFO."""
    def __init__(self):
        self.condition = threading.Condition()
        self.value = None
        self.serial = 0
        self.clients = 0

    def put(self, value):
        with self.condition:
            self.value = value
            self.serial += 1
            self.condition.notify_all()

    def next(self, previous, timeout=.2):
        with self.condition:
            self.condition.wait_for(lambda: self.serial != previous, timeout)
            return self.serial, self.value


class Producer(threading.Thread):
    def __init__(self, latest, fps, status_file, source_factory=WindowsMapping):
        super().__init__(name="hud-latest", daemon=True)
        self.latest, self.period, self.status_file = latest, 1 / fps, status_file
        self.source_factory = source_factory
        self.stop = threading.Event()
        self.metrics = dict(encoded=0, skipped=0, stale=0, rejected=0, slow_clients=0,
                            raw_bytes=0, encoded_bytes=0, encode_ms_total=0.0)
        self.metric_lock = threading.Lock()
        self.last_source = self.last_status = 0.

    def slow_client(self):
        with self.metric_lock:
            self.metrics["slow_clients"] += 1

    def status(self):
        if not self.status_file or time.monotonic() - self.last_status < 1:
            return
        self.last_status = time.monotonic()
        with self.metric_lock:
            state = dict(self.metrics)
        state.update(unix=time.time(), clients=self.latest.clients, protocol=2, layers=1,
                     frame_age_ms=(time.monotonic() - self.last_source) * 1000 if self.last_source else -1,
                     queue_capacity=1, encode_ms_mean=state["encode_ms_total"] / max(1, state["encoded"]))
        try:
            self.status_file.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.status_file.with_suffix(".tmp")
            temporary.write_text(json.dumps(state), encoding="utf8")
            temporary.replace(self.status_file)
        except OSError:
            pass

    def run(self):
        source = self.source_factory()
        encoder = Encoder()
        stalled_since = time.monotonic()
        previous = None
        try:
            while not self.stop.is_set():
                start = time.monotonic()
                try:
                    if self.latest.clients and source.open():
                        frame = source.reader.poll()
                        if frame:
                            if not source.alive(frame.producer):
                                source.close()
                            elif frame.stale():
                                self.metrics["stale"] += 1
                            else:
                                if previous and previous[0] == frame.producer:
                                    self.metrics["skipped"] += max(0, frame.publication - previous[1] - 1)
                                previous = frame.producer, frame.publication
                                t = time.perf_counter()
                                value = encoder.encode(frame)
                                elapsed = (time.perf_counter() - t) * 1000
                                if frame.stale():
                                    self.metrics["stale"] += 1
                                else:
                                    self.latest.put(value)
                                    self.metrics["encoded"] += 1
                                    self.metrics["raw_bytes"] += len(frame.pixels)
                                    self.metrics["encoded_bytes"] += len(value.payload)
                                    self.metrics["encode_ms_total"] += elapsed
                                    self.metrics["compressions"] = encoder.compressions
                                    self.metrics["reused_compression"] = encoder.reused
                                    self.last_source = time.monotonic()
                                stalled_since = time.monotonic()
                        elif time.monotonic() - stalled_since > 2:
                            # Camera/mode/world idle does not mean the publisher
                            # exited. Keep its view until actual process death;
                            # a new publication resumes the same client stream.
                            last = source.reader.last
                            if last is None or not source.alive(last[0]):
                                source.close()
                            stalled_since = time.monotonic()
                        self.metrics["rejected"] = source.reader.rejected
                except (OSError, ValueError):
                    self.metrics["rejected"] += 1
                    source.close()
                self.status()
                self.stop.wait(max(.002, self.period - (time.monotonic() - start)))
        finally:
            source.close()


class Stream(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 64 * 1024)
        sock.settimeout(.1)
        version = 1
        hello = bytearray()
        try:
            try:
                while len(hello) < 5:
                    chunk = sock.recv(5 - len(hello))
                    if not chunk:
                        return
                    hello.extend(chunk)
                if hello == b"TIME\n":
                    # A separate lightweight calibration connection. Neither
                    # source acquisition nor the HUD stream is restarted.
                    nonce = bytearray()
                    while len(nonce) < 8:
                        part = sock.recv(8 - len(nonce))
                        if not part:
                            return
                        nonce.extend(part)
                    received_ns = time.time_ns()
                    sent_ns = time.time_ns()
                    sock.sendall(struct.pack("!4sHHQQQ", b"HCLK", 1, 32,
                                            struct.unpack("!Q", nonce)[0], received_ns, sent_ns))
                    return
                if hello != b"HUD2\n":
                    return
                version = 2
            except socket.timeout:
                if hello:
                    return
            sock.settimeout(.15)
            with self.server.latest.condition:
                self.server.latest.clients += 1
            try:
                serial = -1
                while not self.server.producer.stop.is_set():
                    if select.select([sock], [], [], 0)[0]:
                        # Client writes no more data after negotiation. EOF or an
                        # unexpected request closes an otherwise idle connection.
                        return
                    newest, value = self.server.latest.next(serial)
                    if newest == serial or value is None or value.frame.stale():
                        serial = newest
                        continue
                    serial = newest
                    sock.sendall(value.packet(version))
            finally:
                with self.server.latest.condition:
                    self.server.latest.clients -= 1
        except socket.timeout:
            self.server.producer.slow_client()
        except (ConnectionError, OSError):
            pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address, latest, producer):
        self.latest, self.producer = latest, producer
        super().__init__(address, Stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=25603)
    parser.add_argument("--frame-name", default=os.environ.get("PALCRAFT_FRAME_NAME", "Local\\MCPassthroughFrame"))
    parser.add_argument("--frame-file", type=Path, default=os.environ.get("PALCRAFT_MC_FRAME_FILE"),
                        help="Native Mac MCPT file; must match Java -Dpalcraft.frameFile")
    parser.add_argument("--fps", type=float, default=60)
    parser.add_argument("--status-file", type=Path, default=Path(__file__).resolve().parent / "bridge/hud-relay-status.json")
    args = parser.parse_args()
    if not 1 <= args.fps <= 120:
        parser.error("--fps must be in 1..120")
    if args.frame_file and os.name == "nt":
        parser.error("--frame-file requires a native POSIX process")
    if not args.frame_file and os.name != "nt":
        parser.error("--frame-file is required for the native Mac relay")
    latest = Latest()
    source_factory = (lambda: MacFileMapping(args.frame_file)) if args.frame_file else (lambda: WindowsMapping(args.frame_name))
    producer = Producer(latest, args.fps, args.status_file, source_factory)
    with Server(("127.0.0.1", args.port), latest, producer) as server:
        producer.start()
        try:
            server.serve_forever()
        finally:
            producer.stop.set()
            producer.join(timeout=2)


if __name__ == "__main__":
    main()
