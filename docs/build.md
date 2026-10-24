# Building EclipseNatives

GitHub Actions is the authoritative builder. Local builds are supported for
debugging, but a release is only ever produced by `.github/workflows/native.yml`
on a `native-v*` tag. There is no Gradle wrapper, no checked-in binary and no
submodule.

## 1. What you need

| Tool | Version | Why |
|---|---|---|
| Android NDK | r28c (`28.2.13676358`) | the only NDK the release workflow installs |
| CMake | 3.22 or newer | Shaderc/SPIRV-Tools minimum |
| Ninja | any recent | CMake's default generator on the CI image |
| Python | 3.9 or newer | lock, ELF gate, packaging |
| curl, tar, sha256sum | standard | source fetch and verification |
| Bash | 4.x | `mapfile`, arrays |

Set `ANDROID_NDK_ROOT` to the NDK directory. `ANDROID_HOME` also works if the
NDK is installed at `$ANDROID_HOME/ndk/28.2.13676358`.

The scripts compile against the API 26 sysroot, not the newest platform. That is
deliberate: `minSdk` is 26, and the two later libc entry points are supplied by
`compat/android_compat.c`. Do not raise `ECLIPSE_API` to make a build pass; fix
the missing API with a documented shim instead.

## 2. Layout

```
sources.lock.json        immutable pin + SHA-256 for every archive
scripts/lib.sh           shared toolchain/flag setup, one ABI at a time
scripts/fetch-sources.sh download, verify, extract into .build/src
scripts/build-libffi.sh  static libffi (auto-called by build-lwjgl.sh)
scripts/build-lwjgl.sh   liblwjgl, opengl, stb, vma
scripts/build-freetype.sh
scripts/build-openal.sh
scripts/build-spirv-cross.sh
scripts/build-shaderc.sh
scripts/check-elf.py     16 KB / DT_NEEDED / export gate
scripts/package.py       AAR, zip, manifest, checksums
compat/                  original API-26 shim (the only non-upstream C)
licenses/                every bundled license text
```

Build output is deliberately outside the repository:

| Variable | Default | Contents |
|---|---|---|
| `ECLIPSE_BUILD_DIR` | `.build` | per-ABI object trees and CMake builds |
| `ECLIPSE_SOURCE_DIR` | `.build/src` | extracted, verified sources |
| `ECLIPSE_CACHE_DIR` | `.build/cache` | verified archives |
| `ECLIPSE_OUT_DIR` | `out` | final `jni/<abi>/*.so` and packages |
| `JOBS` | CPU count | parallel make/CMake jobs |

All four are ignored by `.gitignore`. Nothing under them is committed.

## 3. Build one ABI

```bash
export ANDROID_NDK_ROOT=/path/to/android-ndk-r28c

scripts/build-lwjgl.sh arm64-v8a
scripts/build-freetype.sh arm64-v8a
scripts/build-openal.sh arm64-v8a
scripts/build-spirv-cross.sh arm64-v8a
scripts/build-shaderc.sh arm64-v8a
scripts/package.py --require-abi arm64-v8a
```

`build-lwjgl.sh` calls `build-libffi.sh` automatically if
`.build/<abi>/libffi.a` is missing. To build both ABIs, repeat every command
with `x86_64`; `scripts/package.py --require-abi arm64-v8a --require-abi x86_64`
then produces the dual-ABI release.

Every script starts by calling `fetch-sources.sh`, which is idempotent. The
first run downloads all nine archives; later runs reuse the cache after
re-verifying the SHA-256.

## 4. What each build does

### libffi

`configure` with `--host=aarch64-linux-android` (or `x86_64-linux-android`),
`--disable-shared --enable-static`, and:

```text
CFLAGS="-O2 -fPIC -include compat/android_compat.h -DECLIPSE_COMPAT_REDIRECT_MEMFD"
ac_cv_func_memfd_create=yes
```

The cache answer is required because API 26 headers do not declare
`memfd_create`; the shim provides the syscall. The resulting `libffi.a` is
linked into `liblwjgl.so`; it is never shipped as a separate file.

### LWJGL

The recipe mirrors `config/linux/build.xml`:

- core: `main/c/*.c`, `generated/c/*.c`, `generated/c/linux/*.c`, and
  `main/c/linux/liburing/*.c`;
- opengl: all `generated/c/*.c` except `org_lwjgl_opengl_WGL.c`;
- stb: all 11 `generated/c/*.c`;
- vma: the two generated `.cpp` files.

Flags match upstream's `-DLWJGL_LINUX -DLWJGL_<arch>`, plus Android's
`-fPIC`, `-D_GNU_SOURCE`, `-D_FILE_OFFSET_BITS=64`, API 26, and the 16 KB link
flags. The upstream version script is used unchanged. `-Werror` is not enabled:
the NDK's Bionic headers and newer clang produce warnings that upstream's GCC
build does not, and suppressing them with a patch would be worse than accepting
them.

`liblwjgl_vma.so` links libc++ statically and exports only its JNI entry
points. `liblwjgl_opengl.so` has no link-time GL dependency; every GL symbol is
resolved at runtime through `dlsym`.

### FreeType

CMake shared build with all optional dependencies off:

```text
BUILD_SHARED_LIBS=ON
FT_DISABLE_ZLIB=TRUE
FT_DISABLE_BZIP2=TRUE
FT_DISABLE_PNG=TRUE
FT_DISABLE_HARFBUZZ=TRUE
FT_DISABLE_BROTLI=TRUE
```

The result is `libfreetype.so` with only libc/libm dependencies.

