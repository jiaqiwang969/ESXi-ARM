#!/usr/bin/env bash
set -euo pipefail

# Download and extract AAVMF firmware files from Ubuntu qemu-efi-aarch64 package.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR=${1:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02"}
DEB_URL=${DEB_URL:-"http://security.ubuntu.com/ubuntu/pool/main/e/edk2/qemu-efi-aarch64_2022.02-3ubuntu0.22.04.5_all.deb"}

mkdir -p "$OUT_DIR"
TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

DEB_PATH="$TMP_DIR/qemu-efi-aarch64.deb"
echo "Downloading: $DEB_URL"
curl -L --fail --retry 2 --max-time 120 -o "$DEB_PATH" "$DEB_URL"

(
  cd "$TMP_DIR"
  ar x "$DEB_PATH"
  mkdir data
  if [[ -f data.tar.zst ]]; then
    tar -xf data.tar.zst -C data
  elif [[ -f data.tar.xz ]]; then
    tar -xf data.tar.xz -C data
  elif [[ -f data.tar.gz ]]; then
    tar -xf data.tar.gz -C data
  else
    echo "ERROR: no data.tar.* found in deb" >&2
    exit 3
  fi

  cp data/usr/share/AAVMF/AAVMF_CODE.fd "$OUT_DIR/"
  cp data/usr/share/AAVMF/AAVMF_VARS.fd "$OUT_DIR/"
  cp data/usr/share/AAVMF/AAVMF_VARS.ms.fd "$OUT_DIR/"
  cp data/usr/share/AAVMF/AAVMF_VARS.snakeoil.fd "$OUT_DIR/"
)

echo "Extracted firmware to: $OUT_DIR"
ls -lh "$OUT_DIR"/AAVMF_*.fd
