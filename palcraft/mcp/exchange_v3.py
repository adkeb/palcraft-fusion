"""The existing witness worker's v3 leg: same WAL, actual saved NBT, two Level witnesses.

No inventory mutation and no service lifecycle. Decode only a changed save off the
Pal game thread. Native produce permits are placed in the configured server RPC root.
"""
import hashlib
from pathlib import Path
import time
import uuid
from exchange_recovery import atomic_write, read, IDENTITY
import escrow_credit
import escrow_witness
from escrow_io import read_and_force


def native_request_id(lease, operation):
    code = {'moveIn': 1, 'credit': 2, 'deliver': 3, 'dispose': 4}[operation]
    txid = str(uuid.UUID(lease['owner_tx']))
    value = (int(txid[-8:], 16) + lease['generation'] * 4096 + (lease.get('operations', {}).get(operation, {}).get('attempt') or lease.get('next_attempt', {}).get(operation) or 1) * 16 + code) & 0xffffffff
    return txid[:-8] + f'{value:08x}'


def read_saved_leg(path, tx, leg):
    # Reuse the bounded actual-NBT reader and world/UUID/race validation. The
    # owner's debit utility takes a marker prefix; a credit marker is validated
    # by retaining all its actual save checks and replacing only the requested leg.
    path = Path(path)
    if leg == 'debit':
        return escrow_credit.read_saved_debit(path, tx)
    stat = path.stat()
    data = read_and_force(path, 16 * 1024 * 1024)
    import gzip, io, struct
    raw = data
    if raw[:2] == b'\x1f\x8b':
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as zipped:
            raw = zipped.read(16 * 1024 * 1024 + 1)
    saved = escrow_credit.NbtReader(raw).root()
    encoded = saved.get('UUID')
    if not isinstance(encoded, list) or len(encoded) != 4 or any(type(x) is not int for x in encoded):
        raise ValueError('Saved MC UUID missing')
    actual_uid = str(uuid.UUID(bytes=struct.pack('>4I', *(x & 0xffffffff for x in encoded))))
    marker = f'palcraft.exchange.v3:{tx["id"]}:{leg}'
    if (path.parent.name != 'playerdata' or path.parent.parent.resolve() != Path(tx['mc_world']).resolve() or
            path.name != actual_uid + '.dat' or actual_uid != tx['mc_uid'] or
            marker not in saved.get('Tags', []) or any(type(x) is not str for x in saved.get('Tags', []))):
        raise ValueError('Actual atomic MC leg/world/player receipt missing')
    after = path.stat()
    if (stat.st_mtime_ns, stat.st_size, stat.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino) or path.read_bytes() != data:
        raise ValueError('Actual saved MC player changed during verification')
    return {'mc_receipt_sha256': hashlib.sha256(data).hexdigest(), 'marker': marker,
            'player_data': str(path.resolve()), 'saved_player_uid': actual_uid}


def publish_bound_witness(root, current_path, lease, witness):
    """Bind the parser's real witness to the exact selected lease, including tentative rebases."""
    if not escrow_witness.accept_witness(lease, witness) or escrow_witness.select_current(read(current_path), lease['owner_tx']) != lease:
        raise ValueError('Current exact lease changed before bound witness publication')
    witness['lease_record'] = lease
    path = Path(root) / f'escrow-witness-{lease["owner_tx"]}-g{lease["generation"]}-{lease["status"]}.json'
    atomic_write(path, witness)
    return witness


