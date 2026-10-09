#!/usr/bin/env bash
# Common environment for the EclipseNative build scripts.
# Source this from the other scripts. DRAFT: validated via CI runs.

set -euo pipefail

ECLIPSE_COMPONENT="${ECLIPSE_COMPONENT:?set to lwjgl3 or openal}"
ECLIPSE_ARCH="${ECLIPSE_ARCH:?set to arm, arm64, x86 or x86_64}"

ANDROID_API="${ANDROID_API:-21}"
NDK_VERSION="${NDK_VERSION:-25.2.9519653}"
NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}/ndk/${NDK_VERSION}}"

WORKSPACE="${WORKSPACE:-${GITHUB_WORKSPACE:-$(pwd)}}"
OUT_DIR="${OUT_DIR:-${WORKSPACE}/out/so}"

HOST_TAG="${HOST_TAG:-linux-x86_64}"
TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}"
PATH="${TOOLCHAIN}/bin:${PATH}"

case "${ECLIPSE_ARCH}" in
    arm)    NDK_ABI="armeabi-v7a"; LWJGL_ARCH="arm32"; TRIPLE_PREFIX="armv7a-linux-androideabi" ;;
    arm64)  NDK_ABI="arm64-v8a";   LWJGL_ARCH="arm64"; TRIPLE_PREFIX="aarch64-linux-android" ;;
    x86)    NDK_ABI="x86";         LWJGL_ARCH="x86";   TRIPLE_PREFIX="i686-linux-android" ;;
    x86_64) NDK_ABI="x86_64";      LWJGL_ARCH="x64";   TRIPLE_PREFIX="x86_64-linux-android" ;;
    *) echo "unknown arch: ${ECLIPSE_ARCH}" >&2; exit 1 ;;
esac

ABI_OUT_DIR="${OUT_DIR}/${NDK_ABI}"
mkdir -p "${ABI_OUT_DIR}"

export NDK_ROOT TOOLCHAIN ANDROID_API NDK_VERSION WORKSPACE OUT_DIR ABI_OUT_DIR
export NDK_ABI LWJGL_ARCH TRIPLE_PREFIX
