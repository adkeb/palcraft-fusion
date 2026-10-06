#!/usr/bin/env python3
"""Offline, selected crash facts only: no command lines or general memory dump."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import xml.etree.ElementTree as ET


def analyze(dump, dll, xml):
    data, binary = dump.read_bytes(), dll.read_bytes()
    if data[:4] != b'MDMP':
        raise ValueError('Not a minidump')
    count, directory = struct.unpack_from('<II', data, 8)
    streams = {}
    for i in range(count):
        kind, size, rva = struct.unpack_from('<III', data, directory + 12 * i)
        streams[kind] = (size, rva)
    modules = []
    q = streams[4][1]
    for i in range(struct.unpack_from('<I', data, q)[0]):
        at = q + 4 + 108 * i
        base, size, _, timestamp, name = struct.unpack_from('<QIIII', data, at)
        length = struct.unpack_from('<I', data, name)[0]
        label = data[name + 4:name + 4 + length].decode('utf-16le').replace('\\', '/').split('/')[-1]
        if label.lower() != 'ue4ss.dll':
            continue
        cv_size, cv_rva = struct.unpack_from('<II', data, at + 76)
        modules.append({'name': label, 'base': base, 'size': size,
                        'timestamp': timestamp, 'codeview': data[cv_rva:cv_rva + min(24, cv_size)].hex()})
    if len(modules) != 1:
        raise ValueError('Actual UE4SS module must be unique')
    module = modules[0]
    pe = struct.unpack_from('<I', binary, 0x3c)[0]
    image_base = struct.unpack_from('<Q', binary, pe + 24 + 24)[0]
    local_timestamp = struct.unpack_from('<I', binary, pe + 8)[0]
    codeview_start = binary.index(b'RSDS')
    local_cv = binary[codeview_start:codeview_start + 24].hex()
    if local_cv != module['codeview'] or local_timestamp != module['timestamp']:
        raise ValueError('DLL does not match the actual dump CodeView identity/timestamp')
    q = streams[6][1]
    thread_id = struct.unpack_from('<I', data, q)[0]
    code, _, _, address, n, _ = struct.unpack_from('<IIQQII', data, q + 8)
    information = struct.unpack_from('<15Q', data, q + 40)[:n]
    _, context = struct.unpack_from('<II', data, q + 160)
    offsets = {'rax': 120, 'rcx': 128, 'rdx': 136, 'rbx': 144, 'rsp': 152,
               'rbp': 160, 'rsi': 168, 'rdi': 176, 'r12': 216, 'r13': 224,
               'r14': 232, 'r15': 240, 'rip': 248}
    regs = {key: struct.unpack_from('<Q', data, context + off)[0] for key, off in offsets.items()}
    ranges = []
    q = streams[5][1]
    for i in range(struct.unpack_from('<I', data, q)[0]):
        ranges.append(struct.unpack_from('<QII', data, q + 4 + 16 * i))
    q = streams[3][1]
    for i in range(struct.unpack_from('<I', data, q)[0]):
        if struct.unpack_from('<I', data, q + 4 + 48 * i)[0] == thread_id:
            ranges.append(struct.unpack_from('<QII', data, q + 4 + 48 * i + 24))

    def memory_qword(address):
        for start, size, rva in ranges:
            if start <= address and address + 8 <= start + size:
                return struct.unpack_from('<Q', data, rva + address - start)[0]
        return None

    # These stack offsets are established by the matching DLL's FindProperty
    # instructions (+3c20c7 / +3c20cb), not guessed from unrelated registers.
    selected = {
        'find_property_struct_argument': memory_qword(regs['rbp'] - 0x50),
        'find_property_fname_argument': memory_qword(regs['rbp'] - 0x48),
        'lua_native_object_vtable': memory_qword(regs['r12']),
        'lua_native_object_class': memory_qword(regs['r12'] + 0x10),
    }
    root = ET.parse(xml).getroot()
    facts = {key: root.findtext('.//' + key) for key in ['CrashType', 'ErrorMessage', 'SecondsSinceStart', 'EngineVersion', 'PCallStack']}
    report = {
        'kind': 'actual_crash_offline_analysis', 'read_only': True,
        'minidump_sha256': hashlib.sha256(data).hexdigest(),
        'dll_sha256': hashlib.sha256(binary).hexdigest(),
        'dll_matches_dump_codeview_and_timestamp': True,
        'module': {**module, 'base': hex(module['base'])},
        'exception_thread': thread_id, 'exception_code': hex(code),
        'exception_address': hex(address), 'exception_module_offset': hex(address - module['base']),
        'exception_information': [hex(x) for x in information],
        'registers': {key: hex(value) for key, value in regs.items()},
        'selected_memory': {key: None if value is None else hex(value) for key, value in selected.items()},
        'fname_comparison_index': None if selected['find_property_fname_argument'] is None else hex(selected['find_property_fname_argument'] & 0xffffffff),
        'fname_number': None if selected['find_property_fname_argument'] is None else selected['find_property_fname_argument'] >> 32,
        'xml_facts': facts,
        'interpretation': 'Fault is a Lua native UObject member lookup on a corrupt/noncanonical class pointer; object producer/lifetime cause remains to be confirmed by its owner.'
    }
    windows = [(0x1e8990, 0x1e8a04), (0x3c2080, 0x3c215a),
               (0x2703e0, 0x270432), (0x2720b0, 0x2720c8), (0x3c2740, 0x3c2784)]
    assembly = []
    for start, end in windows:
        assembly.append(subprocess.check_output([
            '/usr/bin/objdump', '-d', '--start-address=' + hex(image_base + start),
            '--stop-address=' + hex(image_base + end), str(dll)], text=True))
    return report, '\n'.join(assembly)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dump', type=Path, required=True)
    parser.add_argument('--dll', type=Path, required=True)
    parser.add_argument('--xml', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result, assembly = analyze(args.dump, args.dll, args.xml)
    (args.output / 'crash-analysis.json').write_text(json.dumps(result, indent=2) + '\n')
    (args.output / 'crash-disassembly.txt').write_text(assembly)
    print(json.dumps({key: result[key] for key in ['dll_sha256', 'minidump_sha256', 'exception_module_offset', 'fname_comparison_index', 'selected_memory']}))
