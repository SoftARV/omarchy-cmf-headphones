#!/bin/bash
# The real omarchy-plugin-validate, whenever it is on the machine.
#
# manifest_test.sh reproduces a subset of these checks in jq so CI can run
# them on a bare GitHub runner. This file is the authority: it invokes the
# actual validator the shell's CLI uses, so a rule Omarchy adds later is
# caught here without anyone remembering to mirror it.
#
# It skips -- loudly -- rather than passing when Omarchy is absent. A check
# that quietly succeeds because the tool is missing is worse than no check.
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
# shellcheck source-path=SCRIPTDIR source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

if ! command -v omarchy-plugin-validate >/dev/null 2>&1; then
  skip "CI" "omarchy-plugin-validate is not installed; jq subset ran instead"
  report
  exit $?
fi

if out=$(omarchy-plugin-validate "$ROOT" 2>&1); then
  pass "omarchy-plugin-validate accepts this repo"
else
  fail "omarchy-plugin-validate accepts this repo" "$out"
fi

# A plugin folder is rejected outright if it contains a symlink anywhere, so
# prove the validator would notice one rather than trusting that it would.
# The link is created outside the repo, pointing in -- never the reverse.
probe=$(mktemp -d "${TMPDIR:-/tmp}/cmf-validate-probe.XXXXXX")
cp "$ROOT/manifest.json" "$probe/"
while IFS= read -r ep; do
  [[ -n $ep ]] && cp "$ROOT/$ep" "$probe/"
done < <(jq -r '.entryPoints[]?' "$ROOT/manifest.json")
for extra in "$ROOT"/*.qml; do
  cp "$extra" "$probe/" 2>/dev/null || true
done

if omarchy-plugin-validate "$probe" >/dev/null 2>&1; then
  pass "a plain copy of the runtime files validates"
else
  fail "a plain copy of the runtime files validates" \
       "$(omarchy-plugin-validate "$probe" 2>&1)"
fi

ln -s /etc/hostname "$probe/sneaky"
if omarchy-plugin-validate "$probe" >/dev/null 2>&1; then
  fail "the validator rejects a folder containing a symlink" \
       "it accepted one, so the no-symlink rule is not what we think"
else
  pass "the validator rejects a folder containing a symlink"
fi
rm -rf "$probe"

report
