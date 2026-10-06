"""Standalone path/authority ports for the existing v3 registrar and worker.

No game/service calls, save writes, UID allocation or transaction creation.
The profile is trusted local runtime configuration, not a rehydration receipt.
"""
from pathlib import Path
import hashlib
import json
import re
import time
import uuid
from escrow_io import read_and_force

CLIENT_SHA='e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'

def load_scope(path):
    scope=json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if scope.get('kind')!='palcraft_standalone_runtime' or scope.get('configured_for_runtime') is not True:
        raise ValueError('Actual configured private singleplayer runtime profile required')
    scope['world_directory']=str(scope['world_directory']).upper()
    if re.fullmatch('[0-9A-F]{32}',scope['world_directory']) is None:
        raise ValueError('Actual loaded world directory required')
    scope['pal_uid']=str(uuid.UUID(scope['pal_uid']))
    for key in ['private_user_dir_host','installed_level_path_host','exchange_root_host','rpc_root_host','wine_prefix_host',
                'pal_exe_host','durable_dll_host','credit_dll_host']:
        scope[key]=str(Path(scope[key]).resolve())
    level=validate_level(scope,scope['installed_level_path_host'])
    for host,windows in [('exchange_root_host','exchange_root_windows'),('rpc_root_host','rpc_root_windows'),
                         ('pal_exe_host','pal_exe_windows'),('durable_dll_host','durable_dll_windows'),('credit_dll_host','credit_dll_windows')]:
        mapped=wine_path(scope,scope[windows])
        if mapped!=Path(scope[host]):
            raise ValueError('Mac/Wine physical path differs: '+host)
    if hashlib.sha256(Path(scope['pal_exe_host']).read_bytes()).hexdigest()!=CLIENT_SHA:
        raise ValueError('Actual client image differs from matched e590 ABI')
    if level.name.lower()!='level.sav':raise ValueError('Actual Level.sav required')
    return scope

def wine_path(scope,path):
    normalized=str(path).replace('\\','/')
    if re.match('^[A-Za-z]:/',normalized) is None:
        raise ValueError('Actual absolute Wine drive path required')
    parts=normalized[3:].split('/')
    if any(x in {'.','..'} for x in parts):raise ValueError('Traversal is not a runtime path mapping')
    drive=(Path(scope['wine_prefix_host'])/'dosdevices'/(normalized[0].lower()+':')).resolve()
    if not drive.is_dir():raise ValueError('Declared private Wine drive mapping is missing')
    return drive.joinpath(*parts).resolve()

def validate_level(scope,level):
    level=Path(level).resolve();selected=Path(scope['installed_level_path_host']).resolve()
    root=Path(scope['private_user_dir_host']).resolve()
    if level!=selected or root not in level.parents or level.name.lower()!='level.sav' or level.parent.name.upper()!=scope['world_directory']:
        raise ValueError('Only the actual runtime-selected private singleplayer Level is in scope')
    if not level.is_file():raise ValueError('Installed singleplayer Level does not exist')
    return level

def authority_matches(scope,snapshot):
    a=snapshot.get('authority',{})
    return (snapshot.get('player_uid')==scope['pal_uid'] and a.get('mode')=='standalone' and
            a.get('world_directory')==scope['world_directory'] and a.get('local_controller') is True and
            a.get('has_authority') is True and a.get('world_multiplayer_enabled') is False and
            a.get('dedicated_server') is False and a.get('remote_connected_players')==0)

def current_process_binding(scope):
    root=Path(scope['rpc_root_host'])
    process=json.loads(read_and_force(root/'escrow-client-process.json'))
    exchange=Path(scope['exchange_root_host'])
    binding=json.loads(read_and_force(exchange/'escrow-client-process-binding.json'))
    if (process.get('kind')!='palworld_client_process_identity' or process.get('native_code_matched') is not True or
            process.get('read_only') is not True or process.get('executable_sha256')!=CLIENT_SHA or
            not 0<=time.time()-process.get('observed_unix',0)<=5):
        raise ValueError('Fresh actual in-process client identity is unavailable')
    if any(binding.get(k)!=process.get(k) for k in ['pid','process_created_filetime','executable_sha256']):
        raise ValueError('Native client process differs from installed process binding')
    if binding.get('world_directory')!=scope['world_directory'] or binding.get('pal_uid')!=scope['pal_uid']:
        raise ValueError('Current process binding belongs to another actual local host/world')
    str(uuid.UUID(binding['boot_id']))
    if binding.get('kind')!='palworld_client_process_binding' or type(binding.get('revision')) is not int:
        raise ValueError('Actual immutable process binding WAL is missing')
    name='pal-client-process-'+binding['boot_id']+f'.r{binding["revision"]:06d}'
    if any(json.loads(read_and_force(exchange/(name+suffix)))!=binding for suffix in ['.json','.durable.json']):
        raise ValueError('Process binding has no exact actual durable receipt')
    return binding

def lua_scope(scope):
    return {'mode':'standalone','world_directory':scope['world_directory'],'pal_uid':scope['pal_uid'],
            'scripts_dir':scope['scripts_dir_windows'],'rpc_root':scope['rpc_root_windows'],
            'exchange_root':scope['exchange_root_windows']}
