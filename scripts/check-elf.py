#!/usr/bin/env python3
"""Structural gate for an EclipseNatives Android shared library.

Checks, in order of importance:

  1. ELF identity: 64-bit, ET_DYN, machine matching the requested ABI.
  2. 16 KB segments: every PT_LOAD must have p_align >= 0x4000 and satisfy
     (p_vaddr - p_offset) % p_align == 0. Both are enforced by a 16 KB kernel.
  3. RELRO sanity: page-rounding must not put writable memory outside RELRO.
     A RELRO end that is not 16 KB aligned is a warning, matching the app gate.
  4. Executable stack and DT_TEXTREL are rejected.
  5. No DT_RPATH / DT_RUNPATH (Android ignores them and they hide packaging bugs).
  6. DT_NEEDED is restricted to platform libraries. In particular
     libc++_shared.so must never appear: every C++ component here statically
     links libc++ so the app does not have to ship another runtime.
  7. Each library exports the entry points its consumer dlsym()s.

Usage:
  check-elf.py --abi arm64-v8a out/jni/arm64-v8a/*.so
  check-elf.py out/jni/x86_64/liblwjgl.so        # machine inferred from --abi=any

Exit: 0 pass, 1 failure, 2 usage. Warnings never change the exit code.
"""
from __future__ import annotations

import argparse
import pathlib
import struct
import sys

PT_LOAD = 1
PT_DYNAMIC = 2
PT_GNU_RELRO = 0x6474E552
PT_GNU_STACK = 0x6474E551
PF_X = 0x1
PF_W = 0x2
PAGE_16K = 0x4000

ET_DYN = 3
EM_AARCH64 = 183
EM_X86_64 = 62

SHT_DYNSYM = 11
SHN_UNDEF = 0
STB_GLOBAL = 1
STB_WEAK = 2

DT_NULL = 0
DT_NEEDED = 1
DT_STRTAB = 5
DT_RPATH = 15
DT_TEXTREL = 22
DT_RUNPATH = 29
DT_FLAGS = 30
DF_TEXTREL = 0x4

ELF_MAGIC = b"\x7fELF"
ELFCLASS64 = 2

ALLOWED_NEEDED = {
    "libc.so",
    "libm.so",
    "libdl.so",
    "liblog.so",
    "libandroid.so",
    "libOpenSLES.so",
    "libz.so",
}

# basename -> (description, [required exported symbols])
EXPORTS = {
    "liblwjgl.so": (
        "LWJGL core JNI",
        ["JNI_OnLoad", "Java_org_lwjgl_system_jni_JNINativeInterface_nGetJavaVM"],
    ),
    "liblwjgl_opengl.so": ("LWJGL OpenGL JNI", ["Java_org_lwjgl_opengl_GL11C_glClear"]),
    "liblwjgl_stb.so": ("LWJGL stb JNI", ["Java_org_lwjgl_stb_STBImage_nstbi_1image_1free"]),
    "liblwjgl_vma.so": ("LWJGL VMA JNI", ["Java_org_lwjgl_util_vma_Vma_nvmaCreateAllocator"]),
    "libfreetype.so": ("FreeType", ["FT_Init_FreeType"]),
    "libopenal.so": ("OpenAL Soft", ["alcOpenDevice", "alGetError"]),
    "libshaderc.so": ("Shaderc", ["shaderc_compile_into_spv", "shaderc_compiler_initialize"]),
    "libspirv-cross.so": ("SPIRV-Cross C API", ["spvc_get_version", "spvc_context_create"]),
}


