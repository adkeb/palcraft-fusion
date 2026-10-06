#!/usr/bin/env python3
"""Read-only Pal save verification plus fsynced exchange witnesses. Never grants or removes items.

Run on the backend that owns exchangeDir. The existing patched palworld-save-tools vendor
and pyooz 0.0.8 are required to parse real PlM/PlZ Level.sav files. No REST/save response,
mtime-only change, aggregate item count, or hand-written acknowledgement is sufficient.
"""
import argparse
import contextlib
import hashlib
import io
import json
import os
import re
from pathlib import Path
import sys
import time
import uuid
import urllib.request
import urllib.parse
import base64

IDENTITY = ("protocol", "id", "mc_uid", "player_uid", "mc_world", "item", "count", "action", "fingerprint")
TERMINAL = {"completed", "refunded", "rejected"}


def read(path):
    with Path(path).open(encoding="utf-8") as source:
        return json.load(source)


def atomic_write(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + "." + str(uuid.uuid4()) + ".tmp")
    try:
        with temporary.open("x", encoding="utf-8") as destination:
            json.dump(value, destination, ensure_ascii=False, separators=(",", ":"))
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, path)
        if os.name != "nt":
            fd = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
    finally:
        if temporary.exists():
            temporary.unlink()


def pal_records(root):
    """Return only complete immutable chains; corruption or a gap stops verification."""
    grouped = {}
    for path in Path(root).glob("pal-*.r*.json"):
        if path.name.startswith("pal-active.") or path.name.endswith(".durable.json") or ".unconfirmed" in path.name:
            continue
        record = read(path)
        txid = str(uuid.UUID(record["id"]))
        revision = record["revision"]
        if type(revision) is not int or revision < 1 or path.name != f"pal-{txid}.r{revision:06d}.json":
            raise ValueError("Pal journal identity/revision mismatch")
        grouped.setdefault(txid, {})[revision] = (record, path)
    latest = {}
    for txid, chain in grouped.items():
        if sorted(chain) != list(range(1, max(chain) + 1)):
            raise ValueError("Pal journal has missing revisions: " + txid)
        first = chain[1][0]
        for record, _ in chain.values():
            if any(record.get(key) != first.get(key) for key in IDENTITY):
                raise ValueError("Pal journal payload changed: " + txid)
        latest[txid] = chain[max(chain)]
    return latest


def status(root):
    pals = pal_records(root)
    transactions = []
    for path in sorted(Path(root).glob("mc-*.json")):
        row = read(path)
        if row.get("state") in TERMINAL:
            continue
        pal = pals.get(row.get("id"), ({}, None))[0]
        transactions.append({"id": row.get("id"), "mc_uid": row.get("mc_uid"),
                             "player_uid": row.get("player_uid"), "item": row.get("item"),
                             "count": row.get("count"), "to_mc": row.get("to_mc"),
                             "mc_state": row.get("state"), "pal_state": pal.get("status"),
                             "pal_revision": pal.get("revision"),
                             "reason": pal.get("error", row.get("blocked", row.get("error"))),
                             "mc_debit_durable": row.get("mc_debit_durable", False),
                             "pal_effect_observed": pal.get("effect_observed", False),
                             "pal_effect_attempted": pal.get("effect_attempted", False),
                             "manual_audit_required": row.get("state") == "needs_recovery" or pal.get("status") == "needs_recovery" or pal.get("recovery_required") is True})
    return {"protocol": 3 if any(read(path).get("protocol") == 3 for path in Path(root).glob("mc-*.json")) else 2, "pending_count": len(transactions), "transactions": transactions}


