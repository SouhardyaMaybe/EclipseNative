#!/usr/bin/env bash
# Shared environment for the EclipseNatives build scripts.
#
# Every build script is invoked as:  scripts/build-<component>.sh <abi>
# Supported ABIs: arm64-v8a, x86_64. API 26 is the floor because that is the
# app's minSdk. Libraries are compiled against the API 26 sysroot; entry points
# added by later API levels are provided by compat/android_compat.c, never by
# raising the target.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/scripts/lock.py"

API="${ECLIPSE_API:-26}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

BUILD_ROOT="${ECLIPSE_BUILD_DIR:-$ROOT/.build}"
SOURCE_DIR="${ECLIPSE_SOURCE_DIR:-$BUILD_ROOT/src}"
CACHE_DIR="${ECLIPSE_CACHE_DIR:-$BUILD_ROOT/cache}"
OUT_DIR="${ECLIPSE_OUT_DIR:-$ROOT/out}"

# All notes go to stderr so that "$(build_compat)" style callers only ever see
# the value they asked for on stdout.
note() {
    echo "==> $*" >&2
}

die() {
    echo "error: $*" >&2
    exit 1
}

lock_field() {
    python3 "$LOCK" "$1" "$2"
}

fetch_sources() {
    bash "$ROOT/scripts/fetch-sources.sh"
}

setup_abi() {
    ABI="${1:?usage: build-<component>.sh <arm64-v8a|x86_64>}"
    case "$ABI" in
        arm64-v8a)
            TRIPLE="aarch64-linux-android"
            CMAKE_ABI="arm64-v8a"
            ELF_MACHINE=183
            LWJGL_ARCH=arm64
            FFI_TARGET_DIR=aarch64
            FFI_ARCH_DEFINE=""
            ;;
        x86_64)
            TRIPLE="x86_64-linux-android"
            CMAKE_ABI="x86_64"
            ELF_MACHINE=62
            LWJGL_ARCH=x64
            FFI_TARGET_DIR=x86
            FFI_ARCH_DEFINE="-DX86_64"
            ;;
        *)
            die "unsupported ABI: $ABI (expected arm64-v8a or x86_64)"
            ;;
    esac

    local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    local ndk_root="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
    if [ -z "$ndk_root" ] && [ -n "$sdk_root" ]; then
        ndk_root="$sdk_root/ndk/$NDK_VERSION"
    fi
    NDK="${ndk_root:?set ANDROID_NDK_ROOT (or ANDROID_HOME with NDK $NDK_VERSION installed)}"

    TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
    CC="$TOOLCHAIN/bin/${TRIPLE}${API}-clang"
    CXX="$TOOLCHAIN/bin/${TRIPLE}${API}-clang++"
    AR="$TOOLCHAIN/bin/llvm-ar"
    RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
    STRIP="$TOOLCHAIN/bin/llvm-strip"
    READELF="$TOOLCHAIN/bin/llvm-readelf"
    NM="$TOOLCHAIN/bin/llvm-nm"
    CMAKE_TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"

    for tool in "$CC" "$CXX" "$AR" "$STRIP" "$READELF" "$CMAKE_TOOLCHAIN"; do
        [ -e "$tool" ] || die "missing NDK tool: $tool"
    done
    command -v cmake >/dev/null || die "cmake is not installed"

    BUILD_ABI="$BUILD_ROOT/$ABI"
    OBJ_ABI="$BUILD_ABI/obj"
    OUT_ABI="$OUT_DIR/jni/$ABI"
    mkdir -p "$BUILD_ABI" "$OBJ_ABI" "$OUT_ABI" "$SOURCE_DIR" "$CACHE_DIR"

    # Equivalent of the upstream config/linux/build.xml flags, translated from
    # GCC/glibc to the NDK. The upstream recipe targets never Android.
    COMMON_CFLAGS=(
        "-O2" "-fPIC" "-fstack-protector-strong"
        "-pthread" "-DNDEBUG"
        "-D_GNU_SOURCE" "-D_FILE_OFFSET_BITS=64"
        "-U_FORTIFY_SOURCE"
    )
    COMMON_LDFLAGS=(
        "-shared"
        "-Wl,--no-undefined"
        "-Wl,-z,noexecstack"
        "-Wl,-z,relro"
        "-Wl,-z,now"
        "-Wl,-z,max-page-size=16384"
        "-Wl,-z,common-page-size=16384"
        "-Wl,--build-id=sha1"
    )
    CMAKE_COMMON=(
        "-DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN"
        "-DANDROID_ABI=$CMAKE_ABI"
        "-DANDROID_PLATFORM=android-$API"
        "-DANDROID_STL=c++_static"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
        "-DCMAKE_C_FLAGS=-O2 -fPIC -fstack-protector-strong -U_FORTIFY_SOURCE"
        "-DCMAKE_CXX_FLAGS=-O2 -fPIC -fstack-protector-strong -U_FORTIFY_SOURCE"
        "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-undefined -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -Wl,--build-id=sha1 -Wl,--exclude-libs,ALL"
    )

    export ABI TRIPLE API NDK TOOLCHAIN CC CXX AR RANLIB STRIP READELF NM
    export BUILD_ABI OBJ_ABI OUT_ABI SOURCE_DIR CACHE_DIR OUT_DIR BUILD_ROOT
    export LWJGL_ARCH FFI_TARGET_DIR FFI_ARCH_DEFINE ELF_MACHINE CMAKE_TOOLCHAIN
    note "$ABI ($TRIPLE, API $API, NDK $NDK_VERSION)"
}

build_compat() {
    local out="$BUILD_ABI/compat"
    mkdir -p "$out"
    COMPAT_OBJ="$out/android_compat.o"
    "$CC" "${COMMON_CFLAGS[@]}" -include "$ROOT/compat/android_compat.h" \
        -c "$ROOT/compat/android_compat.c" -o "$COMPAT_OBJ"
}

cmake_configure() {
    local source="$1"
    local build="$2"
    shift 2
    mkdir -p "$build"
    cmake -S "$source" -B "$build" "${CMAKE_COMMON[@]}" "$@"
}

cmake_build() {
    local build="$1"
    cmake --build "$build" --parallel "$JOBS"
}

strip_library() {
    local library="$1"
    [ -f "$library" ] || die "cannot strip missing file: $library"
    "$STRIP" --strip-unneeded "$library"
}

elf_report() {
    local library="$1"
    python3 "$ROOT/scripts/check-elf.py" --abi "$ABI" "$library"
}

require_library() {
    local library="$1"
    [ -f "$library" ] || die "expected library was not produced: $library"
}
