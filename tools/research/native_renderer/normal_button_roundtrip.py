import socket,struct,json,os,time
from pathlib import Path
s=socket.create_connection(('127.0.0.1',25599),timeout=5)
s.sendall(b'GET / HTTP/1.1\r\nHost: 127.0.0.1:25599\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n')
h=b''
while not h.endswith(b'\r\n\r\n'):h+=s.recv(1)
assert b' 101 ' in h

def send(q):
 p=json.dumps(q).encode();m=os.urandom(4)
 header=bytes([0x81,0x80|len(p)]) if len(p)<126 else bytes([0x81,0xfe])+struct.pack('!H',len(p))
 s.sendall(header+m+bytes(c^m[i%4] for i,c in enumerate(p)))
def receive(n):
 b=b''
 while len(b)<n:
  p=s.recv(n-len(b))
  if not p:raise EOFError()
  b+=p
 return b
def inspect():
 send({'t':'inspect'})
 while True:
  a,b=receive(2);n=b&127
  if n==126:n=struct.unpack('!H',receive(2))[0]
  elif n==127:n=struct.unpack('!Q',receive(8))[0]
  m=receive(4) if b&128 else None;p=receive(n)
  if m:p=bytes(c^m[i%4] for i,c in enumerate(p))
  if a&15==1:
   q=json.loads(p)
   if q.get('t')=='inspection':return q
out={'type':'normal_survival_button_place','started_unix':time.time()}
try:
 out['before']=inspect()
 assert not out['before']['creative']
 assert any(v['slot']==0 and v['item']=='minecraft:oak_button' and v['count']==1 for v in out['before']['inventory'])
 assert out['before']['aim']['block']=='minecraft:oak_planks'
 send({'t':'mode','on':True});send({'t':'slot','n':0});time.sleep(.15)
 send({'t':'key','k':'use','down':True});time.sleep(.18);send({'t':'key','k':'use','down':False});time.sleep(.7)
 out['after_place']=inspect()
 out['finished_unix']=time.time()
finally:
 send({'t':'key','k':'use','down':False});send({'t':'key','k':'attack','down':False});s.close()
p=Path('work/minecraft-fusion/native_renderer/button-place-inspection.json');p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(out,ensure_ascii=False))
