"""Offline personal V4 model and RGBA producer. Writes only output_staging.
Installer owns identity, session checks, resource selection and activation."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import sys
import zipfile
from pathlib import Path

BASE=Path(__file__).resolve().parent

class ResourceError(ValueError):
    def __init__(self,code,message,missing=()):
        super().__init__(message);self.code=code;self.missing=list(missing)
    def report(self):return {'ok':False,'code':self.code,'message':str(self),'missing':self.missing,'no_game_or_service_calls':True}

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb')as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def load_tools():
    modules={}
    for name in ['prepare_models_v2','prepare_models_v3','prepare_models_v4','prepare_material_pixels']:
        path=BASE/(name+'.py')
        if not path.is_file():raise ResourceError('V4_TOOL_MISSING','Required V4 tool is missing',[str(path)])
        spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
        sys.modules[name]=module
        try:spec.loader.exec_module(module)
        except ModuleNotFoundError as e:raise ResourceError('V4_DEPENDENCY_MISSING','Python dependency is missing',[e.name])from e
        modules[name]=module
    return modules

def validate(jar,packs,corpus_manifest):
    missing=[str(p)for p in [jar,*packs,corpus_manifest]if not p.is_file()]
    if missing:raise ResourceError('V4_INPUT_MISSING','Personal input files are missing',missing)
    try:
        with zipfile.ZipFile(jar)as archive:
            version=json.loads(archive.read('version.json'))
            if version.get('id')!='26.3':raise ResourceError('V4_MC_VERSION','A Minecraft 26.3 client JAR is required')
            if not any(n.startswith('assets/minecraft/blockstates/')for n in archive.namelist()):raise ResourceError('V4_CLIENT_ASSETS','The JAR does not contain client block assets')
        for pack in packs:
            if not zipfile.is_zipfile(pack):raise ResourceError('V4_PACK_INVALID','Resource pack is not a ZIP',[str(pack)])
        definition=json.loads(corpus_manifest.read_text())
    except (OSError,KeyError,zipfile.BadZipFile,json.JSONDecodeError)as e:raise ResourceError('V4_INPUT_INVALID',str(e))from e
    jar_sha=digest(jar)
    if definition.get('minecraft_client_sha256')!=jar_sha:raise ResourceError('V4_CORPUS_JAR_MISMATCH','The three geometry corpora must match this exact client JAR')
    paths={};receipts={}
    for role in ['chest','entity','decor']:
        item=definition.get('corpora',{}).get(role)
        if not item:raise ResourceError('V4_CORPUS_MISSING','Required geometry corpus role is missing',[role])
        path=(corpus_manifest.parent/item['path']).resolve();meta_path=path.with_suffix('.meta.json')
        missing=[str(p)for p in [path,meta_path]if not p.is_file()]
        if missing:raise ResourceError('V4_CORPUS_MISSING','Required geometry corpus or matching metadata is missing',missing)
        if digest(path)!=item['sha256']or digest(meta_path)!=item['meta_sha256']:raise ResourceError('V4_CORPUS_HASH','Geometry corpus changed',[str(path)])
        meta=json.loads(meta_path.read_text())
        if meta.get('minecraft_client_sha256')!=jar_sha:raise ResourceError('V4_CORPUS_JAR_MISMATCH','Geometry metadata belongs to another client JAR',[str(meta_path)])
        paths[role]=path;receipts[role]={'sha256':item['sha256'],'meta_sha256':item['meta_sha256'],'minecraft_client_sha256':jar_sha}
    return jar_sha,paths,receipts

def inventory(root):
    return [{'relative':p.relative_to(root).as_posix(),'sha256':digest(p),'bytes':p.stat().st_size}for p in sorted(root.rglob('*'))if p.is_file()]

def content_hash(files):
    return hashlib.sha256(''.join(r['relative']+'\0'+r['sha256']+'\n'for r in files).encode()).hexdigest()

def prepare_personal_v4(existing26_3jar,output_staging,resource_packs=(),dry_run=False,*,corpus_manifest=None):
    jar=Path(existing26_3jar).resolve();packs=[Path(p).resolve()for p in resource_packs]
    output=Path(output_staging).resolve();corpus_manifest=Path(corpus_manifest or BASE/'geometry-corpora.json').resolve()
    jar_sha,corpora,receipts=validate(jar,packs,corpus_manifest)
    if output.exists()and any(output.iterdir()):raise ResourceError('V4_OUTPUT_NOT_EMPTY','Output staging must be an empty independent directory')
    if dry_run:
        return {'ok':True,'dry_run':True,'schema':4,'minecraft_jar_sha256':jar_sha,'corpora':receipts,'original_resolution':True,'no_game_or_service_calls':True}
    modules=load_tools();output.mkdir(parents=True,exist_ok=True);bridge=output/'bridge';bridge.mkdir()
    staging=bridge/'models-v4.pending'
    converter=modules['prepare_models_v4'].ConverterV4(str(jar),str(staging),[str(p)for p in packs],1,str(corpora['chest']),entity_models=str(corpora['entity']),decor_models=str(corpora['decor']))
    try:manifest=converter.prepare()
    except (OSError,KeyError,ValueError)as e:raise ResourceError('V4_EXTRACT_FAILED',str(e))from e
    finally:
        for source in converter.sources:source.close()
    if manifest.get('schema')!=4 or not manifest.get('decorations_static_data_available')or not manifest.get('motion_data_available'):
        raise ResourceError('V4_SCHEMA_INCOMPLETE','The actual V4/V3/V2 extraction chain did not complete')
    if manifest.get('issues'):raise ResourceError('V4_EXTRACT_PARTIAL','Referenced resources are missing or invalid',[str(row)for row in manifest['issues']])
    personal={'schema':4,'minecraft_version':'26.3','minecraft_jar_sha256':jar_sha,'resource_pack_sha256':[digest(p)for p in packs],
        'corpora':receipts,'texture_min_size':1,'original_resolution':True,'minecraft_jar_packaged':False,'no_game_or_service_calls':True}
    (staging/'personal-source.json').write_text(json.dumps(personal,indent=2)+'\n')
    files=inventory(staging);sha=content_hash(files);namespace='models-v4-'+sha
    assets=bridge/namespace;staging.rename(assets)
    (assets/'CONTENT.sha256').write_text(''.join(r['sha256']+'  '+r['relative']+'\n'for r in files))
    # Only sprites that can need runtime tint, plus the actual biome-water
    # surfaces. The existing RGBA tool includes their animated frame sidecars.
    sprites=set()
    for model in(assets/'models').rglob('*.json'):
        for face in json.loads(model.read_text()).get('faces',[]):
            if face.get('tint',-1)>=0:sprites.add(face['texture'])
    for name in ['water_still','water_flow','water_overlay']:
        if(assets/'textures/minecraft/block'/(name+'.png')).is_file():sprites.add('minecraft:block/'+name)
    pixels=bridge/'material-pixels-v1'/namespace
    try:index=modules['prepare_material_pixels'].prepare(assets,pixels,sorted(sprites))
    except (OSError,ValueError)as e:raise ResourceError('V4_RGBA_PREPARE',str(e))from e
    selector={'schema_version':1,'directory':namespace,'provider_version':3,'content_hash':sha}
    registry={'version':1,'enabled':True,'pixel_packages':{namespace+'/':{'namespace':namespace,'index_path':'material-pixels-v1/'+namespace+'/index.json'}}}
    for name,value in [('model-assets.json',selector),('material-runtime-v1.json',registry)]:
        (bridge/name).write_text(json.dumps(value,indent=2)+'\n')
    report={'ok':True,'schema':4,'namespace':namespace,'model_manifest_sha256':digest(assets/'manifest.json'),'model_content_sha256':sha,
        'model_files':len(files),'rgba_textures':len(index['textures']),'sprites':sorted(sprites),
        'registry_files':['bridge/model-assets.json','bridge/material-runtime-v1.json'],
        'runtime_config_patch':{'model_asset_directory':namespace},'minecraft_jar_sha256':jar_sha,
        'original_resolution':True,'no_game_or_service_calls':True,'minecraft_jar_packaged':False,
        'runtime_verified':False,'unimplemented_special_models':manifest.get('special_models',[]),'files':inventory(output)}
    (output/'prepare-report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('jar');p.add_argument('output_staging')
    p.add_argument('--resource-pack',action='append',default=[]);p.add_argument('--corpus-manifest');p.add_argument('--dry-run',action='store_true')
    a=p.parse_args()
    try:
        result=prepare_personal_v4(a.jar,a.output_staging,a.resource_pack,a.dry_run,corpus_manifest=a.corpus_manifest)
        print(json.dumps({k:v for k,v in result.items()if k!='files'},ensure_ascii=False));return 0
    except ResourceError as e:print(json.dumps(e.report(),ensure_ascii=False));return 2

if __name__=='__main__':raise SystemExit(main())
