#!/usr/bin/env python3
"""Read-only PE helper for bounded local disassembly of the copied lab exe."""
import argparse
import json
from pathlib import Path
import struct
import subprocess

IMAGE = Path(__file__).with_name('PalServer-Win64-Shipping-Cmd.exe')

class PE:
    def __init__(self, path=IMAGE):
        self.data = path.read_bytes()
        self.path = path
        nt = struct.unpack_from('<I', self.data, 0x3c)[0]
        assert self.data[nt:nt+4] == b'PE\0\0'
        count = struct.unpack_from('<H', self.data, nt+6)[0]
        opt_size = struct.unpack_from('<H', self.data, nt+20)[0]
        opt = nt+24
        assert struct.unpack_from('<H', self.data, opt)[0] == 0x20b
        self.base = struct.unpack_from('<Q', self.data, opt+24)[0]
        self.sections = []
        for i in range(count):
            off = opt+opt_size+i*40
            name, vs, va, rs, raw = struct.unpack_from('<8sIIII', self.data, off)
            self.sections.append(dict(name=name.rstrip(b'\0').decode(), rva=va, vsize=vs, size=rs, offset=raw))
        prva, psize = struct.unpack_from('<II', self.data, opt+112+3*8)
        poff = self.offset(prva)
        self.functions = [struct.unpack_from('<III', self.data, p) for p in range(poff, poff+psize, 12)]

    def offset(self, rva):
        for s in self.sections:
            if s['rva'] <= rva < s['rva']+s['size']:
                return s['offset'] + rva-s['rva']
        raise ValueError(hex(rva))

    def containing(self, rva):
        for start, end, unwind in self.functions:
            if start <= rva < end:
                return start, end, unwind
        return None

    def utf16(self, va, n=512):
        off = self.offset(va-self.base)
        raw = self.data[off:off+n*2]
        return raw.decode('utf-16le', errors='replace').split('\0')[0]

    def disassemble(self, rva, size=None):
        containing = self.containing(rva)
        start = rva if size or not containing else containing[0]
        end = start+size if size else containing[1] if containing else rva+256
        output = subprocess.check_output(['/usr/bin/objdump', '-d', '--x86-asm-syntax=intel',
            '--start-address='+hex(self.base+start), '--stop-address='+hex(self.base+end), str(self.path)], text=True)
        return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('rva', type=lambda x: int(x,0))
    parser.add_argument('--size', type=lambda x: int(x,0))
    parser.add_argument('--string', action='store_true')
    args=parser.parse_args()
    pe=PE()
    if args.string:
        print(pe.utf16(pe.base+args.rva))
    else:
        print(pe.disassemble(args.rva,args.size))
