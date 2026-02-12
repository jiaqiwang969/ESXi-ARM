#!/usr/bin/env bash
set -euo pipefail

# Run ESXi-Arm installer in QEMU using AAVMF firmware known to boot reliably.
# Defaults are tuned for Apple Silicon + QEMU 10.x + serial console workflow.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

PAYLOAD_DIR=${1:-"$ROOT_DIR/out/esxi8-allowlegacy-payload"}
DISK_IMG=${2:-"$ROOT_DIR/vm/esxi-disk.qcow2"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_TEMPLATE=${AAVMF_VARS_TEMPLATE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_VARS.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi8.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
DISK_SIZE=${DISK_SIZE:-80G}
DISK_BUS=${DISK_BUS:-usb}

if [[ ! -d "$PAYLOAD_DIR" ]]; then
  echo "ERROR: payload dir not found: $PAYLOAD_DIR" >&2
  exit 2
fi
if [[ ! -f "$PAYLOAD_DIR/EFI/BOOT/BOOTAA64.EFI" ]]; then
  echo "ERROR: payload missing EFI/BOOT/BOOTAA64.EFI: $PAYLOAD_DIR" >&2
  exit 2
fi
if [[ ! -f "$PAYLOAD_DIR/K.B00" ]]; then
  echo "ERROR: payload missing K.B00: $PAYLOAD_DIR" >&2
  exit 2
fi
if [[ ! -f "$AAVMF_CODE" ]]; then
  echo "ERROR: AAVMF_CODE not found: $AAVMF_CODE" >&2
  exit 2
fi
if [[ ! -f "$AAVMF_VARS_TEMPLATE" ]]; then
  echo "ERROR: AAVMF_VARS template not found: $AAVMF_VARS_TEMPLATE" >&2
  exit 2
fi

mkdir -p "$(dirname "$DISK_IMG")"
if [[ ! -f "$DISK_IMG" ]]; then
  echo "Creating disk image: $DISK_IMG ($DISK_SIZE)"
  qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" >/dev/null
fi

mkdir -p "$(dirname "$AAVMF_VARS_RUNTIME")"
if [[ ! -f "$AAVMF_VARS_RUNTIME" ]]; then
  cp "$AAVMF_VARS_TEMPLATE" "$AAVMF_VARS_RUNTIME"
fi

if [[ "$ACCEL" == "hvf" ]]; then
  CPU_MODEL=${CPU_MODEL:-host}
  echo "WARN: hvf can panic on some setups; tcg is more stable for ESXi-Arm installer."
else
  CPU_MODEL=${CPU_MODEL:-max}
fi

case "$DISK_BUS" in
  nvme)
    DISK_DEVICE_ARGS=(-device nvme,serial=esxiinstall,drive=esxidisk)
    ;;
  usb)
    # Attach a second USB disk (separate from installer payload USB) for install target.
    DISK_DEVICE_ARGS=(-device usb-storage,bus=xhci.0,drive=esxidisk)
    ;;
  *)
    echo "ERROR: unsupported DISK_BUS='$DISK_BUS' (supported: usb, nvme)" >&2
    exit 2
    ;;
esac

echo "Payload:      $PAYLOAD_DIR"
echo "Disk:         $DISK_IMG"
echo "Disk bus:     $DISK_BUS"
echo "Firmware:     $AAVMF_CODE"
echo "Vars:         $AAVMF_VARS_RUNTIME"
echo "Accel/CPU:    $ACCEL / $CPU_MODEL"
echo "Machine:      $MACHINE_OPTS"
echo "RAM/CPUs:     ${RAM_MB}MB / $CPUS"

exec qemu-system-aarch64 \
  -accel "$ACCEL" \
  -machine "$MACHINE_OPTS" \
  -cpu "$CPU_MODEL" \
  -smp "$CPUS" \
  -m "$RAM_MB" \
  -device qemu-xhci,id=xhci \
  -drive if=none,id=esxiboot,format=raw,file=fat:rw:"$PAYLOAD_DIR" \
  -device usb-storage,bus=xhci.0,drive=esxiboot,bootindex=0 \
  -drive if=none,id=esxidisk,file="$DISK_IMG",format=qcow2 \
  "${DISK_DEVICE_ARGS[@]}" \
  -netdev user,id=net0 \
  -device vmxnet3,netdev=net0,mac=52:54:00:12:34:56 \
  -drive if=pflash,format=raw,readonly=on,file="$AAVMF_CODE" \
  -drive if=pflash,format=raw,file="$AAVMF_VARS_RUNTIME" \
  -serial mon:stdio \
  -nographic