def load_saved_slots(data, vendor=None):
    if vendor:
        sys.path.insert(0, str(vendor))
    from palworld_save_tools.gvas import GvasFile
    from palworld_save_tools.palsav import decompress_sav_to_gvas
    from palworld_save_tools.paltypes import PALWORLD_TYPE_HINTS
    from palworld_save_tools.archive import FArchiveReader
    raw, _ = decompress_sav_to_gvas(data)
    # Leave item-slot RawData opaque, then decode its verified index/count/static/dynamic header.
    # The 1.0 save representation uses sparse RawData slots rather than reflected live fields.
    warnings = io.StringIO()
    with contextlib.redirect_stdout(warnings):
        gvas = GvasFile.read(raw, PALWORLD_TYPE_HINTS, {}, allow_nan=True)
    if "ItemContainerSaveData" in warnings.getvalue():
        raise ValueError("Save parser could not confirm the item-container schema")
    containers = gvas.properties["worldSaveData"]["value"]["ItemContainerSaveData"]["value"]
    out = {}
    for entry in containers:
        container_id = str(entry["key"]["ID"]["value"]).lower()
        uuid.UUID(container_id)
        if container_id in out:
            raise ValueError("Duplicate saved container")
        value = entry["value"]
        capacity = value["SlotNum"]["value"]
        if type(capacity) is not int or not 0 <= capacity <= 1000:
            raise ValueError("Invalid saved container capacity")
        slots = {}
        for slot in value.get("Slots", {}).get("value", {}).get("values", []):
            encoded = bytes(slot["RawData"]["value"]["values"])
            reader = FArchiveReader(encoded)
            index, count = reader.i32(), reader.i32()
            if index in slots or not 0 <= index < capacity or count < 0:
                raise ValueError("Duplicate or invalid saved item slot")
            ref = {"container_id": container_id, "slot": index, "count": count, "item": ""}
            if count:
                ref["item"] = reader.fstring()
                ref["dynamic_world"] = str(reader.guid()).lower()
                ref["dynamic_guid"] = str(reader.guid()).lower()
            slots[index] = ref
        out[container_id] = (capacity, slots)
    return out


def verify_after(row, saved):
    if row.get("protocol") != 2 or row.get("status") != "awaiting_pal_save" or row.get("effect_observed") is not True:
        raise ValueError("Only a native effect already observed by the game thread can receive a witness")
    expected = row.get("expected_after")
    if not isinstance(expected, list) or not expected:
        raise ValueError("No observed affected slots")
    seen = set()
    for ref in expected:
        key = (ref["container_id"], ref["slot"])
        if key in seen:
            raise ValueError("Duplicate affected slot")
        seen.add(key)
        capacity, slots = saved[ref["container_id"]]
        if not 0 <= ref["slot"] < capacity:
            raise ValueError("Saved affected slot lies outside its container")
        actual = slots.get(ref["slot"], {"container_id": ref["container_id"], "slot": ref["slot"], "count": 0, "item": ""})
        if actual != ref:
            raise ValueError("Saved slot does not contain the observed effect: " + str(key))


