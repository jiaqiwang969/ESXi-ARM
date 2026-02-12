#!/usr/bin/env bash
set -euo pipefail

# One-shot bootstrap for ESXi on QEMU (macOS vmnet-shared):
# - boot VM in background
# - discover guest IP by MAC on bridge100
# - try enabling SSH via DCUI sendkey (QEMU monitor)
# - write work/vm/esxi_info.env
#
# Usage:
#   sudo ROOT_PASSWORD='VMware123!' work/scripts/esxi_vmnet_bootstrap.sh [disk.qcow2]

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

DISK_IMG=${1:-"$ROOT_DIR/vm/esxi-install-e2e.qcow2"}
AAVMF_VARS_RUNTIME=${AAVMF_VARS_RUNTIME:-"$ROOT_DIR/vm/AAVMF_VARS-esxi-e2e.fd"}
ROOT_PASSWORD=${ROOT_PASSWORD:-VMware123!}

MAC_ADDR=${MAC_ADDR:-52:54:00:12:34:56}
MONITOR_SOCK=${MONITOR_SOCK:-"$ROOT_DIR/vm/qemu-monitor.sock"}
SERIAL_SOCK=${SERIAL_SOCK:-"$ROOT_DIR/vm/qemu-serial.sock"}
PID_FILE=${PID_FILE:-"$ROOT_DIR/vm/qemu.pid"}
INFO_FILE=${INFO_FILE:-"$ROOT_DIR/vm/esxi_info.env"}

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  die "vmnet-shared requires root on macOS. Run with sudo."
fi

for f in "$DISK_IMG" "$AAVMF_VARS_RUNTIME"; do
  [[ -f "$f" ]] || die "not found: $f"
done

ARP_BIN=/usr/sbin/arp
IFCONFIG_BIN=/sbin/ifconfig
PING_BIN=/sbin/ping
NC_BIN=/usr/bin/nc

find_bridge_subnet_prefix() {
  # Returns e.g. "192.168.2." from bridge100 inet address.
  "$IFCONFIG_BIN" bridge100 2>/dev/null | awk '/inet[[:space:]]/ {print $2; exit}' | sed 's/\.[0-9]*$/./'
}

find_guest_ip_by_arp() {
  # Normalize MACs to 2-hex-digit octets, then match.
  local target
  target=$(echo "$MAC_ADDR" | awk -F: '{
    for (i=1;i<=NF;i++) {
      oct=tolower($i);
      if (length(oct)==1) oct="0"oct;
      out=(i==1?oct:out":"oct);
    }
    print out;
  }')

  "$ARP_BIN" -a 2>/dev/null | awk -v target="$target" '
    {
      ip=$2; gsub(/[()]/,"",ip);
      mac=$4;
      n=split(mac,a,":");
      if (n < 6) next;
      norm="";
      for(i=1;i<=n;i++){
        oct=tolower(a[i]);
        if(length(oct)==1) oct="0"oct;
        norm=(i==1?oct:norm":"oct);
      }
      if(norm==target){
        print ip;
        exit 0;
      }
    }
  '
}

check_port_open() {
  local ip="$1"
  local port="$2"
  "$NC_BIN" -z -w 3 "$ip" "$port" >/dev/null 2>&1
}

log "Stopping any previous vmnet-shared VM (best-effort)..."
if [[ -f "$PID_FILE" || -S "$MONITOR_SOCK" || -S "$SERIAL_SOCK" ]]; then
  # Ignore failure; user might have another VM.
  "$ROOT_DIR/scripts/esxi_vmnet_kill.sh" >/dev/null 2>&1 || true
fi

log "Booting ESXi VM in background (vmnet-shared)..."
DISK_IMG="$DISK_IMG" \
AAVMF_VARS_RUNTIME="$AAVMF_VARS_RUNTIME" \
MAC_ADDR="$MAC_ADDR" \
MONITOR_SOCK="$MONITOR_SOCK" \
SERIAL_SOCK="$SERIAL_SOCK" \
PID_FILE="$PID_FILE" \
"$ROOT_DIR/scripts/run_esxi8_boot_installed_vmnet.sh" --bg "$DISK_IMG"

QEMU_PID=""
if [[ -f "$PID_FILE" ]]; then
  QEMU_PID=$(cat "$PID_FILE" 2>/dev/null || true)
fi

log "Waiting for bridge100 subnet..."
SUBNET_PREFIX=""
for _ in $(seq 1 60); do
  SUBNET_PREFIX=$(find_bridge_subnet_prefix || true)
  if [[ -n "$SUBNET_PREFIX" ]]; then
    break
  fi
  sleep 1
done
[[ -n "$SUBNET_PREFIX" ]] || die "bridge100 not found / no inet address. Is vmnet-shared supported on this host?"
log "bridge100 subnet: ${SUBNET_PREFIX}0/24"

log "Waiting for ESXi DHCP + ARP entry (by MAC)..."
GUEST_IP=""
for t in $(seq 1 120); do
  # Gentle ping sweep to populate ARP; keep the range small.
  if (( t % 10 == 1 )); then
    for i in $(seq 2 20); do
      "$PING_BIN" -c 1 -W 1000 "${SUBNET_PREFIX}${i}" >/dev/null 2>&1 || true
    done
  fi

  GUEST_IP=$(find_guest_ip_by_arp || true)
  if [[ -n "$GUEST_IP" ]]; then
    log "Guest IP found: $GUEST_IP"
    break
  fi
  sleep 2
done
[[ -n "$GUEST_IP" ]] || die "failed to discover ESXi IP via ARP (MAC=$MAC_ADDR)"

log "Waiting a bit for services..."
sleep 20

log "Trying to enable SSH via DCUI sendkey (best-effort)..."
ROOT_PASSWORD="$ROOT_PASSWORD" \
MONITOR_SOCK="$MONITOR_SOCK" \
"$ROOT_DIR/scripts/esxi_vmnet_enable_ssh.sh" || true

log "Checking connectivity..."
if check_port_open "$GUEST_IP" 443; then
  log "HTTPS port 443: reachable"
else
  log "WARN: HTTPS port 443 not reachable yet"
fi
if check_port_open "$GUEST_IP" 22; then
  log "SSH port 22: reachable"
else
  log "WARN: SSH port 22 not reachable yet (may need manual enable in DCUI)"
fi

log "Writing connection info: $INFO_FILE"
mkdir -p "$(dirname "$INFO_FILE")"
cat >"$INFO_FILE" <<EOF
# ESXi VM connection info (vmnet-shared)
# Generated: $(date -Iseconds)
ESXI_IP=$GUEST_IP
ESXI_USER=root
ESXI_PASSWORD=$ROOT_PASSWORD
ESXI_MAC=$MAC_ADDR
QEMU_PID=${QEMU_PID:-}
DISK_IMG=$DISK_IMG
AAVMF_VARS_RUNTIME=$AAVMF_VARS_RUNTIME
MONITOR_SOCK=$MONITOR_SOCK
SERIAL_SOCK=$SERIAL_SOCK
EOF

log "Done."
log "  source $INFO_FILE"
log "  ssh root@$GUEST_IP"
log "  https://$GUEST_IP/"
