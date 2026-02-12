#!/usr/bin/env bash
set -euo pipefail

# Stop ESXi QEMU VM started by run_esxi8_boot_installed_vmnet.sh (vmnet-shared mode).
#
# Usage:
#   sudo work/scripts/esxi_vmnet_kill.sh

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

PID_FILE=${PID_FILE:-"$ROOT_DIR/vm/qemu.pid"}
MONITOR_SOCK=${MONITOR_SOCK:-"$ROOT_DIR/vm/qemu-monitor.sock"}
SERIAL_SOCK=${SERIAL_SOCK:-"$ROOT_DIR/vm/qemu-serial.sock"}

SOCAT_BIN=${SOCAT_BIN:-}
if [[ -z "$SOCAT_BIN" ]]; then
  if command -v socat >/dev/null 2>&1; then
    SOCAT_BIN=$(command -v socat)
  elif [[ -x /opt/homebrew/bin/socat ]]; then
    SOCAT_BIN=/opt/homebrew/bin/socat
  elif [[ -x /usr/local/bin/socat ]]; then
    SOCAT_BIN=/usr/local/bin/socat
  else
    SOCAT_BIN=""
  fi
fi

if [[ -S "$MONITOR_SOCK" && -n "$SOCAT_BIN" ]]; then
  echo "Sending quit to QEMU monitor..."
  echo "quit" | "$SOCAT_BIN" - "UNIX-CONNECT:$MONITOR_SOCK" 2>/dev/null || true
  sleep 2
fi

if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "Killing QEMU (PID $PID)..."
    kill "$PID" 2>/dev/null || true
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

rm -f "$MONITOR_SOCK" "$SERIAL_SOCK"

echo "Done."

