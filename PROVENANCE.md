# Provenance and licensing ledger

This file records what EclipseNatives actually contains, where every byte of
third-party code came from, and which license applies to it. It is written to
be auditable without trusting the build scripts: each source archive is pinned
by SHA-256 in [`sources.lock.json`](sources.lock.json), and every compiled file
is listed below by module.

## 1. Scope of original code

The original code in this repository is limited to:

| Path | Purpose | License |
|---|---|---|
| `scripts/*.sh`, `scripts/*.py` | fetch, build, verify and package | Apache-2.0 |
| `compat/android_compat.{c,h}` | API-26 shims for two libc functions | Apache-2.0 |
| `docs/*.md`, `README.md`, `PROVENANCE.md`, `NOTICE` | documentation | Apache-2.0 |
| `.github/workflows/*.yml` | CI definition | Apache-2.0 |

No source file inside any upstream archive is edited, patched or replaced.
There is no patch directory, no `sed` against library source, and no vendored
fork. Everything Android-specific is expressed as compiler/linker flags,
CMake options, an autoconf cache answer, or the force-included compatibility
header described in §4.

The Java bindings that consume these libraries are the unmodified LWJGL 3.4.3
artifacts; the generated C sources in `modules/lwjgl/*/src/generated/c` are
upstream-generated files, compiled as shipped.

## 2. Pinned sources

Every archive is downloaded from the upstream project's own GitHub repository
(or its official release asset) and checked against the SHA-256 below before
extraction. A mismatch stops the build.

| Key | Upstream | Pin | Archive SHA-256 | License |
|---|---|---|---|---|
| `lwjgl` | https://github.com/LWJGL/lwjgl3 | `30fac9b95f99cda97312232be25ba55297bf9951` (3.4.3) | `db97020d78fb6f6086121fba9c99ac07a50c4188a7658b06d488a2eae021de40` | BSD-3-Clause |
| `libffi` | https://github.com/libffi/libffi | `v3.8.0` | `7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4` | MIT |
| `freetype` | https://github.com/freetype/freetype | `0a0221a1347e2f1e07c395263540026e9a0aa7c7` (2.14.3) | `11cd478953fc1d382f20a233b8e2aed6c31b47cbf0568c4bdb3334bcc1550698` | FTL or GPL-2.0-or-later |
| `openal` | https://github.com/kcat/openal-soft | `7f9c6de1162b1d4604b9a2f8bcd6c53021566221` (1.25.1) | `a6423b0efd2fee3d7d07c169388e7bf453aab5d5b57fb9bc335d970b7e44e397` | LGPL-2.0-or-later |
| `shaderc` | https://github.com/google/shaderc | `2c8cae778eec0283b44acbe7ed1a386865d78799` (v2026.3) | `e6d6492a363cdef271e466f67cae3ad0d48f7e748491b8e2fe51424c08e391ad` | Apache-2.0 |
| `glslang` | https://github.com/KhronosGroup/glslang | `168d452a4f460d24b588fed08477a81c44ee27a1` | `c167b2474af06cbab93abae8249efaf88fb79a09f30488e2a24d399e4258ce7a` | BSD-3-Clause, Apache-2.0, MIT |
| `spirv-tools` | https://github.com/KhronosGroup/SPIRV-Tools | `b707790a898e44038547df54580022fc1cf89c3d` | `05d8af89737bde57571c48dbd36714c9f520a69623e14de72c3be6b600e277d6` | Apache-2.0 |
| `spirv-headers` | https://github.com/KhronosGroup/SPIRV-Headers | `29981f65241605e08b0ede4cfeb999fe3b723c6a` | `232899f1ad4104fb5bc377b94596c7621575eee62ad9a9e8f929b63a7dd8a7ad` | Apache-2.0 and MIT |
| `spirv-cross` | https://github.com/KhronosGroup/SPIRV-Cross | `6c09849fe88c48eaed08413aa022aaa136a3a057` (vulkan-sdk-1.4.357.0) | `b81b9956289950570953738e666a031ca32ff64e4fc925eba89f227c42109518` | Apache-2.0 |

