"""MS-SHLLINK drive-letter shortcut bytes, using only Python's standard library.

This module never resolves or executes the target, registers a menu, or launches
Wine/WSH. Metadata and the Windows ANSI code page are explicit caller inputs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import uuid

CLSID = uuid.UUID('00021401-0000-0000-c000-000000000046').bytes_le
FLAGS = 0x02 | 0x04 | 0x10 | 0x20 | 0x80  # LinkInfo, name, workdir, arguments, Unicode


def _uint(name, value, bits=32):
    if type(value) is not int or not 0 <= value < (1 << bits):
        raise ValueError(name + ' must be an unsigned integer of the specified width')
    return value


def _unicode(name, value):
    if not isinstance(value, str) or any(c in value for c in '\0\r\n'):
        raise ValueError(name + ' must be text without NUL or line breaks')
    try:
        return value.encode('utf-16le')
    except UnicodeEncodeError:
        raise ValueError(name + ' must be valid Unicode') from None


def _windows_path(name, value):
    encoded = _unicode(name, value)
    if not re.match(r'^[A-Za-z]:\\', value) or any(c in value[2:] for c in '<>:"|?*'):
        raise ValueError(name + ' must be an absolute Windows drive-letter path')
    if '..' in value[3:].split('\\'):
        raise ValueError(name + ' must not traverse parent directories')
    return encoded


def _counted(name, value, limit=260):
    encoded = _unicode(name, value)
    count = len(encoded) // 2
    if count > limit:
        raise ValueError(name + ' exceeds the ShellLink StringData character limit')
    return struct.pack('<H', count) + encoded  # No terminating NUL in StringData.


def encode_shell_link(target, arguments, working_directory, description, *,
                      ansi_encoding, volume_drive_type, volume_serial_number,
                      volume_label, file_attributes, target_file_size):
    """Encode a genuine local .lnk; arguments is the original raw argument string.

    The ANSI compatibility path must be representable in the supplied code page.
    No default volume serial, target metadata, account identity or token is used.
    FILETIMEs are explicitly unset (zero), as allowed by MS-SHLLINK 2.1.
    """
    target_utf16 = _windows_path('target', target)
    _windows_path('working_directory', working_directory)
    drive_type = _uint('volume_drive_type', volume_drive_type)
    if drive_type > 6:
        raise ValueError('volume_drive_type is not a defined MS-SHLLINK drive type')
    serial = _uint('volume_serial_number', volume_serial_number)
    attributes = _uint('file_attributes', file_attributes)
    if attributes & ~0x7FB7 or attributes & 0x80 and attributes != 0x80:
        raise ValueError('file_attributes contains reserved or incompatible bits')
    size = _uint('target_file_size', target_file_size, 64) & 0xFFFFFFFF
    try:
        target_ansi = target.encode(ansi_encoding, errors='strict')
    except (LookupError, UnicodeEncodeError, TypeError):
        raise ValueError('Supply the actual ANSI code page capable of representing the target') from None
    if b'\0' in target_ansi:
        raise ValueError('ANSI compatibility encoding must not insert NUL bytes')
    label = _unicode('volume_label', volume_label) + b'\0\0'
    # 0x14 selects the extra Unicode label offset; it points past the 20-byte header.
    volume = struct.pack('<IIIII', 20 + len(label), drive_type, serial, 0x14, 0x14) + label
    local_ansi = target_ansi + b'\0'
    local_unicode = target_utf16 + b'\0\0'
    volume_offset = 0x24
    local_offset = volume_offset + len(volume)
    suffix_offset = local_offset + len(local_ansi)
    local_unicode_offset = suffix_offset + 1
    suffix_unicode_offset = local_unicode_offset + len(local_unicode)
    info_size = suffix_unicode_offset + 2
    info = struct.pack('<9I', info_size, 0x24, 1, volume_offset, local_offset,
                       0, suffix_offset, local_unicode_offset, suffix_unicode_offset)
    info += volume + local_ansi + b'\0' + local_unicode + b'\0\0'
    header = struct.pack('<I16sIIQQQIiIHHII', 0x4C, CLSID, FLAGS, attributes,
                         0, 0, 0, size, 0, 1, 0, 0, 0, 0)
    strings = (_counted('description', description) +
               _counted('working_directory', working_directory) +
               _counted('arguments', arguments, 0xFFFF))
    return header + info + strings + struct.pack('<I', 0)  # ExtraData terminal block.


def encode_menu_spec(spec, metadata):
    """Preserve the existing helper's target/argv/workdir/description unchanged."""
    # list2cmdline formats text; no subprocess is created by this stdlib function.
    arguments = subprocess.list2cmdline(spec['arguments'])
    return encode_shell_link(spec['target'], arguments, spec['workdir'],
                             spec['description'], **metadata)


def write_owned_link(owned_directory, filename, data):
    """Write only a .lnk in an already caller-validated private menu namespace.

    The existing helper must keep its root/bottle/session_guard and ownership
    checks before calling this function. This writer creates no ownership role.
    """
    directory = Path(owned_directory).absolute()
    if directory.resolve() != directory or any(p.is_symlink() for p in (directory, *directory.parents)):
        raise ValueError('The owned menu directory must be an existing physical path')
    if not directory.is_dir():
        raise ValueError('The caller must prepare its owned menu directory')
    if (not isinstance(filename, str) or Path(filename).name != filename or
            any(c in filename for c in '\\/\0\r\n:') or not filename.lower().endswith('.lnk')):
        raise ValueError('Supply one owned .lnk filename')
    path = directory / filename
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'source_only': True, 'target_executed': False, 'vendor_engine_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, help='Private caller JSON; arguments remain inside the file')
    parser.add_argument('--owned-directory', required=True)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    values = json.loads(Path(args.input).read_text(encoding='utf-8'))
    data = encode_shell_link(**values)
    print(json.dumps(write_owned_link(args.owned_directory, args.name, data)))


if __name__ == '__main__':
    main()
