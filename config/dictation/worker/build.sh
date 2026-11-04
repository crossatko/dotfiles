#!/bin/bash
# Builds the dictation-whisper worker against an existing whisper.cpp build or install (Vulkan backend recommended).
#
#   config/dictation/worker/build.sh [OUTPUT]
#
# whisper.cpp location (pick one):
#   WHISPER_PREFIX=DIR   an install prefix (DIR/include/whisper.h, DIR/lib/libwhisper.so) or a source tree with a
#                        build dir: WHISPER_PREFIX=SRC WHISPER_BUILD=SRC/build (headers from SRC/include and
#                        SRC/ggml/include, libraries from WHISPER_BUILD/bin or WHISPER_BUILD/src)
#   nothing              the system install (pkg-config whisper, else /usr/include + /usr/lib)
# OUTPUT defaults to ${XDG_DATA_HOME:-$HOME/.local/share}/dictation/bin/dictation-whisper, where the service looks.
# The binary gets an rpath to the library dir, so a private build needs no LD_LIBRARY_PATH.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=${1:-${XDG_DATA_HOME:-$HOME/.local/share}/dictation/bin/dictation-whisper}
cc=${CC:-cc}
cflags=(-O2 -Wall -Wextra -std=c11)
inc=()
lib=()

if [ -n "${WHISPER_PREFIX:-}" ]; then
  for d in "$WHISPER_PREFIX/include" "$WHISPER_PREFIX/ggml/include"; do [ -d "$d" ] && inc+=("-I$d"); done
  libdir=""
  for d in ${WHISPER_BUILD:+"$WHISPER_BUILD/bin" "$WHISPER_BUILD/src"} "$WHISPER_PREFIX/lib" "$WHISPER_PREFIX/lib64"; do
    if [ -e "$d/libwhisper.so" ]; then libdir=$d; break; fi
  done
  if [ -z "$libdir" ]; then
    echo "build.sh: libwhisper.so not found under WHISPER_PREFIX/WHISPER_BUILD" >&2
    exit 1
  fi
  lib=("-L$libdir" "-Wl,-rpath,$libdir" -lwhisper -lggml -lggml-base)
elif pkg-config --exists whisper 2>/dev/null; then
  read -r -a inc <<<"$(pkg-config --cflags whisper)"
  read -r -a lib <<<"$(pkg-config --libs whisper) -lggml -lggml-base"
else
  lib=(-lwhisper -lggml -lggml-base)
fi

mkdir -p "$(dirname "$out")"
"$cc" "${cflags[@]}" "${inc[@]}" -o "$out.tmp" "$here/dictation-whisper.c" "${lib[@]}"
mv "$out.tmp" "$out"
echo "built $out"
