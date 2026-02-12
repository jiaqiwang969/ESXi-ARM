#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <source-iso> <patched-kb00> <output-dir>" >&2
  exit 1
fi

SOURCE_ISO=$1
PATCHED_KB00=$2
OUT_DIR=$3

if [[ ! -f "$SOURCE_ISO" ]]; then
  echo "ERROR: source ISO not found: $SOURCE_ISO" >&2
  exit 1
fi
if [[ ! -f "$PATCHED_KB00" ]]; then
  echo "ERROR: patched K.B00 not found: $PATCHED_KB00" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
7z x -y -o"$OUT_DIR" "$SOURCE_ISO" >/dev/null
cp "$PATCHED_KB00" "$OUT_DIR/K.B00"

echo "Patched payload ready at: $OUT_DIR"
echo "Key files:"
ls -lh "$OUT_DIR/K.B00" "$OUT_DIR/BOOT.CFG" "$OUT_DIR/EFI/BOOT/BOOTAA64.EFI"

echo
echo "Next: copy all files from '$OUT_DIR' to a FAT32 USB partition, then boot:"
echo "  \\EFI\\BOOT\\BOOTAA64.EFI"
