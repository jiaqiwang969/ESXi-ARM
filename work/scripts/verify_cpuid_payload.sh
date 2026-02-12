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

hex_at_offset() {
  python3 - "$1" "$2" <<'PY'
import sys

path = sys.argv[1]
off = int(sys.argv[2], 0)
with open(path, "rb") as f:
    f.seek(off)
    b = f.read(4)
print(b.hex())
PY
}

B1=$(hex_at_offset "$TMP_BIN" 0x31963c)
B2=$(hex_at_offset "$TMP_BIN" 0x319690)

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    python3 - "$1" <<'PY'
import hashlib
import sys

path = sys.argv[1]
h = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
  fi
}

echo "K.B00 sha256: $(sha256_file "$K_B00")"
echo "Offset 0x31963c: $B1"
echo "Offset 0x319690: $B2"

if [[ "$B1" == "1f2003d5" && "$B2" == "1f2003d5" ]]; then
  echo "RESULT: CPUID patch is PRESENT (expected NOP/NOP)."
  exit 0
fi

echo "RESULT: CPUID patch is NOT present (or K.B00 differs)." >&2
exit 3
