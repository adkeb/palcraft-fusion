"""Protocol, concurrent publication, compatibility and backpressure regression tests."""
import os
from pathlib import Path
import socket
import struct
import sys
import threading
import time
import unittest
import weakref
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from hud_protocol import Frame, SnapshotReader, Encoder, encode, V2
from hud_relay import Latest, Server


def shared(w=4, h=3, flags=10, producer=123, publication=1):
    stride = w * h * 12
    data = bytearray(4096 + stride * 3)
    struct.pack_into("<4sIIIqiiqii", data, 0, b"MCPT", 1, 4096, 3, stride, 3840, 2160, publication, 0, producer)
    struct.pack_into("<qqqii", data, 256, 2, publication, 991, w, h)
    struct.pack_into("<I", data, 256 + 44, flags)
    struct.pack_into("<qqI", data, 256 + 104, 1000, 1001, 3)
    pixels = bytes([12, 24, 36, 255]) * (w * h)
    data[4096 + 2 * len(pixels):4096 + 3 * len(pixels)] = pixels
    return data, pixels


def frame(w=4, h=3, rgba=None, count=42):
    now = time.time_ns() // 1_000_000
    return Frame(w, h, rgba or bytes([12, 24, 36, 255]) * (w * h), 123, count, count, 991, now, now, 31)


def exact(sock, n):
    out = bytearray()
    while len(out) < n:
        value = sock.recv(n - len(out))
        if not value:
            raise EOFError
        out.extend(value)
    return bytes(out)


class ProtocolTests(unittest.TestCase):
    def test_hud_only_plane_and_metadata(self):
        data, pixels = shared()
        reads = []
        def read(offset, n):
            reads.append((offset, n))
            return bytes(data[offset:offset+n])
        result = SnapshotReader(read).poll(1005)
        self.assertEqual(result.pixels, pixels)
        self.assertEqual((result.capture_ms, result.publish_ms, result.flags), (1000, 1001, 31))
        self.assertEqual([offset for offset, n in reads if offset >= 4096], [4096 + len(pixels)*2])

    def test_legacy_shared_memory(self):
        data, pixels = shared(flags=7)
        result = SnapshotReader(lambda o, n: bytes(data[o:o+n])).poll(5000)
        self.assertEqual(result.capture_ms, 5000)
        self.assertEqual(result.flags, 15)
        self.assertEqual(result.pixels, pixels)

    def test_odd_slot_is_not_read(self):
        data, _ = shared()
        struct.pack_into("<q", data, 256, 3)
        reader = SnapshotReader(lambda o, n: bytes(data[o:o+n]))
        self.assertIsNone(reader.poll(1005))
        self.assertEqual(reader.rejected, 1)

    def test_rewritten_pixels_are_not_published(self):
        data, _ = shared()
        def read(offset, n):
            result = bytes(data[offset:offset+n])
            if offset >= 4096:
                struct.pack_into("<q", data, 256, 4)
            return result
        self.assertIsNone(SnapshotReader(read).poll(1005))

    def test_publication_change_during_copy(self):
        data, _ = shared()
        def read(offset, n):
            result = bytes(data[offset:offset+n])
            if offset >= 4096:
                struct.pack_into("<q", data, 32, 2)
            return result
        self.assertIsNone(SnapshotReader(read).poll(1005))

    def test_restarted_producer_same_counter(self):
        data, _ = shared()
        reader = SnapshotReader(lambda o, n: bytes(data[o:o+n]))
        self.assertEqual(reader.poll(1005).producer, 123)
        self.assertIsNone(reader.poll(1005))
        struct.pack_into("<i", data, 44, 456)
        self.assertEqual(reader.poll(1005).producer, 456)

    def test_bounds_fail_before_raw_copy(self):
        data, _ = shared()
        struct.pack_into("<i", data, 256+24, 4000)
        with self.assertRaises(ValueError):
            SnapshotReader(lambda o, n: bytes(data[o:o+n])).poll(1005)

    def test_250ms_source_expiry(self):
        data, _ = shared()
        result = SnapshotReader(lambda o, n: bytes(data[o:o+n])).poll(1250)
        self.assertFalse(result.stale(1250))
        self.assertTrue(result.stale(1251))

    def test_wire_versions_and_premultiplied_pixels(self):
        f = frame()
        e = encode(f)
        old = e.packet(1)
        self.assertEqual(struct.unpack("!III", old[:12]), (4, 3, len(e.payload)))
        self.assertEqual(zlib.decompress(old[12:]), f.pixels)
        new = e.packet(2)
        values = V2.unpack(new[:64])
        self.assertEqual(V2.size, 64)
        self.assertEqual(values[:7], (b"PHUD", 2, 64, 4, 3, len(e.payload), 31))
        self.assertEqual(values[7:], (123, 0, 42, 991, f.capture_ms, f.publish_ms))
        self.assertEqual(zlib.decompress(new[64:]), f.pixels)

    def test_latest_frame_has_no_fifo(self):
        latest = Latest()
        references = []
        for n in range(1000):
            value = encode(frame(count=n))
            references.append(weakref.ref(value))
            latest.put(value)
        serial, value = latest.next(-1, 0)
        self.assertEqual((serial, value.frame.frame), (1000, 999))
        self.assertEqual(sum(ref() is not None for ref in references), 1)

    def test_identical_pixels_refresh_metadata_without_compression(self):
        encoder = Encoder()
        a = encoder.encode(frame(count=41))
        b = encoder.encode(frame(count=42))
        self.assertEqual((encoder.compressions, encoder.reused), (1,1))
        self.assertEqual(b.frame.frame, 42)
        self.assertIs(b.payload, a.payload)
        self.assertEqual(zlib.decompress(b.payload), b.frame.pixels)
        encoder.encode(frame(rgba=b"\0"*48, count=43))
        self.assertEqual(encoder.compressions, 2)


