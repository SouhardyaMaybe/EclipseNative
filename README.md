# EclipseNatives

Android natives for the Eclipse Launcher's runtime, built from upstream sources
on GitHub Actions and published as a GitHub Release.

**Status: pipeline under construction.** Nothing here has been released yet.
The first successful `Native` run produces the artifact set described below;
until then treat every version number as a draft.

## What this repository is

Minecraft: Java Edition 26.3 runs on the JVM and expects desktop LWJGL natives.
No official Android builds of those libraries exist. This repository builds
them for `arm64-v8a` and `x86_64` from the exact upstream revisions that the
LWJGL 3.4.3 Java bindings were generated against:

| Library | Upstream | Pin | License |
|---|---|---|---|
| `liblwjgl.so` | [LWJGL 3.4.3](https://github.com/LWJGL/lwjgl3) | `30fac9b9` | BSD-3-Clause |
| `liblwjgl_opengl.so` | LWJGL 3.4.3 | `30fac9b9` | BSD-3-Clause |
| `liblwjgl_stb.so` | LWJGL 3.4.3 (stb) | `30fac9b9` | MIT / public domain |
| `liblwjgl_vma.so` | LWJGL 3.4.3 (VMA) | `30fac9b9` | MIT |
| `libfreetype.so` | [FreeType](https://github.com/freetype/freetype) | `0a0221a` (2.14.3) | FTL or GPL-2.0-or-later |
| `libopenal.so` | [OpenAL Soft](https://github.com/kcat/openal-soft) | `7f9c6de` | LGPL-2.0-or-later |
| `libshaderc.so` | [Shaderc](https://github.com/google/shaderc) | `v2026.3` (`2c8cae7`) | Apache-2.0 |
| `libspirv-cross.so` | [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) | `6c09849` | Apache-2.0 |

`libffi` 3.8.0 (MIT) is linked statically into `liblwjgl.so`. Shaderc's pinned
glslang, SPIRV-Tools and SPIRV-Headers revisions are listed in
[`sources.lock.json`](sources.lock.json), which is the single source of truth
for every archive and its SHA-256.

SDL3 is **not** built here: it lives in the separate EclipseSDL3 component so
its window-system seam can be reviewed and released independently.

## Why the libraries are rebuilt

LWJGL publishes Linux, Windows and macOS natives, not Android ones. Android's
Bionic libc, its dynamic linker, its 16 KB page-size transition and the absence
of `libGL.so` all make a desktop `.so` unusable. Rebuilding the same upstream
sources with the NDK is build configuration, not a fork: this repository
contains no modified library source.

The only original C code is [`compat/android_compat.c`](compat/android_compat.c),
which supplies two libc entry points that Android added after API 26:

| Symbol | Added in | Used by | Implementation |
|---|---|---|---|
| `memfd_create` | API 30 | libffi closure trampolines | raw `__NR_memfd_create` syscall |
| `aligned_alloc` | API 28 | LWJGL libc bindings | `posix_memalign` wrapper |

This matters: `/data` is mounted `noexec` and `/dev/shm` does not exist on
Android, so libffi's file-backed trampoline paths cannot work. Forcing the
memfd path — and providing it on API 26 — is what makes Java callbacks work.

## Build configuration

Everything below is a build-flag or packaging decision, applied to unmodified
upstream sources.

- **NDK r28c** (`28.2.13676358`), API 26, clang, `-fPIC`, `-O2`.
- **16 KB segments**: `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384`
  on every shared link.
- **Static libc++** (`ANDROID_STL=c++_static`, `-static-libstdc++`) so the app
  does not ship `libc++_shared.so`.
- **Hidden internals**: LWJGL libraries use upstream's
  `config/linux/version.script`; the CMake libraries link with
  `-Wl,--exclude-libs,ALL`. Only the public API is exported.
- **`--no-undefined`** on every shared link. A missing platform symbol fails
  the build instead of the device.
- **OpenAL Soft** uses the official OpenSL ES backend
  (`ALSOFT_REQUIRE_OPENSL=ON`). PipeWire, PulseAudio, ALSA, OSS, sndio, JACK and
  the WAV writer are explicitly disabled. AAudio arrives with the SDL3 AAudio
  backend in v1.1.
- **Shaderc** skips tests, examples, executables and installation;
  `-Werror` is off for the third-party tree.
- **SPIRV-Cross** keeps every backend enabled because LWJGL's generated `Spvc`
  class resolves all `spvc_*` entry points at class initialisation.
  `libspirv-cross-c-shared.so` is copied to `libspirv-cross.so`, the bundled
  name LWJGL looks for.

## Verification gates

`scripts/check-elf.py` runs on every library and `scripts/package.py` runs it
again on the packaged set. It fails the build when:

- the file is not a 64-bit `ET_DYN` object for the requested ABI;
- a `PT_LOAD` segment has `p_align < 0x4000` or incongruent `p_vaddr`/`p_offset`;
- RELRO page-rounding covers writable memory outside RELRO;
- the stack is executable, `DT_TEXTREL` is set, or `DT_RPATH`/`DT_RUNPATH` is present;
- a `DT_NEEDED` entry is not a platform library (this is what keeps
  `libc++_shared.so` and `libGL.so` out);
- a library is missing the entry points its consumer `dlsym()`s.

Non-16 KB-aligned RELRO ends are warnings, matching the app's gate and Google's
own `androidx.graphics.path`.

The package step also asserts that exactly the eight expected libraries exist
for each ABI, and emits `BUILD-MANIFEST.json` plus `SHA256SUMS.txt`.

## Artifacts

A release named `native-v<version>` attaches:

| File | Contents |
|---|---|
| `eclipsenatives-<version>.aar` | `jni/<abi>/*.so`, `assets/licenses/*`, `assets/eclipsenatives/BUILD-MANIFEST.json`, minimal manifest |
| `eclipsenatives-<version>.zip` | the same payload plus `BUILD-MANIFEST.json` and `SHA256SUMS.txt` |
| `BUILD-MANIFEST.json` | versions, commit, per-library SHA-256 and size, source lock digest |
| `SHA256SUMS.txt` | hashes of the AAR, the zip and the manifest |

The app's Gradle build downloads the AAR, verifies its SHA-256 and extracts
`jni/` into the APK's native library directory. Binaries are never committed.

## Building locally

You do not need to: Actions is the authoritative builder. If you want to
reproduce a build, install NDK r28c, set `ANDROID_NDK_ROOT`, then:

```bash
bash scripts/build-lwjgl.sh arm64-v8a
bash scripts/build-freetype.sh arm64-v8a
bash scripts/build-openal.sh arm64-v8a
bash scripts/build-spirv-cross.sh arm64-v8a
bash scripts/build-shaderc.sh arm64-v8a
python3 scripts/package.py --require-abi arm64-v8a
```

Sources are downloaded from the lock file into `.build/`, verified against
their SHA-256, and never modified.

## Known limitations

- **64-bit only.** 32-bit Android is out of scope; the app's ABI filters match.
- **`org.lwjgl.system.linux.Stat`** exposes glibc's `struct stat` layout. The
  JNI call itself works on Android, but the Java field offsets do not match
  Bionic's structure. The game does not use this binding; it is documented
  rather than patched because patching generated code would create a fork.
- **OpenSL ES only.** AAudio lands with SDL3's AAudio backend in v1.1.
- **No Vulkan JNI shim.** Vulkan is reached through SDL3 and `liblwjgl_vma.so`;
  LWJGL's `liblwjgl_vulkan.so` is not built because Minecraft does not load it.

## Licensing

The build scripts and the compat shim are Apache-2.0 (see [`LICENSE`](LICENSE)).
Every bundled library keeps its upstream license; the complete texts are in
[`licenses/`](licenses/) and are copied into the AAR's assets. See
[`PROVENANCE.md`](PROVENANCE.md) for the file-by-file audit.

Eclipse Launcher is not affiliated with Mojang, Microsoft, the Eclipse
Foundation, or any launcher project mentioned in its research.

Minecraft is a trademark of Mojang Synergies AB. This project does not
distribute Minecraft game files. Users must own a legitimate Minecraft: Java
Edition account.

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR
MICROSOFT.
