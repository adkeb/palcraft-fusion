"""One bounded synthetic original-producer/original-template case; never executes any role."""
import ast,hashlib,importlib.util,json,pathlib,tempfile
HERE=pathlib.Path(__file__).resolve().parent.parent

def load(path,name):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
old=load(HERE/'base/mac/scripts/prepare_launch.py','original_prepare')
new=load(HERE/'source/mac/scripts/prepare_launch.py','candidate_prepare')
tree=ast.parse((HERE/'base/installer/standalone.py').read_text());fn=next(x for x in tree.body if isinstance(x,ast.FunctionDef)and x.name=='generated_files')
namespace={'Path':pathlib.Path,'DEV':'PalCraft-Dev','USER':'PalCraft-Client-User','TOOLS':'PalCraft-Dev/player-tools','BIN':'PalCraft-Client/Pal/Binaries/Win64/','json':json}
exec(compile(ast.Module(body=[fn],type_ignores=[]),'@original-generated-files','exec'),namespace)
with tempfile.TemporaryDirectory(prefix='window-fixture-',dir=HERE/'checks')as tmp:
 t=pathlib.Path(tmp);backend=t/'fixture-backend';root=t/'fixture-root';(backend/'setup').mkdir(parents=True);(backend/'client/versions/26.3').mkdir(parents=True)
 (backend/'setup/mac-dependency-plan.json').write_text(json.dumps({'libraries':[]}));(backend/'client/versions/26.3/26.3.jar').write_bytes(b'SYNTHETIC PATH EXISTENCE ONLY; never loaded')
 q=backend/'client/versions/fabric-loader-0.19.5-26.3';q.mkdir();(q/'fabric-loader-0.19.5-26.3.json').write_text(json.dumps({'id':'fixture-loader','arguments':{'jvm':[]}}))
 profile={'root':str(root),'windows_root':'Z:/fixture-root','bottle_root':str(t/'fixture-bottle'),'standalone':{'backend_root':str(backend),'save_account_directory':'fixture-account','backend_configuration':{'performance':{'mc_fps':60,'hud_fps':30,'render_distance':4,'simulation_distance':12,'mute':True,'mc_window_width':640,'mc_window_height':360}}},'connection':{'identity':{'mc_uuid':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','mc_name':'Fixture','pal_uid':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','world_id':'fixture-world'},'world_origin':{'x':1,'y':2,'z':3}}}
 manifest={'files':[{'role':'minecraft_mod','target':'PalCraft-Dev/minecraft-mods/passthrough-fixture.jar','sha256':'a'*64}]}
 files=namespace['generated_files'](profile,manifest);cfg=json.loads(files['PalCraft-Dev/player-tools/standalone/mac-runtime-config.json']);assert cfg['performance']['mc_window_width']==640 and cfg['performance']['mc_window_height']==360
 cfgpath=t/'config.json';cfg['launch_dir']=str(t/'launch');cfgpath.write_text(json.dumps(cfg));old.prepare_launch(cfgpath)
 roles={r:json.loads((t/'launch'/f'{r}.json').read_text())for r in ['server','guest','hud']};template=t/'original-template.json';template.write_text(json.dumps({'roles':roles}));original_bytes=template.read_bytes()
 cfg['preserve_launch_template']=str(template);cfgpath.write_text(json.dumps(cfg));new.prepare_launch(cfgpath,{'mc_fps':60,'hud_fps':30})
 actual={r:json.loads((t/'launch'/f'{r}.json').read_text())for r in roles}
 a,b=roles['guest']['arguments'],actual['guest']['arguments'];differences=[i for i in range(len(a))if a[i]!=b[i]]
 assert len(a)==len(b) and differences==[a.index('--width')+1,a.index('--height')+1]
 assert [b[i]for i in differences]==['640','360']
 for role in ['server','hud']:assert actual[role]['arguments']==roles[role]['arguments']
 for role in roles:
  for key in ['executable','main','cwd','same_original_uuid','frame_file']:assert actual[role][key]==roles[role][key]
 assert template.read_bytes()==original_bytes
 del cfg['performance']['mc_window_width'];del cfg['performance']['mc_window_height'];cfgpath.write_text(json.dumps(cfg));new.prepare_launch(cfgpath,{'mc_fps':60,'hud_fps':30})
 assert json.loads((t/'launch/guest.json').read_text())['arguments']==a
 for invalid in [{'mc_window_width':640},{'mc_window_width':True,'mc_window_height':360},{'mc_window_width':1921,'mc_window_height':360}]:
  bad=json.loads(json.dumps(cfg));bad['performance'].update(invalid);cfgpath.write_text(json.dumps(bad))
  try:new.prepare_launch(cfgpath)
  except ValueError:pass
  else:raise AssertionError('Invalid optional pair accepted')
print(json.dumps({'ok':True,'cases':1,'synthetic_only':True,'original_generated_configuration_preserves_pair':True,'only_original_guest_width_height_values_changed':2,'default_args_unchanged':True,'server_HUD_world_UUID_credential_frame_CWD_template_bytes_preserved':True,'optional_pair_and_integer_bounds_rejected_invalid':True,'actual_roles_or_framebuffer_or_HiDPI_1280x720_verified':False}))
