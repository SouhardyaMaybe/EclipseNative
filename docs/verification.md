# Verification

EclipseNatives has no on-device test in CI. CI proves that the sources are the
pinned ones, that the binaries are structurally valid for Android, that only
platform libraries are needed, and that the expected JNI entry points exist. The
gaps are listed honestly in §6.

## 1. Source verification

`scripts/fetch-sources.sh` is the only downloader. For every source it:

1. Reads `url`, `sha256`, `root` and `version` from `sources.lock.json`.
2. Reuses `.build/cache/<name>-<sha>.tar.gz` only if its SHA-256 matches.
3. Downloads with `curl -fsSL --retry 4` otherwise.
4. Verifies the archive again with `sha256sum -c`.
5. Extracts with `tar --strip-components=1 --no-same-owner`.
6. Writes a marker containing the digest; a lock change forces re-extraction.

There is no `git clone`, no submodule, no `latest` URL and no network access
after extraction. `scripts/lock.py --check` enforces schema 1, HTTPS URLs,
lowercase 64-hex digests and the presence of every required field.

## 2. Binary verification: `scripts/check-elf.py`

The gate runs after every link and again inside `package.py`. It fails a release
for any of the following.

| Check | Why it is fatal |
|---|---|
| Not 64-bit ELF, not `ET_DYN` | Android will not map it as a shared object. |
| Wrong `e_machine` for the ABI | `arm64-v8a` requires `EM_AARCH64` (183), `x86_64` requires `EM_X86_64` (62). |
| `PT_LOAD p_align < 0x4000` | A 16 KB-page kernel cannot map the segment. |
| `(p_vaddr - p_offset) % p_align != 0` | The segment is not congruent; the loader rejects it. |
| RELRO page-rounding covers writable memory outside RELRO | The linker makes live writable data read-only and the app crashes. |
| `PT_GNU_STACK` has `PF_X` | Executable stack; blocked by W^X and a security defect. |
| `DT_TEXTREL` / `DF_TEXTREL` | Text relocations break W^X and are rejected by modern Android. |
| `DT_RPATH` or `DT_RUNPATH` | Android ignores it; its presence hides a packaging mistake. |
| `DT_NEEDED` outside the allowlist | The library would need a non-platform dependency. |
| Missing required exported symbol | The Java binding would fail at `dlsym`/class-init time. |
| No `PT_DYNAMIC` | Not a loadable shared object. |

The `DT_NEEDED` allowlist is:

```text
libc.so libm.so libdl.so liblog.so libandroid.so
libOpenSLES.so libz.so
```

In particular `libc++_shared.so`, `libGL.so`, `libEGL.so`, `libvulkan.so`,
`libstdc++.so.6` and `libgcc_s.so.1` are rejected. This is what guarantees that
the app does not have to ship a second C++ runtime or a desktop GL shim.

Required exports per library:

| Library | Symbols checked |
|---|---|
| `liblwjgl.so` | `JNI_OnLoad`, `Java_org_lwjgl_system_jni_JNINativeInterface_nGetJavaVM` |
| `liblwjgl_opengl.so` | `Java_org_lwjgl_opengl_GL11C_glClear` |
| `liblwjgl_stb.so` | `Java_org_lwjgl_stb_STBImage_nstbi_1image_1free` |
| `liblwjgl_vma.so` | `Java_org_lwjgl_util_vma_Vma_nvmaCreateAllocator` |
| `libfreetype.so` | `FT_Init_FreeType` |
| `libopenal.so` | `alcOpenDevice`, `alGetError` |
| `libshaderc.so` | `shaderc_compiler_initialize`, `shaderc_compile_into_spv` |
| `libspirv-cross.so` | `spvc_get_version`, `spvc_context_create` |

The sample is intentionally small: one prominent entry point per library is
enough to catch an empty or stripped-to-nothing artifact. It is not a full ABI
comparison against LWJGL's Java declarations.

### Warnings

A `PT_GNU_RELRO` end that is not 16 KB aligned produces a warning, not a
failure. On Android the `mprotect` then spans the following page; if that page
is unmapped the hardening is skipped with a linker warning, and if it contains
writable data the *hard* RELRO rule above catches the crash condition. Google's
own `androidx.graphics.path` ships in this state, so the warning is visible in
the log but does not block a release. Treat a new warning as a prompt to inspect
the link map, not as noise to ignore.

## 3. Packaging verification

`scripts/package.py` asserts:

- exactly eight `.so` files per required ABI, no extras and no omissions;
- the ELF gate passes on the packaged copies;
- the AAR contains `AndroidManifest.xml`, `R.txt`, the eight libraries, all
  license texts and `assets/eclipsenatives/BUILD-MANIFEST.json`;
