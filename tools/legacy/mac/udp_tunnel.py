#!/usr/bin/env python3
"""Frame Palworld test UDP over a loopback-only SSH TCP forward."""
import asyncio, struct, sys
class Relay(asyncio.DatagramProtocol):
 def __init__(self,writer):self.writer=writer
 def datagram_received(self,data,addr):self.writer.write(struct.pack('!I',len(data))+data)
async def remote(reader,writer):
 transport,_=await asyncio.get_running_loop().create_datagram_endpoint(lambda:Relay(writer),remote_addr=('127.0.0.1',8321))
 try:
  while True:
   n=struct.unpack('!I',await reader.readexactly(4))[0]
   if n>65535:raise ValueError('invalid UDP frame')
   transport.sendto(await reader.readexactly(n))
 except (asyncio.IncompleteReadError,ConnectionError):pass
 finally:transport.close();writer.close()
class Local(asyncio.DatagramProtocol):
 def __init__(self):self.peers={}
 def connection_made(self,t):self.transport=t
 def datagram_received(self,data,addr):
  if addr not in self.peers:self.peers[addr]=asyncio.Queue();asyncio.create_task(self.session(addr,self.peers[addr]))
  self.peers[addr].put_nowait(data)
 async def session(self,addr,q):
  writer=None
  try:
   reader,writer=await asyncio.open_connection('127.0.0.1',18321)
   async def send():
    while True:
     data=await q.get();writer.write(struct.pack('!I',len(data))+data);await writer.drain()
   async def receive():
    while True:
     n=struct.unpack('!I',await reader.readexactly(4))[0]
     if n>65535:raise ValueError('invalid UDP frame')
     self.transport.sendto(await reader.readexactly(n),addr)
   tasks=[asyncio.create_task(send()),asyncio.create_task(receive())]
   await asyncio.wait(tasks,return_when=asyncio.FIRST_EXCEPTION)
   for task in tasks:task.cancel()
  except (OSError,asyncio.IncompleteReadError):pass
  finally:
   if writer:writer.close()
   self.peers.pop(addr,None)
async def main():
 if sys.argv[1]=='server':
  server=await asyncio.start_server(remote,'127.0.0.1',18321)
  async with server:await server.serve_forever()
 else:
  await asyncio.get_running_loop().create_datagram_endpoint(Local,local_addr=('127.0.0.1',8321))
  await asyncio.Event().wait()
asyncio.run(main())
