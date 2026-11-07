# a3.sh — Storage Bytes and Inodes

> [!NOTE]
> Runnable script: [`scripts/a3.sh`](../../scripts/a3.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

> [!WARNING]
> **Spoiler alert**
> Reading this script, and especially the collapsed sections below, reveals how the lab is broken. Finish the lab first: *A3 - Storage Bytes Inodes and LVM*.

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Spoiler: What the Faults Are](#spoiler-what-the-faults-are)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Harness for the storage lab. It builds two small loopback filesystems so nothing can fill your real root filesystem, then creates two different kinds of "disk full" problem.

**Used by:** *A3 - Storage Bytes Inodes and LVM*

| Command | What it does |
|---|---|
| `baseline` | Creates two image files under `/var/lib/platlab-a3`, formats them ext4 (one with a deliberately small inode count), and mounts them at `/mnt/platlab-data` and `/mnt/platlab-spool`. |
| `inject` | Creates the symptoms and prints the ticket text. |
| `check` | Passes when the data mount is under 70% used, the spool mount is under 80% inode use and accepts new files, and the legitimate large file `quarterly-export.tar` still exists (deleting it is a fail). |
| `reset` | Kills the background process, unmounts both filesystems, and deletes the images and mount points. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash a3.sh baseline      # snapshot the VM after this step
sudo bash a3.sh inject
sudo bash a3.sh check
sudo bash a3.sh reset
```

---

## Spoiler: What the Faults Are
> [↑ Back to TOC](#table-of-contents)

<details><summary>Spoiler: open only after you have a written root cause</summary>

The inject step starts a background process (named `platlab-reporter`) that writes about 130 MB to a log and then has the log deleted while it keeps the file open, so the bytes stay allocated but invisible to `du`. It also writes two legitimate-looking large files, and creates about 1,000 empty files to exhaust the spool filesystem's inodes.

</details>

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. Loop-mount support (`mount -o loop`), `mkfs.ext4`, `truncate`, `dd`, `setsid`.
- **Safety:** Everything lives in loopback images and two mount points. The only lasting effect outside those is one background `sleep` process, which `reset` kills.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

<details><summary>Full script (click to expand; this reveals the faults)</summary>

```bash
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
```

</details>
