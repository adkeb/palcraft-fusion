"""Compile only the three reviewed MC units over a user's exact legal F35 base."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import os
import subprocess
import time
import zipfile

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main(args):
    delta=Path(args.delta_root).resolve();freeze=Path(args.freeze).resolve()
    base=Path(args.base_mod).resolve();jdk=Path(args.jdk_home).resolve()
    runtime=Path(args.runtime_root).resolve();fabric=Path(args.fabric_api).resolve()
    original=json.loads((freeze/'build-recipe.json').read_text())
    assert sha(base)==original['final_mod_sha256'],'Use the exact F35 runtime base'
    assert sha(fabric)==original['fabric_api_distribution']['sha256']
    build=delta/'build';build.mkdir(exist_ok=True)
    output=delta/'outputs';output.mkdir(exist_ok=True)
    embedded=build/'dependencies';embedded.mkdir(exist_ok=True)
    classes=build/'production-classes';classes.mkdir(exist_ok=True)
    helper=build/'compile-helper';helper.mkdir(exist_ok=True)
    overlay=build/'fabric-interface-compile.jar'
    cp=[]
    with zipfile.ZipFile(base)as old,zipfile.ZipFile(fabric)as api:
        for entry in original['classpath']:
            if entry['root']=='runtime':
                path=runtime/entry['relative'];assert path.is_file(),entry['relative']
            else:
                archive=old if entry['root']=='base-embedded'else api
                data=archive.read(entry['relative'])
                assert hashlib.sha256(data).hexdigest()==entry['sha256']
                path=embedded/Path(entry['relative']).name;path.write_bytes(data)
            cp.append(path)
    environment=os.environ.copy()
    for key in ['JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS','CLASSPATH']:
        environment.pop(key,None)
    calls=[]
    def run(command):
        started=time.monotonic()
        result=subprocess.run(command,capture_output=True,text=True,env=environment)
        calls.append({'argv':command,'exit_code':result.returncode,'elapsed_seconds':round(time.monotonic()-started,3)})
        (build/('javac-stage-'+str(len(calls))+'.stdout.txt')).write_text(result.stdout)
        (build/('javac-stage-'+str(len(calls))+'.stderr.txt')).write_text(result.stderr)
        assert result.returncode==0,result.stderr
    asm=next(p for p in cp if p.name=='asm-9.10.1.jar')
    minecraft=next(p for p in cp if p.name=='26.3.jar')
    compiler=str(jdk/'bin/javac');java=str(jdk/'bin/java')
    quiet=['-J-XX:ActiveProcessorCount=1','-J-XX:+UseSerialGC']
    helper_source=freeze/original['compile_interface_overlay']['source']
    assert sha(helper_source)==original['compile_interface_overlay']['source_sha256']
    run([compiler,'-J-Xmx128m',*quiet,'-classpath',str(asm),'-d',str(helper),str(helper_source)])
    run([java,'-Xmx128m','-XX:ActiveProcessorCount=1','-XX:+UseSerialGC','-classpath',os.pathsep.join([str(helper),str(asm)]),
        'FabricCompileInterfaces',str(minecraft),str(overlay)])
    with zipfile.ZipFile(overlay)as z:
        assert set(z.namelist())==set(original['compile_interface_overlay']['targets'])
    selected=sorted((delta/'source/mc/src/main/java').rglob('*.java'))
    assert len(selected)==3
    for src in selected:
        name=src.relative_to(delta/'source/mc').as_posix()
        assert sha(delta/'base/mc'/name)==original['allowed_source_members'][name],name
    run([compiler,'-J-Xmx512m',*quiet,*original['javac_flags'],'-classpath',
        os.pathsep.join(str(p)for p in [overlay,base,*cp]),'-d',str(classes),*(str(p)for p in selected)])
    production={p.relative_to(classes).as_posix():p.read_bytes()for p in sorted(classes.rglob('*.class'))}
    assert production and all(n.startswith('dev/rehan/passthrough/')for n in production)
    version='0.2.0-integration.10.9-center-source'
    destination=output/('passthrough-'+version+'.jar')
    assert not destination.exists(),'Keep the original compiler output'
    with zipfile.ZipFile(base)as old:
        old_names=old.namelist();assert set(production)<=set(old_names)
        metadata=json.loads(old.read('fabric.mod.json'));metadata['version']=version
        replacements={**production,'fabric.mod.json':(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n').encode()}
        with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED)as candidate:
            for info in old.infolist():
                candidate.writestr(copy.deepcopy(info),replacements.get(info.filename,old.read(info.filename)))
    with zipfile.ZipFile(base)as old,zipfile.ZipFile(destination)as candidate:
        assert candidate.namelist()==old.namelist()
        preserved=[n for n in old.namelist()if n not in replacements]
        assert all(old.read(n)==candidate.read(n)for n in preserved)
        assert not any(n.startswith(('net/minecraft/','FabricCompileInterfaces','compile-helper/'))for n in candidate.namelist())
    source_names=original['allowed_source_members']
    source_archive=output/'mc10_9-center-source.zip'
    new_source_pins={}
    with zipfile.ZipFile(source_archive,'w',compression=zipfile.ZIP_DEFLATED)as z:
        for name in sorted(source_names):
            src=delta/'source/mc'/name
            if not src.is_file():src=freeze/'source'/name
            data=src.read_bytes();new_source_pins[name]=hashlib.sha256(data).hexdigest()
            if not(delta/'source/mc'/name).is_file():assert new_source_pins[name]==source_names[name],name
            info=zipfile.ZipInfo(name,(2026,10,7,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
            z.writestr(info,data)
    recipe=copy.deepcopy(original)
    recipe.update(version=version,base_mod_sha256=sha(base),final_mod_sha256=sha(destination),final_mod_bytes=destination.stat().st_size,
        allowed_source_members=new_source_pins,allowed_source_member_count=len(new_source_pins),
        compile_sources={p.relative_to(delta/'source/mc').as_posix():sha(p)for p in selected},
        production_classes={n:hashlib.sha256(data).hexdigest()for n,data in production.items()},
        production_class_count=len(production),source_archive_sha256=sha(source_archive),
        assembly={'base':'exact legal F35 runtime','replace':sorted(replacements),'all_other_entry_bytes_preserved':True})
    (output/'build-recipe.json').write_text(json.dumps(recipe,ensure_ascii=False,indent=2)+'\n')
    receipt={'schema':1,'ok':True,'version':version,'base_mod_sha256':sha(base),'jar_sha256':sha(destination),
        'jar_bytes':destination.stat().st_size,'java_sources_compiled':3,'production_class_count':len(production),
        'production_classes':recipe['production_classes'],'runtime_entries':len(old_names),
        'runtime_classes':sum(n.endswith('.class')for n in old_names),'unchanged_entry_bytes_preserved':len(preserved),
        'compile_overlay_runtime_excluded':True,'source_archive':source_archive.name,
        'source_archive_sha256':sha(source_archive),'source_archive_members':len(new_source_pins),
        'existing_legal_runtime_dependencies_reused':True,'full_source_project_recompiled':False,
        'worker_concurrency':1,'nice':os.getpriority(os.PRIO_PROCESS,0),'max_heap_mib':512,'calls':calls,
        'runtime_or_scene_verified':False,'managed_mc_payload_slots':1}
    (output/'build-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in receipt.items()if k not in ['calls','production_classes']},ensure_ascii=False,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['delta-root','freeze','base-mod','jdk-home','runtime-root','fabric-api']:
        parser.add_argument('--'+name,required=True)
    main(parser.parse_args())
