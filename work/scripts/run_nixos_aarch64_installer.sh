#!/usr/bin/env bash
set -euo pipefail

# Boot a full NixOS aarch64 installer in QEMU with UEFI firmware.
# This creates an independent NixOS system target (VM disk), not a host-side Nix install.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_ROOT=$(cd "$ROOT_DIR/.." && pwd)

ISO_PATH=${1:-"$ROOT_DIR/iso/latest-nixos-minimal-aarch64-linux.iso"}
DISK_IMG=${2:-"$ROOT_DIR/vm/nixos-aarch64.qcow2"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_TEMPLATE=${AAVMF_VARS_TEMPLATE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_VARS.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-nixos.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
DISK_SIZE=${DISK_SIZE:-80G}
SSH_FWD_PORT=${SSH_FWD_PORT:-10022}
RESET_VARS=${RESET_VARS:-0}
SHARE_REPO=${SHARE_REPO:-1}
MOUNT_TAG=${MOUNT_TAG:-esxiarm_repo}

if [[ ! -f "$ISO_PATH" ]]; then
  echo "ERROR: NixOS installer ISO not found: $ISO_PATH" >&2
  echo "Hint: run work/scripts/fetch_nixos_aarch64_iso.sh first" >&2
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
if ! [[ "$SSH_FWD_PORT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SSH_FWD_PORT must be an integer, got: $SSH_FWD_PORT" >&2
  exit 2
fi

mkdir -p "$(dirname "$DISK_IMG")" "$(dirname "$AAVMF_VARS_RUNTIME")"
if [[ ! -f "$DISK_IMG" ]]; then
  echo "Creating disk image: $DISK_IMG ($DISK_SIZE)"
  qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" >/dev/null
fi
if [[ ! -f "$AAVMF_VARS_RUNTIME" || "$RESET_VARS" == "1" ]]; then
  cp -f "$AAVMF_VARS_TEMPLATE" "$AAVMF_VARS_RUNTIME"
fi

if [[ "$ACCEL" == "hvf" ]]; then
  CPU_MODEL=${CPU_MODEL:-host}
else
  CPU_MODEL=${CPU_MODEL:-max}
fi

EXTRA_FS_ARGS=()
if [[ "$SHARE_REPO" == "1" ]]; then
  EXTRA_FS_ARGS=(
    -fsdev "local,id=repofs,path=$PROJECT_ROOT,security_model=none,readonly=on"
    -device "virtio-9p-pci,fsdev=repofs,mount_tag=$MOUNT_TAG"
  )
fi

echo "ISO:          $ISO_PATH"
echo "Disk:         $DISK_IMG"
echo "Firmware:     $AAVMF_CODE"
echo "Vars:         $AAVMF_VARS_RUNTIME"
echo "Accel/CPU:    $ACCEL / $CPU_MODEL"
echo "Machine:      $MACHINE_OPTS"
echo "RAM/CPUs:     ${RAM_MB}MB / $CPUS"
echo "SSH forward:  localhost:${SSH_FWD_PORT} -> guest:22"
if [[ "$SHARE_REPO" == "1" ]]; then
  echo "Repo share:   tag=$MOUNT_TAG (read-only 9p)"
fi

echo
echo "Tip: installer login user is usually nixos (no password) on tty1."
echo "After install, keep this same Vars file for persistent UEFI boot entries."
if [[ "$SHARE_REPO" == "1" ]]; then
  echo "Inside guest you can mount repo by:"
  echo "  sudo mkdir -p /mnt/repo && sudo mount -t 9p -o trans=virtio,version=9p2000.L $MOUNT_TAG /mnt/repo"
fi

exec qemu-system-aarch64 \
  -accel "$ACCEL" \
  -machine "$MACHINE_OPTS" \
  -cpu "$CPU_MODEL" \
  -smp "$CPUS" \
  -m "$RAM_MB" \
  -device qemu-xhci,id=xhci \
  -drive if=none,id=nixosiso,format=raw,readonly=on,file="$ISO_PATH" \
  -device usb-storage,bus=xhci.0,drive=nixosiso,bootindex=0 \
  -drive if=none,id=systemdisk,file="$DISK_IMG",format=qcow2 \
  -device virtio-blk-pci,drive=systemdisk,bootindex=1 \
  -netdev user,id=net0,hostfwd=tcp::${SSH_FWD_PORT}-:22 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:65:43:21 \
  -drive if=pflash,format=raw,readonly=on,file="$AAVMF_CODE" \
  -drive if=pflash,format=raw,file="$AAVMF_VARS_RUNTIME" \
  "${EXTRA_FS_ARGS[@]}" \
  -serial mon:stdio \
  -nographic
