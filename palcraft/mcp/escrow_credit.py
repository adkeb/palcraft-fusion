#!/usr/bin/env python3
"""Create one native produce permit from an ACTUAL saved MC debit tag.

This module neither grants nor moves anything. The exchange owner calls it only
after its v3 WAL/MC saved-player debit step. Claimed permits are never recycled.
"""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import uuid
from escrow_io import read_and_force


def guid(value):
    value = str(uuid.UUID(value)).replace('-', '')
    return struct.pack('<4I', *(int(value[i:i + 8], 16) for i in range(0, 32, 8)))


class NbtReader:
    """Bounded plain NBT reader: used only to inspect UUID and vanilla entity Tags."""
    def __init__(self, raw):
        self.raw, self.pos = raw, 0
        if len(raw) > 16 * 1024 * 1024:
            raise ValueError('Saved player NBT exceeds limit')

    def take(self, n):
        if n < 0 or self.pos + n > len(self.raw):
            raise ValueError('Truncated NBT')
        p = self.pos
        self.pos += n
        return self.raw[p:self.pos]

    def number(self, format):
        return struct.unpack('>' + format, self.take(struct.calcsize('>' + format)))[0]

    def text(self):
        raw = self.take(self.number('H')).replace(b'\xc0\x80', b'\0')
        text = raw.decode('utf-8', 'surrogatepass')
        return text.encode('utf-16', 'surrogatepass').decode('utf-16')

    def count(self):
        n = self.number('i')
        if not 0 <= n <= 1_000_000:
            raise ValueError('NBT collection length exceeds limit')
        return n

    def payload(self, kind, depth=0):
        if depth > 64:
            raise ValueError('NBT nesting exceeds limit')
        if kind in {1, 2, 3, 4, 5, 6}:
            return self.number({1: 'b', 2: 'h', 3: 'i', 4: 'q', 5: 'f', 6: 'd'}[kind])
        if kind == 7:
            return self.take(self.count())
        if kind == 8:
            return self.text()
        if kind == 9:
            element, n = self.number('B'), self.count()
            if element == 0 and n:
                raise ValueError('Nonempty NBT End list')
            return [self.payload(element, depth + 1) for _ in range(n)]
        if kind == 10:
            out = {}
            while True:
                element = self.number('B')
                if element == 0:
                    return out
                key = self.text()
                if key in out:
                    raise ValueError('Duplicate NBT field')
                out[key] = self.payload(element, depth + 1)
        if kind in {11, 12}:
            return [self.number('i' if kind == 11 else 'q') for _ in range(self.count())]
        raise ValueError('Unknown NBT type')

    def root(self):
        if self.number('B') != 10:
            raise ValueError('NBT root must be a compound')
        self.text()
        out = self.payload(10)
        if self.pos != len(self.raw):
            raise ValueError('NBT has trailing bytes')
        return out


def read_saved_debit(player_data, tx, marker_prefix='palcraft.exchange.v3:'):
    path = Path(player_data)
    if path.parent.name != 'playerdata' or path.parent.parent.resolve() != Path(tx['mc_world']).resolve():
        raise ValueError('Saved MC debit receipt belongs to another world')
    stat = path.stat()
    raw = read_and_force(path, 16 * 1024 * 1024)
    if len(raw) > 16 * 1024 * 1024:
        raise ValueError('Saved player file exceeds limit')
    if raw[:2] == b'\x1f\x8b':
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as zipped:
            decoded = zipped.read(16 * 1024 * 1024 + 1)
    else:
        decoded = raw
    data = NbtReader(decoded).root()
    encoded = data.get('UUID')
    if not isinstance(encoded, list) or len(encoded) != 4 or any(type(x) is not int for x in encoded):
        raise ValueError('Saved player UUID missing')
    actual_uid = str(uuid.UUID(bytes=struct.pack('>4I', *(x & 0xffffffff for x in encoded))))
    if actual_uid != tx['mc_uid'] or path.name != actual_uid + '.dat':
        raise ValueError('Saved MC player identity mismatch')
    marker = marker_prefix + tx['id'] + ':debit'
    tags = data.get('Tags')
    if not isinstance(tags, list) or marker not in tags or any(type(x) is not str for x in tags):
        raise ValueError('Actual atomic MC debit receipt not in saved player Tags')
    after = path.stat()
    if (stat.st_mtime_ns, stat.st_size, stat.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino) or path.read_bytes() != raw:
        raise ValueError('Saved MC player changed while verifying debit')
    return {'mc_receipt_sha256': hashlib.sha256(raw).hexdigest(), 'marker': marker,
            'player_data': str(path.resolve()), 'saved_player_uid': actual_uid}