### OpenAL Soft

CMake shared build with the official OpenSL ES backend:

```text
LIBTYPE=SHARED
ALSOFT_BACKEND_OPENSL=ON
ALSOFT_REQUIRE_OPENSL=ON
```

Every other backend is explicitly off, including Oboe, PortAudio, SDL2 and
SDL3. `ALSOFT_EMBED_HRTF_DATA=ON` keeps the HRTF tables inside the library so
the app does not have to install a data directory. The output is
`libopenal.so`; it is not linked into any other library.

### SPIRV-Cross

`SPIRV_CROSS_SHARED=ON`, CLI/tests/install off. The upstream target is
`spirv-cross-c-shared`; the script copies it to `libspirv-cross.so` and leaves
the internal SONAME alone. All backends stay enabled because LWJGL's `Spvc`
class resolves the whole `spvc_*` surface during class initialisation.

### Shaderc

Shaderc's `third_party/` directory is populated with symlinks:

```text
.build/src/shaderc/third_party/glslang       -> .build/src/glslang
.build/src/shaderc/third_party/spirv-tools   -> .build/src/spirv-tools
.build/src/shaderc/third_party/spirv-headers -> .build/src/spirv-headers
```

The script also passes `-DSPIRV-Headers_SOURCE_DIR=<...>/spirv-headers` so that
`libshaderc` and SPIRV-Tools see the headers even though the CMake project
scopes differ. Tests, examples, executables, installation, copyright checks and
`-Werror` are off. `glslang`, `SPIRV-Tools` and `SPIRV-Headers` are compiled
from their own pinned trees, not from bundled copies.

## 5. Packaging

`scripts/package.py`:

1. Ensures each required ABI has exactly the eight expected `.so` files.
2. Re-runs `check-elf.py` on the packaged set.
3. Writes `eclipsenatives-<version>.aar` with
   `jni/<abi>/*.so`, `assets/licenses/*`, `assets/eclipsenatives/BUILD-MANIFEST.json`
   and a minimal manifest.
4. Writes `eclipsenatives-<version>.zip` with the same payload plus
   `BUILD-MANIFEST.json` and `SHA256SUMS.txt`.
5. Writes the standalone `BUILD-MANIFEST.json` and outer `SHA256SUMS.txt`.

The version comes from the top-level `version` field in `sources.lock.json`.
The packaging is deterministic apart from the `builtAt` timestamp (use
`SOURCE_DATE_EPOCH` to pin it) and the commit field.

## 6. Updating a pin

1. Identify the new upstream tag/commit and its license.
2. Download the archive from the upstream project's own URL.
3. Compute `sha256sum` and confirm the value independently (release page,
   signed tag, or a second network path).
4. Update the entry in `sources.lock.json` (URL, SHA-256, version, license).
5. If the license changed, update `licenses/` and `PROVENANCE.md`.
6. Open a pull request. CI must rebuild both ABIs and pass the ELF gate before
   the pin is merged.

Do not use GitHub's auto-generated archive URL for a moving branch. All current
URLs are commit-addressed `codeload.github.com` archives or the official libffi
release asset. If upstream ever regenerates an archive, the build fails with a
hash mismatch; that is intentional.

## 7. CI

`.github/workflows/native.yml` runs on:

- pushes to `main` that touch sources, scripts, compat, licenses or workflows;
- pull requests with the same path filter;
- `workflow_dispatch`;
- `workflow_call` (used by the release workflow).

It has one `build` matrix job per ABI and a `package` job that downloads both
ABIs' artifacts, runs `package.py`, and uploads the AAR/zip/manifest/checksums.
A tag push alone does not trigger `native.yml`; tags are handled by
`release.yml`, which calls the reusable workflow and then publishes the
artifacts. This avoids the GitHub Actions rule that a `paths` filter can
suppress a tag-triggered run.

## 8. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `hash mismatch` | upstream archive changed, or the lock is wrong. Do not bypass. |
| `missing NDK tool` | `ANDROID_NDK_ROOT` points at the wrong NDK; r28c is required. |
| `undefined symbol: memfd_create` | libffi was configured without `ac_cv_func_memfd_create=yes`, or the compat header was not force-included. |
| `undefined symbol: aligned_alloc` | a LWJGL translation unit that references it was built without `-DECLIPSE_COMPAT_REDIRECT_ALLOC`. |
| `SPIRV-Headers was not found` | the symlink or `-DSPIRV-Headers_SOURCE_DIR` is missing. |
| `PT_LOAD p_align=0x1000` | the link line lost `-Wl,-z,max-page-size=16384`. |
| `DT_NEEDED on libc++_shared.so` | a CMake target ignored `ANDROID_STL=c++_static`. |
| `DT_NEEDED on libGL.so` | a desktop GL link leaked in; OpenGL must be dlsym-only. |
| `GNU_RELRO ends at ... not 16 KB aligned` | warning only; the hard RELRO check still runs. |
| Shaderc build OOM | lower `JOBS`; Shaderc/glslang is the memory peak. |
| CMake picks the wrong compiler | always pass the NDK toolchain file; `lib.sh` does. |

## 9. Release

```bash
git tag native-v0.1.0
git push origin native-v0.1.0
```

`release.yml` verifies that the tag matches `native-v<lock version>`, calls
`native.yml`, downloads the package artifact, and creates the GitHub Release
with `gh release create --verify-tag`. The release notes link to
`BUILD-MANIFEST.json` and `SHA256SUMS.txt`; consumers must verify both before
using the AAR.
