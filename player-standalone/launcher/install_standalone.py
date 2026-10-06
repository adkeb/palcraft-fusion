#!/usr/bin/env python3
"""Mac offline singleplayer installation using the portable installer."""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.core import PlayerError, read_json
from installer.standalone import setup_standalone, prepare_backend, enrollment_profile, uninstall_standalone, rotate_events

def main():
    p=argparse.ArgumentParser(description=__doc__);commands=p.add_subparsers(dest='command',required=True)
    install=commands.add_parser('install')
    for name in ('root','game','resume-parameters','bottle','bottle-root','crossover-app','backend-root'):
        install.add_argument('--'+name,required=True)
    install.add_argument('--bottle-mode',choices=('existing-selected','create-owned'),default='existing-selected')
    install.add_argument('--game-copy-mode',choices=('copy','apfs-clone'),default='copy')
    install.add_argument('--bundle',default=str(Path(__file__).resolve().parents[1]/'release.zip'))
    for name in ('backend','uninstall','enrollment-profile','rotate-events'):
        sub=commands.add_parser(name);sub.add_argument('--root',required=True)
        if name=='enrollment-profile':sub.add_argument('--guest-manifest',required=True);sub.add_argument('--output',required=True)
        else:sub.add_argument('--dry-run',action='store_true')
        if name=='rotate-events':sub.add_argument('--normal-stop-receipt',required=True)
    install.add_argument('--dry-run',action='store_true')
    a=p.parse_args()
    try:
        if a.command=='install':r=setup_standalone(a.root,a.game,a.bundle,read_json(a.resume_parameters),
            bottle_name=a.bottle,bottle_root=a.bottle_root,crossover_app=a.crossover_app,backend_root=a.backend_root,
            bottle_mode=a.bottle_mode,copy_mode=a.game_copy_mode,dry_run=a.dry_run)
        elif a.command=='backend':r=prepare_backend(a.root,a.dry_run)
        elif a.command=='enrollment-profile':r=enrollment_profile(a.root,a.guest_manifest,a.output)
        elif a.command=='rotate-events':r=rotate_events(a.root,a.normal_stop_receipt,a.dry_run)
        else:r=uninstall_standalone(a.root,a.dry_run)
    except (PlayerError,OSError,ValueError)as e:
        print(json.dumps(e.as_dict()if isinstance(e,PlayerError)else{'ok':False,'message':str(e)},ensure_ascii=False));return 2
    print(json.dumps(r,ensure_ascii=False,indent=2));return 0
if __name__=='__main__':raise SystemExit(main())
