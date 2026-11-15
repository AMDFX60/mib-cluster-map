#!/usr/bin/env python3
"""Patches QEMU 9.2's ARM translator to fault misaligned accesses like the unit.

The head unit's QNX kernel runs with alignment checking on: a NEON load or
store of 16 or 32-bit elements at an address not aligned to the element
size stops the program with SIGBUS (as 1.3.0-beta2's player did). Linux, and
so qemu-arm, allow it. With this patch:
  MIBCM_STRICT_ALIGN=1  every NEON element access must be aligned to its
                        element size (what the unit enforces on NEON);
  MIBCM_STRICT_ALIGN=2  every access, core loads and stores too, but only in
                        code between MIBCM_STRICT_RANGE=lo-hi (hex addresses;
                        Linux's C library start-up code would fault first).

    qemu_strict.py <qemu source dir>
"""
import os
import sys

src = sys.argv[1]


def edit(path, old, new, count=1):
    path = os.path.join(src, path)
    with open(path) as f:
        text = f.read()
    if new in text and old not in text:
        return
    if text.count(old) != count:
        sys.exit("qemu_strict: %s: expected %d match(es) of %r" % (path, count, old))
    with open(path, "w") as f:
        f.write(text.replace(old, new))


edit("target/arm/tcg/translate.h", '#include "cpu-features.h"\n',
     '#include "cpu-features.h"\n#include <stdlib.h>\n#include <stdio.h>\n'
     '/* mib-cluster-map tests/neon: alignment checks like the head unit. */\n'
     'static inline bool mibcm_strict(int level)\n{\n    static int v = -1;\n'
     '    if (v < 0) {\n        const char *e = getenv("MIBCM_STRICT_ALIGN");\n'
     '        v = e ? atoi(e) : 0;\n    }\n    return v >= level;\n}\n'
     'static inline bool mibcm_strict_pc(unsigned long pc)\n{\n'
     '    static int init;\n    static unsigned long lo, hi;\n'
     '    if (!init) {\n        const char *e = getenv("MIBCM_STRICT_RANGE");\n'
     '        if (e) {\n            sscanf(e, "%lx-%lx", &lo, &hi);\n        }\n'
     '        init = 1;\n    }\n'
     '    return mibcm_strict(2) && (!hi || (pc >= lo && pc < hi));\n}\n')
edit("target/arm/tcg/translate.c",
     "dc->align_mem = EX_TBFLAG_ANY(tb_flags, ALIGN_MEM);",
     "dc->align_mem = EX_TBFLAG_ANY(tb_flags, ALIGN_MEM) || mibcm_strict_pc(dc->base.pc_first);")
# VLD/VST multiple structures, all lanes, single lane.
edit("target/arm/tcg/translate-neon.c",
     "align = s->align_mem ? MO_ALIGN : 0;",
     "align = (s->align_mem || mibcm_strict(1)) ? MO_ALIGN : 0;")
edit("target/arm/tcg/translate-neon.c",
     "    mop = size | align;\n",
     "    mop = size | (align ? align : (mibcm_strict(1) ? MO_ALIGN : 0));\n")
edit("target/arm/tcg/translate-neon.c",
     "    mop = finalize_memop(s, a->size);\n",
     "    mop = finalize_memop(s, a->size);\n"
     "    if (mibcm_strict(1) && !(mop & MO_AMASK)) {\n        mop |= MO_ALIGN;\n    }\n")
print("qemu_strict: patched")
