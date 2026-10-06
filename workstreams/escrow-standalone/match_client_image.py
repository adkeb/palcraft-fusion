#!/usr/bin/env python3
"""Bounded static full-function match; never loads either image or calls a game."""
from pathlib import Path
import hashlib
import json
import re
import struct
import sys

BASE=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(BASE/'work/palworld-live/native-research'))
from inspect_pe import PE
TASK=Path(__file__).resolve().parent
CLIENT=BASE/'work/minecraft-fusion/mac/drive_d/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/Palworld-Win64-Shipping.exe'

def signature(pe,rva):
    start,end,_=pe.containing(rva)
    assert start==rva
    raw=pe.data[pe.offset(start):pe.offset(start)+end-start]
    mask=bytearray(b'\1'*len(raw));relocations=[]
    assembly=pe.disassemble(rva)
    for line in assembly.splitlines():
        m=re.match(r'^\s*([0-9a-f]+):\s*((?:[0-9a-f]{2}\s+)+)\s*([^\t]+)\t(.*)',line)
        if not m:continue
        address=int(m[1],16)-pe.base;code=bytes.fromhex(m[2]);op=m[3].strip();operand=m[4]
        p=address-start
        assert raw[p:p+len(code)]==code
        rip=re.search(r'\[rip\s*([+-])\s*(0x[0-9a-f]+)\]',operand)
        if rip:
            value=int(rip[2],16)*(1 if rip[1]=='+' else -1)
            encoded=struct.pack('<i',value);positions=[i for i in range(len(code)-3) if code[i:i+4]==encoded]
            assert len(positions)==1,(line,positions)
            a=p+positions[0];mask[a:a+4]=b'\0'*4;relocations.append({'offset':a,'kind':'rip32','target_rva':address+len(code)+value})
        elif '[rip' in operand:raise ValueError('Unhandled RIP-relative encoding: '+line)
        if op in {'call','jmp'} and code[0] in {0xe8,0xe9}:
            target=address+len(code)+struct.unpack_from('<i',code,1)[0]
            if op=='call' or not start<=target<end:
                mask[p+1:p+5]=b'\0'*4;relocations.append({'offset':p+1,'kind':'rel32','target_rva':target})
    spans=[];a=None
    for i,b in enumerate(mask+b'\0'):
        if b and a is None:a=i
        elif not b and a is not None:spans.append((a,i));a=None
    anchor=max(spans,key=lambda z:z[1]-z[0])
    return raw,mask,anchor,assembly,relocations

def raw_to_rva(pe,offset):
    for section in pe.sections:
        if section['offset']<=offset<section['offset']+section['size']:
            return section['rva']+offset-section['offset']
    raise ValueError('File offset is unmapped')

def main():
    server,client=PE(),PE(CLIENT)
    assert hashlib.sha256(client.data).hexdigest()=='e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'
    facts={'source_only':True,'game_calls':0,'client_path':str(CLIENT),'client_sha256':hashlib.sha256(client.data).hexdigest(),'functions':{}}
    for name,rva in [('prepare',0x2e6c180),('commit',0x2e60400),('game_free',0x32a0700),('get_container',0x3034120)]:
        raw,mask,anchor,assembly,relocations=signature(server,rva);a,b=anchor
        matches=[];offset=0;seen=0
        while True:
            at=client.data.find(raw[a:b],offset)
            if at<0:break
            offset=at+1;seen+=1;begin=at-a
            candidate=client.data[begin:begin+len(raw)]
            if len(candidate)!=len(raw) or any(ok and x!=y for x,y,ok in zip(raw,candidate,mask)):continue
            mapped=raw_to_rva(client,begin);function=client.containing(mapped)
            if function and function[0]==mapped and function[1]-function[0]==len(raw):matches.append(mapped)
        row={'server_rva':hex(rva),'function_bytes':len(raw),'unmasked_bytes':sum(mask),'anchor_bytes':b-a,'anchor_hits':seen,'client_matches':[hex(z) for z in matches],'masked_external_references':relocations}
        facts['functions'][name]=row
        (TASK/(name+'-server.asm')).write_text(assembly)
        if len(matches)==1:
            (TASK/(name+'-client.asm')).write_text(client.disassemble(matches[0]))
        print(json.dumps({'name':name,**{k:row[k] for k in ['function_bytes','unmasked_bytes','anchor_hits','client_matches']}}))
    (TASK/'client-function-match.json').write_text(json.dumps(facts,indent=2)+'\n')

if __name__=='__main__':main()
