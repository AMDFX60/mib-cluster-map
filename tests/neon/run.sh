#!/bin/bash
# PC test of the player's H.264 NEON code against the head unit's alignment
# rule, in an ARM emulator.
#
#   tests/neon/run.sh [test|prof|all]     (standard: test)
#
# The head unit's QNX kernel stops a program (SIGBUS) at a NEON load or store
# of 16 or 32-bit elements that is not aligned to the element size; Linux and
# Android allow it. 1.3.0-beta2 crashed that way, 1.3.0 to 1.4.0 left the six
# FFmpeg routines that do it to C, and 1.4.1 rewrites them
# (tools/ffmpeg_patches.py). This test builds, once, in the docker volume
# mib-cluster-map-neontest:
#   - QEMU 9.2.0 for ARM, patched (qemu_strict.py) to fault such accesses
#     like the unit, or every misaligned access in FFmpeg's code;
#   - FFmpeg 6.1.5 for a Cortex-A9 with the car's flags: as shipped (orig),
#     as 1.4.0 (c6) and as 1.4.1 (new); each with FFmpeg's checkasm and
#     dectest.c, which decodes like the player;
#   - test streams from the cockpit photos in docs/images.
# test: every picture of every stream from c6 and new must equal FFmpeg's C
#   code without a fault, checkasm must pass, and orig must stop in
#   ff_h264_h_loop_filter_luma_neon as the car did (or the check is broken).
# prof: instructions per picture with each variant (fprof.c, a QEMU
#   plugin): the PC's estimate of the decoding time.
#
# Needs docker (Docker Desktop on Windows, from Git Bash). The first run
# takes about 15 minutes, later ones a few.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMG=mib-cluster-map-neontest:1
HOST_ROOT=$ROOT
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    export MSYS_NO_PATHCONV=1
    HOST_ROOT=$(cygpath -m "$ROOT")
    if ! command -v docker >/dev/null 2>&1; then
      for d in "$(cygpath -u "${LOCALAPPDATA:-C:/}")/Programs/DockerDesktop/resources/bin" \
               "/c/Program Files/Docker/Docker/resources/bin"; do
        if [ -e "$d/docker.exe" ]; then PATH="$d:$PATH"; break; fi
      done
    fi ;;
esac
docker image inspect "$IMG" >/dev/null 2>&1 || docker build -t "$IMG" "$HOST_ROOT/tests/neon"
docker run --rm -v "$HOST_ROOT":/repo:ro -v mib-cluster-map-neontest:/t "$IMG" \
  bash /repo/tests/neon/inner.sh "${1:-test}"
