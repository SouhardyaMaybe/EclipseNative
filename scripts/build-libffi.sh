#!/usr/bin/env bash
# Build the static libffi that liblwjgl.so links.
#
# LWJGL 3.4.3 vendors libffi headers that declare FFI_VERSION_STRING "3.8.0"
# and that ABI is what the Java bindings and liblwjgl.so were compiled against,
# so this script pins libffi 3.8.0 (see sources.lock.json).
#
# Android detail: libffi allocates closure trampolines in a file-backed
# mapping. /data is mounted noexec and /dev/shm does not exist, so the memfd
# path is the only one that works. memfd_create arrived in API 30, so the
# configure probe is forced to yes and compat/android_compat.c supplies the
# syscall wrapper for API 26.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

setup_abi "${1:-}"
fetch_sources

SRC="$SOURCE_DIR/libffi"
FFI_DIR="$BUILD_ABI/libffi"
PREFIX="$FFI_DIR/install"
LIB="$PREFIX/lib/libffi.a"

if [ -f "$LIB" ]; then
    note "libffi already built: $LIB"
    cp -f "$LIB" "$BUILD_ABI/libffi.a"
    exit 0
fi

note "configuring libffi $(lock_field libffi version)"
rm -rf "$FFI_DIR"
mkdir -p "$FFI_DIR"
cd "$FFI_DIR"

"$SRC/configure" \
    --host="$TRIPLE" \
    --prefix="$PREFIX" \
    --disable-shared \
    --enable-static \
    --disable-docs \
    --disable-multi-os-directory \
    --with-pic \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    CFLAGS="-O2 -fPIC -include $ROOT/compat/android_compat.h -DECLIPSE_COMPAT_REDIRECT_MEMFD" \
    ac_cv_func_memfd_create=yes

make -j"$JOBS"
make install

[ -f "$LIB" ] || die "libffi did not install $LIB"
cp -f "$LIB" "$BUILD_ABI/libffi.a"
note "libffi ready: $BUILD_ABI/libffi.a"
