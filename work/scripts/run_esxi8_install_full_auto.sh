#!/usr/bin/env bash
set -euo pipefail

# Fully automate ESXi-Arm installation in QEMU:
# welcome -> EULA -> target disk -> OSData -> keyboard -> root password ->
# warning acknowledgement -> confirm install -> wait Installation Complete -> exit/reboot.
#
# Note:
# - This script keeps installer payload attached during install.
# - With MACHINE_OPTS defaulting to gic-version=2, installer reboot path is stable in our tests.
# - If your environment still shows reboot instability, use REBOOT_ACTION=poweroff as fallback.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

PAYLOAD_DIR=${1:-"$ROOT_DIR/out/esxi8-allowlegacy-payload"}
DISK_IMG=${2:-"$ROOT_DIR/vm/esxi-install-usb-auto.qcow2"}
LOG_PATH=${3:-"$ROOT_DIR/out/esxi8-install-full-auto.log"}

AAVMF_CODE=${AAVMF_CODE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd"}
AAVMF_VARS_TEMPLATE=${AAVMF_VARS_TEMPLATE:-"$ROOT_DIR/firmware/ubuntu-aavmf-2022.02/AAVMF_VARS.fd"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-install.fd"}

ACCEL=${ACCEL:-tcg}
MACHINE_OPTS=${MACHINE_OPTS:-virt,virtualization=off,gic-version=2}
RAM_MB=${RAM_MB:-8192}
CPUS=${CPUS:-4}
DISK_SIZE=${DISK_SIZE:-40G}
DISK_BUS=${DISK_BUS:-usb}
ROOT_PASSWORD=${ROOT_PASSWORD:-VMware123!}
REBOOT_ACTION=${REBOOT_ACTION:-enter}
REBOOT_OBSERVE_SEC=${REBOOT_OBSERVE_SEC:-180}

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
if [[ -z "$ROOT_PASSWORD" ]]; then
  echo "ERROR: ROOT_PASSWORD must not be empty" >&2
  exit 2
fi
case "$REBOOT_ACTION" in
  poweroff|enter)
    ;;
  *)
    echo "ERROR: unsupported REBOOT_ACTION='$REBOOT_ACTION' (supported: poweroff, enter)" >&2
    exit 2
    ;;
esac
if ! [[ "$REBOOT_OBSERVE_SEC" =~ ^[0-9]+$ ]]; then
  echo "ERROR: REBOOT_OBSERVE_SEC must be an integer, got '$REBOOT_OBSERVE_SEC'" >&2
  exit 2
fi

mkdir -p "$(dirname "$DISK_IMG")" "$(dirname "$AAVMF_VARS_RUNTIME")" "$(dirname "$LOG_PATH")"
if [[ ! -f "$DISK_IMG" ]]; then
  echo "Creating disk image: $DISK_IMG ($DISK_SIZE)"
  qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" >/dev/null
fi

# Fresh vars for install run.
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
if {[llength $argv] < 5} {
  puts stderr "usage: expect <log> <qemu_cmd> <root_password> <reboot_action> <reboot_observe_sec>"
  exit 2
}
set log_path [lindex $argv 0]
set qemu_cmd [lindex $argv 1]
set root_pw [lindex $argv 2]
set reboot_action [lindex $argv 3]
set reboot_observe_sec [lindex $argv 4]
set timeout 1800
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

step {\(Enter\) Continue} 1200 "welcome"
after 800
send "\r"

step {\(F11\) Accept and Continue} 1200 "eula"
after 800
send "\033\[23~"

step {Select a Disk to Install or Upgrade} 1200 "disk"
# Disk #1 is payload USB, disk #2 is install target USB.
after 1000
send "\033\[B"
after 600
send "\r"

set timeout 900
expect {
  -re {Select a Disk to store ESX OSData} {}
  -re {minimum space} {
    after 600
    send "\r"
    after 900
    send "\033\[B"
    after 600
    send "\r"
    step {Select a Disk to store ESX OSData} 900 "osdata_after_retry"
  }
  timeout { fail "osdata" }
  eof { fail "eof_osdata" }
}

after 900
send "\r"

set timeout 600
expect {
  -re {USB/SD-Card device Configuration|installed on a USB/SD device} {
    after 800
    send "\r"
  }
  -re {Please select a keyboard layout|Select a Keyboard Layout} {}
  timeout {}
}

step {Please select a keyboard layout|Select a Keyboard Layout} 900 "keyboard"
after 800
send "\r"

step {Enter a root password|Root password|Confirm password} 900 "root_password"
after 600
send -- "$root_pw\r"
after 400
send "\t"
after 400
send -- "$root_pw\r"
after 600
send "\r"

# Some runs show HARDWARE_VIRTUALIZATION warning page before confirm.
set timeout 600
expect {
  -re {Error\(s\)/Warning\(s\) Found During System Scan} {
    after 700
    send "\r"
    step {Confirm Install|\(F11\) Install} 600 "confirm_after_warning"
  }
  -re {Confirm Install|\(F11\) Install} {}
  timeout { fail "confirm_install" }
  eof { fail "eof_confirm_install" }
}

after 800
send "\033\[23~"

# ANSI redraws are noisy; wait for key phrase.
step {Installation Complete} 3600 "installation_complete"

if {$reboot_action eq "enter"} {
  # Trigger reboot from completion page.
  after 700
  send "\r"

  # Observe reboot path for panic or successful handoff back to firmware.
  set timeout $reboot_observe_sec
  expect {
    -re {VERIFY bora/vmkernel/hardware/arm64/its.c:2934|Module\(s\) involved in panic|PanicvPanicInt|PSOD} {
      puts "\nWARN: detected shutdown panic signature during installer reboot path."
    }
    -re {BdsDxe: loading|BdsDxe: starting|UEFI Interactive Shell|VMware ESXi 8\.0\.3 \[Releasebuild} {
      puts "\nINFO: reboot path reached firmware/kernel handoff without panic signature."
    }
    timeout {
      puts "\nWARN: reboot observe timeout reached without panic/handoff marker."
    }
    eof {}
  }
} elseif {$reboot_action eq "poweroff"} {
  puts "\nINFO: Installation Complete reached; quitting QEMU without installer reboot."
} else {
  fail "invalid_reboot_action"
}

after 500
send "\001x"
expect eof

puts "\nAuto install flow finished."
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
echo "Root pw len: ${#ROOT_PASSWORD} chars"
echo "Reboot mode: $REBOOT_ACTION"
echo "Reboot obs:  ${REBOOT_OBSERVE_SEC}s"

/usr/bin/expect "$EXPECT_SCRIPT" "$LOG_PATH" "$QEMU_CMD" "$ROOT_PASSWORD" "$REBOOT_ACTION" "$REBOOT_OBSERVE_SEC"

if grep -Eaq "VERIFY bora/vmkernel/hardware/arm64/its.c:2934|Module\\(s\\) involved in panic" "$LOG_PATH"; then
  echo "WARN: shutdown panic signature found in install log: $LOG_PATH" >&2
  echo "      Workaround: use REBOOT_ACTION=poweroff, then boot disk-only for validation." >&2
fi
