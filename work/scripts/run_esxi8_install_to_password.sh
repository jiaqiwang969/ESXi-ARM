#!/usr/bin/env bash
set -euo pipefail

# Auto-drive ESXi-Arm installer to the root-password screen, then hand over to user input.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

PAYLOAD_DIR=${1:-"$ROOT_DIR/out/esxi8-allowlegacy-payload"}
DISK_IMG=${2:-"$ROOT_DIR/vm/esxi-install-usb.qcow2"}
LOG_PATH=${3:-"$ROOT_DIR/out/esxi8-install-to-password.log"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_TEMPLATE=${AAVMF_VARS_TEMPLATE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_VARS.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-install.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
DISK_SIZE=${DISK_SIZE:-40G}
DISK_BUS=${DISK_BUS:-usb}

if [[ ! -d "$PAYLOAD_DIR" ]]; then
  echo "ERROR: payload dir not found: $PAYLOAD_DIR" >&2
  exit 2
fi
if [[ ! -f "$PAYLOAD_DIR/EFI/BOOT/BOOTAA64.EFI" ]]; then
  echo "ERROR: payload missing EFI/BOOT/BOOTAA64.EFI: $PAYLOAD_DIR" >&2
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

mkdir -p "$(dirname "$DISK_IMG")" "$(dirname "$AAVMF_VARS_RUNTIME")" "$(dirname "$LOG_PATH")"
if [[ ! -f "$DISK_IMG" ]]; then
  echo "Creating disk image: $DISK_IMG ($DISK_SIZE)"
  qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" >/dev/null
fi
cp -f "$AAVMF_VARS_TEMPLATE" "$AAVMF_VARS_RUNTIME"

if [[ "$ACCEL" == "hvf" ]]; then
  CPU_MODEL=${CPU_MODEL:-host}
else
  CPU_MODEL=${CPU_MODEL:-max}
fi

case "$DISK_BUS" in
  usb)
    DISK_DEVICE_ARG="-device usb-storage,bus=xhci.0,drive=esxidisk"
    ;;
  nvme)
    DISK_DEVICE_ARG="-device nvme,serial=esxiinstall,drive=esxidisk"
    ;;
  *)
    echo "ERROR: unsupported DISK_BUS='$DISK_BUS' (supported: usb, nvme)" >&2
    exit 2
    ;;
esac

QEMU_CMD=$(cat <<CMD
qemu-system-aarch64 \
  -accel $ACCEL \
  -machine $MACHINE_OPTS \
  -cpu $CPU_MODEL \
  -smp $CPUS \
  -m $RAM_MB \
  -device qemu-xhci,id=xhci \
  -drive if=none,id=esxiboot,format=raw,file=fat:rw:$PAYLOAD_DIR \
  -device usb-storage,bus=xhci.0,drive=esxiboot,bootindex=0 \
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
if {[llength $argv] < 2} {
  puts stderr "usage: expect <log> <qemu_cmd>"
  exit 2
}
set log_path [lindex $argv 0]
set qemu_cmd [lindex $argv 1]
set timeout 900
log_user 1
log_file -a $log_path
spawn -noecho bash -lc $qemu_cmd

proc fail {msg} {
  send "\001x"
  puts "\nERROR: $msg"
  exit 1
}
proc step {pat t err} {
  set timeout $t
  expect {
    -re $pat { return }
    timeout { fail $err }
    eof { fail "eof_$err" }
  }
}

step {\(Enter\) Continue} 900 "welcome"
after 1000
send "\r"

step {\(F11\) Accept and Continue} 900 "eula"
after 1000
send "\033\[23~"

step {Select a Disk to Install or Upgrade} 900 "disk"
# For USB target mode, installer payload is first disk, target disk is usually second.
after 1200
send "\033\[B"
after 700
send "\r"

set timeout 600
expect {
  -re {Select a Disk to store ESX OSData} {}
  -re {minimum space} {
    after 700
    send "\r"
    after 900
    send "\033\[B"
    after 700
    send "\r"
    step {Select a Disk to store ESX OSData} 600 "osdata_after_retry"
  }
  timeout { fail "osdata" }
  eof { fail "eof_osdata" }
}

after 1000
send "\r"

set timeout 360
expect {
  -re {USB/SD-Card device Configuration|installed on a USB/SD device} {
    after 1000
    send "\r"
  }
  -re {Please select a keyboard layout|Select a Keyboard Layout} {}
  timeout {}
}

step {Please select a keyboard layout|Select a Keyboard Layout} 900 "keyboard"
after 1000
send "\r"

step {Enter a root password|Root password|Confirm password} 900 "root_password"

puts "\nReached root-password screen. You can continue manually now."
puts "Tips: fill password + confirm, then continue with Enter/F11 prompts."
puts "To exit QEMU from this terminal: Ctrl-a then x"
interact
EXP
chmod +x "$EXPECT_SCRIPT"

echo "Log:         $LOG_PATH"
echo "Payload:     $PAYLOAD_DIR"
echo "Disk:        $DISK_IMG"
echo "Disk bus:    $DISK_BUS"
echo "Firmware:    $AAVMF_CODE"
echo "Vars:        $AAVMF_VARS_RUNTIME"
echo "Accel/CPU:   $ACCEL / $CPU_MODEL"
echo "Machine:     $MACHINE_OPTS"
echo "RAM/CPUs:    ${RAM_MB}MB / $CPUS"

/usr/bin/expect "$EXPECT_SCRIPT" "$LOG_PATH" "$QEMU_CMD"
