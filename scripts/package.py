#!/usr/bin/env python3
"""Package the per-ABI native libraries into the release artifacts.

Inputs (produced by the build scripts):
    out/jni/arm64-v8a/*.so
    out/jni/x86_64/*.so

Outputs:
    out/eclipsenatives-<version>.aar   Gradle-consumable Android library
    out/eclipsenatives-<version>.zip   plain bundle for non-Gradle consumers
    out/BUILD-MANIFEST.json           provenance and per-file hashes
    out/SHA256SUMS.txt                hashes of the three files above

The archive is deterministic: entries are sorted, timestamps are fixed and the
manifest is serialised with sorted keys. Only SOURCE_DATE_EPOCH (or the current
time) appears as build metadata, never in the binary payload.

Usage: package.py [--require-abi arm64-v8a --require-abi x86_64]
Exit: 0 success, 1 verification failure, 2 usage.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import pathlib
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCK = ROOT / "sources.lock.json"
OUT = ROOT / "out"
JNI = OUT / "jni"
LICENSES = ROOT / "licenses"

EXPECTED_LIBRARIES = {
    "liblwjgl.so",
    "liblwjgl_opengl.so",
    "liblwjgl_stb.so",
    "liblwjgl_vma.so",
    "libfreetype.so",
    "libopenal.so",
    "libshaderc.so",
    "libspirv-cross.so",
}

FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def zip_entry(archive: zipfile.ZipFile, name: str, data: bytes, *, stored: bool = False) -> None:
    info = zipfile.ZipInfo(name, date_time=FIXED_TIME)
    info.create_system = 3
    info.external_attr = 0o644 << 16
    info.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
    archive.writestr(info, data)


def build_manifest(version: str, abis: list[str], lock: dict) -> dict:
    libraries: dict[str, list[dict]] = {}
    for abi in abis:
        entries = []
        for path in sorted((JNI / abi).glob("*.so")):
            data = path.read_bytes()
            entries.append(
                {
                    "name": path.name,
                    "size": len(data),
                    "sha256": sha256(data),
                }
            )
        libraries[abi] = entries

    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    built_at = (
        subprocess.run(
            ["date", "-u", "-d", f"@{epoch}", "+%Y-%m-%dT%H:%M:%SZ"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if epoch
        else subprocess.run(
            ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], check=True, capture_output=True, text=True
        ).stdout.strip()
    )

    return {
        "schema": 1,
        "component": "EclipseNatives",
        "version": version,
        "commit": os.environ.get("GITHUB_SHA", "unknown"),
        "builtAt": built_at,
        "android": {
            "minSdk": 26,
            "compileApi": 26,
            "ndk": os.environ.get("NDK_VERSION", "28.2.13676358"),
            "abis": abis,
        },
        "libraries": libraries,
        "sources": {
            name: {
                "version": source["version"],
                "sha256": source["sha256"],
                "license": source["license"],
            }
            for name, source in lock["sources"].items()
        },
        "licenses": sorted(path.name for path in LICENSES.glob("*.txt")),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-abi", action="append", default=[])
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    version = lock["version"]
    abis = sorted(
        path.name for path in JNI.iterdir() if path.is_dir()
    ) if JNI.is_dir() else []
    required = sorted(set(args.require_abi)) if args.require_abi else abis
    if not abis:
        print("package: no out/jni/<abi> directories", file=sys.stderr)
        return 1

    failures: list[str] = []
    unexpected_abis = sorted(set(abis) - set(required))
    if unexpected_abis:
        failures.append(f"unexpected ABI directories: {', '.join(unexpected_abis)}")
    for abi in required:
        directory = JNI / abi
        if not directory.is_dir():
            failures.append(f"{abi}: directory missing")
            continue
        present = {path.name for path in directory.glob("*.so")}
        missing = sorted(EXPECTED_LIBRARIES - present)
        extra = sorted(present - EXPECTED_LIBRARIES)
        if missing:
            failures.append(f"{abi}: missing {', '.join(missing)}")
        if extra:
            failures.append(f"{abi}: unexpected {', '.join(extra)}")
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "check-elf.py"),
                "--abi",
                abi,
                *[str(path) for path in sorted(directory.glob("*.so"))],
            ],
            text=True,
        )
        if result.returncode != 0:
            failures.append(f"{abi}: ELF gate failed")

    if failures:
        for failure in failures:
            print("FAIL " + failure, file=sys.stderr)
        return 1

    version_safe = version.replace("/", "-")
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = build_manifest(version, required, lock)
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()

    manifest_xml = b'<?xml version="1.0" encoding="utf-8"?>\n<manifest xmlns:android="http://schemas.android.com/apk/res/android" />\n'
    aar_metadata = (
        "aarFormatVersion=1.0\n"
        "aarMetadataVersion=1.0\n"
        "minCompileSdk=26\n"
        "minCompileSdkExtension=0\n"
        "minAndroidGradlePluginVersion=8.0.0\n"
    ).encode()
    license_files = sorted(LICENSES.glob("*.txt"))

    aar_path = OUT / f"eclipsenatives-{version_safe}.aar"
    empty_jar = io.BytesIO()
    with zipfile.ZipFile(empty_jar, "w"):
        pass
    with zipfile.ZipFile(aar_path, "w") as archive:
        zip_entry(archive, "AndroidManifest.xml", manifest_xml)
        zip_entry(archive, "classes.jar", empty_jar.getvalue())
        zip_entry(archive, "R.txt", b"")
        zip_entry(
            archive,
            "META-INF/com/android/build/gradle/aar-metadata.properties",
            aar_metadata,
        )
        zip_entry(archive, "assets/eclipsenatives/BUILD-MANIFEST.json", manifest_bytes)
        for license_file in license_files:
            zip_entry(
                archive,
                f"assets/licenses/{license_file.name}",
                license_file.read_bytes(),
            )
        for abi in required:
            for library in sorted((JNI / abi).glob("*.so")):
                zip_entry(archive, f"jni/{abi}/{library.name}", library.read_bytes())

    sums: dict[str, str] = {}
    zip_path = OUT / f"eclipsenatives-{version_safe}.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        zip_entry(archive, "BUILD-MANIFEST.json", manifest_bytes)
        for license_file in license_files:
            zip_entry(archive, f"licenses/{license_file.name}", license_file.read_bytes())
        for abi in required:
            for library in sorted((JNI / abi).glob("*.so")):
                data = library.read_bytes()
                sums[f"jni/{abi}/{library.name}"] = sha256(data)
                zip_entry(archive, f"jni/{abi}/{library.name}", data)
        sums["BUILD-MANIFEST.json"] = sha256(manifest_bytes)
        for license_file in license_files:
            sums[f"licenses/{license_file.name}"] = sha256(license_file.read_bytes())
        sums_text = "".join(
            f"{digest}  {name}\n" for name, digest in sorted(sums.items())
        ).encode()
        zip_entry(archive, "SHA256SUMS.txt", sums_text)

    (OUT / "BUILD-MANIFEST.json").write_bytes(manifest_bytes)
    outer_sums = []
    for path in (aar_path, zip_path):
        outer_sums.append(f"{sha256(path.read_bytes())}  {path.name}")
    outer_sums.append(f"{sha256(manifest_bytes)}  BUILD-MANIFEST.json")
    (OUT / "SHA256SUMS.txt").write_text("\n".join(sorted(outer_sums)) + "\n", encoding="utf-8")

    total = sum(
        len(path.read_bytes()) for abi in required for path in (JNI / abi).glob("*.so")
    )
    print(
        f"package: EclipseNatives {version} — {len(required)} ABI(s), "
        f"{len(EXPECTED_LIBRARIES)} libraries each, {total / 1_000_000:.1f} MB of .so"
    )
    for path in (aar_path, zip_path, OUT / "BUILD-MANIFEST.json", OUT / "SHA256SUMS.txt"):
        print(f"  {path.relative_to(ROOT)}  {path.stat().st_size:,} B")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
