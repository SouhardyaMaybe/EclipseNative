#!/usr/bin/env bash
# Build the LWJGL 3.4.3 JNI libraries for one Android ABI:
#
#   liblwjgl.so          core JNI (JNIEnv access, memory, libc, libffi upcalls)
#   liblwjgl_opengl.so   OpenGL/GLES JNI wrappers (all entry points are dlsym'd)
#   liblwjgl_stb.so      stb_image / stb_vorbis / stb_dxt / stb_easy_font
#   liblwjgl_vma.so      Vulkan Memory Allocator
#
# The source lists and flags mirror modules/lwjgl/*/src and
# config/linux/build.xml. The differences are Android build configuration only:
# NDK clang, bionic headers, API 26, static libc++ for VMA and 16 KB segments.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

setup_abi "${1:-}"
fetch_sources

SRC="$SOURCE_DIR/lwjgl"
VERSION_SCRIPT="$SRC/config/linux/version.script"
[ -f "$VERSION_SCRIPT" ] || die "missing upstream version script: $VERSION_SCRIPT"

if [ ! -f "$BUILD_ABI/libffi.a" ]; then
    bash "$ROOT/scripts/build-libffi.sh" "$ABI"
fi
FFI_LIB="$BUILD_ABI/libffi.a"

build_compat

# ---------------------------------------------------------------------------
# core
# ---------------------------------------------------------------------------
CORE="$SRC/modules/lwjgl/core/src"
CORE_OBJ="$OBJ_ABI/lwjgl"
mkdir -p "$CORE_OBJ"

mapfile -t CORE_MAIN < <(find "$CORE/main/c" -maxdepth 1 -name '*.c' | sort)
mapfile -t CORE_GENERATED < <(find "$CORE/generated/c" -maxdepth 1 -name '*.c' | sort)
mapfile -t CORE_LINUX < <(find "$CORE/generated/c/linux" -maxdepth 1 -name '*.c' | sort)
mapfile -t CORE_URING < <(find "$CORE/main/c/linux/liburing" -maxdepth 1 -name '*.c' | sort)

[ "${#CORE_MAIN[@]}" -gt 0 ] || die "no core main sources found"
[ "${#CORE_GENERATED[@]}" -gt 0 ] || die "no core generated sources found"
[ "${#CORE_LINUX[@]}" -gt 0 ] || die "no core linux sources found"
[ "${#CORE_URING[@]}" -gt 0 ] || die "no liburing sources found"

# Every module includes common_tools.h and LinuxConfig.h from core.
LWJGL_CONFIG=( "-DLWJGL_LINUX" "-DLWJGL_$LWJGL_ARCH" )
LWJGL_INCLUDES=( "-I$CORE/main/c" "-I$CORE/main/c/linux" )

CORE_CFLAGS=(
    "${COMMON_CFLAGS[@]}"
    "-std=gnu11"
    "${LWJGL_CONFIG[@]}"
    $FFI_ARCH_DEFINE
    "${LWJGL_INCLUDES[@]}"
    "-I$CORE/main/c/libffi"
    "-I$CORE/main/c/libffi/$FFI_TARGET_DIR"
    "-I$CORE/main/c/linux/liburing"
    "-I$CORE/main/c/linux/liburing/include"
    "-DCONFIG_HAVE_MEMFD_CREATE"
    "-DECLIPSE_COMPAT_REDIRECT_MEMFD"
    "-include" "$ROOT/compat/android_compat.h"
)

CORE_OBJECTS=()
for source in "${CORE_MAIN[@]}" "${CORE_GENERATED[@]}" "${CORE_LINUX[@]}" "${CORE_URING[@]}"; do
    relative="${source#"$SRC/"}"
    object="$CORE_OBJ/${relative//\//_}.o"
    CORE_OBJECTS+=("$object")
    extra=()
    case "$(basename "$source")" in
        org_lwjgl_system_MemoryAccessJNI.c|org_lwjgl_system_libc_LibCStdlib.c)
            # These two bind aligned_alloc directly in the generated code.
            extra+=("-DECLIPSE_COMPAT_REDIRECT_ALLOC")
            ;;
    esac
    "$CC" "${CORE_CFLAGS[@]}" "${extra[@]}" -c "$source" -o "$object"
done

note "linking liblwjgl.so (${#CORE_OBJECTS[@]} objects)"
"$CC" "${COMMON_LDFLAGS[@]}" \
    -o "$OUT_ABI/liblwjgl.so" \
    "${CORE_OBJECTS[@]}" "$FFI_LIB" "$COMPAT_OBJ" \
    -Wl,--version-script="$VERSION_SCRIPT" \
    -ldl -lm
strip_library "$OUT_ABI/liblwjgl.so"

# ---------------------------------------------------------------------------
# opengl
# ---------------------------------------------------------------------------
OPENGL="$SRC/modules/lwjgl/opengl/src"
OPENGL_OBJ="$OBJ_ABI/lwjgl_opengl"
mkdir -p "$OPENGL_OBJ"