class Runner:
    def __init__(self, root, level, vendor=None, save=None, rpc_root=None, verify_boot=None):
        self.root, self.level, self.vendor, self.save = Path(root), Path(level), vendor, save
        self.rpc_root = Path(rpc_root) if rpc_root else None
        self.cache_key = self.saved = None
        self.save_attempts, self.save_successes = {}, set()
        self.decode_count = 0
        self.verify_boot = verify_boot

    def decoder(self, data, vendor):
        key = hashlib.sha256(data).digest()
        if key != self.cache_key:
            self.saved = escrow_witness.decode_save(data, vendor)
            self.cache_key = key
            self.decode_count += 1
        return self.saved

    def mc_proof(self, lease, leg):
        tx = lease['tx']
        mc = read(self.root / f'mc-{tx["id"]}.json')
        if any(mc.get(key) != tx.get(key) for key in IDENTITY) or mc.get(f'mc_{leg}_durable') is not True:
            raise ValueError('Matching durable MC leg required')
        receipt = mc[f'mc_{leg}_receipt']
        if any(receipt.get(k) != tx.get(k) for k in ('protocol', 'id', 'fingerprint', 'mc_uid', 'mc_world')) or receipt.get('leg') != leg:
            raise ValueError('MC saved receipt binding differs')
        proof = read_saved_leg(Path(tx['mc_world']) / 'playerdata' / (tx['mc_uid'] + '.dat'), tx, leg)
        result = {**proof, 'protocol': 3, 'id': tx['id'], 'fingerprint': tx['fingerprint'],
                  'lease_generation': lease['generation'], 'leg': leg, 'mc_receipt': receipt, 'durable': True}
        path = self.root / f'escrow-mc-{leg}-proof-{tx["id"]}-g{lease["generation"]}.json'
        old = read(path) if path.exists() else None
        if old != result:
            atomic_write(path, result)
        return mc

    def tick(self):
        path = self.root / 'escrow-leases-current.json'
        if not path.exists():
            return {'written': [], 'held': []}
        export = read(path)
        if export.get('protocol') != 3 or not isinstance(export.get('leases'), dict):
            raise ValueError('Current lease export schema differs')
        written, held = [], []
        active = False
        for lease in export['leases'].values():
            if lease['status'] == 'released':
                continue
            active = True
            txid, generation, stage = lease['owner_tx'], lease['generation'], lease['status']
            new_boot_pending = False
            rearm_reason = None
            try:
                if stage == 'claimed' and lease['tx']['action'] == 'credit':
                    if not self.rpc_root:
                        raise ValueError('The installed server RPC root must be configured')
                    mc = self.mc_proof(lease, 'debit')
                    request_id = native_request_id(lease, 'credit')
                    proof = escrow_credit.prepare_permit(self.rpc_root, lease, mc,
                        Path(lease['tx']['mc_world']) / 'playerdata' / (lease['tx']['mc_uid'] + '.dat'), request_id)
                    credit_attempt = lease.get('operations', {}).get('credit', {}).get('attempt') or lease.get('next_attempt', {}).get('credit') or 1
                    proof_path = self.root / f'escrow-credit-proof-{txid}-g{generation}-a{credit_attempt}.json'
                    old = read(proof_path) if proof_path.exists() else None
                    if old != proof:
                        atomic_write(proof_path, proof)
                if stage == 'full_saved' and lease['tx']['action'] == 'debit':
                    self.mc_proof(lease, 'credit')
                if stage in {'needs_recovery', 'moving_in', 'crediting', 'disposing', 'delivering', 'full', 'empty'}:
                    boot_path = self.root / 'escrow-boot-certificate.json'
                    if boot_path.exists():
                        import escrow_rehydrate
                        boot = read(boot_path)
                        rearm_written = False
                        for key, operation in lease['operations'].items():
                            after_phase = 'full' if key in {'moveIn', 'credit'} else 'empty'
                            if (key in {'moveIn', 'credit', 'dispose', 'deliver'} and operation.get('attempted') is True and
                                    not lease.get(after_phase + '_witness') and
                                    (stage not in {'full', 'empty'} or stage == after_phase) and
                                    operation.get('boot_id') != boot.get('boot_id')):
                                new_boot_pending = True
                                if not self.verify_boot:
                                    rearm_reason = 'Trusted new-process checkpoint verifier is pending'
                                    continue
                                proof_path = self.root / f'escrow-rearm-{txid}-g{generation}-{key}-a{operation.get("attempt", 1)}.json'
                                previous = read(proof_path) if proof_path.exists() else {}
                                proof_id = previous.get('proof_id') if previous.get('lease_revision') == lease['revision'] and previous.get('to_boot_id') == boot['boot_id'] else None
                                try:
                                    proof = escrow_rehydrate.make_rearm_proof(lease, key, self.level, boot,
                                        self.verify_boot, self.vendor, self.decoder, proof_id=proof_id)
                                except (ValueError, KeyError, OSError) as error:
                                    # A genuinely saved afterimage refuses rearm and may
                                    # still receive its ordinary full/empty witness below.
                                    rearm_reason = str(error)
                                    continue
                                # A current-row race cannot arm the old revision.
                                current = escrow_witness.select_current(read(path), txid)
                                if current != lease:
                                    raise ValueError('Lease advanced during rearm verification')
                                if previous != proof:
                                    atomic_write(proof_path, proof)
                                rearm_written = True
                        if rearm_written:
                            held.append({'id': txid, 'stage': stage, 'rearm_pending': True,
                                         'reason': 'Fresh checkpoint proof published; awaiting durable rearm'})
                            continue  # Do not overwrite the pre-attempt checkpoint with REST/save.
                if stage in {'full', 'empty'}:
                    output = self.root / f'escrow-witness-{txid}-g{generation}-{stage}.json'
                    if output.exists() and escrow_witness.accept_witness(lease, read(output)) and read(output).get('lease_record') == lease:
                        written.append(f'{txid}:{stage}')
                        continue
                    witness = escrow_witness.write_witness(self.root, path, self.level, self.vendor,
                        decoder=self.decoder, tx_id=txid)
                    publish_bound_witness(self.root, path, lease, witness)
                    written.append(f'{txid}:{witness["stage"]}')
            except (ValueError, KeyError, OSError) as error:
                entry = {'id': txid, 'stage': stage, 'reason': str(error)}
                if new_boot_pending:
                    entry['rearm_pending'] = True
                    if rearm_reason:
                        entry['rearm_reason'] = rearm_reason
                key = (txid, generation, lease['revision'], stage)
                now = time.time()
                if (stage in {'full', 'empty'} and not new_boot_pending and self.save and key not in self.save_successes and
                        now >= lease.get('save_after_unix', 0) and now - self.save_attempts.get(key, 0) >= 3):
                    self.save_attempts[key] = now
                    try:
                        self.save()
                        self.save_successes.add(key)
                        entry['save_requested'] = True
                    except Exception:
                        entry['save_request_failed'] = True
                held.append(entry)
        if not active:
            self.cache_key = self.saved = None
        return {'written': written, 'held': held, 'protocol': 3, 'decode_count': self.decode_count}