class Elf:
    def __init__(self, data: bytes) -> None:
        if len(data) < 64 or data[:4] != ELF_MAGIC:
            raise ValueError("not an ELF file")
        self.data = data
        self.elf_class = data[4]
        self.endian = "<" if data[5] == 1 else ">"
        if self.elf_class != ELFCLASS64:
            raise ValueError(f"expected 64-bit ELF, got class {self.elf_class}")
        self.machine = struct.unpack_from(self.endian + "H", data, 0x12)[0]
        self.etype = struct.unpack_from(self.endian + "H", data, 0x10)[0]

        e_phoff = struct.unpack_from(self.endian + "Q", data, 0x20)[0]
        e_phentsize = struct.unpack_from(self.endian + "H", data, 0x36)[0]
        e_phnum = struct.unpack_from(self.endian + "H", data, 0x38)[0]
        e_shoff = struct.unpack_from(self.endian + "Q", data, 0x28)[0]
        e_shentsize = struct.unpack_from(self.endian + "H", data, 0x3A)[0]
        e_shnum = struct.unpack_from(self.endian + "H", data, 0x3C)[0]

        if e_phnum and e_phoff + e_phnum * e_phentsize > len(data):
            raise ValueError("truncated program header table")
        if e_shnum and e_shoff + e_shnum * e_shentsize > len(data):
            raise ValueError("truncated section header table")

        self.program_headers = []
        for index in range(e_phnum):
            offset = e_phoff + index * e_phentsize
            header = {
                "type": struct.unpack_from(self.endian + "I", data, offset)[0],
                "flags": struct.unpack_from(self.endian + "I", data, offset + 4)[0],
                "offset": struct.unpack_from(self.endian + "Q", data, offset + 8)[0],
                "vaddr": struct.unpack_from(self.endian + "Q", data, offset + 16)[0],
                "filesz": struct.unpack_from(self.endian + "Q", data, offset + 32)[0],
                "memsz": struct.unpack_from(self.endian + "Q", data, offset + 40)[0],
                "align": struct.unpack_from(self.endian + "Q", data, offset + 48)[0],
            }
            self.program_headers.append(header)

        self.sections = []
        for index in range(e_shnum):
            offset = e_shoff + index * e_shentsize
            self.sections.append(
                {
                    "name": struct.unpack_from(self.endian + "I", data, offset)[0],
                    "type": struct.unpack_from(self.endian + "I", data, offset + 4)[0],
                    "offset": struct.unpack_from(self.endian + "Q", data, offset + 24)[0],
                    "size": struct.unpack_from(self.endian + "Q", data, offset + 32)[0],
                    "link": struct.unpack_from(self.endian + "I", data, offset + 40)[0],
                    "entsize": struct.unpack_from(self.endian + "Q", data, offset + 56)[0],
                }
            )

    def vaddr_to_offset(self, address: int) -> int:
        for header in self.program_headers:
            if header["type"] == PT_LOAD and header["vaddr"] <= address < header["vaddr"] + header["filesz"]:
                return header["offset"] + (address - header["vaddr"])
        raise ValueError(f"address 0x{address:x} is not inside a file-backed segment")

    def dynamic_entries(self) -> list[tuple[int, int]]:
        dynamic = [header for header in self.program_headers if header["type"] == PT_DYNAMIC]
        if not dynamic:
            return []
        offset = dynamic[0]["offset"]
        entries = []
        while offset + 16 <= len(self.data):
            tag, value = struct.unpack_from(self.endian + "QQ", self.data, offset)
            entries.append((tag, value))
            offset += 16
            if tag == DT_NULL:
                break
        return entries

    def dynamic_strings(self) -> list[str]:
        entries = self.dynamic_entries()
        strtab = next((value for tag, value in entries if tag == DT_STRTAB), None)
        if strtab is None:
            return []
        base = self.vaddr_to_offset(strtab)
        strings: list[str] = []
        for tag, value in entries:
            if tag != DT_NEEDED:
                continue
            end = self.data.find(b"\0", base + value)
            strings.append(self.data[base + value : end].decode("utf-8", "replace"))
        return strings

    def exported_symbols(self) -> set[str]:
        symbols: set[str] = set()
        for section in self.sections:
            if section["type"] != SHT_DYNSYM or section["entsize"] == 0:
                continue
            strtab = self.sections[section["link"]]
            strings = self.data[strtab["offset"] : strtab["offset"] + strtab["size"]]
            count = section["size"] // section["entsize"]
            for index in range(count):
                offset = section["offset"] + index * section["entsize"]
                name_offset = struct.unpack_from(self.endian + "I", self.data, offset)[0]
                info = self.data[offset + 4]
                shndx = struct.unpack_from(self.endian + "H", self.data, offset + 6)[0]
                bind = info >> 4
                if shndx == SHN_UNDEF or bind not in (STB_GLOBAL, STB_WEAK):
                    continue
                end = strings.find(b"\0", name_offset)
                if end < 0:
                    continue
                symbol = strings[name_offset:end].decode("utf-8", "replace")
                if symbol:
                    symbols.add(symbol)
        return symbols


