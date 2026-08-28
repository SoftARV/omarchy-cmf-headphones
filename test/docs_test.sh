#!/bin/bash
# What has to be true before this is worth pointing a stranger at.
#
# Omarchy's own docs warn that plugins "run as unsandboxed code inside
# omarchy-shell" and tell people to review a repo before enabling it. Most of
# the checks here exist so that review is cheap and the install instructions
# are the ones that actually work.
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
# shellcheck source-path=SCRIPTDIR source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

README="$ROOT/README.md"

# --- licence ---------------------------------------------------------------
assert_file "$ROOT/LICENSE" "LICENSE exists"
if [[ -f $ROOT/LICENSE ]]; then
  assert_contains "$(cat "$ROOT/LICENSE")" "MIT License" "LICENSE is MIT"
fi

# --- changelog -------------------------------------------------------------
assert_file "$ROOT/CHANGELOG.md" "CHANGELOG.md exists"
if [[ -f $ROOT/CHANGELOG.md ]]; then
  changelog=$(cat "$ROOT/CHANGELOG.md")
  assert_contains "$changelog" "## [Unreleased]" "keeps an Unreleased section"
  assert_contains "$changelog" "keepachangelog.com" "states the format it follows"
  assert_contains "$changelog" "0.x" "carries the 0.x stability note"
  if grep -qE '^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' \
      "$ROOT/CHANGELOG.md"; then
    pass "the released entry carries a date"
  else
    fail "the released entry carries a date" "expected: ## [x.y.z] - YYYY-MM-DD"
  fi

  # The manifest is canonical; the changelog is the copy that can drift.
  version=$(jq -r '.version' "$ROOT/manifest.json")
  latest=$(grep -m1 -E '^## \[[0-9]' "$ROOT/CHANGELOG.md" | sed -E 's/^## \[([^]]+)\].*/\1/')
  assert_eq "$version" "$latest" "the newest released entry matches the manifest"
fi

# --- the README installs the thing that exists -----------------------------
readme=$(cat "$README")

if [[ $readme == *"<this repo>"* ]]; then
  fail "no clone placeholder is left in the README" \
       "found '<this repo>', which nobody can type"
else
  pass "no clone placeholder is left in the README"
fi

assert_contains "$readme" "omarchy plugin add" "leads with the supported install path"

# Plugins land disabled so their code can be reviewed first. An install line
# without --enable produces a plugin that appears to do nothing.
if grep -q "omarchy plugin add.*--enable" "$README"; then
  pass "the install line enables the plugin"
else
  fail "the install line enables the plugin" \
       "plugins land disabled; without --enable it looks broken"
fi

assert_contains "$readme" "cmfctl" "names its dependency"

# The docs tell users to review before enabling. Saying plainly what the
# widget executes is what makes that review take a minute instead of an hour.
assert_contains "$readme" "gdbus" "discloses every subprocess it runs"

assert_contains "$readme" "omarchy plugin remove" "explains how to uninstall"

# The rule that costs an afternoon if rediscovered the hard way.
assert_contains "$readme" "symlink" "records why the install copies rather than links"

# Every executable the QML spawns must be named in that section. A disclosure
# is only worth reading if adding a subprocess breaks the build when it is left
# undeclared.
undeclared=()
while IFS= read -r exe; do
  [[ -z $exe ]] && continue
  grep -q "$exe" "$README" || undeclared+=("$exe")
done < <(grep -ohE 'command(:| =) \["[^"]+"' "$ROOT"/*.qml |
  sed -E 's/.*\["([^"]+)".*/\1/' | sort -u)

if (( ${#undeclared[@]} == 0 )); then
  pass "every subprocess the QML spawns is disclosed"
else
  fail "every subprocess the QML spawns is disclosed" \
       "run but undeclared: ${undeclared[*]}"
fi

# --- preview ---------------------------------------------------------------
# Every third-party plugin on this system ships one; it is what a listing shows.
assert_file "$ROOT/preview.png" "preview.png exists"
if [[ -f $ROOT/preview.png ]]; then
  if [[ $(head -c 8 "$ROOT/preview.png" | od -An -tx1 | tr -d ' \n') == 89504e470d0a1a0a ]]; then
    pass "preview.png is really a PNG"
  else
    fail "preview.png is really a PNG"
  fi

  size=$(stat -c%s "$ROOT/preview.png")
  if (( size <= 512000 )); then
    pass "preview.png is under 500 KB ($((size / 1024)) KB)"
  else
    fail "preview.png is under 500 KB" "got: $((size / 1024)) KB"
  fi

  if grep -q "preview.png" "$README"; then
    pass "the README shows the preview"
  else
    fail "the README shows the preview" "committed but never displayed"
  fi
fi

# --- links resolve ---------------------------------------------------------
broken=()
while IFS= read -r doc; do
  dir=$(dirname "$doc")
  while IFS= read -r target; do
    [[ -z $target || $target == http* || $target == '#'* ]] && continue
    target=${target%%#*}
    [[ -z $target ]] && continue
    [[ -e $dir/$target ]] || broken+=("$doc -> $target")
  done < <(grep -oE '\]\([^)]+\)' "$doc" | sed -E 's/^\]\((.*)\)$/\1/')
done < <(find "$ROOT" -name '*.md' -not -path '*/.git/*')

if (( ${#broken[@]} == 0 )); then
  pass "every relative link in the docs resolves"
else
  fail "every relative link in the docs resolves" "${broken[@]}"
fi

# --- nothing identifying ---------------------------------------------------
if leaked=$(git -C "$ROOT" grep -InE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' -- . 2>/dev/null); then
  fail "no device address is committed anywhere" "$leaked"
else
  pass "no device address is committed anywhere"
fi

report
