# puppet-idempotence-check.sh — Idempotence Gate

> [!NOTE]
> Runnable script: [`scripts/puppet-idempotence-check.sh`](../../scripts/puppet-idempotence-check.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

Proves that Puppet code is idempotent. It applies your manifest once to converge the host, applies it again, and fails if the second run changed anything. Any arguments are passed straight to `puppet apply`.

**Used by:** *C1 - Puppet Package File Service on Both Distros*

Run 1 uses `--detailed-exitcodes`; exit 0 or 2 (no change / changes applied) is acceptable, while 4 or 6 (failures) stops with `FAIL`. Run 2 must exit **0**. An exit of 2 means resources changed again, so the script prints `FAIL: not idempotent`; any other code is also a failure. Exit code reference: 0 no changes, 2 changes applied, 4 failures, 6 changes and failures.

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

```bash
sudo bash /opt/platlab/puppet-idempotence-check.sh --modulepath=modules -e 'include platlab_time'
```

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Root (it really applies the catalog). Puppet or OpenVox under `/opt/puppetlabs` (override with the `PUPPET` environment variable).
- **Safety:** **It changes the host** because it performs real applies. Use a disposable VM. It is also used in C4 and C5.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

```bash
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
```
