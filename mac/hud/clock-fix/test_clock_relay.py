import socket,struct,threading,time,sys
from pathlib import Path
sys.path.insert(0,str(Path('work/minecraft-fusion/palcraft/render').resolve()))
from hud_relay import Latest,Server
class Producer:
 stop=threading.Event()
 def slow_client(self):raise AssertionError('calibration socket stalled')
latest=Latest()
server=Server(('127.0.0.1',0),latest,Producer())
thread=threading.Thread(target=server.serve_forever,kwargs={'poll_interval':.01},daemon=True)
thread.start()
try:
 before=time.time_ns()
 nonce=123456789
 with socket.create_connection(server.server_address,timeout=1)as s:
  s.sendall(b'TIME\n'+struct.pack('!Q',nonce))
  buf=b''
  while len(buf)<32:buf+=s.recv(32-len(buf))
 values=struct.unpack('!4sHHQQQ',buf)
 after=time.time_ns()
 assert values[:4]==(b'HCLK',1,32,nonce)
 assert before<=values[4]<=values[5]<=after
 assert latest.clients==0 and latest.serial==0 # calibration never joins/perturbs HUD publication
 print('{"status":"passed","clock_control_packet":true,"hud_stream_unchanged":true,"engine_calls":0}')
finally:
 server.producer.stop.set();server.shutdown();server.server_close();thread.join(1)
