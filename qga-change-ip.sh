#!/bin/sh
# Run change-ip.sh inside a libvirt VM through qemu guest agent. No network or token needed in the guest.
# Usage: qga-change-ip.sh <domain> <old-ip> <new-ip> [gateway]
[ $# -ge 3 ] || { echo "Usage: $0 <domain> <old-ip> <new-ip> [gateway]" >&2; exit 1; }
VM=$1; shift
SCRIPT=$(base64 -w0 "$(dirname "$0")/change-ip.sh") || exit 1
ARGS=$(printf ',"%s"' "$@")

R=$(virsh qemu-agent-command "$VM" "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/sh\",\"arg\":[\"-s\",\"--\"$ARGS],\"input-data\":\"$SCRIPT\",\"capture-output\":true}}") || exit 1
PID=$(echo "$R" | sed 's/.*"pid":\([0-9]*\).*/\1/')

while :; do
  R=$(virsh qemu-agent-command "$VM" "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$PID}}") || exit 1
  case $R in *'"exited":true'*) break ;; esac
  sleep 1
done
echo "$R" | sed -n 's/.*"out-data":"\([^"]*\)".*/\1/p' | base64 -d
echo "$R" | sed -n 's/.*"err-data":"\([^"]*\)".*/\1/p' | base64 -d >&2
case $R in *'"exitcode":0'*) ;; *) exit 1 ;; esac
