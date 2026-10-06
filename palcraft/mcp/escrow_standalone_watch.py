#!/usr/bin/env python3
"""Reuse v3 Runner with in-process normal SP save requests, no server/REST/WMI.

Writes only existing control/proof files. Reads the selected private Level and
actual MC player data. Never initiates a transaction or edits a save.
"""
import argparse
from pathlib import Path
import time
import uuid
import json
from exchange_recovery import atomic_write
from exchange_v3 import Runner
import escrow_standalone

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--scope',type=Path,required=True)
    p.add_argument('--parser-vendor',type=Path)
    p.add_argument('--watch',action='store_true')
    p.add_argument('--interval',type=float,default=1)
    args=p.parse_args()
    if args.interval<.5:p.error('Existing low-power interval must be at least .5 seconds')
    scope=escrow_standalone.load_scope(args.scope)
    root=Path(scope['exchange_root_host'])
    def request_save():
        binding=escrow_standalone.current_process_binding(scope)
        atomic_write(root/'escrow-client-save-command.json',{'protocol':3,'id':str(uuid.uuid4()),
            'world_directory':scope['world_directory'],'pal_uid':scope['pal_uid'],'boot_id':binding['boot_id']})
    runner=Runner(root,scope['installed_level_path_host'],args.parser_vendor,request_save,scope['rpc_root_host'],
                  boot_path=root/'escrow-client-process-binding.json')
    last=None
    while True:
        try:
            escrow_standalone.current_process_binding(scope)
            result=runner.tick()
        except (ValueError,KeyError,OSError) as error:
            result={'written':[],'held':[{'reason':str(error)}]}
        encoded=json.dumps(result,ensure_ascii=False,sort_keys=True)
        if encoded!=last:print(encoded,flush=True);last=encoded
        if not args.watch:return
        time.sleep(args.interval)

if __name__=='__main__':main()
