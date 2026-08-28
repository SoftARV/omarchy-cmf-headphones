#!/bin/bash
# Widget test runner. Needs bash and jq; no compositor, no headphones.
#
#   ./test/run.sh              run everything
#   ./test/run.sh manifest     run only tests whose file name matches a substring
#
# Every test reports through test/lib/assert.sh; the runner reads the tallies
# off a stdout marker rather than parsing prose.
#
# Lint is optional on purpose: a missing linter reports a skip and never fails
# the suite, because a runner you cannot run locally stops being run at all.

set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
FILTER="${1:-}"

c() { if [[ -t 1 ]]; then printf '\033[%sm' "$1"; fi; }

command -v jq >/dev/null || {
  echo "test/run.sh: jq is required" >&2
  exit 1
}

files_run=0
failed=()
skipped=()

shopt -s nullglob

for test_file in "$TEST_DIR"/*_test.sh; do
  name=$(basename "$test_file" _test.sh)
  [[ -n $FILTER && $name != *"$FILTER"* ]] && continue

  printf '%s%s%s\n' "$(c '1')" "$name" "$(c 0)"
  files_run=$((files_run + 1))

  output=$(bash "$test_file" 2>&1)
  status=$?

  # Hide the machine-readable tally from the human output.
  printf '%s\n' "$output" | grep -v '^ASSERT_TALLY ' || true

  # A file that dies before report() emits no tally. That is a crash, not a
  # pass, so treat a missing tally as a failure rather than trusting the exit
  # code of whatever ran last.
  tally=$(printf '%s\n' "$output" | grep '^ASSERT_TALLY ' | tail -1)
  if [[ -z $tally ]]; then
    printf '  %sFAIL%s no tally -- the file exited before report()\n' \
      "$(c '31')" "$(c 0)"
    failed+=("$name")
  else
    read -r _ _ t_fail t_skip <<<"$tally"
    (( t_fail == 0 && status == 0 )) || failed+=("$name")
    (( t_skip == 0 )) || skipped+=("$name has $t_skip skipped assertion(s)")
  fi
done

if [[ -z $FILTER ]]; then
  if command -v shellcheck >/dev/null 2>&1; then
    printf '%sshellcheck%s\n' "$(c '1')" "$(c 0)"
    shellcheck -x "$ROOT"/install.sh "$TEST_DIR"/*.sh "$TEST_DIR"/lib/*.sh 2>&1 |
      sed 's/^/  /'
    (( PIPESTATUS[0] == 0 )) || failed+=("shellcheck")
  else
    skipped+=("shellcheck is not installed; lint runs in CI only")
  fi
fi

printf '\n'
for note in "${skipped[@]:-}"; do
  [[ -n $note ]] && printf '  %sskip%s  %s\n' "$(c '33')" "$(c 0)" "$note"
done

if (( ${#failed[@]} )); then
  printf '  %sFAIL%s  %s\n' "$(c '31')" "$(c 0)" "${failed[*]}"
  exit 1
fi

printf '  %sok%s    %d file(s)\n' "$(c '32')" "$(c 0)" "$files_run"
