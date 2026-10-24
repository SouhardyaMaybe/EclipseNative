#!/usr/bin/env bash
# Build Shaderc v2026.3 and its pinned glslang / SPIRV-Tools / SPIRV-Headers
# revisions for Android.
#
# Shaderc turns the GLSL that Minecraft emits into SPIR-V; SPIRV-Cross (built
# separately) turns that SPIR-V into GLSL 330, which Sandpaper rewrites for
# GLES 3.2. Only the shared library is needed, so tests, examples, executables
# and installation are all disabled.
#
# Upstream's third_party/ layout is reproduced with symlinks to the verified
# source trees; no files are copied or patched.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

setup_abi "${1:-}"
fetch_sources

SRC="$SOURCE_DIR/shaderc"
BUILD="$BUILD_ABI/shaderc"

mkdir -p "$SRC/third_party"
ln -sfn "$SOURCE_DIR/glslang" "$SRC/third_party/glslang"
ln -sfn "$SOURCE_DIR/spirv-tools" "$SRC/third_party/spirv-tools"
ln -sfn "$SOURCE_DIR/spirv-headers" "$SRC/third_party/spirv-headers"

cmake_configure "$SRC" "$BUILD" \
    -DSHADERC_SKIP_TESTS=ON \
    -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_EXECUTABLES=ON \
    -DSHADERC_SKIP_INSTALL=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSHADERC_ENABLE_WERROR_COMPILE=OFF \
    -DENABLE_GLSLANG_BINARIES=OFF \
    -DGLSLANG_TESTS=OFF \
    -DSPIRV_SKIP_TESTS=ON \
    -DSPIRV_SKIP_EXECUTABLES=ON \
    -DSPIRV_WERROR=OFF \
    -DSPIRV-Headers_SOURCE_DIR="$SOURCE_DIR/spirv-headers"
cmake_build "$BUILD"

# Upstream builds the shared library as libshaderc_shared.so.1 (SOVERSION 1);
# LWJGL looks for libshaderc.so. The copy is renamed, the SONAME is left alone:
# the library is only opened by absolute path, so the loader never consults it.
LIBRARY="$(find "$BUILD" -maxdepth 2 -name 'libshaderc_shared.so*' -type f | head -1)"
[ -n "$LIBRARY" ] || die "Shaderc did not produce libshaderc_shared.so"
cp -f "$LIBRARY" "$OUT_ABI/libshaderc.so"
strip_library "$OUT_ABI/libshaderc.so"
elf_report "$OUT_ABI/libshaderc.so"
note "Shaderc ready: $OUT_ABI/libshaderc.so"
