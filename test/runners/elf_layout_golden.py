#!/usr/bin/env python3

import argparse
import os
import struct
import sys


ELF_MAGIC = b"\x7fELF"
SHT_NAMES = {
    0: "NULL",
    1: "PROGBITS",
    2: "SYMTAB",
    3: "STRTAB",
    4: "RELA",
    5: "HASH",
    6: "DYNAMIC",
    7: "NOTE",
    8: "NOBITS",
    9: "REL",
    10: "SHLIB",
    11: "DYNSYM",
}
PT_NAMES = {
    0: "NULL",
    1: "LOAD",
    2: "DYNAMIC",
    3: "INTERP",
    4: "NOTE",
    5: "SHLIB",
    6: "PHDR",
    7: "TLS",
    0x6474E551: "GNU_STACK",
}
ET_NAMES = {
    0: "NONE (None)",
    1: "REL (Relocatable file)",
    2: "EXEC (Executable file)",
    3: "DYN (Shared object file)",
    4: "CORE (Core file)",
}
SHF_WRITE = 0x1
SHF_ALLOC = 0x2
SHF_EXECINSTR = 0x4
PF_X = 0x1
PF_W = 0x2
PF_R = 0x4


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("test_dir")
    parser.add_argument("build_dir")
    parser.add_argument("build_config")
    parser.add_argument("bsp")
    return parser.parse_args()


def read_c_string(blob: bytes, offset: int) -> str:
    end = blob.find(b"\x00", offset)
    if end == -1:
        end = len(blob)
    return blob[offset:end].decode("utf-8")


def parse_elf(path: str) -> tuple[dict, list[dict], list[dict]]:
    data = open(path, "rb").read()
    if data[:4] != ELF_MAGIC:
        raise ValueError(f"{path} is not an ELF file")
    if data[4] != 1 or data[5] != 1:
        raise ValueError("only 32-bit little-endian ELF is supported")

    header = struct.unpack_from("<16sHHIIIIIHHHHHH", data, 0)
    elf = {
        "e_type": header[1],
        "e_entry": header[4],
        "e_phoff": header[5],
        "e_shoff": header[6],
        "e_phentsize": header[9],
        "e_phnum": header[10],
        "e_shentsize": header[11],
        "e_shnum": header[12],
        "e_shstrndx": header[13],
    }

    sections: list[dict] = []
    for idx in range(elf["e_shnum"]):
        off = elf["e_shoff"] + idx * elf["e_shentsize"]
        sh = struct.unpack_from("<IIIIIIIIII", data, off)
        sections.append(
            {
                "index": idx,
                "name_off": sh[0],
                "type": sh[1],
                "flags": sh[2],
                "addr": sh[3],
                "offset": sh[4],
                "size": sh[5],
                "link": sh[6],
                "info": sh[7],
                "addralign": sh[8],
                "entsize": sh[9],
            }
        )

    shstr = sections[elf["e_shstrndx"]]
    shstr_data = data[shstr["offset"] : shstr["offset"] + shstr["size"]]
    for section in sections:
        section["name"] = read_c_string(shstr_data, section["name_off"])

    programs: list[dict] = []
    for idx in range(elf["e_phnum"]):
        off = elf["e_phoff"] + idx * elf["e_phentsize"]
        ph = struct.unpack_from("<IIIIIIII", data, off)
        programs.append(
            {
                "index": idx,
                "type": ph[0],
                "offset": ph[1],
                "vaddr": ph[2],
                "paddr": ph[3],
                "filesz": ph[4],
                "memsz": ph[5],
                "flags": ph[6],
                "align": ph[7],
            }
        )

    return elf, sections, programs


def format_sh_flags(flags: int) -> str:
    chars = []
    if flags & SHF_WRITE:
        chars.append("W")
    if flags & SHF_ALLOC:
        chars.append("A")
    if flags & SHF_EXECINSTR:
        chars.append("X")
    return "".join(chars)


def format_ph_flags(flags: int) -> str:
    parts = [
        "R" if flags & PF_R else " ",
        "W" if flags & PF_W else " ",
        "E" if flags & PF_X else " ",
    ]
    return "".join(parts).rstrip()


def section_in_segment(section: dict, program: dict) -> bool:
    if section["flags"] & SHF_ALLOC == 0:
        return False

    start = section["addr"]
    end = start + max(section["size"], 1)
    seg_start = program["vaddr"]
    seg_end = seg_start + max(program["memsz"], 1)
    if start < seg_start or end > seg_end:
        return False

    if section["type"] != 8:
        file_start = section["offset"]
        file_end = file_start + max(section["size"], 1)
        seg_file_start = program["offset"]
        seg_file_end = seg_file_start + max(program["filesz"], 1)
        if file_start < seg_file_start or file_end > seg_file_end:
            return False

    return True


