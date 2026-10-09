# EclipseNative pipeline plan

Goal: build, in CI, drop-in replacements for the two prebuilt native aars the
launcher ships in `EclipseLauncher/libs/`: `lwjgl3-natives-release.aar` and
`openal-soft-release.aar`. This document is the working plan; DRAFT items are
to be corrected via CI iteration.

## 1. Verified artifact contracts (read-only inspection of current aars)

`lwjgl3-natives-release.aar`:

- `jni/<abi>/liblwjgl.so`, `liblwjgl_opengl.so`, `liblwjgl_nanovg.so`,
  `liblwjgl_stb.so`, `liblwjgl_tinyfd.so`, `liblwjgl_vma.so`,
  `libfreetype.so`, `libshaderc.so` for all four ABIs
  (`armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`); note there is NO
  `liblwjgl_glfw.so` and no separate `libglfw.so` - GLFW java classes are
  shipped separately as `assets/components/lwjgl3/lwjgl-glfw-classes.jar`
  (the launcher's own `jre_lwjgl3glfw` bindings).
- `assets/licenses/` texts: lwjgl, glfw, freetype, khronos, libffi, liburing,
  nanosvg, nanovg, openal-soft, shaderc, tinyfd, vma, blendish.
- empty `classes.jar` (pure native aar).

`openal-soft-release.aar`:

- `jni/<abi>/libopenal.so` for all four ABIs
- `assets/licenses/`: OBOE_APACHE2, OPENAL-SOFT_GPL2, PFFFT_LICENSE

ABIs map to the launcher's arch names: `arm`->armeabi-v7a,
`arm64`->arm64-v8a, `x86`->x86, `x86_64`->x86_64.

## 2. LWJGL3 natives

- Source: https://github.com/LWJGL/lwjgl3 (BSD-3-Clause). For fidelity to the
  shipped artifact, the FCL/Pojav Android forks are the practical references:
  - https://github.com/FCL-Team/lwjgl3 (`ci_build_android.bash`)
  - https://github.com/PojavLauncherTeam/lwjgl3 (`wip/rebase_3.3.3`)
- Per-ABI flow (DRAFT, modeled on `ci_build_android.bash`):
  1. Cross-build libffi (static) and freetype (shared, `libfreetype.so`
     shipped inside the aar).
  2. Provide `libshaderc.so` per ABI - the reference build downloads
     prebuilts; our pipeline should build shaderc from source in a later
     iteration (open item).
  3. `ant init` then `ant ... compile compile-native release` with
     `ANDROID=1`, `LWJGL_BUILD_ARCH=arm64|arm32|x86|x64`, and the binding
     set trimmed to: core bindings + `shaderc`, `vulkan`, `vma`, `spvc`
     enabled; everything else disabled.
  4. Collect `liblwjgl*.so`, `libfreetype.so`, `libshaderc.so` into
     `jni/<abi>/`.
- Packaging: `lwjgl3-android` Android-library module; CI copies the four ABI
  outputs into `src/main/jniLibs/`, adds `assets/licenses/` texts, runs
  `assembleRelease`.

## 3. OpenAL Soft

- Source: https://github.com/kcat/openal-soft (GPL-2.0-or-later).
  The shipped binary matches FCL's Oboe-backed fork:
  https://github.com/FCL-Team/OpenAL (branch `1.22.2-fcl`).
- Per-ABI flow (DRAFT): CMake with the NDK toolchain file
  (`android.toolchain.cmake`, ABI + API 21), Oboe dependency
  (`cmake/FindOboe.cmake` / `ALSOFT_OBOE_ENABLED`), build `libopenal.so`,
  strip with `llvm-strip`.
- Packaging: `openal-android` Android-library module, same CI pattern.

## 4. CI shape

`.github/workflows/build-native.yml`:

- triggers: `workflow_dispatch`, tag pushes matching `native-*`.
- `build` job: matrix `component: [lwjgl3, openal]` x
  `arch: [arm, arm64, x86, x86_64]` (8 cells, fail-fast off).
  Steps: checkout, free disk space, setup-java 17 (temurin) + ant,
  setup-android + NDK 25.2.9519653, run the component's per-ABI script,
  upload `<component>-so-<arch>` artifact.
- `assemble` job: per component, download the four ABI artifacts into
  `src/main/jniLibs/`, `gradle :lwjgl3-android:assembleRelease` (or
  `:openal-android:...`), upload the aar; on tag runs attach
  `lwjgl3-natives-release.aar` / `openal-soft-release.aar` to the GitHub
  publish job.

## 5. Open questions / risks

- LWJGL's `ant` native build expects a bootstrapped generator; the FCL script
  stubs it (`touch` files) to keep "LWJGLX" functions - decide whether to do
  the same or run upstream's generator properly.
- `libshaderc.so`: prebuilt download (fast, matches shipped artifact) vs
  building shaderc from source (cleaner provenance, much longer CI).
- GLFW on Android: upstream LWJGL3 does not build desktop GLFW for Android;
  the launcher relies on its own `jre_lwjgl3glfw` bindings + a GLFW Android
  port linked into `liblwjgl.so`. Confirm the exact upstream/fork revision
  once `jre_lwjgl3glfw` migrates here.
- x86/x86_64 LWJGL: the reference script works around missing Linux x86 libs;
  expect similar quirks.
- Oboe version pinning for openal-soft; PFFFT enabled or not (license asset
  suggests yes).
- AAR metadata: keep `classes.jar` empty and manifest minimal so the aar is a
  pure jni container like the current artifacts.

## 6. Future: jre_lwjgl3glfw migration

Move the launcher-side Java GLFW bindings (producing the
`lwjgl-glfw-classes.jar` asset) into this repo as a third module once the
native pipelines are stable; candidate upstreams for reference:
PojavLauncherTeam/lwjgl3-glfw-java (bindings + `convert_and_out.bash`) and
FCL-Team/lwjgl3-fcl (LWJGL3 Java side).
