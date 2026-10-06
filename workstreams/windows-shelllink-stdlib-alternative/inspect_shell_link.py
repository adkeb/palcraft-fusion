"""Read-only MS-SHLLINK structural inspection; never invokes a vendor process."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import uuid


def inspect_shell_link(data, *, ansi_encoding):
    def require(ok, message):
        if not ok:
            raise ValueError(message)

    def u32(offset):
        require(0 <= offset <= len(data) - 4, 'Truncated 32-bit field')
        return struct.unpack_from('<I', data, offset)[0]

    def zstring(start, end, unicode=False):
        require(0 <= start < end <= len(data), 'String offset outside its structure')
        unit = 2 if unicode else 1
        cursor = start
        while cursor + unit <= end:
            if data[cursor:cursor + unit] == b'\0' * unit:
                return data[start:cursor].decode('utf-16le' if unicode else ansi_encoding)
            cursor += unit
        raise ValueError('No string terminator inside the structure')

    require(len(data) >= 0x4C and u32(0) == 0x4C, 'Invalid ShellLink header size')
    require(data[4:20] == uuid.UUID('00021401-0000-0000-c000-000000000046').bytes_le,
            'Invalid ShellLink CLSID')
    require(data[66:76] == bytes(10), 'Nonzero reserved header fields')
    flags, position = u32(20), 0x4C
    if flags & 1:
        require(position + 2 <= len(data), 'Truncated IDList length')
        count = struct.unpack_from('<H', data, position)[0]
        position += count + 2
        require(position <= len(data), 'Truncated IDList')
    require(flags & 2, 'This inspector requires the local LinkInfo target')
    start = position
    size, header, info_flags = u32(start), u32(start + 4), u32(start + 8)
    end = start + size
    require(end <= len(data) and (header == 0x1C or header >= 0x24) and header < size,
            'Invalid LinkInfo extent or header')
    require(info_flags == 1, 'Only VolumeIDAndLocalBasePath is supported here')
    offsets = {name: u32(start + field) for name, field in
               [('volume', 12), ('local', 16), ('network', 20), ('suffix', 24)]}
    require(offsets['network'] == 0, 'Unexpected network-relative link')
    for name in ('volume', 'local', 'suffix'):
        require(header <= offsets[name] < size, 'LinkInfo offset outside its data extent')
    vstart = start + offsets['volume']; vsize = u32(vstart)
    require(vsize > 0x10 and vstart + vsize <= end, 'Invalid VolumeID extent')
    label_offset = u32(vstart + 12)
    if label_offset == 0x14:
        require(vsize >= 0x16, 'Truncated Unicode VolumeID')
        label_offset = u32(vstart + 16)
        require(0x14 <= label_offset < vsize, 'Invalid Unicode volume label offset')
        label = zstring(vstart + label_offset, vstart + vsize, True)
    else:
        require(0x10 <= label_offset < vsize, 'Invalid ANSI volume label offset')
        label = zstring(vstart + label_offset, vstart + vsize)
    local_ansi = zstring(start + offsets['local'], end)
    suffix_ansi = zstring(start + offsets['suffix'], end)
    target = local_ansi + suffix_ansi
    if header >= 0x24:
        offsets.update(local_unicode=u32(start + 28), suffix_unicode=u32(start + 32))
        for name in ('local_unicode', 'suffix_unicode'):
            require(header <= offsets[name] < size, 'Unicode path offset outside LinkInfo')
        target = (zstring(start + offsets['local_unicode'], end, True) +
                  zstring(start + offsets['suffix_unicode'], end, True))
    position = end
    strings, string_counts = {}, {}
    for bit, name in [(4, 'description'), (8, 'relative_path'), (16, 'working_directory'),
                      (32, 'arguments'), (64, 'icon_location')]:
        if not flags & bit:
            continue
        require(position + 2 <= len(data), 'Truncated StringData count')
        count = struct.unpack_from('<H', data, position)[0]; position += 2
        byte_count = count * (2 if flags & 0x80 else 1)
        require(position + byte_count <= len(data), 'Truncated StringData payload')
        strings[name] = data[position:position + byte_count].decode('utf-16le' if flags & 0x80 else ansi_encoding)
        string_counts[name] = count
        position += byte_count
    extra_start = position
    blocks = []
    while True:
        block_size = u32(position)
        if block_size < 4:
            position += 4
            break
        require(block_size >= 8 and position + block_size <= len(data), 'Invalid ExtraData block size')
        blocks.append({'size': block_size, 'signature': u32(position + 4)})
        position += block_size
    require(position == len(data), 'Unexpected data after the ExtraData terminal')
    return {'header_size': 0x4C, 'flags': flags, 'file_attributes': u32(24),
            'target_file_size_low32': u32(52), 'show_command': u32(60),
            'link_info_size': size, 'link_info_header_size': header,
            'link_info_offsets': offsets, 'volume_drive_type': u32(vstart + 4),
            'volume_serial_number': u32(vstart + 8), 'volume_label': label,
            'target': target, 'ansi_target': local_ansi + suffix_ansi,
            'string_counts_utf16_units': string_counts, **strings,
            'extra_offset': extra_start, 'extra_blocks': blocks, 'terminal_block_present': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('link')
    parser.add_argument('--ansi-encoding', required=True)
    args = parser.parse_args()
    data = Path(args.link).read_bytes()
    value = inspect_shell_link(data, ansi_encoding=args.ansi_encoding)
    # Never print target/arguments/tokens or metadata identities from a private link.
    summary = {key: value[key] for key in ('header_size', 'flags', 'link_info_size',
               'link_info_header_size', 'string_counts_utf16_units', 'terminal_block_present')}
    summary.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                   source_only=True, vendor_engine_verified=False, target_executed=False)
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
