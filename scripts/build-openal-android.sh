#!/usr/bin/env bash
# ===========================================================================
# FIRST DRAFT - build OpenAL Soft (Oboe backend) for one Android ABI.
#
# Modeled on FCL-Team/OpenAL branch 1.22.2-fcl (the build that produced the
# currently shipped openal-soft-release.aar). Iterate via CI runs.
# ===========================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
ECLIPSE_COMPONENT=openal
ECLIPSE_ARCH="${1:?usage: build-openal-android.sh <arm|arm64|x86|x86_64>}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env.sh"

OPENAL_REPO="${OPENAL_REPO:-https://github.com/FCL-Team/OpenAL.git}"
OPENAL_BRANCH="${OPENAL_BRANCH:-1.22.2-fcl}"
OBOE_REPO="${OBOE_REPO:-https://github.com/google/oboe.git}"
OBOE_BRANCH="${OBOE_BRANCH:-1.8.1}"

BUILD_DIR="${WORKSPACE}/openal-soft"
OBOE_DIR="${WORKSPACE}/oboe"
rm -rf "${BUILD_DIR}" "${OBOE_DIR}"

git clone --depth 1 -b "${OBOE_BRANCH}" "${OBOE_REPO}" "${OBOE_DIR}"
git clone --depth 1 -b "${OPENAL_BRANCH}" "${OPENAL_REPO}" "${BUILD_DIR}"

TOOLCHAIN_FILE="${NDK_ROOT}/build/cmake/android.toolchain.cmake"

# --- Oboe (static) ----------------------------------------------------------
cmake -S "${OBOE_DIR}" -B "${OBOE_DIR}/build-android" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DANDROID_ABI="${NDK_ABI}" \
    -DANDROID_PLATFORM="android-${ANDROID_API}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF
cmake --build "${OBOE_DIR}/build-android" -j"$(nproc)"

# --- OpenAL Soft ------------------------------------------------------------
# DRAFT flag set: Oboe backend on, examples/tests/install off; the exact
# ALSOFT_* cache names are validated by the first CI run against the fork's
# CMakeLists.
cmake -S "${BUILD_DIR}" -B "${BUILD_DIR}/build-android" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DANDROID_ABI="${NDK_ABI}" \
    -DANDROID_PLATFORM="android-${ANDROID_API}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DALSOFT_OBOE_ENABLED=ON \
    -DALSOFT_TESTS=OFF \
    -DALSOFT_EXAMPLES=OFF \
    -DALSOFT_UTILS=OFF \
    -DALSOFT_INSTALL=OFF \
    -DOBOE_DIR="${OBOE_DIR}/build-android"
cmake --build "${BUILD_DIR}/build-android" -j"$(nproc)"

cp "${BUILD_DIR}/build-android/libopenal.so" "${ABI_OUT_DIR}/"
llvm-strip --strip-unneeded "${ABI_OUT_DIR}/libopenal.so"

echo "produced:" && ls -la "${ABI_OUT_DIR}"
