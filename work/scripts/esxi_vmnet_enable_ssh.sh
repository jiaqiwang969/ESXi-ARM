#!/usr/bin/env bash
set -euo pipefail

# Enable ESXi SSH via DCUI using QEMU monitor sendkey.
#
# This script assumes the ESXi VM is already booted and a QEMU monitor unix
# socket exists (created by run_esxi8_boot_installed_vmnet.sh --bg).
#
# Usage:
#   sudo ROOT_PASSWORD='VMware123!' work/scripts/esxi_vmnet_enable_ssh.sh
#
# Notes:
# - DCUI menu ordering can differ by build/config; if it doesn't work, enable
#   SSH manually in DCUI: F2 -> Troubleshooting Options -> Enable SSH.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

MONITOR_SOCK=${MONITOR_SOCK:-"$ROOT_DIR/vm/qemu-monitor.sock"}
ROOT_PASSWORD=${ROOT_PASSWORD:-VMware123!}

if [[ ! -S "$MONITOR_SOCK" ]]; then
  echo "ERROR: monitor socket not found: $MONITOR_SOCK" >&2
  echo "Hint: start VM with: sudo work/scripts/run_esxi8_boot_installed_vmnet.sh --bg <disk>" >&2
  exit 2
fi

SOCAT_BIN=${SOCAT_BIN:-}
if [[ -z "$SOCAT_BIN" ]]; then
  if command -v socat >/dev/null 2>&1; then
    SOCAT_BIN=$(command -v socat)
  elif [[ -x /opt/homebrew/bin/socat ]]; then
    SOCAT_BIN=/opt/homebrew/bin/socat
  elif [[ -x /usr/local/bin/socat ]]; then
    SOCAT_BIN=/usr/local/bin/socat
  else
    echo "ERROR: socat not found. Install it (brew install socat) or set SOCAT_BIN." >&2
    exit 2
  fi
fi

send_monitor() {
  echo "$1" | "$SOCAT_BIN" -T2 - "UNIX-CONNECT:$MONITOR_SOCK" >/dev/null 2>&1
}

send_key() {
  send_monitor "sendkey $1"
  sleep 0.3
}

send_string() {
  local str="$1"
  for ((i = 0; i < ${#str}; i++)); do
    local c="${str:$i:1}"
    case "$c" in
      [a-z]) send_key "$c" ;;
      [A-Z]) send_key "shift-$(echo "$c" | tr 'A-Z' 'a-z')" ;;
      [0-9]) send_key "$c" ;;
      '!') send_key "shift-1" ;;
      '@') send_key "shift-2" ;;
      '#') send_key "shift-3" ;;
      '-') send_key "minus" ;;
      '_') send_key "shift-minus" ;;
      '.') send_key "dot" ;;
      ' ') send_key "spc" ;;
      *) echo "WARN: unsupported char for sendkey: '$c'" >&2 ;;
    esac
  done
}

echo "Enabling SSH via DCUI sendkey..."

echo "  F2 -> Customize System"
send_key "f2"
sleep 8

echo "  Entering root password"
send_string "$ROOT_PASSWORD"
sleep 1
send_key "ret"
sleep 8

echo "  Navigating to Troubleshooting Options"
# Empirically, Troubleshooting Options is ~7 items down in DCUI menu.
for _ in $(seq 1 7); do
  send_key "down"
  sleep 0.5
done
send_key "ret"
sleep 5

echo "  Enabling ESXi Shell"
send_key "ret"
sleep 3

echo "  Enabling SSH"
send_key "down"
sleep 0.5
send_key "ret"
sleep 5

echo "  Esc back to DCUI"
send_key "esc"
sleep 2
send_key "esc"
sleep 2

echo "Done. If SSH is still not reachable, enable it manually in DCUI."

