#!/usr/bin/env bash
# PlatLab installer: downloads every lab script onto this VM in one step.
#
# Usage (run on the lab VM):
#   curl -fsSL https://raw.githubusercontent.com/Colisian/platlab/main/install.sh | sudo bash
#
# Why an installer instead of piping each lab script straight into bash?
#   - mock.sh calls the other scripts by path, so they all have to sit in the same folder.
#   - Several scripts print "$0" in their usage hints; when piped, "$0" is just "bash".
#   - Having real files on disk lets you re-run check/reset later without re-downloading.
set -euo pipefail

# These can be overridden, e.g. to test a branch:
#   curl -fsSL .../install.sh | sudo BRANCH=dev bash
REPO="${REPO:-Colisian/platlab}"
BRANCH="${BRANCH:-main}"
DEST="${DEST:-/opt/platlab}"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/scripts"

# Kept as an explicit list (not a directory listing) because raw.githubusercontent.com
# serves single files only; it has no "list this folder" feature.
SCRIPTS=(a1.sh a2.sh a3.sh a4.sh a5.sh a6.sh mock.sh ci-check.sh puppet-idempotence-check.sh)

# Root is needed to write to /opt and because every lab harness needs root anyway.
[[ $EUID -eq 0 ]] || { echo "Run as root: curl -fsSL <url>/install.sh | sudo bash"; exit 1; }

# curl is the only dependency. Minimal Rocky/RHEL and Ubuntu images normally ship it,
# but the check gives a clear message instead of a confusing failure.
command -v curl >/dev/null || { echo "curl is required (dnf install curl / apt-get install curl)"; exit 1; }

mkdir -p "$DEST"
for s in "${SCRIPTS[@]}"; do
  # Download to a temp file first, then move into place, so a dropped connection
  # never leaves a half-written script that would fail in a confusing way later.
  tmp="$(mktemp)"
  if curl -fsSL --retry 3 -o "$tmp" "$BASE/$s"; then
    install -m 0755 "$tmp" "$DEST/$s"
    echo "  installed $DEST/$s"
  else
    echo "  FAILED to download $BASE/$s"; rm -f "$tmp"; exit 1
  fi
  rm -f "$tmp"
done

cat <<EOF

PlatLab scripts are in $DEST
Next steps:
  cd $DEST
  sudo bash a1.sh baseline     # build the healthy state
  # snapshot the VM here
  sudo bash a1.sh inject       # break it, then troubleshoot
  sudo bash a1.sh check        # grade your fix
  sudo bash a1.sh reset        # clean up

Blind capstone: sudo bash mock.sh start
EOF