def find_top_level_elf(idf_dir: str) -> str:
    candidates = []
    for name in os.listdir(idf_dir):
        if not name.endswith(".elf"):
            continue
        if name == "bootloader.elf":
            continue
        full = os.path.join(idf_dir, name)
        if os.path.isfile(full):
            candidates.append(full)
    if len(candidates) != 1:
        raise ValueError(f"expected exactly one top-level app ELF in {idf_dir}, found {len(candidates)}")
    return candidates[0]


def size_or_zero(path: str) -> int:
    return os.path.getsize(path) if os.path.exists(path) else 0


def section_size(sections: list[dict], name: str) -> int:
    for section in sections:
        if section["name"] == name:
            return section["size"]
    return 0


def build_profile(build_config: str) -> str:
    return os.path.dirname(build_config)


def generate_report(test_dir: str, build_dir: str, build_config: str, bsp: str) -> str:
    idf_dir = os.path.join(test_dir, build_dir, "idf")
    elf_path = find_top_level_elf(idf_dir)
    app_name = os.path.splitext(os.path.basename(elf_path))[0]
    app_bin_path = os.path.join(idf_dir, f"{app_name}.bin")
    bootloader_bin_path = os.path.join(idf_dir, "bootloader", "bootloader.bin")

    elf, sections, programs = parse_elf(elf_path)
    alloc_sections = [section for section in sections if section["index"] != 0 and section["flags"] & SHF_ALLOC]
    profile = build_profile(build_config)

    iram_used = section_size(alloc_sections, ".iram0.vectors") + section_size(alloc_sections, ".iram0.text")
    iram_reserved = 0
    for program in programs:
        mapped_names = [section["name"] for section in alloc_sections if section_in_segment(section, program)]
        if ".iram0.vectors" in mapped_names or ".iram0.text" in mapped_names:
            iram_reserved = program["memsz"]
            break

    lines = [
        f"# {app_name} ELF layout golden",
        f"# Built from: {test_dir}",
        f"# Build profile: {profile}",
        "# Command inputs:",
        f"#   -Dbuild_config={build_config}",
        f"#   -Dbsp={bsp}",
        "#",
        "# Image size summary:",
        f"#   bootloader.bin: {size_or_zero(bootloader_bin_path)} bytes",
        f"#   {app_name}.bin: {size_or_zero(app_bin_path)} bytes",
        f"#   IRAM used (.iram0.vectors + .iram0.text): {iram_used} bytes",
        f"#   IRAM reserved LOAD segment: {iram_reserved} bytes",
        f"#   Flash appdesc (.flash.appdesc): {section_size(alloc_sections, '.flash.appdesc')} bytes",
        f"#   Flash rodata (.flash.rodata): {section_size(alloc_sections, '.flash.rodata')} bytes",
        f"#   Flash text (.flash.text): {section_size(alloc_sections, '.flash.text')} bytes",
        "#",
        "# Capture source:",
        "#   generated by test/runners/elf_layout_golden.py",
        "",
        f"Elf file type is {ET_NAMES.get(elf['e_type'], str(elf['e_type']))}",
        f"Entry point 0x{elf['e_entry']:08x}",
        "",
        "Section Headers:",
        "  [Nr] Name                Type      Addr     Off    Size   ES Flg Lk Inf Al",
    ]

    for section in alloc_sections:
        type_name = SHT_NAMES.get(section["type"], str(section["type"]))
        lines.append(
            f"  [{section['index']:2d}] {section['name']:<19} {type_name:<9} "
            f"{section['addr']:08x} {section['offset']:06x} {section['size']:06x} "
            f"{section['entsize']:02x} {format_sh_flags(section['flags']):>3} "
            f"{section['link']:2d} {section['info']:3d} {section['addralign']:2d}"
        )

    lines.extend(
        [
            "",
            "Program Headers:",
            "  Type      Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align",
        ]
    )

    for program in programs:
        type_name = PT_NAMES.get(program["type"], hex(program["type"]))
        lines.append(
            f"  {type_name:<9} 0x{program['offset']:06x} 0x{program['vaddr']:08x} "
            f"0x{program['paddr']:08x} 0x{program['filesz']:05x} 0x{program['memsz']:05x} "
            f"{format_ph_flags(program['flags']):<3} 0x{program['align']:x}"
        )

    lines.extend(["", "Section to Segment mapping:", "  Segment Sections..."])
    for program in programs:
        mapped = [section["name"] for section in alloc_sections if section_in_segment(section, program)]
        if mapped:
            lines.append(f"   {program['index']:02d}     {' '.join(mapped)}")

    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    sys.stdout.write(generate_report(args.test_dir, args.build_dir, args.build_config, args.bsp))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