mapfile -t GL_SOURCES < <(
    find "$OPENGL/generated/c" -maxdepth 1 -name '*.c' \
        ! -name 'org_lwjgl_opengl_WGL.c' | sort
)
[ "${#GL_SOURCES[@]}" -gt 0 ] || die "no opengl sources found"

GL_OBJECTS=()
for source in "${GL_SOURCES[@]}"; do
    object="$OPENGL_OBJ/$(basename "${source%.c}").o"
    GL_OBJECTS+=("$object")
    "$CC" "${COMMON_CFLAGS[@]}" -std=gnu11 \
        "${LWJGL_CONFIG[@]}" "${LWJGL_INCLUDES[@]}" \
        "-I$OPENGL/main/c" \
        "-include" "$ROOT/compat/android_compat.h" \
        -c "$source" -o "$object"
done

note "linking liblwjgl_opengl.so (${#GL_OBJECTS[@]} objects)"
"$CC" "${COMMON_LDFLAGS[@]}" \
    -o "$OUT_ABI/liblwjgl_opengl.so" \
    "${GL_OBJECTS[@]}" \
    -Wl,--version-script="$VERSION_SCRIPT" \
    -ldl -lm
strip_library "$OUT_ABI/liblwjgl_opengl.so"

# ---------------------------------------------------------------------------
# stb
# ---------------------------------------------------------------------------
STB="$SRC/modules/lwjgl/stb/src"
STB_OBJ="$OBJ_ABI/lwjgl_stb"
mkdir -p "$STB_OBJ"

mapfile -t STB_SOURCES < <(find "$STB/generated/c" -maxdepth 1 -name '*.c' | sort)
[ "${#STB_SOURCES[@]}" -gt 0 ] || die "no stb sources found"

STB_OBJECTS=()
for source in "${STB_SOURCES[@]}"; do
    object="$STB_OBJ/$(basename "${source%.c}").o"
    STB_OBJECTS+=("$object")
    "$CC" "${COMMON_CFLAGS[@]}" -std=gnu11 \
        "${LWJGL_CONFIG[@]}" "${LWJGL_INCLUDES[@]}" \
        "-isystem$STB/main/c" \
        "-DECLIPSE_COMPAT_REDIRECT_ALLOC" \
        "-include" "$ROOT/compat/android_compat.h" \
        -c "$source" -o "$object"
done

note "linking liblwjgl_stb.so (${#STB_OBJECTS[@]} objects)"
"$CC" "${COMMON_LDFLAGS[@]}" \
    -o "$OUT_ABI/liblwjgl_stb.so" \
    "${STB_OBJECTS[@]}" "$COMPAT_OBJ" \
    -Wl,--version-script="$VERSION_SCRIPT" \
    -lm
strip_library "$OUT_ABI/liblwjgl_stb.so"

# ---------------------------------------------------------------------------
# vma
# ---------------------------------------------------------------------------
VMA="$SRC/modules/lwjgl/vma/src"
VMA_OBJ="$OBJ_ABI/lwjgl_vma"
mkdir -p "$VMA_OBJ"

mapfile -t VMA_SOURCES < <(find "$VMA/generated/c" -maxdepth 1 -name '*.cpp' | sort)
[ "${#VMA_SOURCES[@]}" -gt 1 ] || die "expected Vma.cpp and LibVma.cpp"

VMA_OBJECTS=()
for source in "${VMA_SOURCES[@]}"; do
    object="$VMA_OBJ/$(basename "${source%.cpp}").o"
    VMA_OBJECTS+=("$object")
    "$CXX" "${COMMON_CFLAGS[@]}" -std=gnu++17 \
        "${LWJGL_CONFIG[@]}" "${LWJGL_INCLUDES[@]}" \
        "-I$VMA/main/c" \
        "-I$SRC/modules/lwjgl/vulkan/src/main/c" \
        "-DECLIPSE_COMPAT_REDIRECT_ALLOC" \
        "-include" "$ROOT/compat/android_compat.h" \
        -c "$source" -o "$object"
done

note "linking liblwjgl_vma.so (${#VMA_OBJECTS[@]} objects)"
"$CXX" "${COMMON_LDFLAGS[@]}" \
    -o "$OUT_ABI/liblwjgl_vma.so" \
    "${VMA_OBJECTS[@]}" "$COMPAT_OBJ" \
    -Wl,--version-script="$VERSION_SCRIPT" \
    -static-libstdc++ -lm
strip_library "$OUT_ABI/liblwjgl_vma.so"

for library in liblwjgl liblwjgl_opengl liblwjgl_stb liblwjgl_vma; do
    require_library "$OUT_ABI/$library.so"
    elf_report "$OUT_ABI/$library.so"
done

note "LWJGL libraries ready in $OUT_ABI"
