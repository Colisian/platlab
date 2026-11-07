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
