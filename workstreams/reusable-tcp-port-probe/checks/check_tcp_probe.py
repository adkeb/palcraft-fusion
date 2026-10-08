"""Three real ephemeral-socket cases; no application ports or services touched."""
import ast,json,pathlib,platform,re,shutil,socket,subprocess,sys,time
HERE=pathlib.Path(__file__).resolve().parent.parent
FORBIDDEN={25567,25599,25603,8321}
def load(path):
 tree=ast.parse(path.read_text());node=next(x for x in tree.body if isinstance(x,ast.FunctionDef)and x.name=='_port_free')
 namespace={'socket':socket};exec(compile(ast.Module(body=[node],type_ignores=[]),str(path),'exec'),namespace)
 return namespace['_port_free']
old=load(HERE/'base/launcher/runtime.py');new=load(HERE/'source/launcher/runtime.py')
results=[]
def owned_socket(host,kind=socket.SOCK_STREAM,reuse=False):
 s=socket.socket(socket.AF_INET,kind);s.settimeout(1)
 if reuse:s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
 s.bind((host,0));assert s.getsockname()[1]not in FORBIDDEN
 return s
# A server-side active close puts the fixture server tuple into actual TIME_WAIT.
with owned_socket('127.0.0.1',reuse=True)as listener:
 port=listener.getsockname()[1];listener.listen(1)
 with socket.socket(socket.AF_INET,socket.SOCK_STREAM)as client:
  client.settimeout(1);client.connect(('127.0.0.1',port));peer=client.getsockname()[1];assert peer not in FORBIDDEN
  with listener.accept()[0]as accepted:
   accepted.settimeout(1);accepted.sendall(b'fixture');assert client.recv(7)==b'fixture'
   accepted.shutdown(socket.SHUT_WR);assert client.recv(1)==b''
   client.shutdown(socket.SHUT_WR);assert accepted.recv(1)==b''
netstat=shutil.which('netstat');assert netstat,'Actual TIME_WAIT observation requires the existing netstat utility'
observed=[];started=time.monotonic()
while time.monotonic()-started<1:
 p=subprocess.run([netstat,'-anp','tcp'],text=True,capture_output=True,timeout=2);assert p.returncode==0,p.stderr
 observed=[line.strip()for line in p.stdout.splitlines()if 'TIME_WAIT'in line and f'127.0.0.1.{port}'in line and f'127.0.0.1.{peer}'in line]
 if observed:break
 time.sleep(.01)
assert observed,'Fixture tuple did not enter observed TIME_WAIT'
assert old(port)==False and new(port)==True
results.append({'case':'actual_ephemeral_TIME_WAIT_matches_reusable_listener_policy','local_port':port,'peer_port':peer,'state':'TIME_WAIT','netstat_fixture_rows':observed,'old_bind_only_free':False,'new_dual_address_reuse_bind_listen_free':True})
active=[]
for host in ['127.0.0.1','0.0.0.0']:
 with owned_socket(host,reuse=True)as listener:
  listener.listen(1);p=listener.getsockname()[1]
  assert old(p)==False and new(p)==False
  active.append({'bind_host':host,'fixture_port':p,'old_and_new_refuse_active_listener':True})
results.append({'case':'loopback_and_wildcard_active_reusable_TCP_listeners_refused','listeners':active})
udp=[]
for host in ['127.0.0.1','0.0.0.0']:
 with owned_socket(host,kind=socket.SOCK_DGRAM)as held:
  p=held.getsockname()[1];assert old(p,udp=True)==False and new(p,udp=True)==False
 assert old(p,udp=True)==True and new(p,udp=True)==True
 udp.append({'bind_host':host,'fixture_port':p,'held_refused':True,'closed_free':True})
results.append({'case':'UDP_original_bind_exclusivity_preserved','sockets':udp})
print(json.dumps({'ok':True,'cases':3,'platform':platform.system(),'actual_ephemeral_socket_cases':True,'synthetic_Game_session_data':False,'application_ports_or_roles_probed':False,'fixture_only':True,'results':results},indent=2))
