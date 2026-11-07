# ci-check.sh — Puppet Static Checks

> [!NOTE]
> Runnable script: [`scripts/ci-check.sh`](../../scripts/ci-check.sh). Install all labs with the one-liner in the [main README](../../README.md#quick-start).

## Table of Contents

- [What It Does](#what-it-does)
- [How to Run It](#how-to-run-it)
- [Requirements and Safety](#requirements-and-safety)
- [Full Script](#full-script)

---

## What It Does
> [↑ Back to TOC](#table-of-contents)

A small static-analysis gate for a Puppet control repo. Point it at a directory and it runs syntax, template, data, and style checks, exits non-zero if any fail, and prints `RESULT: PASS` or `RESULT: FAIL`. It is meant to be run by hand, as a pre-commit hook, or as a CI job.

**Used by:** *C4 - Puppet Testing and Safe Rollout*

1. `puppet parser validate` on every `*.pp` file. 2. `puppet epp validate` on every `*.epp` template. 3. Loads every `*.yaml` file with Ruby's YAML parser to catch broken Hiera data. 4. `puppet-lint --fail-on-warnings` on the `site/` directory (with the autoloader-layout and documentation checks turned off). Each failure is reported but the script keeps going so you see everything at once.

---

## How to Run It
> [↑ Back to TOC](#table-of-contents)

```bash
bash /opt/platlab/ci-check.sh <repo-dir>     # defaults to the current directory
```

---

## Requirements and Safety
> [↑ Back to TOC](#table-of-contents)

- **Requirements:** Puppet or OpenVox agent installed under `/opt/puppetlabs`. `puppet-lint` is installed with `sudo /opt/puppetlabs/puppet/bin/gem install puppet-lint --no-document`.
- **Safety:** Strictly read-only.
- Use disposable VMs only, as described in [the security note](../../README.md#security-note).

---

## Full Script
> [↑ Back to TOC](#table-of-contents)

```bash
#!/usr/bin/env bash
# ci-check.sh: static checks for a Puppet control repo.  Usage: bash ci-check.sh <repo-dir>
# Exit status is non-zero if ANY check fails, so a CI job or pre-commit hook can block the change.
set -uo pipefail
REPO=${1:-.}
PUPPET=/opt/puppetlabs/bin/puppet
RUBYBIN=/opt/puppetlabs/puppet/bin
fail=0

step() { printf '\n== %s\n' "$*"; }
run()  { "$@" || { echo "FAILED: $*"; fail=1; }; }

step "puppet parser validate (*.pp)"
while IFS= read -r -d '' f; do run "$PUPPET" parser validate "$f"; done < <(find "$REPO" -name '*.pp' -print0)

step "puppet epp validate (*.epp)"
while IFS= read -r -d '' f; do run "$PUPPET" epp validate "$f"; done < <(find "$REPO" -name '*.epp' -print0)

step "YAML syntax (Hiera data)"
while IFS= read -r -d '' f; do run "$RUBYBIN/ruby" -ryaml -e 'YAML.load_file(ARGV[0])' "$f"; done < <(find "$REPO" -name '*.yaml' -print0)

step "puppet-lint (warnings are failures)"
if [[ -x $RUBYBIN/puppet-lint ]]; then
  run "$RUBYBIN/puppet-lint" --fail-on-warnings --no-autoloader_layout-check --no-documentation-check "$REPO/site"
else
  echo "puppet-lint not installed: sudo $RUBYBIN/gem install puppet-lint --no-document"; fail=1
fi

echo; if (( fail )); then echo "RESULT: FAIL"; else echo "RESULT: PASS"; fi
exit $fail
```
