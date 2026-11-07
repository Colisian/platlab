# a4.sh — Memory Pressure and OOM

> [!NOTE]
> Runnable script: [`scripts/a4.sh`](../../scripts/a4.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

> [!WARNING]
> **Spoiler alert**
> Reading this script, and especially the collapsed sections below, reveals how the lab is broken. Finish the lab first: *A4 - Memory Pressure and the OOM Killer*.

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Spoiler: What the Faults Are](#spoiler-what-the-faults-are)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Harness for the OOM lab. It runs a small service that leaks memory, but inside a cgroup memory limit, so the kernel kills only that service and never threatens the VM.

**Used by:** *A4 - Memory Pressure and the OOM Killer*

| Command | What it does |
|---|---|
| `baseline` | Writes the leaking program to `/opt/platlab/leaky-report.py` and a systemd unit `platlab-report.service` (with `MemoryMax=256M`, `Restart=always`), then reloads systemd. |
| `inject` | Records the start time and starts the service. It then takes a few minutes for a clear restart pattern to appear. |
| `check` | Prints `WAIT` until 5 minutes after inject (a quiet log that early proves nothing). After that it passes if there were no OOM kills in the last 4 minutes **and** a memory limit is still enforced. Removing the limit is treated as a forbidden shortcut. |
| `reset` | Stops the service and removes the unit, any drop-ins, the program, and the start-time marker. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash a4.sh baseline      # snapshot the VM after this step
sudo bash a4.sh inject
sudo bash a4.sh check
sudo bash a4.sh reset
```

---

## Spoiler: What the Faults Are
> [↑ Back to TOC](#table-of-contents)

<details><summary>Spoiler: open only after you have a written root cause</summary>

The program allocates and touches about 8 MB per second forever, so it reaches the 256 MB limit in about 30 seconds, gets OOM-killed by its cgroup, and restarts 10 seconds later.

</details>

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. systemd with cgroup v2 memory accounting. `python3`.
- **Safety:** Memory is capped by `MemoryMax` and swap is disabled for the unit, so the host stays healthy.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

<details><summary>Full script (click to expand; this reveals the faults)</summary>

```bash
#!/usr/bin/env bash
# PlatLab A4 harness (memory / OOM). Reading past this line spoils the lab.
# Usage: sudo bash a4.sh baseline|inject|check|reset
# The leaky service is capped by a cgroup (MemoryMax), so it cannot take the whole VM down.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

baseline() {
  mkdir -p /opt/platlab
  cat > /opt/platlab/leaky-report.py <<'EOF'
import time
chunks = []
while True:
    block = bytearray(8 * 1024 * 1024)
    for i in range(0, len(block), 4096):
        block[i] = 1
    chunks.append(block)
    time.sleep(1)
EOF
  cat > /etc/systemd/system/platlab-report.service <<'EOF'
[Unit]
Description=PlatLab nightly report generator (owner: analytics team)

[Service]
ExecStart=/usr/bin/python3 /opt/platlab/leaky-report.py
MemoryMax=256M
MemorySwapMax=0
Restart=always
RestartSec=10
EOF
  systemctl daemon-reload
  echo "Baseline OK. Snapshot, then run inject."
}

inject() {
  date +%s > /var/lib/platlab-a4.started
  systemctl start platlab-report.service
  echo "Injected. Ticket: 'The reporting service keeps restarting and analytics keeps missing their reports. It has been happening since Monday's release.' Wait ~5 minutes before investigating."
}

check() {
  local rc=0
  local started; started=$(cat /var/lib/platlab-a4.started 2>/dev/null || echo 0)
  if (( $(date +%s) - started < 300 )); then
    echo "WAIT  results are only meaningful 5 minutes after inject (started $(( $(date +%s) - started ))s ago); a quiet log this early proves nothing"
    return 1
  fi
  local recent; recent=$(journalctl -k --since "-4 min" --no-pager 2>/dev/null | grep -ci 'out of memory\|oom-kill' || true)
  if [[ $recent -eq 0 ]]; then echo "PASS  no OOM kills in the last 4 minutes"; else echo "FAIL  $recent OOM log lines in the last 4 minutes"; rc=1; fi
  local mm; mm=$(systemctl show platlab-report.service -p MemoryMax --value 2>/dev/null || echo unknown)
  if [[ $mm != infinity && $mm != unknown && $mm != "" ]]; then echo "PASS  a memory limit is still enforced ($mm)"
  else echo "FAIL  the memory limit was removed (MemoryMax=$mm): the host is now exposed"; rc=1; fi
  return $rc
}

reset() {
  systemctl stop platlab-report.service 2>/dev/null || true
  systemctl reset-failed platlab-report.service 2>/dev/null || true
  rm -f /var/lib/platlab-a4.started
  rm -rf /etc/systemd/system/platlab-report.service /etc/systemd/system/platlab-report.service.d /opt/platlab
  systemctl daemon-reload
  echo "Reset complete."
}

case "${1:-}" in
  baseline) baseline ;; inject) inject ;; check) check ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 baseline|inject|check|reset"; exit 1 ;;
esac
```

</details>
