#!/usr/bin/env bash
set -euo pipefail

# Boot an already-installed ESXi-Arm disk using macOS vmnet-shared networking.
#
# Why:
# - QEMU user-mode networking (SLIRP) is often enough for boot/install validation,
#   but inbound connections (SSH/HTTPS via hostfwd) can be unreliable with ESXi.
# - vmnet-shared gives the guest a real IP on bridge100 (typically 192.168.2.0/24).
#
# Notes:
# - vmnet-shared typically requires root privileges on macOS -> run with sudo.
#
# Usage:
#   sudo work/scripts/run_esxi8_boot_installed_vmnet.sh [--bg] [disk.qcow2]
#
# Background mode:
# - Creates monitor/serial unix sockets for automation / debugging.
# - Writes PID file for stop script.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

MODE=fg
if [[ "${1:-}" == "--bg" ]]; then
  MODE=bg
  shift
fi

DISK_IMG=${1:-"$ROOT_DIR/vm/esxi-install-e2e.qcow2"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-e2e.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}

MAC_ADDR=${MAC_ADDR:-52:54:00:12:34:56}

MONITOR_SOCK=${MONITOR_SOCK:-"$ROOT_DIR/vm/qemu-monitor.sock"}
SERIAL_SOCK=${SERIAL_SOCK:-"$ROOT_DIR/vm/qemu-serial.sock"}
PID_FILE=${PID_FILE:-"$ROOT_DIR/vm/qemu.pid"}

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: vmnet-shared typically requires root on macOS. Please run with sudo." >&2
  echo "  sudo $0 --bg \"$DISK_IMG\"" >&2
  exit 2
fi

if [[ ! -f "$DISK_IMG" ]]; then
  echo "ERROR: disk image not found: $DISK_IMG" >&2
  exit 2
fi
if [[ ! -f "$AAVMF_CODE" ]]; then
  echo "ERROR: AAVMF_CODE not found: $AAVMF_CODE" >&2
  exit 2
fi
if [[ ! -f "$AAVMF_VARS_RUNTIME" ]]; then
  echo "ERROR: AAVMF_VARS runtime not found: $AAVMF_VARS_RUNTIME" >&2
  exit 2
fi

QEMU_BIN=${QEMU_BIN:-}
if [[ -z "$QEMU_BIN" ]]; then
  if command -v qemu-system-aarch64 >/dev/null 2>&1; then
    QEMU_BIN=$(command -v qemu-system-aarch64)
  elif [[ -x /opt/homebrew/bin/qemu-system-aarch64 ]]; then
    QEMU_BIN=/opt/homebrew/bin/qemu-system-aarch64
  elif [[ -x /usr/local/bin/qemu-system-aarch64 ]]; then
    QEMU_BIN=/usr/local/bin/qemu-system-aarch64
  else
    echo "ERROR: qemu-system-aarch64 not found. Set QEMU_BIN or install qemu." >&2
    exit 2
  fi
fi

if [[ "$ACCEL" == "hvf" ]]; then
  CPU_MODEL=${CPU_MODEL:-host}
  echo "WARN: hvf can be less stable in this setup; tcg is recommended."
else
  CPU_MODEL=${CPU_MODEL:-max}
fi

mkdir -p "$(dirname "$MONITOR_SOCK")" "$(dirname "$SERIAL_SOCK")" "$(dirname "$PID_FILE")"
rm -f "$MONITOR_SOCK" "$SERIAL_SOCK"

echo "Disk:        $DISK_IMG"
echo "Firmware:    $AAVMF_CODE"
echo "Vars:        $AAVMF_VARS_RUNTIME"
echo "Network:     vmnet-shared (guest gets DHCP IP on bridge100)"
echo "MAC:         $MAC_ADDR"
echo "Accel/CPU:   $ACCEL / $CPU_MODEL"
echo "Machine:     $MACHINE_OPTS"
echo "RAM/CPUs:    ${RAM_MB}MB / $CPUS"
echo "Monitor:     $MONITOR_SOCK"
echo "Serial:      $SERIAL_SOCK"
echo "PID file:    $PID_FILE"

QEMU_COMMON=(
  -accel "$ACCEL"
  -machine "$MACHINE_OPTS"
  -cpu "$CPU_MODEL"
  -smp "$CPUS"
  -m "$RAM_MB"
  -device qemu-xhci,id=xhci
  -drive "if=none,id=esxidisk,file=$DISK_IMG,format=qcow2"
  -device usb-storage,bus=xhci.0,drive=esxidisk,bootindex=0
  -netdev vmnet-shared,id=net0
  -device vmxnet3,netdev=net0,mac="$MAC_ADDR"
  -drive "if=pflash,format=raw,readonly=on,file=$AAVMF_CODE"
  -drive "if=pflash,format=raw,file=$AAVMF_VARS_RUNTIME"
  -monitor "unix:$MONITOR_SOCK,server,nowait"
  -nographic
)

if [[ "$MODE" == "bg" ]]; then
  echo "Starting in background..."
  nohup "$QEMU_BIN" "${QEMU_COMMON[@]}" \
    -serial "unix:$SERIAL_SOCK,server,nowait" \
    </dev/null >/dev/null 2>&1 &
  QPID=$!
  echo "$QPID" >"$PID_FILE"
  echo "PID: $QPID"
  echo
  echo "Connect serial:  socat -,rawer unix-connect:$SERIAL_SOCK"
  echo "Connect monitor: socat -,rawer unix-connect:$MONITOR_SOCK"
  echo "Stop VM:        sudo work/scripts/esxi_vmnet_kill.sh"
else
  echo "Starting in foreground (Ctrl-A X to quit)..."
  echo
  exec "$QEMU_BIN" "${QEMU_COMMON[@]}" -serial mon:stdio
fi

