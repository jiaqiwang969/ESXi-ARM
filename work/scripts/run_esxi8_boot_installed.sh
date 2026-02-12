#!/usr/bin/env bash
set -euo pipefail

# Boot an already-installed ESXi-Arm disk (no installer payload attached).
# Use the same AAVMF vars file from install so Boot#### entries are preserved.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

DISK_IMG=${1:-"$ROOT_DIR/vm/esxi-install-usb-auto.qcow2"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-install.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
DISK_BUS=${DISK_BUS:-usb}

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

if [[ "$ACCEL" == "hvf" ]]; then
  CPU_MODEL=${CPU_MODEL:-host}
  echo "WARN: hvf can be less stable in this setup; tcg is recommended."
else
  CPU_MODEL=${CPU_MODEL:-max}
fi

case "$DISK_BUS" in
  usb)
    DISK_DEVICE_ARGS=(-device usb-storage,bus=xhci.0,drive=esxidisk,bootindex=0)
    ;;
  nvme)
    DISK_DEVICE_ARGS=(-device nvme,serial=esxiroot,drive=esxidisk,bootindex=0)
    ;;
  *)
    echo "ERROR: unsupported DISK_BUS='$DISK_BUS' (supported: usb, nvme)" >&2
    exit 2
    ;;
esac

echo "Disk:        $DISK_IMG"
echo "Disk bus:    $DISK_BUS"
echo "Firmware:    $AAVMF_CODE"
echo "Vars:        $AAVMF_VARS_RUNTIME"
echo "Accel/CPU:   $ACCEL / $CPU_MODEL"
echo "Machine:     $MACHINE_OPTS"
echo "RAM/CPUs:    ${RAM_MB}MB / $CPUS"

exec qemu-system-aarch64 \
  -accel "$ACCEL" \
  -machine "$MACHINE_OPTS" \
  -cpu "$CPU_MODEL" \
  -smp "$CPUS" \
  -m "$RAM_MB" \
  -device qemu-xhci,id=xhci \
  -drive if=none,id=esxidisk,file="$DISK_IMG",format=qcow2 \
  "${DISK_DEVICE_ARGS[@]}" \
  -netdev user,id=net0 \
  -device vmxnet3,netdev=net0,mac=52:54:00:12:34:56 \
  -drive if=pflash,format=raw,readonly=on,file="$AAVMF_CODE" \
  -drive if=pflash,format=raw,file="$AAVMF_VARS_RUNTIME" \
  -serial mon:stdio \
  -nographic