The Shaderc, glslang, SPIRV-Tools and SPIRV-Headers pins are the exact
revisions in Shaderc v2026.3's `DEPS` file, not arbitrary newer commits.

## 3. What each shared library contains

### `liblwjgl.so`

Source: `modules/lwjgl/core/src`

| Source set | Files | Origin |
|---|---|---|
| `main/c/*.c` | 5 files (`common_tools.c`, `org_lwjgl_system_MemoryUtil.c`, `org_lwjgl_system_SharedLibraryUtil.c`, `org_lwjgl_system_ThreadLocalUtil.c`, `org_lwjgl_system_Upcalls.c`) | LWJGL |
| `main/c/linux/*` | `LinuxConfig.h` | LWJGL |
| `main/c/linux/liburing/*.c` | `queue.c`, `register.c`, `setup.c`, `syscall.c`, `version.c` | liburing, bundled by LWJGL, MIT |
| `generated/c/*.c` | JNI wrappers for JNI, memory access, libc, libffi | LWJGL-generated |
| `generated/c/linux/*.c` | JNI wrappers for `dl`, `fcntl`, `mman`, pthread, sockets, `stat`, `uio`, `unistd`, io_uring | LWJGL-generated |
| `main/c/libffi/` | vendored `ffi.h` and per-architecture `ffitarget.h` only | libffi headers, MIT |
| external `libffi.a` | linked into the shared object | libffi 3.8.0, MIT |

`miniz` is present in the LWJGL tree at `main/c/dependencies/miniz` but is **not**
compiled: the upstream core recipe only includes `main/c/*.c`, `generated/c/*.c`
and the liburing directory. EclipseNatives matches that recipe, so no miniz code
is shipped. The same applies to `jawt` (disabled in the upstream build) and to
LWJGL modules that Minecraft does not load.

### `liblwjgl_opengl.so`

Source: `modules/lwjgl/opengl/src` — 194 generated `.c` files (the WGL wrapper
is excluded, exactly as in `config/linux/build.xml`). The library only wraps
GL/GLES entry points; it resolves them with `dlsym`, so it has no link-time
dependency on `libGL.so`.

### `liblwjgl_stb.so`

Source: `modules/lwjgl/stb/src` — 11 generated `.c` files, each compiling an
upstream `stb_*` implementation. The stb code is MIT or public domain; the MIT
option is recorded in `licenses/stb.txt`.

### `liblwjgl_vma.so`

Source: `modules/lwjgl/vma/src/generated/c` — `org_lwjgl_util_vma_Vma.cpp` and
`org_lwjgl_util_vma_LibVma.cpp`. VMA is MIT. The Vulkan headers used at compile
time come from `modules/lwjgl/vulkan/src/main/c` (Khronos Apache-2.0/MIT); no
Vulkan loader is linked.

### `libfreetype.so`

Source: FreeType 2.14.3. Only FreeType itself is compiled. Zlib, BZip2, PNG,
HarfBuzz and Brotli support are disabled, so no additional library is bundled.
The FTL is elected from FreeType's FTL/GPL-2.0-or-later dual license; the
required credit is in `NOTICE`.

### `libopenal.so`

Source: OpenAL Soft 1.25.1 (`7f9c6de`). The official OpenSL ES backend is the
only output backend. PipeWire, PulseAudio, ALSA, OSS, sndio, JACK, Oboe,
PortAudio, SDL2, SDL3 and the WAV writer are disabled. PFFFT is embedded by
OpenAL for its resampler; its notice is in `licenses/pffft.txt`.

### `libshaderc.so`

Source: Shaderc v2026.3 plus the pinned glslang, SPIRV-Tools and SPIRV-Headers
trees. The upstream `third_party/` layout is recreated with symlinks to those
verified trees, so no source is copied or modified. glslang, SPIRV-Tools and
SPIRV-Headers retain their own licenses; see `licenses/glslang.txt`,
`licenses/spirv-tools.txt`, `licenses/spirv-headers.txt` and
`licenses/khronos-vulkan.txt`. Tests, examples, command-line tools and install
rules are disabled.

