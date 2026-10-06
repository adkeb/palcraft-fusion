"""One idle socket resume check; no game producer, load, GPU or source-age relaxation."""
import socket,struct,threading,time,sys
from pathlib import Path
sys.path.insert(0,str(Path('work/minecraft-fusion/palcraft/render').resolve()))
from hud_relay import Latest,Server
from hud_protocol import Frame,encode,V2
class Producer:
 stop=threading.Event()
 def slow_client(self):raise AssertionError('client unexpectedly timed out')
latest=Latest();p=Producer();server=Server(('127.0.0.1',0),latest,p)
thread=threading.Thread(target=server.serve_forever,kwargs={'poll_interval':.01},daemon=True);thread.start()
try:
 with socket.create_connection(server.server_address,timeout=1)as s:
  s.sendall(b'HUD2\n')
  # Exceed the removed1.5sec frame watchdog while source is legitimately idle.
  time.sleep(1.6)
  assert latest.clients==1
  now=time.time_ns()//1_000_000
  latest.put(encode(Frame(1,1,b'\0\0\0\0',123,1,1,2,now,now,7)))
  raw=b''
  while len(raw)<64:raw+=s.recv(64-len(raw))
  meta=V2.unpack(raw)
  assert meta[9:11]==(1,2)
 print('{"status":"passed","same_idle_connection_resumes":true,"source_age_limit_ms":250,"game_calls":0}')
finally:
 p.stop.set()
 with latest.condition:latest.condition.notify_all()
 server.shutdown();server.server_close();thread.join(1)
