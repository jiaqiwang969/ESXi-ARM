#!/usr/bin/env python3
"""Patch ESXi ARM 8.0 vmkernel CPUID rejection branches.

This script NOPs two conditional branches in CPUID_Save so CPUs that report
unexpected ID register values do not fail early with "CPU identification failed.".
"""

from __future__ import annotations

import argparse
import gzip
from pathlib import Path

TEXT_VA_BASE = 0x420000000000
TEXT_FILE_OFFSET = 0x280000
NOP = bytes.fromhex("1f2003d5")  # AArch64: nop

# Branches inside CPUID_Save that jump to error-return path.
PATCHES = {
    0x42000009963C: "Skip CTR_EL0 format rejection",
    0x420000099690: "Skip ID_AA64PFR0_EL1 rejection",
}


def va_to_file_offset(va: int) -> int:
    return TEXT_FILE_OFFSET + (va - TEXT_VA_BASE)


def patch_vmkernel(src: Path, dst: Path) -> None:
    data = bytearray(src.read_bytes())

    for va, reason in PATCHES.items():
        off = va_to_file_offset(va)
        old = bytes(data[off : off + 4])
        if old == NOP:
            # Already patched.
            continue
        if old[:1] not in {b"\xc0", b"\xe0"}:
            raise RuntimeError(
                f"Unexpected instruction bytes at {va:#x} ({off:#x}): {old.hex()}"
            )
        data[off : off + 4] = NOP
        print(f"Patched {va:#x} ({off:#x}): {old.hex()} -> {NOP.hex()} [{reason}]")

    dst.write_bytes(data)


def write_kb00(vmkernel_bin: Path, kb00_out: Path) -> None:
    with gzip.GzipFile(filename="", mode="wb", fileobj=kb00_out.open("wb"), mtime=0) as gz:
        gz.write(vmkernel_bin.read_bytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-vmkernel", required=True, type=Path)
    parser.add_argument("--output-vmkernel", required=True, type=Path)
    parser.add_argument("--output-kb00", required=True, type=Path)
    args = parser.parse_args()

    patch_vmkernel(args.input_vmkernel, args.output_vmkernel)
    write_kb00(args.output_vmkernel, args.output_kb00)

    print(f"Wrote patched vmkernel: {args.output_vmkernel}")
    print(f"Wrote patched K.B00:     {args.output_kb00}")


if __name__ == "__main__":
    main()