### `libspirv-cross.so`

Source: SPIRV-Cross `6c09849`. All target backends (GLSL, HLSL, MSL, C++, JSON
reflection) remain enabled because LWJGL's generated `Spvc` class resolves every
public `spvc_*` symbol during class initialisation. The upstream CMake target
`spirv-cross-c-shared` is renamed at copy time to `libspirv-cross.so`, the name
the LWJGL binding asks for. The ELF SONAME still says
`libspirv-cross-c-shared.so.0`; the library is only ever opened by absolute
path, so the mismatch cannot affect dynamic linking. No file content is
changed.

FreeType and OpenAL are handled the same way: their versioned CMake outputs are
copied to `libfreetype.so` and `libopenal.so`, and their internal SONAMEs keep
the upstream versioned names. Both are loaded by absolute path, so the filename
seen by the app and the SONAME recorded in the ELF do not need to agree.

## 4. The only non-upstream code: `compat/android_compat.c`

API 26 is the app's minimum. Two libc entry points used by the upstream sources
were added later:

| Symbol | Android API | Consumer | Shim |
|---|---|---|---|
| `memfd_create` | 30 | libffi closure trampolines | `syscall(__NR_memfd_create, ...)` |
| `aligned_alloc` | 28 | `org_lwjgl_system_MemoryAccessJNI.c`, `org_lwjgl_system_libc_LibCStdlib.c`, and the allocator setup in `org_lwjgl_stb_LibSTB.c` / `org_lwjgl_util_vma_LibVma.cpp` | `posix_memalign` wrapper |

Why the memfd path is mandatory: Android mounts `/data` `noexec` and has no
`/dev/shm`, so libffi's temporary-file trampoline paths cannot work. libffi's
`configure` probe is answered with `ac_cv_func_memfd_create=yes`; the
force-included header redirects the call to the shim. This is an autoconf cache
answer plus a macro, not a source patch. `MFD_CLOEXEC` is defined because API 26
headers predate it.

The `aligned_alloc` macro is enabled only for the two core units that call it
directly and for the stb/VMA modules whose allocator setup references it. It is
not applied globally: doing so would also rewrite the parameter name
`aligned_alloc` in LWJGL's `lwjgl_malloc.h`. That rename is harmless for JNI
(parameter names are not part of the contract), but a narrow opt-in keeps the
generated code comparable with upstream.

`-include compat/android_compat.h` is passed to the compiler; the upstream file
on disk is untouched. The resulting `eclipse_*` symbols are local to
`liblwjgl.so` (the version script hides everything that does not match
`*org_lwjgl_*` or `JNI_On*`).

## 5. Build configuration that differs from desktop Linux

These are the only differences from upstream's `config/linux/build.xml` and
upstream CMake defaults. Each is a flag or an option, not a source change.

| Area | Desktop upstream | EclipseNatives Android |
|---|---|---|
| Toolchain | GCC/glibc | NDK r28c clang, Bionic, API 26 |
| C standard | `gnu11` | `gnu11` |
| C++ standard | `gnu++2a` | `gnu++17` (enough for VMA/Shaderc/SPIRV-Cross) |
| Optimization | `-O3 -flto=auto` | `-O2`, no LTO |
| Page size | linker default (4 KB) | `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384` |
| C++ runtime | system libstdc++ | static libc++ (`c++_static` / `-static-libstdc++`) |
| Exported symbols (LWJGL) | upstream version script | same upstream `config/linux/version.script` |
| Exported symbols (CMake) | default visibility | `-Wl,--exclude-libs,ALL` |
| PIC | `-fPIC` | `-fPIC` plus `CMAKE_POSITION_INDEPENDENT_CODE=ON` |
| Undefined symbols | `--no-undefined` | `--no-undefined` |
| `memfd_create` | glibc, API independent | shim on API < 30 |
| `aligned_alloc` | glibc | shim on API < 28 |
| OpenAL backend | many desktop backends | OpenSL ES only |
| Shaderc CMake | builds CLI/tests/examples | all skipped |
| SPIRV-Cross output | `libspirv-cross-c-shared.so` | copied to `libspirv-cross.so` |
| libffi | shared system library | static 3.8.0 linked into `liblwjgl.so` |

