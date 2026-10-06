#!/usr/bin/env python3
"""Operator entry for the same proxy during a leased Lab integration window.

This entry does not adopt/install a root, create a bottle, start SSH, or control any server.
Normal players use the managed launcher's start/stop. The operator owns this foreground
process and its lease; Ctrl-C/SIGTERM closes its own sockets and marks snapshots stale.
"""
import argparse
import asyncio
import importlib.util
import json
import logging
import signal
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.credentials import inspect_credential
from launcher.session_proxy import SessionProxy, sign_receiver_from_path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--credential', type=Path, required=True)
    p.add_argument('--protocol', type=Path, required=True, help='frozen multiplayer/session_client.py')
    p.add_argument('--status', type=Path, required=True, help='personal bridge/session-bind-status.json')
    p.add_argument('--listen-port', type=int, default=25599)
    p.add_argument('--upstream-port', type=int, default=25598)
    p.add_argument('--sign-receiver', type=Path, help='next-only approved receiver.py; omitted keeps the current frozen protocol')
    p.add_argument('--check', action='store_true', help='offline inspection only; does not bind ports or write status')
    args = p.parse_args()
    if args.status.name != 'session-bind-status.json' or args.status.parent.name != 'bridge' or not args.status.is_absolute():
        p.error('--status must be an absolute personal bridge/session-bind-status.json')
    if args.protocol.name != 'session_client.py' or not args.protocol.is_file():
        p.error('--protocol must identify the frozen session_client.py')
    if not 1024 <= args.listen_port <= 65535 or not 1024 <= args.upstream_port <= 65535 or args.listen_port == args.upstream_port:
        p.error('two distinct loopback ports are required')
    public = inspect_credential(args.credential)
    spec = importlib.util.spec_from_file_location('palcraft_operator_session_protocol', args.protocol)
    protocol = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(protocol)
    value = protocol.load_credential(args.credential)
    receiver_factory = sign_receiver_from_path(args.sign_receiver) if args.sign_receiver else None
    if args.check:
        print(json.dumps({'ok': True, 'offline': True, 'protocol': 2, 'identity': public['identity'],
                          'server_session_id': public['server_session_id'], 'signature_verified_locally': False,
                          'listen': '127.0.0.1:' + str(args.listen_port), 'upstream': '127.0.0.1:' + str(args.upstream_port),
                          'writes_status': False, 'starts_other_processes': False}, ensure_ascii=False))
        return 0

    async def serve():
        event = asyncio.Event()
        loop = asyncio.get_running_loop()
        for signum in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(signum, event.set)
            except NotImplementedError:
                pass
        proxy = SessionProxy(value, protocol, args.status, args.upstream_port, args.listen_port, sign_receiver_factory=receiver_factory)
        await proxy.serve(event)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    try:
        asyncio.run(serve())
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
