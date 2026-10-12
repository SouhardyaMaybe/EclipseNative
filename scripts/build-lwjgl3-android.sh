#!/usr/bin/env bash
# ===========================================================================
# Build the LWJGL3 Android natives for one ABI.
#
# Modeled on FCL-Team/lwjgl3 ci_build_android.bash: cross-build libffi +
# freetype, fetch shaderc, stub the code generator, then drive LWJGL's ant
# native build with ANDROID=1.
#
# The natives are built from the FCL-Team Android rebase branch whose base
# matches the Java classes the launcher ships (upstream LWJGL does not build
# Android natives and publishes no natives-android artifacts). JNI is
# version-locked to the Java side, so this pin must track the jars in the
# app repo's jre_lwjgl3glfw/libs/ (see docs/plan.md).
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
ECLIPSE_COMPONENT=lwjgl3
ECLIPSE_ARCH="${1:?usage: build-lwjgl3-android.sh <arm|arm64|x86|x86_64>}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env.sh"

LWJGL_REPO="${LWJGL_REPO:-https://github.com/FCL-Team/lwjgl3.git}"
# 3.4.x JNI base (branch gradle.properties: lwjglVersion=3.4.1). The app
# ships 3.4.3 Java classes; upstream 3.4.1->3.4.3 has no C changes in core
# and only vendored-header churn in stb/vma, and the app-repo verification
# harness exercises the shipped 3.4.3 classes against these natives on the
# device JRE before the aar is consumed.
LWJGL_BRANCH="${LWJGL_BRANCH:-wip/rebase_3.4.1}"
# Versions match the reference ci_build_android.bash on that branch.
LIBFFI_VERSION="${LIBFFI_VERSION:-3.5.2}"
FREETYPE_VERSION="${FREETYPE_VERSION:-2.14.1}"

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
# LWJGL's ant build hard-fails on JDK 9+ without a JAVA8_HOME (see the
# -check-release-jdk target); setup-java exports JAVA_HOME_8_X64 for the
# secondary JDK 8 install.
export JAVA8_HOME="${JAVA8_HOME:-${JAVA_HOME_8_X64:-}}"
if [[ -z "${JAVA8_HOME}" ]]; then
    echo "JAVA8_HOME is not set and JAVA_HOME_8_X64 is unavailable" >&2
    exit 1
fi
apt list --installed 2>/dev/null | grep -q "^ant/" || { sudo apt-get update -q && sudo apt-get install -y -q ant; }
ant init
export LWJGL_BUILD_OFFLINE=true
# `yes` exits with SIGPIPE once ant closes stdin; under pipefail that would
# fail the build even when ant succeeds, so relax it for this pipeline only
# (ant's own exit status still drives set -e).
set +o pipefail
# Binding set mirrors the reference ci_build_android.bash on the 3.4.1
# branch, with two deliberate differences: sdl stays false (SDL3 for the
# 26.3 client comes from the EclipseSDL3 pipeline, building a second SDL3
# here would shadow it) and spng stays false (no consumer).
yes | ant -Dplatform.linux=true \
    -Dbinding.assimp=false -Dbinding.bgfx=false -Dbinding.cuda=false \
    -Dbinding.egl=false -Dbinding.fmod=false -Dbinding.harfbuzz=false \
    -Dbinding.hwloc=false -Dbinding.jawt=false -Dbinding.jemalloc=false \
    -Dbinding.ktx=false -Dbinding.libdivide=false -Dbinding.llvm=false \
    -Dbinding.lmdb=false -Dbinding.lz4=false -Dbinding.meow=false \
    -Dbinding.meshoptimizer=false -Dbinding.msdfgen=false -Dbinding.nfd=false \
    -Dbinding.nuklear=false -Dbinding.odbc=false -Dbinding.opengles=false \
    -Dbinding.opencl=false -Dbinding.openvr=false -Dbinding.openxr=false \
    -Dbinding.opus=false -Dbinding.par=false -Dbinding.remotery=false \
    -Dbinding.renderdoc=false -Dbinding.rpmalloc=false -Dbinding.sdl=false \
    -Dbinding.spng=false -Dbinding.sse=false -Dbinding.tinyexr=false \
    -Dbinding.tootle=false -Dbinding.xxhash=false -Dbinding.yoga=false \
    -Dbinding.zstd=false \
    -Dbinding.shaderc=true -Dbinding.vulkan=true -Dbinding.vma=true \
    -Dbinding.spvc=true \
    -Dbuild.type=release/3.4.1 \
    -Djavadoc.skip=true \
    compile compile-native release
set -o pipefail

# --- collect outputs matching the shipped aar contract ----------------------
# Recursive, same as the reference ci_build_android.bash: only the core
# library (liblwjgl.so) is linked into ${LWJGL_NATIVE} itself; each binding
# module links its liblwjgl_<binding>.so into a per-module subdirectory
# (${lib.native}/${module.<binding>.path}, e.g. .../org/lwjgl/opengl/). A
# top-level-only find silently drops liblwjgl_opengl/_nanovg/_stb/_tinyfd/
# _vma.so (native-v1.0.0 shipped none of them). GLFW is deliberately absent:
# upstream LWJGL does not build desktop GLFW for Android; the launcher ships
# its own jre_lwjgl3glfw bindings.
find "${LWJGL_NATIVE}" -name 'liblwjgl*.so' -exec cp {} "${ABI_OUT_DIR}/" \;
cp "${LWJGL_NATIVE}/libfreetype.so" "${ABI_OUT_DIR}/"
if [[ -f "${LWJGL_NATIVE}/shaderc/libshaderc.so" ]]; then
    cp "${LWJGL_NATIVE}/shaderc/libshaderc.so" "${ABI_OUT_DIR}/"
fi

# Fail loudly rather than release an aar that is missing a native library the
# launcher loads (the native-v1.0.0 gap: missing binding libs went unnoticed
# until the aar was inspected).
for lib in liblwjgl.so liblwjgl_opengl.so liblwjgl_nanovg.so liblwjgl_stb.so \
    liblwjgl_tinyfd.so liblwjgl_vma.so libfreetype.so libshaderc.so; do
    if [[ ! -s "${ABI_OUT_DIR}/${lib}" ]]; then
        echo "ERROR: expected non-empty ${lib} for ${NDK_ABI} in ${ABI_OUT_DIR}" >&2
        exit 1
    fi
done

echo "produced:" && ls -la "${ABI_OUT_DIR}"
