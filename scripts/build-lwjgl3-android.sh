#!/usr/bin/env bash
# ===========================================================================
# FIRST DRAFT - build the LWJGL3 Android natives for one ABI.
#
# Modeled on FCL-Team/lwjgl3 ci_build_android.bash (the build that produced
# the currently shipped aar): cross-build libffi + freetype, fetch shaderc,
# stub the code generator, then drive LWJGL's ant native build with ANDROID=1.
# Iterate via CI runs.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
ECLIPSE_COMPONENT=lwjgl3
ECLIPSE_ARCH="${1:?usage: build-lwjgl3-android.sh <arm|arm64|x86|x86_64>}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env.sh"

LWJGL_REPO="${LWJGL_REPO:-https://github.com/FCL-Team/lwjgl3.git}"
LWJGL_BRANCH="${LWJGL_BRANCH:-wip/rebase_3.3.3}"
LIBFFI_VERSION="${LIBFFI_VERSION:-3.4.6}"
FREETYPE_VERSION="${FREETYPE_VERSION:-2.13.2}"

BUILD_DIR="${WORKSPACE}/lwjgl3"
rm -rf "${BUILD_DIR}"
git clone --depth 1 -b "${LWJGL_BRANCH}" "${LWJGL_REPO}" "${BUILD_DIR}"
cd "${BUILD_DIR}"

export ANDROID=1
export LWJGL_BUILD_ARCH="${LWJGL_ARCH}"
TARGET="${TRIPLE_PREFIX}"

LWJGL_NATIVE="bin/libs/native/linux/${LWJGL_ARCH}/org/lwjgl"
mkdir -p "${LWJGL_NATIVE}"

# --- libffi (static) -------------------------------------------------------
if [[ ! -d libffi ]]; then
    wget -q "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz"
    tar xf "libffi-${LIBFFI_VERSION}.tar.gz"
    mv "libffi-${LIBFFI_VERSION}" libffi
fi
(
    cd libffi
    bash configure --host="${TARGET}" --prefix="$PWD/${TARGET}-build" \
        CC="${TRIPLE_PREFIX}${ANDROID_API}-clang" \
        CXX="${TRIPLE_PREFIX}${ANDROID_API}-clang++"
    make -j"$(nproc)"
    # libffi builds into a host-triple subdirectory; installing to the
    # prefix is what makes the artifact land at a predictable path.
    make install
)
cp "libffi/${TARGET}-build/lib/libffi.a" "${LWJGL_NATIVE}/" 2>/dev/null \
    || cp "libffi/${TARGET}/.libs/libffi.a" "${LWJGL_NATIVE}/"

# --- freetype (shared, shipped inside the aar) -----------------------------
if [[ ! -d freetype ]]; then
    wget -q "https://downloads.sourceforge.net/project/freetype/freetype2/${FREETYPE_VERSION}/freetype-${FREETYPE_VERSION}.tar.gz"
    tar xf "freetype-${FREETYPE_VERSION}.tar.gz"
    mv "freetype-${FREETYPE_VERSION}" freetype
fi
(
    cd freetype
    export CC="${TRIPLE_PREFIX}${ANDROID_API}-clang"
    ./configure --host="${TARGET}" --prefix="$PWD/build-android" \
        --without-zlib --with-brotli=no --with-bzip2=no --with-png=no \
        --with-harfbuzz=no --enable-static=no --enable-shared=yes
    make -j"$(nproc)"
    make install
    llvm-strip "./build-android/lib/libfreetype.so"
)
cp freetype/build-android/lib/libfreetype.so "${LWJGL_NATIVE}/"

# --- shaderc (DRAFT: prebuilt input, as the reference build does) ----------
# TODO(provenance): build shaderc from source in a later iteration.
wget -q -nc "https://github.com/AngelAuraMC/shaderc/releases/latest/download/libshaderc-${NDK_ABI}.zip" || true
if [[ -f "libshaderc-${NDK_ABI}.zip" ]]; then
    unzip -o "libshaderc-${NDK_ABI}.zip" -d "${LWJGL_NATIVE}/shaderc"
fi

# --- stub the generator (same hack as the reference build) -----------------
mkdir -p bin/classes/generator bin/classes/templates/META-INF
touch bin/classes/generator/generated-touch.txt bin/classes/templates/META-INF/touch.txt

# --- LWJGL native build ------------------------------------------------------
apt list --installed 2>/dev/null | grep -q "^ant/" || { sudo apt-get update -q && sudo apt-get install -y -q ant; }
ant init
export LWJGL_BUILD_OFFLINE=true
yes | ant -Dplatform.linux=true \
    -Dbinding.assimp=false -Dbinding.bgfx=false -Dbinding.cuda=false \
    -Dbinding.egl=false -Dbinding.fmod=false -Dbinding.harfbuzz=false \
    -Dbinding.hwloc=false -Dbinding.jawt=false -Dbinding.jemalloc=false \
    -Dbinding.ktx=false -Dbinding.libdivide=false -Dbinding.llvm=false \
    -Dbinding.lmdb=false -Dbinding.lz4=false -Dbinding.meow=false \
    -Dbinding.meshoptimizer=false -Dbinding.nfd=false -Dbinding.nuklear=false \
    -Dbinding.odbc=false -Dbinding.opengles=false -Dbinding.opencl=false \
    -Dbinding.openvr=false -Dbinding.openxr=false -Dbinding.opus=false \
    -Dbinding.par=false -Dbinding.remotery=false -Dbinding.rpmalloc=false \
    -Dbinding.sse=false -Dbinding.tinyexr=false -Dbinding.tootle=false \
    -Dbinding.xxhash=false -Dbinding.yoga=false -Dbinding.zstd=false \
    -Dbinding.shaderc=true -Dbinding.vulkan=true -Dbinding.vma=true \
    -Dbinding.spvc=true \
    -Dbuild.type=release/3.3.3 \
    -Djavadoc.skip=true \
    compile compile-native release

# --- collect outputs matching the shipped aar contract ----------------------
find "${LWJGL_NATIVE}" -maxdepth 1 -name 'liblwjgl*.so' -exec cp {} "${ABI_OUT_DIR}/" \;
cp "${LWJGL_NATIVE}/libfreetype.so" "${ABI_OUT_DIR}/"
if [[ -f "${LWJGL_NATIVE}/shaderc/libshaderc.so" ]]; then
    cp "${LWJGL_NATIVE}/shaderc/libshaderc.so" "${ABI_OUT_DIR}/"
fi

echo "produced:" && ls -la "${ABI_OUT_DIR}"
