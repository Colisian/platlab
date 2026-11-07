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
