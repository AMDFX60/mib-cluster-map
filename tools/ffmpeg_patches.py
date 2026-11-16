#!/usr/bin/env python3
"""The fork's changes to FFmpeg 6.1.5 for the player's H.264 decoder.

    tools/ffmpeg_patches.py <ffmpeg source dir>

Three patches, all giving bit for bit the pictures of FFmpeg's C code:

tools/ffmpeg_intra_neon.patch (1.4.2-beta1): the bS = 4 loop filters (an
edge next to an intra-coded block) in NEON. FFmpeg has them in NEON only
for aarch64; on 32-bit ARM they ran in C, about 9 % of the decoding work on
the Superb's recorded cockpit stream (Google Maps puts intra blocks
wherever new map comes into view). Luma vertical and horizontal edges, and
chroma ones for 4:2:0; the MBAFF and 4:2:2 vertical-edge variants stay in
C (the phone sends neither). Byte-element loads and stores only, like the
rewritten routines below.

tools/ffmpeg_deblock_skip.patch (1.4.1-beta2): the deblocking loop skips
the per-macroblock set-up where the filter cannot change a pixel (an inter
16x16 block without coefficients next to neighbours with the same motion;
see no_deblock_edges() in it). On ARM FFmpeg has no fast path for that
set-up (no h264_loop_filter_strength), so it was 10 to 20 % of the decoding
work; a map moving as a whole is made of such blocks. PC: up to 15 % fewer instructions per picture, 6 % on the
night map stream.

tools/ffmpeg_qnx_aligned.patch (1.4.1-beta1), the NEON routines:
Linux and Android let a NEON load or store of 16 or 32-bit elements land on
any address. The head unit's QNX kernel does not (alignment checking is on):
it stops the player with SIGBUS. 1.3.0-beta2 crashed at every start in
ff_h264_h_loop_filter_luma_neon ("vst1.32 {d8[0]}, [r0]" at pix-2).

Up to 1.4.0 the six routines that do this used FFmpeg's C code instead. From
1.4.1 tools/ffmpeg_qnx_aligned.patch rewrites their misaligned accesses with
byte elements, which need no alignment, and they run in NEON again:
  h264_h_loop_filter_luma: 4-byte stores at pix-2 -> vst4.8 by row;
  h264_h_loop_filter_chroma (and chroma422): 4-byte loads and stores at
      pix-2 -> vld4.8 by row, and vst2.8 of the two changed bytes;
  put/avg_h264_chroma_mc4: 4-byte loads from any source address in the
      vertical-only and copy paths -> 8-byte vld1.8 rows, as its other paths;
  put/avg_h264_chroma_mc2: the same, and no ldrh from an odd address;
  pred8x8 plane: a 4-byte load at src - stride - 1 -> vld1.8.
Each gives the same pictures as FFmpeg's C code, bit for bit (checked with
FFmpeg's checkasm and whole streams in an ARM emulator that faults
misaligned NEON accesses as the unit does: tests/neon/).

The patches are applied by exact text, wherever the lines are (no fuzz),
and only once; running this again changes nothing. Afterwards every decoder
NEON file is scanned: a 16, 32 or 64-bit element load or store without an
alignment qualifier, or an ldrh/strh, fails the build, so a new FFmpeg
version that adds one is noticed.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = [  # (patch, a file it changes, a text that is there once applied)
    ("ffmpeg_qnx_aligned.patch", "libavcodec/arm/h264dsp_neon.S", "QNX (mib-cluster-map)"),
    ("ffmpeg_intra_neon.patch", "libavcodec/arm/h264dsp_init_arm.c", "ff_h264_h_loop_filter_luma_intra_neon;"),
    ("ffmpeg_deblock_skip.patch", "libavcodec/h264_slice.c", "no_deblock_edges(h, sl, mb_x"),
]
SCANNED = ["h264dsp_neon.S", "h264cmc_neon.S", "h264pred_neon.S",
           "h264qpel_neon.S", "h264idct_neon.S"]


def fail(msg):
    print("ffmpeg_patches: " + msg, file=sys.stderr)
    sys.exit(1)


HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")


def hunks(text):
    """Yields (path, old lines, new lines) for each hunk of a unified diff."""
    lines = text.replace("\r\n", "\n").split("\n")
    path, i = None, 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if line.startswith("+++ "):
            path = line[4:].split("\t")[0].split("/", 1)[1]
            continue
        m = HUNK.match(line)
        if not m:
            continue
        nold = int(m.group(1) or 1)
        nnew = int(m.group(2) or 1)
        old, new = [], []
        while len(old) < nold or len(new) < nnew:
            if i >= len(lines):
                fail("patch ends inside a hunk")
            line = lines[i]
            i += 1
            if line.startswith("\\"):
                continue  # "\ No newline at end of file"
            tag, body = (line[:1], line[1:]) if line else (" ", "")
            if tag in " -":
                old.append(body)
            if tag in " +":
                new.append(body)
            if tag not in " -+":
                fail("cannot read patch line: " + line)
        yield path, old, new


def apply(src, patch_name):
    with open(os.path.join(HERE, patch_name)) as f:
        patch = f.read()
    for path, old, new in hunks(patch):
        full = os.path.join(src, path)
        if not os.path.isfile(full):
            fail(full + " missing")
        with open(full) as f:
            text = f.read()
        o = "\n".join(old) + "\n"
        n = "\n".join(new) + "\n"
        if text.count(o) == 1:
            text = text.replace(o, n)
        elif text.count(n) == 1:
            continue  # already applied
        else:
            fail("a hunk for %s does not match (another FFmpeg version?)" % path)
        with open(full, "w") as f:
            f.write(text)


ELEM = re.compile(r"^\s*v(ld|st)[1-4]\.(16|32|64)\s+\{[^}]*\}\s*,\s*\[([^\]]*)\]")
HALF = re.compile(r"^\s*(ldrh|strh)")
FUNC = re.compile(r"^\s*function\s+(\S+?),")
# Accesses the scan finds that are aligned all the same: (file, function).
ALIGNED = {
    # strh r3, [r1]: clears the DC coefficient in the int16_t block, which
    # is always aligned (run in the car since 1.3.0).
    ("h264idct_neon.S", "ff_h264_idct_dc_add_neon"),
    ("h264idct_neon.S", "ff_h264_idct8_dc_add_neon"),
}


def scan(src):
    bad = []
    for name in SCANNED:
        func = "?"
        with open(os.path.join(src, "libavcodec", "arm", name)) as f:
            for no, line in enumerate(f, 1):
                m = FUNC.match(line)
                if m:
                    func = m.group(1)
                code = line.split("@")[0]
                m = ELEM.match(code)
                if (m and ":" not in m.group(3)) or HALF.match(code):
                    if (name, func) in ALIGNED and not m:
                        continue
                    bad.append("%s:%d (%s): %s" % (name, no, func, code.strip()))
    if bad:
        fail("misaligned access left:\n  " + "\n  ".join(bad))


def main():
    if len(sys.argv) != 2:
        fail("usage: ffmpeg_patches.py <ffmpeg source dir>")
    src = sys.argv[1]
    for name, path, mark in PATCHES:
        apply(src, name)
        with open(os.path.join(src, path)) as f:
            if mark not in f.read():
                fail(name + " not applied")
    scan(src)
    print("ffmpeg_patches: " + ", ".join(p[0] for p in PATCHES) +
          " applied; no misaligned NEON access left in " + ", ".join(SCANNED))


main()
