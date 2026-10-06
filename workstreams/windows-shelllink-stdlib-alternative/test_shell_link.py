"""Finite byte/offset checks using synthetic inputs; no Windows or vendor calls."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile

from windows_shell_link import encode_menu_spec, encode_shell_link, write_owned_link
from inspect_shell_link import inspect_shell_link

root = Path(__file__).resolve().parent
values = json.loads((root / 'fixtures/unicode-input.json').read_text())
data = encode_shell_link(**values)
parsed = inspect_shell_link(data, ansi_encoding=values['ansi_encoding'])
for input_key, result_key in [('target', 'target'), ('arguments', 'arguments'),
                              ('working_directory', 'working_directory'), ('description', 'description')]:
    assert parsed[result_key] == values[input_key]
assert parsed['ansi_target'] == values['target']
assert parsed['flags'] == 0xB6 and parsed['link_info_header_size'] == 0x24
assert parsed['volume_label'] == values['volume_label']
assert parsed['volume_drive_type'] == 0 and parsed['volume_serial_number'] == 0x12345678
assert parsed['string_counts_utf16_units']['description'] == len(values['description'].encode('utf-16le')) // 2
assert parsed['string_counts_utf16_units']['description'] > len(values['description'])
assert parsed['string_counts_utf16_units']['arguments'] > 260
assert parsed['extra_blocks'] == [] and data[-4:] == bytes(4)
assert data[28:52] == bytes(24) and data[66:76] == bytes(10)
assert struct.unpack_from('<I', data, 0x4C)[0] == parsed['link_info_size']
for offset in parsed['link_info_offsets'].values():
    assert offset == 0 or 0x24 <= offset < parsed['link_info_size']

# The caller's original list2cmdline result is preserved exactly, including
# trailing backslashes, embedded quotes, and empty arguments in a text fixture.
argv = ['--root', 'Z:\\测试 空间\\', '--control', 'Z:\\测试 空间\\.palcraft\\control',
        '--token', 'caller-fixture-value', '--fps', '15', 'quoted "value"', '']
spec = {'target': values['target'], 'arguments': argv, 'workdir': values['working_directory'],
        'description': values['description'], 'link_windows': 'C:\\Fixture\\test.lnk'}
metadata = {k: v for k, v in values.items() if k not in ['target', 'arguments', 'working_directory', 'description']}
roundtrip = inspect_shell_link(encode_menu_spec(spec, metadata), ansi_encoding='cp936')
assert roundtrip['arguments'] == subprocess.list2cmdline(argv)
reference_spec = importlib.util.spec_from_file_location('existing_owned_menu_helper', root / 'reference/crossover_menu_helper.py')
reference = importlib.util.module_from_spec(reference_spec)
reference_spec.loader.exec_module(reference)
script = reference.shortcut_source(spec)  # Pure source function, not executed.
argument_line = next(line for line in script.splitlines() if line.startswith('link.Arguments = '))
quoted = argument_line.removeprefix('link.Arguments = ')
assert quoted[0] == quoted[-1] == '"'
assert quoted[1:-1].replace('""', '"') == roundtrip['arguments']

with tempfile.TemporaryDirectory(dir=root) as temporary:
    directory = Path(temporary)
    result = write_owned_link(directory, '测试.lnk', data)
    path = directory / '测试.lnk'
    assert path.read_bytes() == data and path.stat().st_mode & 0o777 == 0o600
    assert result['target_executed'] is False and result['vendor_engine_verified'] is False
    try:
        write_owned_link(directory, '../escape.lnk', data)
    except ValueError:
        pass
    else:
        raise AssertionError('Owned directory must not be escaped')

# Only the relevant corruptions/length boundary are checked, not a format matrix.
for field_offset in [0x4C + 16, 0x4C + 28]:
    corrupt = bytearray(data)
    struct.pack_into('<I', corrupt, field_offset, parsed['link_info_size'])
    try:
        inspect_shell_link(bytes(corrupt), ansi_encoding='cp936')
    except ValueError:
        pass
    else:
        raise AssertionError('Out-of-structure offset must be rejected')
bad = copy.deepcopy(values); bad['arguments'] += '\0'
try:
    encode_shell_link(**bad)
except ValueError:
    pass
else:
    raise AssertionError('NUL cannot enter an argument string')
bad = copy.deepcopy(values); bad['ansi_encoding'] = 'cp1252'
try:
    encode_shell_link(**bad)
except ValueError:
    pass
else:
    raise AssertionError('An unknown/incompatible ANSI shadow must not be silently invented')

print(json.dumps({'source_only': True, 'unicode_target_arguments_workdir_description_roundtrip': True,
                  'UTF16_counts_offsets_and_ExtraData_terminal_verified': True,
                  'long_arguments_above_260_preserved': True, 'original_helper_quoting_identical': True,
                  'owned_mode_0600': True, 'target_executed': False, 'vendor_engine_verified': False,
                  'processes_or_WSH_started': False}))
