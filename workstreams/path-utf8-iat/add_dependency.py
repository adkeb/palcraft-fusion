#!/usr/bin/env python3
"""Import-only extension of one authorized copy. Existing section bytes/RVAs stay."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

BASE_SHA256 = '21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8'
DLL = b'PalCraftUE4SSUtf8.dll\0'
SYMBOL = b'palcraft_utf8_dependency_marker\0'


def align(value, boundary):
    return (value + boundary - 1) // boundary * boundary


def apply(input_path, output_path, expected_sha256):
    source = Path(input_path).read_bytes()
    before_hash = hashlib.sha256(source).hexdigest()
    if before_hash != expected_sha256:
        raise ValueError('Input is not the explicitly pinned module')
    image = bytearray(source)
    pe = struct.unpack_from('<I', image, 0x3c)[0]
    if image[pe:pe + 4] != b'PE\0\0' or struct.unpack_from('<H', image, pe + 4)[0] != 0x8664:
        raise ValueError('Only the pinned x64 PE32+ module is supported')
    count = struct.unpack_from('<H', image, pe + 6)[0]
    optional = pe + 24
    if struct.unpack_from('<H', image, optional)[0] != 0x20b:
        raise ValueError('PE32+ required')
    table = optional + struct.unpack_from('<H', image, pe + 20)[0]
    section_alignment, file_alignment = struct.unpack_from('<II', image, optional + 32)
    sections = []
    for i in range(count):
        offset = table + i * 40
        name = bytes(image[offset:offset + 8]).rstrip(b'\0').decode()
        virtual, rva, raw_size, raw = struct.unpack_from('<4I', image, offset + 8)
        sections.append({'name': name, 'rva': rva, 'virtual_size': virtual,
                         'raw_size': raw_size, 'raw_offset': raw})
    if table + (count + 1) * 40 > min(s['raw_offset'] for s in sections if s['raw_size']):
        raise ValueError('No section header slack; no existing data will be relocated')
    if struct.unpack_from('<II', image, optional + 112 + 4 * 8) != (0, 0):
        raise ValueError('A signed image must not be modified by this tool')

    def file_offset(rva):
        for s in sections:
            if s['rva'] <= rva < s['rva'] + max(s['virtual_size'], s['raw_size']):
                return s['raw_offset'] + rva - s['rva']
        raise ValueError('RVA outside file sections')

    import_rva, import_size = struct.unpack_from('<II', image, optional + 112 + 8)
    descriptors = []
    offset = file_offset(import_rva)
    for i in range(import_size // 20):
        entry = bytes(image[offset + i * 20:offset + (i + 1) * 20])
        if struct.unpack_from('<I', entry, 12)[0] == 0: break
        descriptors.append(entry)
    if not descriptors:
        raise ValueError('Existing import descriptors required')
    new_rva = align(max(s['rva'] + max(s['virtual_size'], s['raw_size']) for s in sections), section_alignment)
    raw_start = align(len(image), file_alignment)
    descriptor_bytes = (len(descriptors) + 2) * 20
    payload = bytearray(descriptor_bytes)
    for i, d in enumerate(descriptors): payload[i * 20:(i + 1) * 20] = d
    name_offset = len(payload); payload.extend(DLL)
    if len(payload) % 2: payload.append(0)
    symbol_offset = len(payload); payload.extend(b'\0\0' + SYMBOL)
    payload.extend(b'\0' * (align(len(payload), 8) - len(payload)))
    lookup_offset = len(payload); payload.extend(struct.pack('<QQ', new_rva + symbol_offset, 0))
    iat_offset = len(payload); payload.extend(struct.pack('<QQ', new_rva + symbol_offset, 0))
    struct.pack_into('<5I', payload, len(descriptors) * 20, new_rva + lookup_offset, 0, 0,
                     new_rva + name_offset, new_rva + iat_offset)
    raw_size = align(len(payload), file_alignment)
    image.extend(b'\0' * (raw_start - len(image)))
    image.extend(payload)
    image.extend(b'\0' * (raw_size - len(payload)))
    struct.pack_into('<H', image, pe + 6, count + 1)
    struct.pack_into('<I', image, optional + 8, struct.unpack_from('<I', image, optional + 8)[0] + raw_size)
    struct.pack_into('<I', image, optional + 56, align(new_rva + len(payload), section_alignment))
    struct.pack_into('<I', image, optional + 64, 0)  # Checksum recalculated below.
    struct.pack_into('<II', image, optional + 112 + 8, new_rva, descriptor_bytes)
    struct.pack_into('<II', image, optional + 112 + 11 * 8, 0, 0)  # No old bound-import metadata.
    section = struct.pack('<8s6I2HI', b'.pcu8\0\0\0', len(payload), new_rva, raw_size, raw_start,
                          0, 0, 0, 0, 0xc0000040)
    image[table + count * 40:table + (count + 1) * 40] = section
    checksum = 0
    for i in range(0, len(image), 2):
        value = image[i] | ((image[i + 1] if i + 1 < len(image) else 0) << 8)
        checksum += value
        checksum = (checksum & 0xffff) + (checksum >> 16)
    checksum = (checksum & 0xffff) + (checksum >> 16)
    struct.pack_into('<I', image, optional + 64, checksum + len(image))
    # The import directory header moves; all original section bytes stay identical.
    for s in sections:
        a, n = s['raw_offset'], s['raw_size']
        if image[a:a + n] != source[a:a + n]:
            raise AssertionError('Original code/data/resource section changed')
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    Path(output_path).write_bytes(image)
    report = {'source_sha256': before_hash, 'candidate_sha256': hashlib.sha256(image).hexdigest(),
              'candidate_bytes': len(image), 'added_dependency': DLL[:-1].decode(),
              'added_import_symbol': SYMBOL[:-1].decode(), 'import_count_before': len(descriptors),
              'import_count_after': len(descriptors) + 1, 'new_section': '.pcu8',
              'original_sections_identical': sections, 'original_section_rvas_unchanged': True,
              'code_or_game_executable_patched': False, 'existing_import_descriptors_identical': True,
              'deployed': False}
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--expected-sha256', default=BASE_SHA256)
    p.add_argument('--report', required=True)
    args = p.parse_args()
    report = apply(args.input, args.output, args.expected_sha256)
    Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k:v for k,v in report.items() if k != 'original_sections_identical'}))
