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
