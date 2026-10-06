"""Bounded RFC6455 text framing for a single player's loopback sockets."""
import asyncio
import base64
import hashlib
import os
import struct

LIMIT = 8 * 1024 * 1024
GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'


class WireError(Exception):
    pass


async def read_headers(reader):
    try:
        raw = await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), 5)
        if len(raw) > 16384:
            raise WireError('WS_HEADER_TOO_LARGE')
        lines = raw.decode('ascii').split('\r\n')
        fields = {}
        for line in lines[1:]:
            if line:
                key, value = line.split(':', 1)
                key = key.strip().lower()
                if key in fields:
                    raise WireError('WS_DUPLICATE_HEADER')
                fields[key] = value.strip()
        return lines[0], fields
    except (ValueError, UnicodeError, asyncio.LimitOverrunError):
        raise WireError('WS_HEADER_INVALID')


class TextSocket:
    def __init__(self, reader, writer, client=False):
        self.reader, self.writer, self.client = reader, writer, client
        self.lock = asyncio.Lock()

    @classmethod
    async def connect(cls, port):
        reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', port, limit=16384), 5)
        key = base64.b64encode(os.urandom(16)).decode()
        writer.write(('GET / HTTP/1.1\r\nHost: 127.0.0.1:' + str(port) + '\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                      'Sec-WebSocket-Key: ' + key + '\r\nSec-WebSocket-Version: 13\r\n\r\n').encode('ascii'))
        await writer.drain()
        try:
            line, fields = await read_headers(reader)
            expected = base64.b64encode(hashlib.sha1((key + GUID).encode('ascii')).digest()).decode()
            if not line.startswith('HTTP/1.1 101 ') or fields.get('sec-websocket-accept') != expected or fields.get('upgrade', '').lower() != 'websocket':
                raise WireError('WS_UPSTREAM_HANDSHAKE')
            return cls(reader, writer, True)
        except BaseException:
            writer.close()
            raise

    @classmethod
    async def accept(cls, reader, writer):
        line, fields = await read_headers(reader)
        key = fields.get('sec-websocket-key', '')
        try:
            raw = base64.b64decode(key, validate=True)
        except ValueError:
            raise WireError('WS_CLIENT_KEY')
        if line != 'GET / HTTP/1.1' or fields.get('upgrade', '').lower() != 'websocket' or fields.get('sec-websocket-version') != '13' or len(raw) != 16 or \
                'upgrade' not in {x.strip().lower() for x in fields.get('connection', '').split(',')}:
            raise WireError('WS_CLIENT_HANDSHAKE')
        answer = base64.b64encode(hashlib.sha1((key + GUID).encode('ascii')).digest()).decode()
        writer.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + answer + '\r\n\r\n').encode())
        await writer.drain()
        return cls(reader, writer)

    async def frame(self, opcode, data):
        n = len(data)
        if n > LIMIT or opcode >= 8 and n > 125:
            raise WireError('WS_MESSAGE_TOO_LARGE')
        flag = 128 if self.client else 0
        header = bytes([128 | opcode])
        if n < 126:
            header += bytes([flag | n])
        elif n < 65536:
            header += bytes([flag | 126]) + struct.pack('!H', n)
        else:
            header += bytes([flag | 127]) + struct.pack('!Q', n)
        if self.client:
            mask = os.urandom(4)
            header += mask
            data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
        async with self.lock:
            self.writer.write(header + data)
            await self.writer.drain()

    async def send(self, text):
        await self.frame(1, text.encode('utf-8'))

    async def receive(self):
        output = bytearray()
        fragmented = False
        while True:
            header = await self.reader.readexactly(2)
            fin, opcode = bool(header[0] & 128), header[0] & 15
            masked, n = bool(header[1] & 128), header[1] & 127
            if header[0] & 112 or masked == self.client or opcode not in (0, 1, 8, 9, 10):
                raise WireError('WS_FRAME_INVALID')
            if n == 126:
                n = struct.unpack('!H', await self.reader.readexactly(2))[0]
                if n < 126:
                    raise WireError('WS_FRAME_NONMINIMAL')
            elif n == 127:
                n = struct.unpack('!Q', await self.reader.readexactly(8))[0]
                if n < 65536:
                    raise WireError('WS_FRAME_NONMINIMAL')
            if n > LIMIT or len(output) + n > LIMIT or opcode >= 8 and (not fin or n > 125):
                raise WireError('WS_FRAME_LENGTH')
            mask = await self.reader.readexactly(4) if masked else None
            data = await self.reader.readexactly(n)
            if mask:
                data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
            if opcode == 8:
                raise EOFError('WS_CLOSE')
            if opcode == 9:
                await self.frame(10, data)
                continue
            if opcode == 10:
                continue
            if opcode == 0 and not fragmented or opcode == 1 and fragmented:
                raise WireError('WS_FRAGMENT_SEQUENCE')
            output.extend(data)
            if fin:
                try:
                    return output.decode('utf-8')
                except UnicodeError:
                    raise WireError('WS_UTF8')
            fragmented = True

    async def close(self):
        if not self.writer.is_closing():
            try:
                await asyncio.wait_for(self.frame(8, struct.pack('!H', 1000)), 0.5)
            except (OSError, ConnectionError, asyncio.TimeoutError):
                pass
            self.writer.close()
        try:
            await asyncio.wait_for(self.writer.wait_closed(), 2)
        except (OSError, ConnectionError, asyncio.TimeoutError):
            pass
