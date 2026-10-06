import socket,struct,json,os,time
from pathlib import Path
s=socket.create_connection(('127.0.0.1',25599),timeout=5)
s.sendall(b'GET / HTTP/1.1\r\nHost: 127.0.0.1:25599\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n')
h=b''
while not h.endswith(b'\r\n\r\n'):h+=s.recv(1)
assert b' 101 ' in h
payload=json.dumps({'t':'inspect'}).encode();mask=os.urandom(4)
s.sendall(bytes([0x81,0x80|len(payload)])+mask+bytes(c^mask[i%4] for i,c in enumerate(payload)))
def receive(n):
 b=b''
 while len(b)<n:
  p=s.recv(n-len(b))
  if not p:raise EOFError()
  b+=p
 return b
until=time.monotonic()+5;result=None
try:
 while time.monotonic()<until:
  a,b=receive(2);n=b&127
  if n==126:n=struct.unpack('!H',receive(2))[0]
  elif n==127:n=struct.unpack('!Q',receive(8))[0]
  mask=receive(4) if b&128 else None;body=receive(n)
  if mask:body=bytes(c^mask[i%4] for i,c in enumerate(body))
  if a&15==1:
   v=json.loads(body)
   if v.get('t')=='inspection':result=v;break
finally:s.close()
assert result,'No MC inspection response'
Path('work/minecraft-fusion/native_renderer/mc-inspection.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False))