class SocketTests(unittest.TestCase):
    def setUp(self):
        self.latest = Latest()
        class FakeProducer:
            stop = threading.Event()
            slow = 0
            def slow_client(self):
                self.slow += 1
        self.producer = FakeProducer()
        self.server = Server(("127.0.0.1", 0), self.latest, self.producer)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval":.01}, daemon=True)
        self.thread.start()
        self.sockets = []

    def tearDown(self):
        self.producer.stop.set()
        with self.latest.condition:
            self.latest.condition.notify_all()
        for s in self.sockets:
            s.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(1)

    def connect(self, version):
        s = socket.create_connection(self.server.server_address, timeout=1)
        self.sockets.append(s)
        if version == 2:
            # Also prove a fragmented hello is negotiated.
            s.sendall(b"HUD")
            s.sendall(b"2\n")
        deadline = time.monotonic() + 1
        while self.latest.clients == 0 and time.monotonic() < deadline:
            time.sleep(.005)
        self.assertEqual(self.latest.clients, 1)
        return s

    def test_old_client_receives_12byte_header(self):
        s = self.connect(1)
        f = frame()
        self.latest.put(encode(f))
        w, h, n = struct.unpack("!III", exact(s,12))
        self.assertEqual((w,h), (4,3))
        self.assertEqual(zlib.decompress(exact(s,n)), f.pixels)

    def test_new_client_receives_source_frame_and_time(self):
        s = self.connect(2)
        f = frame()
        self.latest.put(encode(f))
        values = V2.unpack(exact(s,64))
        self.assertEqual(values[9:11], (42,991))
        self.assertEqual(zlib.decompress(exact(s, values[5])), f.pixels)

    def test_slow_socket_disconnects_instead_of_accumulating(self):
        s = self.connect(2)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
        self.latest.put(encode(frame(1024,1024,os.urandom(1024*1024*4))))
        deadline = time.monotonic() + 1
        while self.producer.slow == 0 and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(self.producer.slow, 1)
        self.assertEqual(self.latest.clients, 0)

    def test_idle_closed_client_is_removed(self):
        s = self.connect(2)
        s.close()
        deadline = time.monotonic() + 1
        while self.latest.clients and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(self.latest.clients, 0)


if __name__ == "__main__":
    unittest.main()
