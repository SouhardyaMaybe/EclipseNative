#!/usr/bin/env bash
# Build FreeType 2.14.3 for Android.
#
# FreeType is the only font rasterizer the game uses (through LWJGL's bindings).
# Optional image/compression dependencies are disabled so the library depends on
# nothing but libc/libm; the game never loads PNG- or BZip2-compressed fonts.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

setup_abi "${1:-}"
fetch_sources

SRC="$SOURCE_DIR/freetype"
BUILD="$BUILD_ABI/freetype"

cmake_configure "$SRC" "$BUILD" \
    -DBUILD_SHARED_LIBS=ON \
    -DFT_DISABLE_ZLIB=TRUE \
    -DFT_DISABLE_BZIP2=TRUE \
    -DFT_DISABLE_PNG=TRUE \
    -DFT_DISABLE_HARFBUZZ=TRUE \
    -DFT_DISABLE_BROTLI=TRUE
cmake_build "$BUILD"

LIBRARY="$(find "$BUILD" -maxdepth 2 -name 'libfreetype.so*' -type f | head -1)"
[ -n "$LIBRARY" ] || die "FreeType did not produce libfreetype.so"
cp -f "$LIBRARY" "$OUT_ABI/libfreetype.so"
strip_library "$OUT_ABI/libfreetype.so"
elf_report "$OUT_ABI/libfreetype.so"
note "FreeType ready: $OUT_ABI/libfreetype.so"
