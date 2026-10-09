# EclipseNative

Build pipelines for the native components the Eclipse Launcher app ships as
prebuilt Android binaries: the LWJGL3 Android natives aar
(`lwjgl3-natives-release.aar`) and the OpenAL Soft aar
(`openal-soft-release.aar`). Both are built with the Android NDK for the four
supported ABIs and packaged by small Android-library Gradle projects.

**Status: DRAFT skeleton.** Scripts and workflow are written to be validated
and iterated via CI runs; no successful native build has been produced yet.

## Components

### lwjgl3-android -> `lwjgl3-natives-release.aar`

The launcher-side aar must contain, per ABI
(`armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`):

```
liblwjgl.so  liblwjgl_opengl.so  liblwjgl_nanovg.so  liblwjgl_stb.so
liblwjgl_tinyfd.so  liblwjgl_vma.so  libfreetype.so  libshaderc.so
```

plus `assets/licenses/*` (lwjgl, glfw, freetype, shaderc, openal-soft, ...).
This matches the layout of the aar the launcher currently ships (verified by
inspecting `EclipseLauncher/libs/lwjgl3-natives-release.aar`, read-only).

- Upstream: https://github.com/LWJGL/lwjgl3 (BSD-3-Clause)
- Reference Android builds (what the shipped aar was evidently built from):
  - https://github.com/FCL-Team/lwjgl3 (`ci_build_android.bash`, BSD-3-Clause)
  - https://github.com/PojavLauncherTeam/lwjgl3 (branch `wip/rebase_3.3.3`)
- Build flow (DRAFT, modeled on `ci_build_android.bash`): cross-build libffi
  and freetype, fetch prebuilt libshaderc/libopenal inputs, then drive
  LWJGL's own `ant` native build with `ANDROID=1` and
  `LWJGL_BUILD_ARCH=arm64|arm32|x86|x64`, collect `liblwjgl*.so` +
  `libfreetype.so` + `libshaderc.so` per ABI.

### openal-android -> `openal-soft-release.aar`

Per ABI: a single `libopenal.so`, plus license assets (OpenAL Soft GPL-2,
Oboe Apache-2.0, PFFFT). Matches the shipped aar's contents (verified by
inspection, read-only).

- Upstream: https://github.com/kcat/openal-soft (GPL-2.0-or-later)
- Reference build: https://github.com/FCL-Team/OpenAL (branch `1.22.2-fcl`),
  an openal-soft fork with an Oboe backend (`alc/backends/oboe.cpp`,
  `cmake/FindOboe.cmake`) - this is what the shipped binary matches.
- Build flow (DRAFT): CMake with the NDK toolchain file, Oboe dependency,
  `-DALSOFT_OBOE_ENABLED=ON`, per-ABI toolchain triple.

### jre_lwjgl3glfw (future)

The launcher's `jre_lwjgl3glfw` module (the Java GLFW bindings jar shipped as
`assets/components/lwjgl3/lwjgl-glfw-classes.jar`) currently lives in the app
repo and will move here later. Related upstreams already identified:
https://github.com/PojavLauncherTeam/lwjgl3-glfw-java (bindings + conversion
scripts) and https://github.com/FCL-Team/lwjgl3-fcl (the Java side of LWJGL3
producing `lwjgl.jar`). No module is scaffolded for it yet.

## Repository layout

```
docs/plan.md                  full pipeline plan and open questions
scripts/env.sh                common environment (ABI/triple mapping, NDK)
scripts/build-lwjgl3-android.sh   LWJGL3 natives per ABI       [DRAFT]
scripts/build-openal-android.sh   OpenAL Soft per ABI          [DRAFT]
lwjgl3-android/               Android-library project packaging the aar [DRAFT]
openal-android/               Android-library project packaging the aar [DRAFT]
.github/workflows/build-native.yml  matrix: component x 4 ABIs; tag publishing
```

## Building

CI is the only supported path for now (`build-native` workflow, manual
dispatch or `jre-*`-style tag push is not used here - tags `native-*`):

1. `build` job: component x arch matrix builds the raw `.so` files with NDK
   25.2.9519653 and uploads them as per-ABI artifacts.
2. `assemble` job: per component, places the four ABI outputs into
   `src/main/jniLibs/<abi>/` and runs `gradle :<module>:assembleRelease`,
   producing `lwjgl3-natives-release.aar` / `openal-soft-release.aar`.
3. On tag runs the aars are attached to the GitHub publish job (file names
   are already unique across components).

The app repo pins the resulting artifact URLs and copies the aars into
`EclipseLauncher/libs/`.

## Licensing notes

- LWJGL3 and its bundled components: BSD-3-Clause (upstream license texts are
  packaged into `assets/licenses/` inside the aar, as the current artifact
  does).
- OpenAL Soft: GPL-2.0-or-later; Oboe: Apache-2.0; PFFFT: its own license.
  Keep shipping the license assets in the aar.
- The scaffolding of this repository (scripts, Gradle files, docs) is
  MIT-licensed (see `LICENSE`).
