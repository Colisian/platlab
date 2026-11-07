# a6.sh — SSH Access Failures

> [!NOTE]
> Runnable script: [`scripts/a6.sh`](../../scripts/a6.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

> [!WARNING]
> **Spoiler alert**
> Reading this script, and especially the collapsed sections below, reveals how the lab is broken. Finish the lab first: *A6 - SSH Access Failures*.

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Spoiler: What the Faults Are](#spoiler-what-the-faults-are)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Harness for the SSH lab. It creates four test users with their own key pairs, breaks three of them in three different ways, and lets you test key-based login for all four from the VM itself.

**Used by:** *A6 - SSH Access Failures*

| Command | What it does |
|---|---|
| `baseline` | Installs and starts OpenSSH server if needed, creates users `lab-alice`, `lab-bob`, `lab-carol`, `lab-dave`, generates an ed25519 key per user in `/root/platlab-keys/`, installs each public key, and confirms all four can log in. |
| `inject` | Applies the faults and prints the ticket text. |
| `try` | Attempts a key login to `127.0.0.1` for each user and prints `ok` or `DENY`. Useful as both a symptom viewer and a quick re-test. |
| `check` | Runs `try`, then verifies you did not weaken sshd: StrictModes still `yes`, root login not enabled, and `lab-alice`'s home directory not group/world writable. |
| `reset` | Removes the drop-in, deletes the four users and their home directories, and deletes the key directory. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash a6.sh baseline      # snapshot the VM after this step
sudo bash a6.sh inject
sudo bash a6.sh try
sudo bash a6.sh check
sudo bash a6.sh reset
```

---

## Spoiler: What the Faults Are
> [↑ Back to TOC](#table-of-contents)

<details><summary>Spoiler: open only after you have a written root cause</summary>

The inject step makes `lab-alice`'s home directory world-writable (StrictModes then refuses her key), sets `lab-carol`'s account expiry date in the past, and adds `DenyUsers lab-dave` in an sshd drop-in file. `lab-bob` is the healthy control.

</details>

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. RHEL family or Ubuntu/Debian. OpenSSH server and client. Package installs on first run.
- **Safety:** Creates and later deletes users starting with `lab-`. Adds and removes one sshd drop-in and reloads (not restarts) sshd, so existing sessions survive.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

<details><summary>Full script (click to expand; this reveals the faults)</summary>

```bash
#!/usr/bin/env bash
# PlatLab A6 harness (SSH access). Reading past this line spoils the lab.
# Usage: sudo bash a6.sh baseline|inject|try|check|reset
# Keep console access. Never test SSH changes only over an SSH session you cannot afford to lose.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0 <baseline|inject|try|check|reset>"; exit 1; }
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" rhel "*|*" fedora "*|*" rocky "*|*" almalinux "*|*" centos "*) FAM=rhel; SSHD=sshd ;;
  *" ubuntu "*|*" debian "*) FAM=debian; SSHD=ssh ;;
  *) echo "Unsupported OS"; exit 1 ;;
esac
USERS=(lab-alice lab-bob lab-carol lab-dave)
KEYS=/root/platlab-keys
DROPIN=/etc/ssh/sshd_config.d/60-local-access.conf

baseline() {
  if [[ $FAM == rhel ]]; then dnf -y -q install openssh-server openssh-clients
  else apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get -y -qq install openssh-server openssh-client; fi
  mkdir -p "$KEYS" /etc/ssh/sshd_config.d; chmod 700 "$KEYS"
  for u in "${USERS[@]}"; do
    id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
    chmod 700 "/home/$u"
    [[ -f $KEYS/$u ]] || ssh-keygen -q -t ed25519 -N '' -C "$u@platlab" -f "$KEYS/$u"
    install -d -m 700 -o "$u" -g "$u" "/home/$u/.ssh"
    install -m 600 -o "$u" -g "$u" "$KEYS/$u.pub" "/home/$u/.ssh/authorized_keys"
    chage -E -1 "$u"
    if [[ $FAM == rhel ]]; then restorecon -R "/home/$u"; fi
  done
  rm -f "$DROPIN"
  mkdir -p /run/sshd
  ssh-keygen -A >/dev/null
  sshd -t
  systemctl enable --now "$SSHD"
  systemctl reload "$SSHD"
  try
  echo "Baseline OK. Snapshot, then run inject."
}

inject() {
  chmod 777 /home/lab-alice
  chage -E 2020-01-01 lab-carol
  echo "DenyUsers lab-dave" > "$DROPIN"
  sshd -t
  systemctl reload "$SSHD"
  echo "Injected. Ticket: 'Three of the four analysts cannot SSH in with their keys since Friday. lab-bob is fine.' Test with: sudo bash $0 try"
}

try() {
  local rc=0
  for u in "${USERS[@]}"; do
    if ssh -q -i "$KEYS/$u" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
         -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$u@127.0.0.1" true 2>/dev/null; then
      echo "ok    $u"
    else
      echo "DENY  $u"; rc=1
    fi
  done
  return $rc
}

check() {
  local rc=0
  try || rc=1
  local sm; sm=$(sshd -T 2>/dev/null | awk '/^strictmodes/{print $2}')
  [[ $sm == yes ]] && echo "PASS  StrictModes still yes" || { echo "FAIL  StrictModes is '$sm'"; rc=1; }
  local pa; pa=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')
  [[ $pa != yes ]] && echo "PASS  PermitRootLogin is '$pa'" || { echo "FAIL  PermitRootLogin yes was enabled"; rc=1; }
  local m; m=$(stat -c %a /home/lab-alice)
  [[ "${m: -2:1}" =~ [0145] && "${m: -1}" =~ [0145] ]] && echo "PASS  lab-alice home mode $m is not group/world writable" || { echo "FAIL  lab-alice home mode $m"; rc=1; }
  return $rc
}

reset() {
  rm -f "$DROPIN"
  for u in "${USERS[@]}"; do userdel -r "$u" 2>/dev/null || true; done
  rm -rf "$KEYS"
  systemctl reload "$SSHD" 2>/dev/null || true
  echo "Reset complete."
}

case "${1:-}" in
  baseline) baseline ;; inject) inject ;; try) try ;; check) check ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 baseline|inject|try|check|reset"; exit 1 ;;
esac
```

</details>
