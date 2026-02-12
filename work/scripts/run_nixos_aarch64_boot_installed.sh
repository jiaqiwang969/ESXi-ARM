#!/usr/bin/env bash
set -euo pipefail

# Boot an already-installed NixOS aarch64 VM disk.
# Keep the same UEFI vars file used during installation.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_ROOT=$(cd "$ROOT_DIR/.." && pwd)

DISK_IMG=${1:-"$ROOT_DIR/vm/nixos-aarch64.qcow2"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-nixos.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
SSH_FWD_PORT=${SSH_FWD_PORT:-10022}
SHARE_REPO=${SHARE_REPO:-1}
MOUNT_TAG=${MOUNT_TAG:-esxiarm_repo}

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
  echo "Hint: install first with run_nixos_aarch64_installer.sh" >&2
  exit 2
fi
if ! [[ "$SSH_FWD_PORT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SSH_FWD_PORT must be an integer, got: $SSH_FWD_PORT" >&2
  exit 2
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

exec qemu-system-aarch64 \
  -accel "$ACCEL" \
  -machine "$MACHINE_OPTS" \
  -cpu "$CPU_MODEL" \
  -smp "$CPUS" \
  -m "$RAM_MB" \
  -drive if=none,id=systemdisk,file="$DISK_IMG",format=qcow2 \
  -device virtio-blk-pci,drive=systemdisk,bootindex=0 \
  -netdev user,id=net0,hostfwd=tcp::${SSH_FWD_PORT}-:22 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:65:43:21 \
  -drive if=pflash,format=raw,readonly=on,file="$AAVMF_CODE" \
  -drive if=pflash,format=raw,file="$AAVMF_VARS_RUNTIME" \
  "${EXTRA_FS_ARGS[@]}" \
  -serial mon:stdio \
  -nographic
