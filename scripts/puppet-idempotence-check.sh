#!/usr/bin/env bash
# Usage: sudo bash puppet-idempotence-check.sh <arguments for `puppet apply`>
# Example: sudo bash puppet-idempotence-check.sh --modulepath=modules -e 'include platlab_time'
# Run 1 converges the host. Run 2 must change nothing; otherwise the code is not idempotent.
set -uo pipefail
PUPPET=${PUPPET:-/opt/puppetlabs/bin/puppet}

echo "== run 1: converge"
"$PUPPET" apply --detailed-exitcodes "$@"; rc1=$?
if [[ $rc1 != 0 && $rc1 != 2 ]]; then echo "FAIL: run 1 exited $rc1 (4 = failures, 6 = changes and failures)"; exit 1; fi

echo "== run 2: must be a no-op"
"$PUPPET" apply --detailed-exitcodes "$@"; rc2=$?
case $rc2 in
  0) echo "PASS: idempotent (run 1 exit $rc1, run 2 exit 0)" ;;
  2) echo "FAIL: not idempotent, run 2 still changed resources (see notices above)"; exit 1 ;;
  *) echo "FAIL: run 2 exited $rc2"; exit 1 ;;
esac