No linker namespace bypass, no `libGL.so`/`libEGL.so` shim, no Turnip/Zink, no
prebuilt driver blob and no `DT_RPATH`/`DT_RUNPATH` are used. The ELF gate in
`scripts/check-elf.py` enforces the last point and restricts `DT_NEEDED` to
platform libraries.

## 6. License obligations

| Component | License | How the obligation is met |
|---|---|---|
| Original scripts, shim, docs | Apache-2.0 | `LICENSE`, source headers where applicable |
| LWJGL, stb, VMA, liburing | BSD-3 / MIT / MIT / MIT | `licenses/lwjgl.txt`, `licenses/stb.txt`, `licenses/vma.txt`, `licenses/liburing.txt`; notices retained |
| libffi | MIT | `licenses/libffi.txt` |
| FreeType | FTL (elected) | `licenses/freetype-FTL.txt`, `licenses/freetype.txt`, credit in `NOTICE` |
| OpenAL Soft | LGPL-2.0-or-later | shared object, `licenses/openal-lgpl-2.0.txt`, complete source and build scripts identified here; users may relink |
| Shaderc, SPIRV-Tools, SPIRV-Cross | Apache-2.0 | `licenses/shaderc-apache-2.0.txt`, `licenses/spirv-tools.txt`, `licenses/spirv-cross.txt` |
| glslang | BSD-3/Apache-2.0/MIT | `licenses/glslang.txt` |
| SPIRV-Headers | Apache-2.0/MIT | `licenses/spirv-headers.txt`, `licenses/khronos-vulkan.txt` |
| libc++ / libc++abi / libunwind | Apache-2.0 WITH LLVM-exception | `licenses/libcxx.txt` |
| PFFFT (in OpenAL) | BSD-style | `licenses/pffft.txt` |

OpenAL is the only LGPL component. It is distributed only as
`jni/<abi>/libopenal.so`, dynamically loaded by the app; it is not statically
linked into `liblwjgl.so` or into the app's Java code. The exact source archive,
its SHA-256, the build flags and the scripts that produce the binary are in this
repository, which satisfies the LGPL's source-availability and relinking
requirements without distributing a modified library.

## 7. Verification and reproducibility

Two independent checks apply to every release:

1. **Source integrity** — `scripts/fetch-sources.sh` verifies each archive
   against `sources.lock.json` before extraction. The lock is reviewed and
   changed only when an upstream pin is deliberately updated.
2. **Binary structure** — `scripts/check-elf.py` checks ELF class/machine,
   16 KB `PT_LOAD` alignment, RELRO coverage, executable stack, `DT_TEXTREL`,
   `DT_RPATH`/`DT_RUNPATH`, the `DT_NEEDED` allowlist, and the presence of the
   entry points each consumer resolves. `scripts/package.py` re-runs the gate
   on the packaged set and asserts that exactly eight libraries exist per ABI.

`BUILD-MANIFEST.json` records the source pins, the NDK version, the commit,
per-library sizes and SHA-256 values. It is attached to the release and copied
into the AAR's assets. `SHA256SUMS.txt` covers the AAR, the zip and the
manifest.

Reproducibility caveat: the build is deterministic with respect to the pinned
sources, flags and NDK, and the archive writer fixes timestamps. Clang and the
NDK are not bit-reproducible across arbitrary versions, so a hash comparison is
only meaningful against the exact NDK in the manifest. The release workflow
builds both ABIs from the same commit and records that commit.

## 8. Trademarks and game files

Eclipse Launcher is an independent project. It is not affiliated with,
endorsed by, or sponsored by the Eclipse Foundation. "Eclipse" is a registered
trademark of the Eclipse Foundation.

Minecraft is a trademark of Mojang Synergies AB. EclipseNatives contains no
Minecraft code, assets or metadata. It only provides Android builds of general
purpose libraries that a Java Edition runtime needs.

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR
MICROSOFT.
