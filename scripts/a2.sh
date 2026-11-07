#!/usr/bin/env bash
# PlatLab A2 harness (latent /etc/fstab problem). Reading this file spoils the lab.
# Usage: sudo bash a2.sh inject|check|reset
# SNAPSHOT THE VM FIRST. After inject, the box only breaks at the next reboot.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
MARK="# platlab-a2"

inject() {
  cp -a /etc/fstab /etc/fstab.platlab-a2.bak
  mkdir -p /data/reports
  printf 'UUID=0badf00d-1234-4bcd-9abc-000000000001 /data/reports ext4 defaults 0 2 %s\n' "$MARK" >> /etc/fstab
  systemctl daemon-reload
  echo "Injected. Ticket: 'Storage team says a new reports volume was added to fstab last week. Please confirm the server is healthy before tonight's kernel-update reboot.'"
}

check() {
  local rc=0
  if grep -q "$MARK" /etc/fstab; then
    if grep "$MARK" /etc/fstab | grep -Eq 'nofail'; then
      echo "PASS  entry is tolerated (nofail) - acceptable only if the app can run without this mount"
    else
      echo "FAIL  the marked fstab entry is still present without nofail"; rc=1
    fi
  else
    echo "PASS  broken entry removed or corrected"
  fi
  findmnt --verify --verbose >/tmp/platlab-a2-verify.txt 2>&1 && echo "PASS  findmnt --verify is clean" \
    || { echo "FAIL  findmnt --verify still reports problems (see /tmp/platlab-a2-verify.txt)"; rc=1; }
  return $rc
}

reset() {
  sed -i "/${MARK}/d" /etc/fstab
  systemctl daemon-reload
  rmdir /data/reports /data 2>/dev/null || true
  echo "Reset complete (fstab entry removed)."
}

case "${1:-}" in
  inject) inject ;; check) check ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 inject|check|reset"; exit 1 ;;
esac
