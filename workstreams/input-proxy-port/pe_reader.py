import struct

def pe_report(path):
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    assert data[:2] == b"MZ" and data[pe:pe + 4] == b"PE\0\0"
    machine, section_count = struct.unpack_from("<HH", data, pe + 4)
    optional_bytes, characteristics = struct.unpack_from("<HH", data, pe + 20)
    optional = pe + 24
    assert machine == 0x8664 and struct.unpack_from("<H", data, optional)[0] == 0x20b and characteristics & 0x2000
    sections = []
    for i in range(section_count):
        offset = optional + optional_bytes + i * 40
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, offset + 8)
        sections.append((virtual_address, max(virtual_size, raw_size), raw_offset))

    def rva(value):
        for start, length, offset in sections:
            if start <= value < start + length:
                return offset + value - start
        raise AssertionError("RVA outside section")

    def string_at(value):
        start = rva(value)
        return data[start:data.index(b"\0", start)].decode("ascii")

    directory = rva(struct.unpack_from("<I", data, optional + 112)[0])
    count = struct.unpack_from("<I", data, directory + 24)[0]
    names = rva(struct.unpack_from("<I", data, directory + 32)[0])
    exports = [string_at(struct.unpack_from("<I", data, names + 4 * i)[0]) for i in range(count)]
    imports = []
    imports_rva = struct.unpack_from("<I", data, optional + 120)[0]
    if imports_rva:
        cursor = rva(imports_rva)
        while any(data[cursor:cursor + 20]):
            imports.append(string_at(struct.unpack_from("<I", data, cursor + 12)[0])); cursor += 20
    return {"format": "PE32+ DLL", "machine": "AMD64", "exports": exports, "imports": imports}
