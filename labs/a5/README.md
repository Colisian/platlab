# a5.sh — Network Path Isolation

> [!NOTE]
> Runnable script: [`scripts/a5.sh`](../../scripts/a5.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

> [!WARNING]
> **Spoiler alert**
> Reading this script, and especially the collapsed sections below, reveals how the lab is broken. Finish the lab first: *A5 - Network Path Isolation*.

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Spoiler: What the Faults Are](#spoiler-what-the-faults-are)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Harness for the networking lab. It sets up a small internal web app reachable by name and port, then breaks the path to it at several layers.

**Used by:** *A5 - Network Path Isolation*

| Command | What it does |
|---|---|
| `baseline` | Detects the VM's primary IPv4 address, creates a tiny app served by a systemd unit on port 9191, maps `platlab-app.internal` to the VM's address in `/etc/hosts`, and opens port 9191 in the host firewall (firewalld on RHEL, ufw on Ubuntu; ufw is enabled with SSH allowed first). |
| `inject` | Applies the faults and prints the ticket text. |
| `check` | Passes when the name resolves to the correct address, requests work by name and by IP, the firewall is still running, and a rule for port 9191 exists. It reminds you that only a request from another machine truly proves the firewall path. |
| `reset` | Stops and removes the service and app directory, removes the hosts entry, and removes the firewall rule. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash a5.sh baseline      # snapshot the VM after this step
sudo bash a5.sh inject
sudo bash a5.sh check
sudo bash a5.sh reset
```

---

## Spoiler: What the Faults Are
> [↑ Back to TOC](#table-of-contents)

<details><summary>Spoiler: open only after you have a written root cause</summary>

The inject step (a) changes the service to bind only to `127.0.0.1`, (b) rewrites the hosts entry to a wrong address on the same subnet, and (c) removes the firewall rule for port 9191.

</details>

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. RHEL family (firewalld) or Ubuntu (ufw; installed if missing). `python3`, `curl`, `ip`.
- **Safety:** Edits `/etc/hosts` and, on Ubuntu, **enables ufw**. The script allows SSH before enabling it, but keep console access. Do not run on a host where enabling a firewall would cut you off.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

<details><summary>Full script (click to expand; this reveals the faults)</summary>

```bash
#!/usr/bin/env bash
# PlatLab A5 harness (name -> route -> bind -> firewall). Reading past this line spoils the lab.
# Usage: sudo bash a5.sh baseline|inject|check|reset
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0 <baseline|inject|check|reset>"; exit 1; }
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" rhel "*|*" fedora "*|*" rocky "*|*" almalinux "*|*" centos "*) FAM=rhel ;;
  *" ubuntu "*|*" debian "*) FAM=debian ;;
  *) echo "Unsupported OS"; exit 1 ;;
esac
PORT=9191
NAME=platlab-app.internal
IP=$(ip -4 route get 1.1.1.1 | sed -n 's/.* src \([0-9.]*\).*/\1/p')
[[ -n $IP ]] || { echo "Could not determine primary IPv4 address"; exit 1; }
BADIP="${IP%.*}.$(( ( ${IP##*.} + 37 ) % 200 + 20 ))"

hosts_del() { local t; t=$(grep -v " ${NAME}\$" /etc/hosts || true); printf '%s\n' "$t" > /etc/hosts; }

fw_open() {
  if [[ $FAM == rhel ]]; then
    command -v firewall-cmd >/dev/null || dnf -y -q install firewalld
    systemctl enable --now firewalld
    firewall-cmd -q --permanent --add-port=${PORT}/tcp; firewall-cmd -q --reload
  else
    apt-get -y -qq install ufw curl >/dev/null
    ufw allow OpenSSH >/dev/null; ufw allow ${PORT}/tcp >/dev/null; ufw --force enable >/dev/null
  fi
}
fw_close() {
  if [[ $FAM == rhel ]]; then
    firewall-cmd -q --permanent --remove-port=${PORT}/tcp; firewall-cmd -q --reload
  else
    ufw delete allow ${PORT}/tcp >/dev/null
  fi
}