def write_witness(root, row, journal_path, level, data, saved):
    verify_after(row, saved)
    before = level.stat()
    if before.st_mtime_ns < row.get("save_after_unix", row["updated_unix"] + 1) * 1_000_000_000:
        raise ValueError("Pal save predates the material-change save barrier")
    digest = hashlib.sha256(data).hexdigest()
    # Verify the currently installed save, not a backup or a file replaced during parsing.
    with level.open("rb") as source:
        current = source.read()
        os.fsync(source.fileno())
    after = level.stat()
    if current != data or (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
        raise ValueError("Pal save changed while verifying")
    latest = read(journal_path)
    next_revision = Path(root) / f'pal-{row["id"]}.r{row["revision"]+1:06d}.json'
    if latest != row or next_revision.exists():
        raise ValueError("Pal transaction advanced while verifying")
    witness = {"protocol": 2, "id": row["id"], "fingerprint": row["fingerprint"],
               "pal_revision": row["revision"], "durable": True,
               "expected_after": row["expected_after"], "save_path": str(level.resolve()),
               "save_sha256": digest, "journal_sha256": hashlib.sha256(journal_path.read_bytes()).hexdigest(),
               "verified_unix": time.time()}
    atomic_write(Path(root) / ("witness-" + row["id"] + ".json"), witness)
    return witness


def once(root, level, vendor=None):
    pending = [(row, path) for row, path in pal_records(root).values() if row.get("status") == "awaiting_pal_save"]
    if not pending:
        return {"written": [], "held": []}
    data = Path(level).read_bytes()
    saved = load_saved_slots(data, vendor)
    written, held = [], []
    for row, path in pending:
        try:
            written.append(write_witness(root, row, path, Path(level), data, saved)["id"])
        except (ValueError, KeyError, OSError) as error:
            held.append({"id": row["id"], "reason": str(error)})
    return {"written": written, "held": held}


def current_pending(root):
    """Only inspect the current mailbox's transaction, instead of rereading all historical WALs."""
    request_path = Path(root) / "request.json"
    if not request_path.exists():
        return []
    request = read(request_path)
    txid = str(uuid.UUID(request["id"]))
    paths = sorted(path for path in Path(root).glob(f"pal-{txid}.r*.json") if not path.name.endswith(".durable.json") and ".unconfirmed" not in path.name)
    if not paths:
        return []
    latest = None
    for revision, path in enumerate(paths, 1):
        row = read(path)
        if path.name != f"pal-{txid}.r{revision:06d}.json" or row["revision"] != revision or any(row.get(key) != request.get(key) for key in IDENTITY):
            raise ValueError("Current Pal WAL is incomplete or its payload changed")
        latest = (row, path)
    return [latest] if latest[0].get("status") == "awaiting_pal_save" else []


def peak_rss_bytes():
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        class Memory(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]
        value = Memory(); value.cb = ctypes.sizeof(value)
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.GetCurrentProcess.restype = wintypes.HANDLE
        get_memory = ctypes.WinDLL("psapi", use_last_error=True).GetProcessMemoryInfo
        get_memory.argtypes = [wintypes.HANDLE, ctypes.POINTER(Memory), wintypes.DWORD]
        get_memory.restype = wintypes.BOOL
        if not get_memory(kernel.GetCurrentProcess(), ctypes.byref(value), value.cb):
            return None
        return value.PeakWorkingSetSize
    import resource
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return value if sys.platform == "darwin" else value * 1024


def request_lab_save(settings, url):
    # Owner-selected endpoint and server settings; credentials never appear in logs or argv.
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("A configured HTTP(S) server save endpoint is required")
    text = Path(settings).read_text(encoding="utf-8-sig")
    match = re.search(r'AdminPassword="([^"\r\n]+)"', text)
    if not match:
        raise ValueError("BridgeLab REST/save admin credential is unavailable")
    token = base64.b64encode(("admin:" + match.group(1)).encode()).decode()
    request = urllib.request.Request(url, data=b"", method="POST", headers={"Authorization": "Basic " + token})
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=5) as response:
        response.read(65536)
    # A successful response starts a save; only the later parsed Level.sav is a witness.


