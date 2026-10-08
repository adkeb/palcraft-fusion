"""Read-only PE/sections comparison. Whole bytes equality is reported, never assumed."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from pe_reader import pe_report

def detail(path):
    data = Path(path).read_bytes(); pe = struct.unpack_from('<I', data, 0x3c)[0]
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    table = pe + 24 + optional_size
    sections = {}
    for index in range(count):
        at = table + index * 40
        name = data[at:at+8].split(b'\0',1)[0].decode('ascii', 'replace')
        vsize, address, size, raw = struct.unpack_from('<IIII', data, at + 8)
        body = data[raw:raw+size]
        sections[name] = {'virtual_size': vsize, 'virtual_address': address, 'raw_size': size,
                          'raw_sha256': hashlib.sha256(body).hexdigest(), 'bytes': body}
    return {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data),
            'coff_timestamp': struct.unpack_from('<I', data, pe+8)[0],
            'optional_checksum': struct.unpack_from('<I', data, pe+24+64)[0],
            'sections': sections, 'report': pe_report(Path(path)), 'bytes': data}

def compare(reference, candidate):
    a, b = detail(reference), detail(candidate)
    sections = {}
    for name in sorted(set(a['sections']) | set(b['sections'])):
        old, new = a['sections'].get(name), b['sections'].get(name)
        sections[name] = {'equal_raw_bytes': old is not None and new is not None and old['bytes'] == new['bytes'],
                          'reference': {k:v for k,v in (old or {}).items() if k!='bytes'},
                          'candidate': {k:v for k,v in (new or {}).items() if k!='bytes'}}
    return {'schema': 1, 'whole_file_byte_identical': a['bytes']==b['bytes'],
            'reference_sha256': a['sha256'], 'candidate_sha256': b['sha256'],
            'reference_bytes': a['size'], 'candidate_bytes': b['size'],
            'PE_format_and_machine_equal': all(a['report'][k]==b['report'][k] for k in ('format','machine')),
            'seven_exports_equal': a['report']['exports']==b['report']['exports'],
            'import_modules_equal': a['report']['imports']==b['report']['imports'],
            'PE_reference': a['report'], 'PE_candidate': b['report'], 'sections': sections,
            'code_section_raw_byte_identical': sections.get('.text',{}).get('equal_raw_bytes',False),
            'coff_timestamp': {'reference':a['coff_timestamp'],'candidate':b['coff_timestamp']},
            'optional_checksum': {'reference':a['optional_checksum'],'candidate':b['optional_checksum']},
            'build_id_section_equal': sections.get('.buildid',{}).get('equal_raw_bytes'),
            'differing_sections': [name for name,value in sections.items() if not value['equal_raw_bytes']],
            'runtime_behaviour_or_other_fresh_environment_not_verified': True}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reference',required=True,type=Path)
    p.add_argument('--candidate',required=True,type=Path);p.add_argument('--report',required=True,type=Path)
    args=p.parse_args();value=compare(args.reference,args.candidate)
    args.report.write_text(json.dumps(value,indent=2)+'\n');print(json.dumps(value,indent=2))
