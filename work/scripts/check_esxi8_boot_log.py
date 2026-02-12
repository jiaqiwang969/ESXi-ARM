#!/usr/bin/env python3
"""Validate an ESXi-Arm boot probe log with simple structured criteria."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
OSC_RE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")

REQUIRED_PATTERNS = [
    ("uefi_boot_path", re.compile(r"BdsDxe: (loading|starting) Boot\d+")),
    ("vmkernel_boot", re.compile(r"Starting VMKernel")),
    ("boot_complete", re.compile(r"Boot complete \(2/2\)")),
    (
        "dcui_or_management",
        re.compile(r"(Starting service DCUI|To manage this host, go to:)"),
    ),
]

OPTIONAL_STRONG_PATTERNS = [
    ("vmware_boot_entry", re.compile(r"Boot\d+\s+\"VMware ESXi\"")),
]

PANIC_PATTERNS = [
    ("panic_its_2934", re.compile(r"its\.c:2934")),
    ("panic_module", re.compile(r"Module\(s\) involved in panic")),
    ("kernel_verify", re.compile(r"\bVERIFY\b")),
]


def normalize_log(raw: str) -> str:
    text = OSC_RE.sub("", raw)
    text = CSI_RE.sub("", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    # Keep printable ASCII + newline/tab for matching and diagnostics.
    cleaned = []
    for ch in text:
        o = ord(ch)
        if ch in "\n\t" or 32 <= o < 127:
            cleaned.append(ch)
    return "".join(cleaned)


def check_patterns(text: str, patterns: list[tuple[str, re.Pattern[str]]]) -> list[str]:
    missing: list[str] = []
    for name, pattern in patterns:
        if not pattern.search(text):
            missing.append(name)
    return missing


def check_panic(text: str) -> list[str]:
    hits: list[str] = []
    for name, pattern in PANIC_PATTERNS:
        if pattern.search(text):
            hits.append(name)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_path", help="Path to serial boot log")
    parser.add_argument(
        "--allow-verify-only",
        action="store_true",
        help="Do not fail on a generic VERIFY hit unless panic-specific signatures are present.",
    )
    args = parser.parse_args()

    log_path = Path(args.log_path)
    if not log_path.is_file():
        print(f"ERROR: log file not found: {log_path}", file=sys.stderr)
        return 2

    text = normalize_log(log_path.read_text(errors="ignore"))

    missing = check_patterns(text, REQUIRED_PATTERNS)
    panic_hits = check_panic(text)
    optional_hits = [
        name for name, pattern in OPTIONAL_STRONG_PATTERNS if pattern.search(text)
    ]

    if args.allow_verify_only and panic_hits == ["kernel_verify"]:
        panic_hits = []

    if missing:
        print("RESULT: FAIL (missing required boot markers)")
        print("Missing:", ", ".join(missing))
        return 3

    if panic_hits:
        print("RESULT: FAIL (panic signature detected)")
        print("Panic markers:", ", ".join(panic_hits))
        return 4

    print("RESULT: PASS")
    print("Markers: " + ", ".join(name for name, _ in REQUIRED_PATTERNS))
    if optional_hits:
        print("Strong markers: " + ", ".join(optional_hits))
    else:
        print("Strong markers: none (acceptable; firmware may boot via generic UEFI entry)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
