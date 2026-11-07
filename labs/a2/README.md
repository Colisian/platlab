# a2.sh — Latent Boot Failure

> [!NOTE]
> Runnable script: [`scripts/a2.sh`](../../scripts/a2.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

> [!WARNING]
> **Spoiler alert**
> Reading this script, and especially the collapsed sections below, reveals how the lab is broken. Finish the lab first: *A2 - Latent Boot Failure and Rescue Mode*.

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Spoiler: What the Faults Are](#spoiler-what-the-faults-are)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Harness for the `/etc/fstab` lab. It plants a problem that does not affect the running system but would break the next boot. It has no `baseline` step because it only needs `inject`.

**Used by:** *A2 - Latent Boot Failure and Rescue Mode*

| Command | What it does |
|---|---|
| `inject` | Backs up `/etc/fstab`, creates a mount point, appends one entry, and reloads systemd. The server keeps running normally; the problem only shows on the next reboot. **Snapshot the VM first.** |
| `check` | Passes if the marked entry was removed or made non-fatal with `nofail`, and if `findmnt --verify` is clean. Writes the verify output to `/tmp/platlab-a2-verify.txt`. |
| `reset` | Removes the marked line from `/etc/fstab`, reloads systemd, and removes the empty mount directories. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash a2.sh inject
sudo bash a2.sh check
sudo bash a2.sh reset
```

---

## Spoiler: What the Faults Are
> [↑ Back to TOC](#table-of-contents)

<details><summary>Spoiler: open only after you have a written root cause</summary>

The appended line is `UUID=0badf00d-1234-4bcd-9abc-000000000001 /data/reports ext4 defaults 0 2` tagged with a `# platlab-a2` marker. That UUID does not exist, and the entry has no `nofail`, so systemd waits for the device and then drops into emergency mode on the next boot.

</details>

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. Any systemd Linux. `findmnt` (util-linux).
- **Safety:** **This one can leave a VM unbootable if you reboot with the fault in place.** That is Part 2 of the lab, and it needs hypervisor console access and a snapshot.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

<details><summary>Full script (click to expand; this reveals the faults)</summary>

```bash
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
```

</details>
