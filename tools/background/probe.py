import socket,subprocess,base64,os,hashlib,struct,json,time,threading,sys
from pathlib import Path
class WS:
 def __init__(self,port=25601):
  self.s=socket.create_connection(('127.0.0.1',port),timeout=5);self.lock=threading.Lock();key=base64.b64encode(os.urandom(16)).decode()
  self.s.sendall(f'GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode());header=b''
  while not header.endswith(b'\r\n\r\n'):
   b=self.s.recv(1)
   if not b:raise EOFError('handshake closed')
   header+=b
  accept=base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
  assert header.startswith(b'HTTP/1.1 101 ') and accept in header,header
 def send(self,v,opcode=1):
  b=json.dumps(v,separators=(',',':')).encode() if opcode==1 else v;m=os.urandom(4);n=len(b);h=bytes([128|opcode,128|n]) if n<126 else bytes([128|opcode,254])+struct.pack('!H',n)
  with self.lock:self.s.sendall(h+m+bytes(x^m[i%4] for i,x in enumerate(b)))
 def take(self,n):
  out=b''
  while len(out)<n:
   b=self.s.recv(n-len(out))
   if not b:raise EOFError('websocket closed')
   out+=b
  return out
 def read(self):
  data=b''
  while True:
   a,b=self.take(2);n=b&127
   if n==126:n=struct.unpack('!H',self.take(2))[0]
   elif n==127:n=struct.unpack('!Q',self.take(8))[0]
   assert n<16*1024*1024
   mask=self.take(4) if b&128 else None;p=self.take(n)
   if mask:p=bytes(x^mask[i%4] for i,x in enumerate(p))
   op=a&15
   if op==8:raise EOFError('close frame')
   if op==9:self.send(p,10);continue
   if op==10:continue
   data+=p
   if a&128:return json.loads(data)
 def inspect(self):
  self.send({'t':'inspect'})
  while True:
   m=self.read()
   if m.get('t')=='inspection':return m
 def close(self):self.s.close()
if __name__=='__main__':
 w=WS();print(json.dumps(w.inspect(),indent=2));w.close()