def check(name: str, data: bytes, abi: str) -> tuple[list[str], list[str]]:
    failures: list[str] = []
    warnings: list[str] = []

    try:
        elf = Elf(data)
    except Exception as exc:  # noqa: BLE001
        return [f"{name}: {exc}"], []

    if elf.etype != ET_DYN:
        failures.append(f"{name}: e_type={elf.etype}, expected ET_DYN (3)")

    expected_machine = {"arm64-v8a": EM_AARCH64, "x86_64": EM_X86_64}.get(abi)
    if expected_machine is not None and elf.machine != expected_machine:
        failures.append(f"{name}: e_machine={elf.machine}, expected {expected_machine} for {abi}")

    loads = [header for header in elf.program_headers if header["type"] == PT_LOAD]
    if not loads:
        failures.append(f"{name}: no PT_LOAD segments")
    for header in loads:
        align = header["align"]
        if align < PAGE_16K:
            failures.append(
                f"{name}: PT_LOAD p_align=0x{align:x} (< 0x4000)"
            )
            continue
        if (header["vaddr"] - header["offset"]) % align != 0:
            failures.append(
                f"{name}: PT_LOAD vaddr 0x{header['vaddr']:x} and offset "
                f"0x{header['offset']:x} are incongruent modulo 0x{align:x}"
            )

    relro = [header for header in elf.program_headers if header["type"] == PT_GNU_RELRO]
    writable = [header for header in loads if header["flags"] & PF_W]
    for segment in relro:
        start = segment["vaddr"]
        end = start + segment["memsz"]
        protected_start = start & ~(PAGE_16K - 1)
        protected_end = (end + PAGE_16K - 1) & ~(PAGE_16K - 1)
        if end % PAGE_16K != 0:
            warnings.append(
                f"{name}: GNU_RELRO ends at 0x{end:x}, not 16 KB aligned "
                f"(mprotect spans 0x{protected_end:x})"
            )
        for header in writable:
            memory_start = header["vaddr"]
            memory_end = memory_start + header["memsz"]
            guarded = max(0, min(memory_end, protected_end) - max(memory_start, protected_start))
            inside = max(0, min(memory_end, end) - max(memory_start, start))
            if guarded > inside:
                failures.append(
                    f"{name}: RELRO rounding 0x{protected_start:x}-0x{protected_end:x} "
                    f"covers writable memory 0x{memory_start:x}-0x{memory_end:x}"
                )

    stack = [header for header in elf.program_headers if header["type"] == PT_GNU_STACK]
    if stack and stack[0]["flags"] & PF_X:
        failures.append(f"{name}: executable stack (PT_GNU_STACK has PF_X)")

    entries = elf.dynamic_entries()
    if any(tag == DT_TEXTREL for tag, _ in entries) or any(
        tag == DT_FLAGS and value & DF_TEXTREL for tag, value in entries
    ):
        failures.append(f"{name}: DT_TEXTREL is set (text relocations break W^X)")
    if any(tag in (DT_RPATH, DT_RUNPATH) for tag, _ in entries):
        failures.append(f"{name}: DT_RPATH/DT_RUNPATH is set")

    if not entries:
        failures.append(f"{name}: no PT_DYNAMIC segment")

    for needed in elf.dynamic_strings():
        if needed not in ALLOWED_NEEDED:
            failures.append(f"{name}: DT_NEEDED on {needed!r} (not a platform library)")

    base = pathlib.Path(name).name
    function, required = EXPORTS.get(base, (None, []))
    if required:
        exported = elf.exported_symbols()
        missing = [symbol for symbol in required if symbol not in exported]
        if missing:
            failures.append(f"{name}: missing exported symbol(s): {', '.join(missing)}")

    return failures, warnings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--abi", default="any", choices=["arm64-v8a", "x86_64", "any"])
    parser.add_argument("--quiet-warnings", action="store_true")
    parser.add_argument("paths", nargs="+", type=pathlib.Path)
    args = parser.parse_args()

    failures: list[str] = []
    warnings: list[str] = []
    checked = 0

    for path in args.paths:
        if not path.is_file():
            failures.append(f"{path}: not a file")
            continue
        found, warned = check(str(path), path.read_bytes(), args.abi)
        failures.extend(found)
        warnings.extend(warned)
        checked += 1

    if warnings and not args.quiet_warnings:
        for warning in warnings:
            print("WARN " + warning, file=sys.stderr)
    for failure in failures:
        print("FAIL " + failure, file=sys.stderr)

    if failures:
        print(
            f"ELF gate: {len(failures)} failure(s), {len(warnings)} warning(s)",
            file=sys.stderr,
        )
        return 1

    print(f"ELF gate: passed ({checked} library/ies, {len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
