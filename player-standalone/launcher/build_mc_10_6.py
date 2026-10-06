#!/usr/bin/env python3
"""Compile exactly the two 10.6 Java sources and repack the normal 10.5 mod."""
import argparse
import copy
import hashlib
import json
import os
import subprocess
import tempfile
import zipfile
from pathlib import Path

def sha(data): return hashlib.sha256(data).hexdigest()

def build(base_mod, jdk_home, runtime_root, freeze, output, dry_run=False):
    freeze=Path(freeze);recipe=json.loads((freeze/'build-recipe.json').read_text())
    base_mod=Path(base_mod);output=Path(output)
    if sha(base_mod.read_bytes())!=recipe['base_mod_sha256']:raise ValueError('Use the exact recorded 10.5 base mod')
    compiler=Path(jdk_home)/'bin/javac'
    deps=[Path(runtime_root)/relative for relative in recipe['classpath_relative']]
    if not compiler.is_file()or not all(p.is_file()for p in deps):raise ValueError('JDK25 or recorded Minecraft/Fabric dependencies missing')
    sources=[freeze/'source'/relative for relative in recipe['sources']]
    for source,relative in zip(sources,recipe['sources']):
        if sha(source.read_bytes())!=recipe['sources'][relative]:raise ValueError('Frozen Java source changed')
    plan={'base_mod':str(base_mod),'compiler':str(compiler),'source_files':[str(p)for p in sources],
          'classpath':[str(base_mod),*[str(p)for p in deps]],'output':str(output),
          'normal_javac_only':True,'new_game_network_or_GUI':False,'original19_tests_rerun':False}
    if dry_run:return {'ok':True,'dry_run':True,**plan}
    if output.exists():raise ValueError('Output already exists; choose a new build file')
    with tempfile.TemporaryDirectory(prefix='palcraft-mc10_6-',dir=output.parent)as directory:
        classes=Path(directory)/'classes';classes.mkdir()
        command=[str(compiler),'-encoding','UTF-8','-proc:none','--release','25','-classpath',os.pathsep.join(plan['classpath']),'-d',str(classes),*[str(p)for p in sources]]
        run=subprocess.run(command,capture_output=True,text=True)
        if run.returncode:raise RuntimeError(run.stderr)
        replacements={}
        for relative,expected in recipe['replacement_classes'].items():
            data=(classes/relative).read_bytes()
            if sha(data)!=expected:raise ValueError('Compiled class differs; use the recorded JDK25/dependencies: '+relative)
            replacements[relative]=data
        replacements['fabric.mod.json']=(freeze/'fabric.mod.json').read_bytes()
        with zipfile.ZipFile(base_mod)as base,zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED)as result:
            for info in base.infolist():
                data=replacements.get(info.filename)
                if data is None:
                    result.writestr(info,base.read(info.filename));continue
                meta=recipe['replacement_zip_metadata'][info.filename]
                chosen=zipfile.ZipInfo(info.filename,tuple(meta['date_time']))
                for key in ('compress_type','create_system','create_version','extract_version','external_attr','internal_attr','flag_bits'):
                    setattr(chosen,key,meta[key])
                chosen.comment=bytes.fromhex(meta['comment_hex']);chosen.extra=bytes.fromhex(meta['extra_hex'])
                result.writestr(chosen,data)
    actual=sha(output.read_bytes())
    receipt={'ok':True,**plan,'jar_sha256':actual,'expected_jar_sha256':recipe['final_mod_sha256'],
             'binary_reproduced':actual==recipe['final_mod_sha256'],'unchanged_original_entries':169,
             'class_inventory':168,'changed_Java_sources':2,'runtime_or_pixel_accepted':False}
    output.with_suffix('.build.json').write_text(json.dumps(receipt,indent=2)+'\n')
    if not receipt['binary_reproduced']:raise ValueError('Artifact bytes differ; see build receipt, do not promote it silently')
    return receipt

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('base-mod','jdk-home','runtime-root','output'):p.add_argument('--'+name,required=True)
    p.add_argument('--freeze',default=str(Path(__file__).resolve().parents[1]/'build/mc10_6'))
    p.add_argument('--dry-run',action='store_true');a=p.parse_args()
    print(json.dumps(build(a.base_mod,a.jdk_home,a.runtime_root,a.freeze,a.output,a.dry_run),indent=2))
