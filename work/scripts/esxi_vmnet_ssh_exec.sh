#!/usr/bin/env bash
set -euo pipefail

# Execute a command on ESXi via SSH using expect (password auth).
#
# Usage:
#   work/scripts/esxi_vmnet_ssh_exec.sh "esxcli system version get"
#
# By default reads connection info from work/vm/esxi_info.env.

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INFO_FILE=${INFO_FILE:-"$ROOT_DIR/vm/esxi_info.env"}

if [[ -f "$INFO_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$INFO_FILE"
fi

ESXI_IP=${ESXI_IP:-}
ESXI_USER=${ESXI_USER:-root}
ESXI_PASSWORD=${ESXI_PASSWORD:-VMware123!}

if [[ -z "${ESXI_IP:-}" ]]; then
  echo "ERROR: ESXI_IP is empty. Set ESXI_IP or source $INFO_FILE" >&2
  exit 2
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <command>" >&2
  exit 2
fi

EXPECT_BIN=${EXPECT_BIN:-/usr/bin/expect}
[[ -x "$EXPECT_BIN" ]] || { echo "ERROR: expect not found: $EXPECT_BIN" >&2; exit 2; }

CMD="$*"
TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT

"$EXPECT_BIN" <<EXPECT_EOF >"$TMPOUT" 2>/dev/null
log_user 0
set timeout 30
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ${ESXI_USER}@${ESXI_IP}
expect {
  "Password:" { send "${ESXI_PASSWORD}\r" }
  "password:" { send "${ESXI_PASSWORD}\r" }
  timeout { exit 1 }
}
expect -re {~\] }
send "${CMD}\r"
log_user 1
expect -re {~\] }
send "exit\r"
expect eof
EXPECT_EOF

# Strip the echoed command line and trailing prompt.
sed '1d;$d' "$TMPOUT"

