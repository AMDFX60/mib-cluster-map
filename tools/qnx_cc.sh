#!/bin/sh
# Compiler wrapper for building FFmpeg with its NEON code for QNX 6.5.
# FFmpeg's C files need stddef.h forced in on QNX 6.5 (size_t and friends);
# its assembly must not get it, or configure finds no working assembler and
# NEON stays off. The same trick wasimlhr's MHI2Q Android Auto cluster
# project uses. build_local.sh copies this next to the FFmpeg source.
CC=${QNX_CC:-arm-unknown-nto-qnx6.5.0eabi-gcc}
for a in "$@"; do
    case "$a" in
        *.c) exec "$CC" -include stddef.h "$@" ;;
    esac
done
exec "$CC" "$@"
