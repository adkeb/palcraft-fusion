"""Compose a legal complete base with a relative, approved Standalone overlay."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from installer.core import target_allowed

def compose(base_release, overlay_root, spec_path, output):
    overlay_root=Path(overlay_root);spec=json.loads(Path(spec_path).read_text())
    changes={entry['target']:entry for entry in spec['files']}
    output=Path(output)
    if output.exists():raise ValueError('Choose a new candidate output; preserve old releases')
    replacements={}
    for target,entry in changes.items():
        if not target_allowed(target):raise ValueError('Unsupported relative installer target: '+target)
        source=overlay_root/entry['source']
        data=source.read_bytes()
        if hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('Overlay changed: '+entry['source'])
        replacements[target]=data
    with zipfile.ZipFile(base_release)as base:
        manifest=json.loads(base.read('manifest.json'));old={e['target']:e for e in manifest['files']}
        for target in spec.get('remove_targets',[]):old.pop(target,None)
        for target,entry in changes.items():
            old[target]={'target':target,'sha256':entry['sha256'],'bytes':len(replacements[target]),
                         'role':entry['role'],'executable':entry.get('executable',False)}
        manifest.update(version=spec['version'],platform='crossover',files=sorted(old.values(),key=lambda e:e['target']),
                        classification='ordinary-player-Standalone-candidate',source_revision=spec['source_revision'])
        manifest['requirements'].update(spec.get('requirements',{}))
        with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED)as result:
            result.writestr('manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2))
            for target in old:
                data=replacements.get(target)
                result.writestr('payload/'+target,base.read('payload/'+target)if data is None else data)
    return {'output':str(output),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'files':len(old),'unchanged_base_assets_transferred_without_repeatedSHA':True,'gameplay_verified':False}

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ('base-release','overlay-root','spec','output'):p.add_argument('--'+name,required=True)
    a=p.parse_args();print(json.dumps(compose(a.base_release,a.overlay_root,a.spec,a.output),indent=2))
