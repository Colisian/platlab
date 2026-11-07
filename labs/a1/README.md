# a1.sh — Layered Web Service Outage

> [!NOTE]
> Runnable script: [`scripts/a1.sh`](../../scripts/a1.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

> [!WARNING]
> **Spoiler alert**
> Reading this script, and especially the collapsed sections below, reveals how the lab is broken. Finish the lab first: *A1 - Layered Web Service Outage*.

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Spoiler: What the Faults Are](#spoiler-what-the-faults-are)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Harness for the nginx outage lab. It builds a healthy nginx site on port 8008, breaks it in several stacked ways at once, grades the outcome, and cleans up.

**Used by:** *A1 - Layered Web Service Outage*

| Command | What it does |
|---|---|
| `baseline` | Installs nginx (plus curl and SELinux tools on RHEL), creates a small site under `/srv/platlab` and a virtual host on port 8008, opens the port in firewalld if it is running, validates the config, starts nginx, and fetches the page to prove it works. Take a VM snapshot after this step. |
| `inject` | Introduces the faults and prints the ticket text you work from. Do not read the details below until you have finished the lab. |
| `check` | Prints `PASS`/`FAIL` lines for outcomes only: nginx config validates, nginx is active, `GET /` on port 8008 returns the site, the docroot is not world-writable, and (RHEL with SELinux on) SELinux is still enforcing and the label matches policy. It never reveals causes. |
| `reset` | Stops the decoy service and nginx, removes the vhost and `/srv/platlab`, and removes the SELinux rule and firewall port on RHEL. |

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

Install the scripts on the VM (see [Quick start](../../README.md#quick-start)), then:

```bash
cd /opt/platlab
sudo bash a1.sh baseline      # snapshot the VM after this step
sudo bash a1.sh inject
sudo bash a1.sh check
sudo bash a1.sh reset
```

---

## Spoiler: What the Faults Are
> [↑ Back to TOC](#table-of-contents)

<details><summary>Spoiler: open only after you have a written root cause</summary>

The inject step (a) removes a semicolon from the vhost so the config no longer validates, (b) starts a transient systemd service called `legacy-report` that occupies port 8008, (c) sets `/srv/platlab` to mode `0700` so the nginx worker cannot traverse it, and (d) on RHEL with SELinux on, runs `restorecon` so the directory gets the default `var_t` label that nginx may not read. The baseline deliberately used the non-persistent `chcon`, which is what makes that last fault possible.

</details>

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root. RHEL family or Ubuntu/Debian. Internet or a mirror for package installs. systemd. `python3` (for the decoy service).
- **Safety:** Only touches nginx, `/srv/platlab`, one vhost file, and one transient unit. On RHEL it adds and removes a firewalld port and an SELinux file-context rule.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

<details><summary>Full script (click to expand; this reveals the faults)</summary>

```bash
#!/usr/bin/env bash
# PlatLab A1 harness. Reading past this line before you finish the lab spoils it.
# Usage: sudo bash a1.sh baseline|inject|check|reset
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0 <baseline|inject|check|reset>"; exit 1; }
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" rhel "*|*" fedora "*|*" rocky "*|*" almalinux "*|*" centos "*) FAM=rhel ;;
  *" ubuntu "*|*" debian "*) FAM=debian ;;
  *) echo "Unsupported OS"; exit 1 ;;
esac

sel_on() { command -v getenforce >/dev/null 2>&1 && [[ $(getenforce) != Disabled ]]; }

baseline() {
  if [[ $FAM == rhel ]]; then
    dnf -y -q install nginx policycoreutils-python-utils
    command -v curl >/dev/null || dnf -y -q install curl
  else
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install nginx curl
  fi
  mkdir -p /srv/platlab
  echo "PLATLAB A1 OK" > /srv/platlab/index.html
  chown -R root:root /srv/platlab
  chmod 755 /srv/platlab
  chmod 644 /srv/platlab/index.html
  cat > /etc/nginx/conf.d/platlab.conf <<'EOF'
server {
    listen 8008;
    server_name _;
    root /srv/platlab;
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
  if [[ $FAM == rhel ]]; then
    # Temporary label only: it does not survive a relabel/restorecon.
    if sel_on; then chcon -R -t httpd_sys_content_t /srv/platlab; fi
    if systemctl is-active --quiet firewalld; then
      firewall-cmd -q --permanent --add-port=8008/tcp
      firewall-cmd -q --reload
    fi
  fi
  nginx -t
  systemctl enable --now nginx
  systemctl restart nginx
  curl -fsS -m 5 http://127.0.0.1:8008/
  echo "Baseline OK. Snapshot the VM now, then run: sudo bash $0 inject"
}

inject() {
  systemctl stop nginx || true
  sed -i 's|=404;|=404|' /etc/nginx/conf.d/platlab.conf
  systemd-run --quiet --unit=legacy-report \
    --description="Legacy report preview (owner: dana)" \
    python3 -m http.server 8008 --bind 0.0.0.0 --directory /var/tmp
  chmod 0700 /srv/platlab
  if [[ $FAM == rhel ]] && sel_on; then restorecon -R /srv/platlab; fi
  systemctl start nginx 2>/dev/null || true
  echo "Injected. Ticket: 'The platlab web site on port 8008 has been down since this morning's change window.'"
}

check() {
  local rc=0
  pass() { echo "PASS  $*"; }
  fail() { echo "FAIL  $*"; rc=1; }
  nginx -t >/dev/null 2>&1 && pass "nginx -t is clean" || fail "nginx config does not validate"
  systemctl is-active --quiet nginx && pass "nginx is active" || fail "nginx is not active"
  curl -fsS -m 5 http://127.0.0.1:8008/ 2>/dev/null | grep -q "PLATLAB A1 OK" \
    && pass "GET / on :8008 returns the site" || fail "GET / on :8008 does not return the site"
  local mode; mode=$(stat -c %a /srv/platlab)
  [[ "${mode: -1}" =~ ^[0145]$ ]] && pass "docroot mode $mode (no world write)" || fail "docroot mode $mode is too open"
  if [[ $FAM == rhel ]] && sel_on; then
    [[ $(getenforce) == Enforcing ]] && pass "SELinux still enforcing" || fail "SELinux is not enforcing"
    if [[ -z $(restorecon -nvR /srv/platlab 2>&1) ]]; then pass "label matches policy (persistent)"
    else fail "label would be reverted by restorecon (not persistent)"; fi
  fi
  return $rc
}

reset() {
  systemctl stop legacy-report 2>/dev/null || true
  systemctl stop nginx 2>/dev/null || true
  rm -f /etc/nginx/conf.d/platlab.conf
  rm -rf /srv/platlab
  if [[ $FAM == rhel ]]; then
    semanage fcontext -d '/srv/platlab(/.*)?' 2>/dev/null || true
    firewall-cmd -q --permanent --remove-port=8008/tcp 2>/dev/null || true
    firewall-cmd -q --reload 2>/dev/null || true
  fi
  echo "Reset complete."
}

case "${1:-}" in
  baseline) baseline ;; inject) inject ;; check) check ;; reset) reset ;;
  *) echo "Usage: sudo bash $0 baseline|inject|check|reset"; exit 1 ;;
esac
```

</details>