class WitnessRunner:
    def __init__(self, root, level, vendor=None, save=None, rpc_root=None, verify_boot=None):
        self.root, self.level, self.vendor, self.save = Path(root), Path(level), vendor, save
        self.cache_key, self.data, self.saved = None, None, None
        self.metrics = None
        self.attempts = {}
        self.save_successes = {}
        self.decode_count = 0
        self.v3 = None
        self.rpc_root = rpc_root
        self.verify_boot = verify_boot

    def tick(self):
        request_path = self.root / "request.json"
        if request_path.exists() and read(request_path).get("protocol") == 3:
            if self.v3 is None:
                from exchange_v3 import Runner
                self.v3 = Runner(self.root, self.level, self.vendor, self.save, self.rpc_root,
                                 verify_boot=self.verify_boot)
            return self.v3.tick()
        pending = current_pending(self.root)
        if not pending:
            self.cache_key, self.data, self.saved = None, None, None
            return {"written": [], "held": []}
        before = self.level.stat()
        written, held = [], []
        for row, journal in pending:
            try:
                existing = self.root / ("witness-" + row["id"] + ".json")
                if existing.exists():
                    witness = read(existing)
                    if witness.get("pal_revision") == row["revision"] and witness.get("fingerprint") == row["fingerprint"] and witness.get("durable") is True and witness.get("expected_after") == row["expected_after"]:
                        written.append(row["id"])
                        continue
                barrier = row.get("save_after_unix", row["updated_unix"] + 1)
                if before.st_mtime_ns < barrier * 1_000_000_000:
                    raise ValueError("Pal save predates the material-change save barrier")
                key = (before.st_mtime_ns, before.st_size, before.st_ino)
                if key != self.cache_key:
                    started, cpu = time.perf_counter(), time.process_time()
                    data = self.level.read_bytes()
                    saved = load_saved_slots(data, self.vendor)
                    after = self.level.stat()
                    if (after.st_mtime_ns, after.st_size, after.st_ino) != key:
                        raise ValueError("Pal save changed during decoding")
                    self.cache_key, self.data, self.saved = key, data, saved
                    self.decode_count += 1
                    self.metrics = {"decode_seconds": round(time.perf_counter() - started, 4),
                                    "decode_cpu_seconds": round(time.process_time() - cpu, 4),
                                    "peak_rss_bytes": peak_rss_bytes(), "save_bytes": len(data),
                                    "containers": len(saved), "decode_count": self.decode_count}
                witness = write_witness(self.root, row, journal, self.level, self.data, self.saved)
                written.append(witness["id"])
            except (ValueError, KeyError, OSError) as error:
                entry = {"id": row["id"], "reason": str(error)}
                conflict = isinstance(error, ValueError) and str(error).startswith("Saved slot does not contain the observed effect:")
                if conflict:
                    blocked = {"protocol": 2, "id": row["id"], "fingerprint": row["fingerprint"],
                               "pal_revision": row["revision"], "needs_inventory_audit": True,
                               "reason": str(error), "verified_unix": time.time()}
                    blocked_path = self.root / ("witness-blocked-" + row["id"] + ".json")
                    previous = read(blocked_path) if blocked_path.exists() else {}
                    if any(previous.get(key) != blocked.get(key) for key in ("pal_revision", "fingerprint", "reason")):
                        atomic_write(blocked_path, blocked)
                now = time.time()
                # One successful immediate save per transaction. Repeated saves cannot fix a moved slot.
                # Failed HTTP requests retry at most once per three seconds without decoding an old save.
                if self.save and row["id"] not in self.save_successes and now >= row.get("save_after_unix", 0) and now - self.attempts.get(row["id"], 0) >= 3:
                    self.attempts[row["id"]] = now
                    try:
                        self.save(); self.save_successes[row["id"]] = now; entry["save_requested"] = True
                    except Exception:
                        # Do not include urllib request/credential-bearing exception representations.
                        entry["save_request_failed"] = True
                held.append(entry)
        result = {"written": written, "held": held}
        if self.metrics:
            result["metrics"] = self.metrics
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["status", "witness"])
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--level", type=Path)
    parser.add_argument("--parser-vendor", type=Path)
    parser.add_argument("--rpc-root", type=Path, help="Installed Pal server RPC root for saved-NBT native credit permits")
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--pal-settings", type=Path)
    parser.add_argument("--pal-save-url", default="http://127.0.0.1:8322/v1/api/save")
    parser.add_argument("--pal-server-root", type=Path, default=Path("D:/PalworldServer-LAN/BridgeLab"))
    parser.add_argument("--request-save", action="store_true", help="Request one immediate save when a witness is blocked")
    args = parser.parse_args()
    if args.action == "status":
        print(json.dumps(status(args.root), ensure_ascii=False, indent=2))
        return
    if not args.level or args.level.name.lower() != "level.sav":
        parser.error("--level must identify the current world Level.sav")
    if args.interval < 0.25:
        parser.error("--interval must be at least 0.25 seconds")
    vendor = args.parser_vendor
    if vendor is None:
        local = Path(__file__).resolve().parents[3] / "palworld-save-toolkit/python/vendor"
        if local.exists():
            vendor = local
    last = None
    settings = args.pal_settings or args.pal_server_root / "Pal/Saved/Config/WindowsServer/PalWorldSettings.ini"
    save = (lambda: request_lab_save(settings, args.pal_save_url)) if args.pal_settings or args.watch or args.request_save else None
    import escrow_bootstrap
    runner = WitnessRunner(args.root, args.level, vendor, save, args.rpc_root or args.pal_server_root / "rpc",
                           verify_boot=escrow_bootstrap.verifier(args.root, args.pal_server_root, args.level))
    while True:
        try:
            result = runner.tick()
        except Exception as error:
            result = {"written": [], "held": [{"reason": str(error)}]}
        encoded = json.dumps(result, ensure_ascii=False, sort_keys=True)
        if encoded != last:
            print(encoded, flush=True)
            last = encoded
        if not args.watch:
            return
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