def prepare_permit(root, lease, mc_record, player_data, native_request_id):
    tx = lease['tx']
    if tx.get('protocol') != 3 or tx.get('action') != 'credit' or lease.get('status') not in {'claimed', 'crediting'}:
        raise ValueError('Only the v3 empty-escrow export stage may receive a credit permit')
    for key, value in tx.items():
        if mc_record.get(key) != value:
            raise ValueError('MC coordinator identity differs from escrow transaction: ' + key)
    if mc_record.get('mc_debit_durable') is not True or mc_record.get('state') != 'waiting_pal':
        raise ValueError('Persisted MC debit WAL prerequisite missing')
    if lease.get('owner_tx') != tx['id'] or type(lease.get('generation')) is not int or lease['generation'] < 1:
        raise ValueError('Unbound escrow generation')
    if type(tx.get('count')) is not int or not 1 <= tx['count'] <= 64:
        raise ValueError('Invalid quantity')
    if tx.get('item') not in {'Wood', 'Stone', 'Coal', 'Charcoal'}:
        raise ValueError('Invalid material')
    proof = read_saved_debit(player_data, tx)
    key = str(uuid.UUID(native_request_id)).replace('-', '')
    root = Path(root)
    path = root / ('escrow-credit-' + key + '.permit.bin')
    claimed = path.with_name(path.name.replace('.permit.bin', '.claimed.bin'))
    if claimed.exists():
        raise ValueError('Native permit was already claimed; reconcile the same lease')
    fingerprint = bytes.fromhex(tx['fingerprint'])
    if len(fingerprint) != 32:
        raise ValueError('Invalid transaction fingerprint')
    wire = (guid(native_request_id) + guid(tx['id']) + guid(lease['container_id']) +
            struct.pack('<iiQ', lease['slot'], tx['count'], lease['generation']) +
            fingerprint + bytes.fromhex(proof['mc_receipt_sha256']))
    if len(wire) != 128:
        raise ValueError('Native permit wire mismatch')
    # No replace: a lost acknowledgement recovers the same complete permit only.
    if path.exists():
        if path.read_bytes() != wire:
            raise ValueError('Existing permit differs')
    else:
        with path.open('xb') as file:
            file.write(wire)
            file.flush()
            os.fsync(file.fileno())
        if os.name != 'nt':
            fd = os.open(root, os.O_RDONLY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
    if claimed.exists():
        raise ValueError('Native permit advanced during preparation')
    return {**proof, 'native_request_id': native_request_id, 'permit_path': str(path),
            'permit_sha256': hashlib.sha256(wire).hexdigest(), 'lease_generation': lease['generation']}


def native_request_id(lease, operation, attempt=None):
    if operation not in {'moveIn', 'credit', 'deliver', 'dispose'}:
        raise ValueError('Unknown native operation')
    if attempt is None:
        op = lease.get('operations', {}).get(operation)
        attempt = op.get('attempt', 1) if op else lease.get('next_attempt', {}).get(operation, 1)
    if type(attempt) is not int or not 1 <= attempt <= 1_000_000:
        raise ValueError('Invalid native attempt')
    suffix = '' if attempt == 1 else f':attempt:{attempt}'
    return str(uuid.uuid5(uuid.UUID(lease['owner_tx']), f'escrow.v3:{lease["generation"]}:{operation}{suffix}'))