- the zip contains the same payload, `BUILD-MANIFEST.json`, `SHA256SUMS.txt`
  and the licenses;
- `SHA256SUMS.txt` covers the AAR, the zip and the manifest;
- the manifest records the exact source pins, NDK version, ABI list, commit,
  per-library size and SHA-256.

To verify a downloaded release by hand:

```bash
sha256sum -c SHA256SUMS.txt
python3 scripts/check-elf.py --abi arm64-v8a \
  $(unzip -Z1 eclipsenatives-0.1.0.aar | grep '^jni/arm64-v8a/.*\.so$')
unzip -l eclipsenatives-0.1.0.aar | grep -E 'AndroidManifest|assets/licenses|jni/'
```

The app's own CI re-runs the 16 KB gate on the final APK, not just on the AAR.
The APK check additionally verifies that uncompressed `.so` entries are aligned
to 16 KB (or that the APK uses `extractNativeLibs=true`, which is the app's
configuration).

## 4. CI gates

`native.yml` has three jobs:

| Job | What it proves |
|---|---|
| `build` (matrix `arm64-v8a`, `x86_64`) | all five recipes compile and link; every `.so` passes `check-elf.py`; per-ABI artifact uploaded |
| `package` | both ABIs present; eight libraries each; AAR/zip/manifest/checksums produced; gate passes again |
| `verify` | re-downloads the packaged artifact; checks `SHA256SUMS.txt`; runs `lock.py --check`; prints `file`/`readelf` summaries |

`release.yml` adds:

- tag/version agreement (`native-v<version>` vs `sources.lock.json`);
- `gh release create --verify-tag`;
- no release if any build, package or verification job failed.

A tag push is never filtered by `paths`; `release.yml` calls the reusable
workflow directly, so a tag cannot silently produce no artifacts.

## 5. What has actually been exercised

At the time of writing, the pipeline is **under construction**. The first green
`Native` run is the evidence that replaces this paragraph. Until then:

- All nine archives have been downloaded and their SHA-256 values recorded.
- The source pins have been checked against LWJGL 3.4.3's `.git` metadata and
  Shaderc v2026.3's `DEPS`.
- The Bionic API levels for the two shimmed functions have been checked
  (`memfd_create` 30, `aligned_alloc` 28).
- The ELF gate logic has been tested against the app's real APKs and against
  LWJGL's published Linux binaries; the Android libraries themselves are not
  built on this machine (no NDK here), so their first real check is CI.

Do not describe a release as "verified" until the `Native`, `Package` and
`Verify` jobs are green for that exact tag.

## 6. Known gaps

| Gap | Consequence | Mitigation |
|---|---|---|
| No on-device run in CI | A structurally valid library can still fail at runtime (missing symbol at a path not exercised, JNI contract mismatch). | Phase 0 spikes install the AAR and boot the JVM; the app's instrumentation suite covers the real load path. |
| No 16 KB hardware or emulator in CI | Only static ELF rules are checked. | The app's manifest gate and a 16 KB emulator job are required before 1.0; `p_align` and congruence are the rules the kernel enforces. |
| No Minecraft run in CI | Shaderc/SPIRV-Cross are checked for exports, not for compiling Minecraft's actual shader corpus. | The launcher's Phase 0 triangle and shader-compile tests run on device with a real `client.jar`. |
| `org.lwjgl.system.linux.Stat` layout | The JNI call works, but glibc's `struct stat` offsets do not match Bionic's. | Documented, not patched. The game does not use this binding. If a future version does, the correct fix is an upstream-compatible Android layout, not a local cast. |
| Static libc++ is not ABI-stable across NDKs | Mixing objects from two NDK versions is unsafe. | Every component in one release is built with the pinned NDK; the manifest records it. |
| OpenSL ES only | AAudio's lower latency is not available in v1. | Official SDL3 AAudio backend is a v1.1 item; no Oboe/FCL fork. |
| No runtime license scanning | A new upstream file could carry a different license than the module's headline license. | The pin review in `docs/build.md` §6 checks the license and updates `licenses/`; the source list is small and audited in `PROVENANCE.md`. |

## 7. Release checklist

- [ ] `scripts/lock.py --check` passes.
- [ ] `sources.lock.json` version matches the tag (`native-v<version>`).
- [ ] Both matrix jobs are green for the tag's commit.
- [ ] `package` is green and the AAR contains both ABIs.
- [ ] `verify` re-checked `SHA256SUMS.txt` and the ELF gate.
- [ ] `BUILD-MANIFEST.json` lists the expected nine sources and eight libraries
      per ABI.
- [ ] `PROVENANCE.md` and `NOTICE` still match the source pins.
- [ ] Release notes state the NDK version and link the manifest.
- [ ] `gh release view native-v<version>` shows the four assets and no
      "draft" flag.
