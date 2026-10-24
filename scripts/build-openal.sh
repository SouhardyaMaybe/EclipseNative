#!/usr/bin/env bash
# Build OpenAL Soft (commit 7f9c6de, the revision LWJGL 3.4.3 was generated
# against) for Android, with the official OpenSL ES backend.
#
# AAudio is deliberately not used: the official SDL3 AAudio backend is a v1.1
# item. Every other backend is switched off explicitly so the result does not
# depend on what the CI image happens to have installed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

setup_abi "${1:-}"
fetch_sources

SRC="$SOURCE_DIR/openal"
BUILD="$BUILD_ABI/openal"

cmake_configure "$SRC" "$BUILD" \
    -DLIBTYPE=SHARED \
    -DALSOFT_UTILS=OFF \
    -DALSOFT_EXAMPLES=OFF \
    -DALSOFT_TESTS=OFF \
    -DALSOFT_BACKEND_OPENSL=ON \
    -DALSOFT_REQUIRE_OPENSL=ON \
    -DALSOFT_BACKEND_PIPEWIRE=OFF \
    -DALSOFT_BACKEND_PULSEAUDIO=OFF \
    -DALSOFT_BACKEND_ALSA=OFF \
    -DALSOFT_BACKEND_OSS=OFF \
    -DALSOFT_BACKEND_SNDIO=OFF \
    -DALSOFT_BACKEND_SOLARIS=OFF \
    -DALSOFT_BACKEND_JACK=OFF \
    -DALSOFT_BACKEND_OBOE=OFF \
    -DALSOFT_BACKEND_PORTAUDIO=OFF \
    -DALSOFT_BACKEND_SDL2=OFF \
    -DALSOFT_BACKEND_SDL3=OFF \
    -DALSOFT_BACKEND_WAVE=OFF \
    -DALSOFT_EMBED_HRTF_DATA=ON
cmake_build "$BUILD"

LIBRARY="$(find "$BUILD" -maxdepth 2 -name 'libopenal.so*' -type f | head -1)"
[ -n "$LIBRARY" ] || die "OpenAL Soft did not produce libopenal.so"
cp -f "$LIBRARY" "$OUT_ABI/libopenal.so"
strip_library "$OUT_ABI/libopenal.so"
elf_report "$OUT_ABI/libopenal.so"
note "OpenAL Soft ready: $OUT_ABI/libopenal.so"