baseline() {
  mkdir -p /opt/platlab-app
  echo "PLATLAB A5 OK" > /opt/platlab-app/index.html
  chmod 755 /opt/platlab-app; chmod 644 /opt/platlab-app/index.html
  cat > /etc/systemd/system/platlab-app.service <<EOF
[Unit]
Description=PlatLab internal app (port ${PORT})
After=network-online.target

[Service]
DynamicUser=yes
WorkingDirectory=/opt/platlab-app
ExecStart=/usr/bin/python3 -m http.server ${PORT} --bind 0.0.0.0
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  hosts_del
  echo "${IP} ${NAME}" >> /etc/hosts
  fw_open
  systemctl daemon-reload
  systemctl enable --now platlab-app
  sleep 1
  curl -fsS -m 5 "http://${NAME}:${PORT}/"
  echo "Baseline OK (${NAME} -> ${IP}). Snapshot, then run inject."
}

inject() {
  sed -i 's/--bind 0.0.0.0/--bind 127.0.0.1/' /etc/systemd/system/platlab-app.service
  systemctl daemon-reload
  systemctl restart platlab-app
  hosts_del
  echo "${BADIP} ${NAME}" >> /etc/hosts
  fw_close
  echo "Injected. Ticket: 'The nightly job on this server cannot reach http://${NAME}:${PORT}/, and my laptop cannot reach the app at http://<server-ip>:${PORT}/ either.'"
}

check() {
  local rc=0
  pass() { echo "PASS  $*"; }
  fail() { echo "FAIL  $*"; rc=1; }
  local got; got=$(getent hosts "$NAME" | awk '{print $1}' | head -1)
  [[ $got == "$IP" ]] && pass "$NAME resolves to $IP" || fail "$NAME resolves to '${got:-nothing}', expected $IP"
  curl -fsS -m 5 "http://${NAME}:${PORT}/" 2>/dev/null | grep -q "PLATLAB A5 OK" \
    && pass "local request by name works" || fail "local request by name fails"
  curl -fsS -m 5 "http://${IP}:${PORT}/" 2>/dev/null | grep -q "PLATLAB A5 OK" \
    && pass "request to ${IP}:${PORT} works (bind address OK)" || fail "request to ${IP}:${PORT} fails (bind address?)"
  if [[ $FAM == rhel ]]; then
    systemctl is-active --quiet firewalld && pass "firewalld still running" || fail "firewalld was stopped"
    firewall-cmd --query-port=${PORT}/tcp >/dev/null 2>&1 && pass "port ${PORT}/tcp allowed in the active zone" \
      || { firewall-cmd --list-all 2>/dev/null | grep -q "${PORT}" && pass "port ${PORT} allowed via rich rule/service" || fail "port ${PORT} not allowed in the active zone"; }
  else
    ufw status | grep -q "Status: active" && pass "ufw still active" || fail "ufw was disabled"
    ufw status | grep -q "${PORT}" && pass "a rule for ${PORT} exists" || fail "no ufw rule for ${PORT}"
  fi
  echo "NOTE  Only a request from ANOTHER machine proves the firewall path. Test from your Mac: curl -m 5 http://${IP}:${PORT}/"
  return $rc
}

reset() {
  systemctl disable --now platlab-app 2>/dev/null || true
  rm -f /etc/systemd/system/platlab-app.service; rm -rf /etc/systemd/system/platlab-app.service.d
  systemctl daemon-reload
  rm -rf /opt/platlab-app
  hosts_del
  fw_close 2>/dev/null || true
  echo "Reset complete."
}

case "${1:-}" in
  baseline) baseline ;; inject) inject ;; check) check ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 baseline|inject|check|reset"; exit 1 ;;
esac
```

</details>
