#!/usr/bin/env bash
set -euo pipefail

# End-to-end flow:
# 1) auto install ESXi-Arm to disk
# 2) cold boot disk-only
# 3) verify boot markers from serial log

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

PAYLOAD_DIR=${1:-"$ROOT_DIR/out/esxi8-allowlegacy-payload"}
DISK_IMG=${2:-"$ROOT_DIR/vm/esxi-install-e2e.qcow2"}

RUN_TAG=${RUN_TAG:-$(date +%Y%m%d-%H%M%S)}
LOG_DIR=${LOG_DIR:-"$ROOT_DIR/out"}
INSTALL_LOG=${INSTALL_LOG:-"$LOG_DIR/esxi8-e2e-install-$RUN_TAG.log"}
BOOT_LOG=${BOOT_LOG:-"$LOG_DIR/esxi8-e2e-boot-$RUN_TAG.log"}

AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-e2e.fd"}
ROOT_PASSWORD=${ROOT_PASSWORD:-VMware123!}
DISK_BUS=${DISK_BUS:-usb}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-2400}
REBOOT_ACTION=${REBOOT_ACTION:-enter}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}

if [[ ! -d "$PAYLOAD_DIR" ]]; then
  echo "ERROR: payload dir not found: $PAYLOAD_DIR" >&2
  exit 2
fi
if [[ ! -f "$PAYLOAD_DIR/EFI/BOOT/BOOTAA64.EFI" ]]; then
  echo "ERROR: payload missing EFI/BOOT/BOOTAA64.EFI: $PAYLOAD_DIR" >&2
  exit 2
fi
if [[ -z "$ROOT_PASSWORD" ]]; then
  echo "ERROR: ROOT_PASSWORD must not be empty" >&2
  exit 2
fi

mkdir -p "$(dirname "$DISK_IMG")" "$(dirname "$AAVMF_VARS_RUNTIME")" "$LOG_DIR"

echo "[1/2] Auto install"
echo "Payload:      $PAYLOAD_DIR"
echo "Disk:         $DISK_IMG"
echo "Vars:         $AAVMF_VARS_RUNTIME"
echo "Install log:  $INSTALL_LOG"
echo "Reboot mode:  $REBOOT_ACTION"
echo "Machine:      $MACHINE_OPTS"

ROOT_PASSWORD="$ROOT_PASSWORD" \
REBOOT_ACTION="$REBOOT_ACTION" \
DISK_BUS="$DISK_BUS" \
AAVMF_VARS_RUNTIME="$AAVMF_VARS_RUNTIME" \
MACHINE_OPTS="$MACHINE_OPTS" \
"$ROOT_DIR/scripts/run_esxi8_install_full_auto.sh" \
  "$PAYLOAD_DIR" \
  "$DISK_IMG" \
  "$INSTALL_LOG"

echo "[2/2] Cold boot + verify"
echo "Boot log:     $BOOT_LOG"

DISK_BUS="$DISK_BUS" \
AAVMF_VARS_RUNTIME="$AAVMF_VARS_RUNTIME" \
BOOT_TIMEOUT="$BOOT_TIMEOUT" \
MACHINE_OPTS="$MACHINE_OPTS" \
"$ROOT_DIR/scripts/run_esxi8_boot_installed_check.sh" \
  "$DISK_IMG" \
  "$BOOT_LOG"

echo
echo "E2E PASS"
echo "- Install log: $INSTALL_LOG"
echo "- Boot log:    $BOOT_LOG"
