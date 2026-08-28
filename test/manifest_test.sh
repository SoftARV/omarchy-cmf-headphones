#!/bin/bash
# The manifest, checked the way the shell checks it.
#
# This mirrors the subset of omarchy-plugin-validate that can be reproduced
# honestly with jq, so CI catches a broken manifest on a runner that has no
# Omarchy installed. It is a subset, not a replacement: validate_test.sh runs
# the real thing whenever it is available, and that one is authoritative.
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
# shellcheck source-path=SCRIPTDIR source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

MANIFEST="$ROOT/manifest.json"

command -v jq >/dev/null || {
  echo "manifest_test.sh: jq is required" >&2
  exit 1
}

assert_file "$MANIFEST" "manifest.json exists"
if [[ ! -f $MANIFEST ]]; then
  report
  exit $?
fi

if jq -e . "$MANIFEST" >/dev/null 2>&1; then
  pass "manifest.json is valid JSON"
else
  fail "manifest.json is valid JSON"
  report
  exit $?
fi

# The registry compares with ===, so the string "1" is rejected just as the
# CLI rejects it. Worth asserting the type, not merely the value.
if jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1; then
  pass "schemaVersion is the number 1"
else
  fail "schemaVersion is the number 1" "got: $(jq -c '.schemaVersion' "$MANIFEST")"
fi

for field in id name version kinds entryPoints; do
  if jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1; then
    pass "declares $field"
  else
    fail "declares $field"
  fi
done

id=$(jq -r '.id // ""' "$MANIFEST")
if [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  pass "id is well formed ($id)"
else
  fail "id is well formed" "got: $id"
fi

if [[ $id == omarchy.* ]]; then
  fail "id stays out of the reserved omarchy.* namespace" "got: $id"
else
  pass "id stays out of the reserved omarchy.* namespace"
fi

if jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" \
    >/dev/null 2>&1; then
  pass "kinds is a non-empty array"
else
  fail "kinds is a non-empty array"
fi

# Claiming a kind without the entry point it loads from is accepted everywhere
# and does nothing: the widget is skipped and the only symptom is a line on the
# shell's console. Refuse it here, while there is someone to tell.
if jq -e '(.kinds | index("bar-widget")) == null or (.entryPoints | has("barWidget"))' \
    "$MANIFEST" >/dev/null 2>&1; then
  pass "a declared bar-widget has a barWidget entry point"
else
  fail "a declared bar-widget has a barWidget entry point"
fi

# Entry points are read as JSON strings so a path containing a newline stays
# one path rather than splitting into fragments that each look safe.
missing=()
unsafe=()
while IFS= read -r ep_json; do
  [[ -z $ep_json ]] && continue
  ep=$(jq -r '.' <<<"$ep_json")
  if [[ -z $ep || $ep == /* || $ep == *".."* || $ep == *$'\n'* ]]; then
    unsafe+=("$ep")
  elif [[ ! -f $ROOT/$ep ]]; then
    missing+=("$ep")
  fi
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")

if (( ${#unsafe[@]} == 0 )); then
  pass "every entry point is a safe relative path"
else
  fail "every entry point is a safe relative path" "${unsafe[@]}"
fi

if (( ${#missing[@]} == 0 )); then
  pass "every entry point exists on disk"
else
  fail "every entry point exists on disk" "${missing[@]}"
fi

if jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection")))
  then .barWidget.defaultSection as $s
       | (["left","center","right"] | index($s)) != null
  else true end' "$MANIFEST" >/dev/null 2>&1; then
  pass "defaultSection is a real bar section"
else
  fail "defaultSection is a real bar section"
fi

# --- the id, everywhere it is repeated -------------------------------------
# The manifest is not the only place it appears. Panel.qml names it twice, as
# moduleName and as ipcTarget, and the README tells people to type it. A rename
# that misses one of those is silent: the plugin loads, and `omarchy-shell <id>
# toggle` addresses something that no longer exists.
for prop in moduleName ipcTarget; do
  declared=$(grep -oE "^[[:space:]]*$prop:[[:space:]]*\"[^\"]+\"" "$ROOT/Panel.qml" |
    head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  if [[ $declared == "$id" ]]; then
    pass "Panel.qml $prop matches the manifest id"
  else
    fail "Panel.qml $prop matches the manifest id" \
         "manifest: $id" "Panel.qml: ${declared:-<not found>}"
  fi
done

if grep -q "$id" "$ROOT/README.md" 2>/dev/null; then
  pass "the README names the current id"
else
  fail "the README names the current id" "no occurrence of $id in README.md"
fi

# Every plugin id on this system is lowercase, and ids are compared literally.
if [[ $id == "${id,,}" ]]; then
  pass "the id is lowercase"
else
  fail "the id is lowercase" "got: $id"
fi

# --- settings schema -------------------------------------------------------
# A key the QML never reads is a switch in the user's settings panel that does
# nothing. The shell hands every field on the entry straight to the plugin, so
# an unread key is a promise the widget cannot keep.
unread=()
while IFS= read -r key; do
  [[ -z $key ]] && continue
  grep -qF "$key" "$ROOT"/*.qml 2>/dev/null || unread+=("$key")
done < <(jq -r '(.barWidget.schema // [])[]?.key' "$MANIFEST")

if (( ${#unread[@]} == 0 )); then
  pass "every settings key is read by the QML"
else
  fail "every settings key is read by the QML" \
       "declared but never read: ${unread[*]}"
fi

# defaults and schema describe the same set of keys. A key in one and not the
# other is how a removed setting leaves a default behind that nothing consumes,
# or a new one ships with no value until the user opens the settings panel.
schema_keys=$(jq -r '[(.barWidget.schema // [])[].key] | sort | join(",")' "$MANIFEST")
default_keys=$(jq -r '[(.barWidget.defaults // {}) | keys[]] | sort | join(",")' "$MANIFEST")
assert_eq "$schema_keys" "$default_keys" "defaults and schema declare the same keys"

# Every first-party manifest gives each key a description; the settings panel
# has room for it and a bare label leaves the user guessing at units.
undescribed=$(jq -r '[(.barWidget.schema // [])[] | select(has("description") | not) | .key] | join(" ")' "$MANIFEST")
if [[ -z $undescribed ]]; then
  pass "every settings key carries a description"
else
  fail "every settings key carries a description" "missing on: $undescribed"
fi

# A description is the only thing most people read before installing. Naming a
# capability the widget has no control for is the same mistake as shipping a
# settings key nothing reads -- both were true here at once.
overclaimed=()
descriptions=$(jq -r '[.description, .barWidget.description] | join(" ")' "$MANIFEST")
for capability in spatial EQ equali; do
  if grep -qi "$capability" <<<"$descriptions" &&
     ! grep -qil "$capability" "$ROOT"/*.qml >/dev/null 2>&1; then
    overclaimed+=("$capability")
  fi
done

if (( ${#overclaimed[@]} == 0 )); then
  pass "the descriptions claim nothing the QML cannot do"
else
  fail "the descriptions claim nothing the QML cannot do" \
       "advertised with no control: ${overclaimed[*]}"
fi

# --- no symlinks -----------------------------------------------------------
# omarchy-plugin-validate refuses a plugin folder containing any symlink, so
# one committed here -- or created by a test -- makes the whole plugin
# un-installable. Cheaper to catch in the suite than in someone's bar.
link=$(find "$ROOT" -name .git -prune -o -type l -print -quit 2>/dev/null)
if [[ -z $link ]]; then
  pass "no symlink anywhere in the plugin folder"
else
  fail "no symlink anywhere in the plugin folder" "$link"
fi

report
