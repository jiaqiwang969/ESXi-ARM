#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <payload-dir-or-mounted-usb-root>" >&2
  exit 1
fi

ROOT_DIR=$1
K_B00="$ROOT_DIR/K.B00"
BOOT_CFG="$ROOT_DIR/BOOT.CFG"
UEFI_BIN="$ROOT_DIR/EFI/BOOT/BOOTAA64.EFI"

if [[ ! -f "$K_B00" ]]; then
  echo "ERROR: missing $K_B00" >&2
  exit 2
fi
if [[ ! -f "$BOOT_CFG" ]]; then
  echo "WARN: missing $BOOT_CFG" >&2
fi
if [[ ! -f "$UEFI_BIN" ]]; then
  echo "WARN: missing $UEFI_BIN" >&2
fi

TMP_BIN=$(mktemp)
cleanup() {
  rm -f "$TMP_BIN"
}
trap cleanup EXIT

gzip -dc "$K_B00" > "$TMP_BIN"

B1=$(xxd -p -l 4 -s $((0x31963c)) "$TMP_BIN")
B2=$(xxd -p -l 4 -s $((0x319690)) "$TMP_BIN")

echo "K.B00 sha256: $(shasum -a 256 "$K_B00" | awk '{print $1}')"
echo "Offset 0x31963c: $B1"
echo "Offset 0x319690: $B2"

if [[ "$B1" == "1f2003d5" && "$B2" == "1f2003d5" ]]; then
  echo "RESULT: CPUID patch is PRESENT (expected NOP/NOP)."
  exit 0
fi

echo "RESULT: CPUID patch is NOT present (or K.B00 differs)." >&2
exit 3
