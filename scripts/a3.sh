#!/usr/bin/env bash
# PlatLab A3 harness (storage). Reading past this line spoils the lab.
# Usage: sudo bash a3.sh baseline|inject|check|reset
# Uses loopback-file filesystems only. Nothing here touches the root filesystem.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
D=/var/lib/platlab-a3
DATA=/mnt/platlab-data
SPOOL=/mnt/platlab-spool

baseline() {
  mkdir -p "$D" "$DATA" "$SPOOL"
  truncate -s 256M "$D/data.img";  mkfs.ext4 -q -F "$D/data.img"
  truncate -s 64M  "$D/spool.img"; mkfs.ext4 -q -F -N 1024 "$D/spool.img"
  mountpoint -q "$DATA"  || mount -o loop "$D/data.img"  "$DATA"
  mountpoint -q "$SPOOL" || mount -o loop "$D/spool.img" "$SPOOL"
  mkdir -p "$DATA/app" "$DATA/exports" "$DATA/cache" "$SPOOL/sessions"
  echo "Baseline OK: $DATA (256M, normal inodes) and $SPOOL (64M, ~1000 inodes). Snapshot, then run inject."
}

inject() {
  # 1) A deleted-but-still-open log: bytes used, invisible to du.
  setsid nohup bash -c "exec 9>$DATA/app/reports.log; dd if=/dev/zero bs=1M count=130 status=none >&9; rm -f $DATA/app/reports.log; exec -a platlab-reporter sleep 1000000" >/dev/null 2>&1 &
  # 2) Legitimate-looking large data the user must not casually delete.
  dd if=/dev/urandom of="$DATA/exports/quarterly-export.tar" bs=1M count=30 status=none
  dd if=/dev/urandom of="$DATA/cache/blob.cache" bs=1M count=15 status=none
  # 3) Inode exhaustion on the spool filesystem.
  for i in $(seq 1 1200); do
    { : > "$SPOOL/sessions/sess_$i"; } 2>/dev/null || break
  done
  sleep 2
  echo "Injected. Ticket: 'Uploads to the spool fail with an error, and the data volume is nearly full, but nobody can find the big files.'"
}

check() {
  local rc=0
  local u; u=$(df --output=pcent "$DATA" | tail -1 | tr -dc 0-9)
  [[ $u -lt 70 ]] && pass_data=1 || pass_data=0
  if [[ $pass_data == 1 ]]; then echo "PASS  $DATA usage ${u}%"; else echo "FAIL  $DATA usage ${u}% (want <70%)"; rc=1; fi
  local iu; iu=$(df --output=ipcent "$SPOOL" | tail -1 | tr -dc 0-9)
  if [[ $iu -lt 80 ]]; then echo "PASS  $SPOOL inode usage ${iu}%"; else echo "FAIL  $SPOOL inode usage ${iu}% (want <80%)"; rc=1; fi
  if { : > "$SPOOL/.write-test"; } 2>/dev/null; then rm -f "$SPOOL/.write-test"; echo "PASS  new files can be created in spool"; else echo "FAIL  cannot create files in spool"; rc=1; fi
  if [[ -f "$DATA/exports/quarterly-export.tar" ]]; then echo "PASS  quarterly-export.tar preserved"; else echo "FAIL  quarterly-export.tar was deleted (was anyone asked?)"; rc=1; fi
  return $rc
}

reset() {
  pkill -f platlab-reporter 2>/dev/null || true
  sleep 1
  umount "$DATA" 2>/dev/null || true
  umount "$SPOOL" 2>/dev/null || true
  rm -rf "$D"
  rmdir "$DATA" "$SPOOL" 2>/dev/null || true
  echo "Reset complete."
}

case "${1:-}" in
  baseline) baseline ;; inject) inject ;; check) check ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 baseline|inject|check|reset"; exit 1 ;;
esac
