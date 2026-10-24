#!/usr/bin/env bash
# Build SPIRV-Cross (vulkan-sdk-1.4.357.0, commit 6c09849) as the C API shared
# library that LWJGL's org.lwjgl.util.spvc bindings load.
#
# All backends stay enabled: LWJGL's generated Spvc class resolves every public
# spvc_* entry point during class initialisation, so a library built with MSL or
# HLSL omitted would fail to load even when only GLSL is used.
#
# The upstream target is libspirv-cross-c-shared.so; it is renamed to
# libspirv-cross.so because that is the bundled name LWJGL looks for. The
# internal SONAME (libspirv-cross-c-shared.so.0) keeps the upstream name, which
# is harmless for a library that is only ever dlopen()ed by absolute path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

setup_abi "${1:-}"
fetch_sources

SRC="$SOURCE_DIR/spirv-cross"
BUILD="$BUILD_ABI/spirv-cross"

cmake_configure "$SRC" "$BUILD" \
    -DSPIRV_CROSS_SHARED=ON \
    -DSPIRV_CROSS_STATIC=OFF \
    -DSPIRV_CROSS_CLI=OFF \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSPIRV_CROSS_SKIP_INSTALL=ON
cmake_build "$BUILD"

LIBRARY="$(find "$BUILD" -maxdepth 1 -name 'libspirv-cross-c-shared.so*' -type f | head -1)"
[ -n "$LIBRARY" ] || die "SPIRV-Cross did not produce libspirv-cross-c-shared.so"
cp -f "$LIBRARY" "$OUT_ABI/libspirv-cross.so"
strip_library "$OUT_ABI/libspirv-cross.so"
elf_report "$OUT_ABI/libspirv-cross.so"
note "SPIRV-Cross ready: $OUT_ABI/libspirv-cross.so"
