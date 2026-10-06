#!/usr/bin/env python3
"""Bounded loopback UDP client for the existing 4-byte network-order TCP relay."""
import argparse
import asyncio
import contextlib
import json
import logging
import os
from pathlib import Path
import signal
import struct
import time

LOG = logging.getLogger('palcraft.udp')
MAX_PACKET = 65507


class LocalRelay(asyncio.DatagramProtocol):
    def __init__(self, tcp_port=18321, idle_seconds=45, max_peers=8, queue_size=128, status_file=None):
        self.tcp_port, self.idle_seconds = tcp_port, idle_seconds
        self.max_peers, self.queue_size = max_peers, queue_size
        self.peers, self.transport = {}, None
        self.tasks = set()
        self.status_file = Path(status_file) if status_file else None
        self.last_error, self.connections = None, 0

    def report(self, stopped=False):
        if not self.status_file:
            return
        connected = sum(p.get('connected', False) for p in self.peers.values())
        replies = [p['last_reply'] for p in self.peers.values() if p.get('last_reply')]
        value = {'schema': 1, 'phase': 'stopped' if stopped else 'connected' if connected else 'reconnecting' if self.last_error else 'listening',
                 'updated_unix': time.time(), 'connected_peers': connected, 'peers': len(self.peers),
                 'connections_created': self.connections, 'last_error': self.last_error,
                 'last_reply_unix': max(replies) if replies else None,
                 'pal_session_verified': False}
        self.status_file.parent.mkdir(parents=True, exist_ok=True)
        temp = self.status_file.with_suffix('.tmp')
        temp.write_text(json.dumps(value) + '\n', encoding='utf-8')
        os.replace(temp, self.status_file)

    def connection_made(self, transport):
        self.transport = transport
        self.report()

    def datagram_received(self, data, addr):
        if len(data) > MAX_PACKET or addr[0] != '127.0.0.1':
            return
        if addr not in self.peers:
            if len(self.peers) >= self.max_peers:
                LOG.warning('UDP_PEER_LIMIT: 已忽略多余本地连接。')
                return
            self.peers[addr] = {'queue': asyncio.Queue(self.queue_size), 'last': time.monotonic()}
            task = asyncio.create_task(self.session(addr, self.peers[addr]))
            self.tasks.add(task)
            task.add_done_callback(self.tasks.discard)
        peer = self.peers[addr]
        peer['last'] = time.monotonic()
        try:
            peer['queue'].put_nowait(data)
        except asyncio.QueueFull:
            LOG.warning('UDP_QUEUE_FULL: 连接拥塞，已丢弃一个 UDP 包。')

    async def session(self, addr, peer):
        writer, tasks = None, []
        try:
            reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1', self.tcp_port), timeout=5)
            peer['connected'] = True
            self.connections += 1
            self.last_error = None
            self.report()

            async def send():
                while True:
                    data = await asyncio.wait_for(peer['queue'].get(), timeout=self.idle_seconds)
                    writer.write(struct.pack('!I', len(data)) + data)
                    await writer.drain()

            async def receive():
                while True:
                    header = await asyncio.wait_for(reader.readexactly(4), timeout=self.idle_seconds)
                    count = struct.unpack('!I', header)[0]
                    if count > MAX_PACKET:
                        raise ValueError('UDP_FRAME_INVALID: TCP 中的 UDP 帧长度异常。')
                    data = await asyncio.wait_for(reader.readexactly(count), timeout=5)
                    self.transport.sendto(data, addr)
                    peer['last_reply'] = time.time()

            tasks = [asyncio.create_task(send()), asyncio.create_task(receive())]
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        except asyncio.TimeoutError:
            self.last_error = 'UDP_IDLE_OR_CONNECT_TIMEOUT'
            LOG.info('UDP_IDLE: 个人 UDP 连接已过期；有新数据时重新连接。')
        except (OSError, asyncio.IncompleteReadError, ValueError) as exc:
            self.last_error = 'UDP_TCP_DISCONNECTED'
            LOG.warning('UDP_CONNECTION: %s', exc)
        except asyncio.CancelledError:
            pass
        finally:
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            if writer:
                writer.close()
                with contextlib.suppress(OSError):
                    await writer.wait_closed()
            self.peers.pop(addr, None)
            self.report()

    async def close(self):
        self.transport.close()
        for task in list(self.tasks):
            task.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)
        self.report(stopped=True)


async def main(args):
    relay = LocalRelay(args.tcp_port, args.idle_seconds, status_file=args.status_file)
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(lambda: relay, local_addr=('127.0.0.1', args.udp_port))
    stop = asyncio.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(signum, stop.set)
    LOG.info('UDP_READY: 个人连接已绑定到 loopback。')
    async def status_tick():
        while True:
            await asyncio.sleep(1)
            relay.report()
    ticker = asyncio.create_task(status_tick())
    try:
        await stop.wait()
    finally:
        ticker.cancel()
        await asyncio.gather(ticker, return_exceptions=True)
        await relay.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tcp-port', type=int, default=18321)
    parser.add_argument('--udp-port', type=int, default=8321)
    parser.add_argument('--idle-seconds', type=float, default=45)
    parser.add_argument('--status-file', type=Path)
    args = parser.parse_args()
    if not 1024 <= args.tcp_port <= 65535 or not 1024 <= args.udp_port <= 65535 or args.idle_seconds <= 0:
        parser.error('端口或连接超时不合法。')
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    asyncio.run(main(args))
