#!/usr/bin/env python3
"""Make the 30 fps copy of NavActiveIgnore.jar for the green menu's switch.

    python3 tools/make_rate_jar.py <NavActiveIgnore.jar> <out.jar> [fps]
    python3 tools/make_rate_jar.py --show <NavActiveIgnore.jar>

The jar's ChangeDataRateSequence._stepChangeDataRate asks the unit to send
the cockpit's map picture at 20 frames per second (stock firmware: 10). The
copy is the same jar with that one constant changed, plus a marker entry
that makes it a different size: the unit has no cmp or checksum tool, so
the switch tells the two apart by size. Anything other than exactly one
"bipush 20" in that method stops the build.
"""
import struct, sys, zipfile

CLASS = "de/vw/mib/asl/internal/mostkombi/streamsink/usecases/ChangeDataRateSequence.class"
METHOD = "_stepChangeDataRate"
MARKER = "META-INF/MIB-CLUSTER-MAP-RATE"

# Operand bytes after each opcode; tableswitch, lookupswitch and wide are
# handled in walk().
OPERANDS = {0x10: 1, 0x12: 1, 0xa9: 1, 0xbc: 1, 0x11: 2, 0x13: 2, 0x14: 2,
            0x84: 2, 0xbb: 2, 0xbd: 2, 0xc0: 2, 0xc1: 2, 0xc6: 2, 0xc7: 2,
            0xb9: 4, 0xba: 4, 0xc8: 4, 0xc9: 4, 0xc5: 3}
OPERANDS.update({op: 1 for op in range(0x15, 0x1a)})
OPERANDS.update({op: 1 for op in range(0x36, 0x3b)})
OPERANDS.update({op: 2 for op in range(0x99, 0xa9)})
OPERANDS.update({op: 2 for op in range(0xb2, 0xb9)})

def constant_pool(data):
    """Returns the pool (index -> (tag, value)) and the offset after it."""
    count = struct.unpack_from(">H", data, 8)[0]
    pool, pos, i = {}, 10, 1
    while i < count:
        tag = data[pos]
        if tag == 1:
            n = struct.unpack_from(">H", data, pos + 1)[0]
            pool[i] = (1, data[pos + 3:pos + 3 + n].decode("utf-8", "replace"))
            pos += 3 + n
        elif tag in (3, 4):
            pool[i] = (tag, data[pos + 1:pos + 5]); pos += 5
        elif tag in (5, 6):
            pool[i] = (tag, data[pos + 1:pos + 9]); pos += 9; i += 1
        elif tag in (7, 8, 16, 19, 20):
            pool[i] = (tag, struct.unpack_from(">H", data, pos + 1)[0]); pos += 3
        elif tag in (9, 10, 11, 12, 17, 18):
            pool[i] = (tag, struct.unpack_from(">HH", data, pos + 1)); pos += 5
        elif tag == 15:
            pool[i] = (tag, data[pos + 1:pos + 4]); pos += 4
        else:
            sys.exit(f"unknown constant pool tag {tag}")
        i += 1
    return pool, pos

def method_code(data):
    """Returns (start, length) of METHOD's bytecode in the class file."""
    pool, pos = constant_pool(data)
    pos += 6
    interfaces = struct.unpack_from(">H", data, pos)[0]
    pos += 2 + 2 * interfaces
    def skip_attributes(p):
        n = struct.unpack_from(">H", data, p)[0]; p += 2
        for _ in range(n):
            p += 6 + struct.unpack_from(">I", data, p + 2)[0]
        return p
    fields = struct.unpack_from(">H", data, pos)[0]; pos += 2
    for _ in range(fields):
        pos = skip_attributes(pos + 6)
    found = []
    methods = struct.unpack_from(">H", data, pos)[0]; pos += 2
    for _ in range(methods):
        name = pool[struct.unpack_from(">H", data, pos + 2)[0]][1]
        n = struct.unpack_from(">H", data, pos + 6)[0]; p = pos + 8
        for _ in range(n):
            aname = pool[struct.unpack_from(">H", data, p)[0]][1]
            alen = struct.unpack_from(">I", data, p + 2)[0]
            if name == METHOD and aname == "Code":
                code_len = struct.unpack_from(">I", data, p + 10)[0]
                found.append((p + 14, code_len))
            p += 6 + alen
        pos = p
    if len(found) != 1:
        sys.exit(f"{METHOD}: found {len(found)} methods with code, expected 1")
    return pool, found[0]

def walk(data, start, length):
    """Yields (offset, opcode, operand bytes) for each instruction."""
    pc = 0
    while pc < length:
        op = data[start + pc]
        if op in (0xaa, 0xab):
            p = pc + 1 + (3 - pc % 4)
            if op == 0xaa:
                lo, hi = struct.unpack_from(">ii", data, start + p + 4)
                size = p + 12 + 4 * (hi - lo + 1) - pc
            else:
                pairs = struct.unpack_from(">i", data, start + p + 4)[0]
                size = p + 8 + 8 * pairs - pc
        elif op == 0xc4:
            size = 6 if data[start + pc + 1] == 0x84 else 4
        else:
            size = 1 + OPERANDS.get(op, 0)
        yield pc, op, data[start + pc + 1:start + pc + size]
        pc += size

def ref_name(pool, index):
    """class.name for a method or field reference, for --show."""
    tag, value = pool.get(index, (0, None))
    if tag not in (9, 10, 11):
        return ""
    cls = pool[pool[value[0]][1]][1]
    nat = pool[value[1]][1]
    return f"{cls}.{pool[nat[0]][1]}{pool[nat[1]][1]}"

def main():
    if sys.argv[1] == "--show":
        data = zipfile.ZipFile(sys.argv[2]).read(CLASS)
        pool, (start, length) = method_code(data)
        for pc, op, arg in walk(data, start, length):
            note = ""
            if op == 0x10:
                note = f"bipush {arg[0]}"
            elif op in (0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9):
                note = ref_name(pool, struct.unpack_from(">H", arg)[0])
            print(f"{pc:4d} {op:02x} {arg.hex()} {note}")
        return
    src, out = sys.argv[1], sys.argv[2]
    fps = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    if not 1 <= fps <= 127:
        sys.exit("fps must fit a bipush (1 to 127)")
    zin = zipfile.ZipFile(src)
    data = bytearray(zin.read(CLASS))
    pool, (start, length) = method_code(data)
    hits = [pc for pc, op, arg in walk(data, start, length) if op == 0x10 and arg[0] == 20]
    if len(hits) != 1:
        sys.exit(f"{METHOD}: {len(hits)} bipush 20, expected exactly 1")
    data[start + hits[0] + 1] = fps
    with zipfile.ZipFile(out, "w") as zout:
        for info in zin.infolist():
            body = bytes(data) if info.filename == CLASS else zin.read(info)
            zout.writestr(info, body, compress_type=info.compress_type)
        marker = zipfile.ZipInfo(MARKER, date_time=(2026, 10, 28, 0, 0, 0))
        zout.writestr(marker, f"cockpit map {fps} fps (mib-cluster-map)\n",
                      compress_type=zipfile.ZIP_STORED)

if __name__ == "__main__":
    main()
