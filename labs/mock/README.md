# mock.sh — Blind Mock Practical

> [!NOTE]
> Runnable script: [`scripts/mock.sh`](../../scripts/mock.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Wrapper that turns the individual fault labs into a blind capstone. It picks two of the labs A1, A3, A4, A5, A6 at random, builds and breaks them, and prints one deliberately vague ticket. The two chosen labs are stored in a root-only state file so you do not know which they are until you ask.

**Used by:** *E1 - Blind Mock Practical*

| Command | What it does |
|---|---|
| `start` | Randomly chooses two labs, runs each one's `baseline` then `inject` with output hidden, saves the choice to `/root/.platlab-mock`, and prints the ticket and rules. Start your timer when the ticket prints. |
| `grade` | Runs the `check` step of each chosen lab and prints its `PASS`/`FAIL` lines. Note that `a4`'s check prints `WAIT` until 5 minutes after start. |
| `reveal` | Prints which two labs were injected. |
| `reset` | Runs `reset` for each chosen lab and removes the state file. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash mock.sh start
sudo bash mock.sh grade
sudo bash mock.sh reveal
sudo bash mock.sh reset
```

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. `a1.sh a3.sh a4.sh a5.sh a6.sh` must be in the **same directory** as `mock.sh`. Use a fresh VM or a snapshot after OS install.
- **Safety:** Inherits every side effect of the five labs it can pick, so read their notes first. Do not open the other scripts before you finish.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

```bash
#!/usr/bin/env bash
# PlatLab mock-practical harness: picks TWO faults at random so you get a blind capstone.
# Usage: sudo bash mock.sh start|grade|reveal|reset
# Requires a1.sh a3.sh a4.sh a5.sh a6.sh in the same directory. Snapshot the VM first.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE=/root/.platlab-mock
POOL=(a1 a3 a4 a5 a6)

start() {
  mapfile -t picks < <(printf '%s\n' "${POOL[@]}" | shuf -n 2)
  printf '%s\n' "${picks[@]}" > "$STATE"; chmod 600 "$STATE"
  for p in "${picks[@]}"; do
    bash "$DIR/$p.sh" baseline >/dev/null 2>&1
    bash "$DIR/$p.sh" inject   >/dev/null 2>&1
  done
  cat <<'EOF'

=== TICKET ===
Priority: High.  Reporter: service owner.
"Since this morning some things on this server are broken. People are complaining and I do not
know whether it is one problem or several. I need it working again and I need to understand
what happened so it does not repeat."

Timebox: 45 minutes to diagnose and remediate, 15 minutes to present.
Rules: gather evidence before changing state; keep security controls on; write your timeline.
Run `sudo bash mock.sh grade` when you believe you are done. Do NOT open the other scripts.
EOF
}

grade() {
  local rc=0
  while read -r p; do echo "--- $p ---"; bash "$DIR/$p.sh" check || rc=1; done < "$STATE"
  return $rc
}

reveal() { echo "Faults injected (lab IDs):"; cat "$STATE"; }

reset() {
  if [[ -f $STATE ]]; then while read -r p; do bash "$DIR/$p.sh" reset || true; done < "$STATE"; rm -f "$STATE"; fi
}

case "${1:-}" in
  start) start ;; grade) grade ;; reveal) reveal ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 start|grade|reveal|reset"; exit 1 ;;
esac
```
