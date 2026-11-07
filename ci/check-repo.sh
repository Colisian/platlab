#!/usr/bin/env bash
# check-repo.sh: make sure every lab script is wired up everywhere it needs to be.
# Run from the repo root:  bash ci/check-repo.sh
# Fails (exit 1) if a script in scripts/ is:
#   - missing from the SCRIPTS=(...) list in install.sh (so the installer would skip it), or
#   - missing a labs/<id>/README.md (so it has no documentation).
# It also fails if install.sh lists a script that doesn't exist (the installer would 404).
set -euo pipefail
fail=0

# Pull the SCRIPTS=( ... ) list out of install.sh without running install.sh.
listed=$(sed -n 's/^SCRIPTS=(\(.*\))$/\1/p' install.sh)
[[ -n $listed ]] || { echo "FAIL  could not find SCRIPTS=(...) in install.sh"; exit 1; }

for path in scripts/*.sh; do
  name=$(basename "$path")
  id=${name%.sh}
  if [[ " $listed " == *" $name "* ]]; then echo "ok    $name is in install.sh"
  else echo "FAIL  $name is not in install.sh SCRIPTS=(...)"; fail=1; fi
  if [[ -f labs/$id/README.md ]]; then echo "ok    labs/$id/README.md exists"
  else echo "FAIL  labs/$id/README.md is missing"; fail=1; fi
done

for name in $listed; do
  [[ -f scripts/$name ]] || { echo "FAIL  install.sh lists $name but scripts/$name does not exist"; fail=1; }
done

if (( fail )); then echo "RESULT: FAIL"; else echo "RESULT: PASS"; fi
exit $fail
