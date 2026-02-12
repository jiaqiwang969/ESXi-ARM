#!/usr/bin/env bash
set -euo pipefail

# Download NixOS aarch64 minimal installer ISO with SHA256 verification.
#
# Note: this is a helper for creating a full NixOS environment (VM or bare metal).
# It does NOT install Nix on the current host.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR=${1:-"$ROOT_DIR/iso"}

# Adjust if you want to pin to a different channel.
NIXOS_CHANNEL=${NIXOS_CHANNEL:-nixos-25.11}

ISO_ALIAS=${ISO_ALIAS:-latest-nixos-minimal-aarch64-linux.iso}
ISO_URL=${ISO_URL:-"https://channels.nixos.org/${NIXOS_CHANNEL}/${ISO_ALIAS}"}
SHA_URL=${SHA_URL:-"${ISO_URL}.sha256"}

mkdir -p "$OUT_DIR"

SHA_TMP="$OUT_DIR/${ISO_ALIAS}.sha256"
echo "Fetching checksum: $SHA_URL"
curl -L --fail --retry 2 --max-time 120 -o "$SHA_TMP" "$SHA_URL"

read -r EXPECTED_HASH EXPECTED_NAME < "$SHA_TMP"

if [[ -z "$EXPECTED_HASH" || -z "$EXPECTED_NAME" ]]; then
  echo "ERROR: unable to parse checksum file: $SHA_TMP" >&2
  exit 3
fi

ISO_PATH="$OUT_DIR/$EXPECTED_NAME"

# If we already have it and it matches, no-op.
if [[ -f "$ISO_PATH" ]]; then
  CURRENT_HASH=""
  if command -v sha256sum >/dev/null 2>&1; then
    CURRENT_HASH=$(sha256sum "$ISO_PATH" | awk "{print \$1}")
  else
    CURRENT_HASH=$(shasum -a 256 "$ISO_PATH" | awk "{print \$1}")
  fi

  if [[ "$CURRENT_HASH" == "$EXPECTED_HASH" ]]; then
    echo "ISO already present and verified: $ISO_PATH"
    ln -sfn "$EXPECTED_NAME" "$OUT_DIR/latest-nixos-minimal-aarch64-linux.iso"
    echo "Latest alias: $OUT_DIR/latest-nixos-minimal-aarch64-linux.iso -> $EXPECTED_NAME"
    exit 0
  fi

  echo "Existing ISO hash mismatch; re-downloading: $ISO_PATH"
fi

TMP_PATH="$ISO_PATH.part"
echo "Downloading ISO: $ISO_URL"
curl -L --fail --retry 2 --max-time 1800 -o "$TMP_PATH" "$ISO_URL"
mv "$TMP_PATH" "$ISO_PATH"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_HASH=$(sha256sum "$ISO_PATH" | awk "{print \$1}")
else
  ACTUAL_HASH=$(shasum -a 256 "$ISO_PATH" | awk "{print \$1}")
fi

if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
  echo "ERROR: SHA256 mismatch for $ISO_PATH" >&2
  echo "  expected: $EXPECTED_HASH" >&2
  echo "  actual:   $ACTUAL_HASH" >&2
  exit 4
fi

ln -sfn "$EXPECTED_NAME" "$OUT_DIR/latest-nixos-minimal-aarch64-linux.iso"
echo "Downloaded and verified: $ISO_PATH"
echo "Latest alias: $OUT_DIR/latest-nixos-minimal-aarch64-linux.iso -> $EXPECTED_NAME"
