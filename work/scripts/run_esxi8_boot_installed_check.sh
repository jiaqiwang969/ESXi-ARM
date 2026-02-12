#!/usr/bin/env bash
set -euo pipefail

# Boot installed ESXi-Arm image (disk-only) and auto-verify serial markers.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

DISK_IMG=${1:-"$ROOT_DIR/vm/esxi-install-usb-auto.qcow2"}
LOG_PATH=${2:-"$ROOT_DIR/out/esxi8-boot-installed-check-$(date +%Y%m%d-%H%M%S).log"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-install.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
DISK_BUS=${DISK_BUS:-usb}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-2400}

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
    DISK_DEVICE_ARG="-device usb-storage,bus=xhci.0,drive=esxidisk,bootindex=0"
    ;;
  nvme)
    DISK_DEVICE_ARG="-device nvme,serial=esxiroot,drive=esxidisk,bootindex=0"
    ;;
  *)
    echo "ERROR: unsupported DISK_BUS='$DISK_BUS' (supported: usb, nvme)" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$LOG_PATH")"

QEMU_CMD=$(cat <<CMD
qemu-system-aarch64 \
  -accel $ACCEL \
  -machine $MACHINE_OPTS \
  -cpu $CPU_MODEL \
  -smp $CPUS \
  -m $RAM_MB \
  -device qemu-xhci,id=xhci \
  -drive if=none,id=esxidisk,file=$DISK_IMG,format=qcow2 \
  $DISK_DEVICE_ARG \
  -netdev user,id=net0 \
  -device vmxnet3,netdev=net0,mac=52:54:00:12:34:56 \
  -drive if=pflash,format=raw,readonly=on,file=$AAVMF_CODE \
  -drive if=pflash,format=raw,file=$AAVMF_VARS_RUNTIME \
  -serial mon:stdio \
  -nographic
CMD
)

EXPECT_SCRIPT=$(mktemp)
cleanup() {
  rm -f "$EXPECT_SCRIPT"
}
trap cleanup EXIT

cat > "$EXPECT_SCRIPT" <<'EXP'
#!/usr/bin/expect -f
if {[llength $argv] < 3} {
  puts stderr "usage: expect <log> <qemu_cmd> <boot_timeout_seconds>"
  exit 2
}
set log_path [lindex $argv 0]
set qemu_cmd [lindex $argv 1]
set boot_timeout [lindex $argv 2]
set timeout $boot_timeout
log_user 1
log_file -a $log_path
spawn -noecho bash -lc $qemu_cmd

proc fail {msg} {
  send "\001x"
  puts "\nERROR: $msg"
  exit 1
}

expect {
  -re {its\.c:2934|Module\(s\) involved in panic|PSOD|PanicvPanicInt} {
    fail "panic_signature"
  }
  -re {Starting VMKernel initialization|Starting VMKernel} {}
  timeout { fail "vmkernel_start_timeout" }
  eof { fail "eof_before_vmkernel" }
}

set timeout $boot_timeout
expect {
  -re {its\.c:2934|Module\(s\) involved in panic|PSOD|PanicvPanicInt} {
    fail "panic_signature"
  }
  -re {Boot complete \(2/2\)} {}
  timeout { fail "boot_complete_timeout" }
  eof { fail "eof_before_boot_complete" }
}

after 600
send "\001x"
expect eof

puts "\nBoot probe finished: boot complete marker observed."
EXP
chmod +x "$EXPECT_SCRIPT"

echo "Disk:        $DISK_IMG"
echo "Disk bus:    $DISK_BUS"
echo "Firmware:    $AAVMF_CODE"
echo "Vars:        $AAVMF_VARS_RUNTIME"
echo "Log:         $LOG_PATH"
echo "Accel/CPU:   $ACCEL / $CPU_MODEL"
echo "Machine:     $MACHINE_OPTS"
echo "RAM/CPUs:    ${RAM_MB}MB / $CPUS"
echo "Timeout:     ${BOOT_TIMEOUT}s"

/usr/bin/expect "$EXPECT_SCRIPT" "$LOG_PATH" "$QEMU_CMD" "$BOOT_TIMEOUT"
"$ROOT_DIR/scripts/check_esxi8_boot_log.py" "$LOG_PATH"
