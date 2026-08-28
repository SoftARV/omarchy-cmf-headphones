#!/bin/bash
# install.sh, against a throwaway XDG_CONFIG_HOME.
#
# The behaviour that matters is which of two modes it picks. Run from a
# development checkout it copies the runtime files into the plugins directory.
# Run from *inside* the plugins directory -- where `omarchy plugin add` puts
# the whole repo -- it must copy nothing, because that directory is the user's
# git checkout and overwriting it is what breaks `omarchy plugin update`.
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
# shellcheck source-path=SCRIPTDIR source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

INSTALL="$ROOT/install.sh"
PLUGIN_ID=$(jq -r '.id' "$ROOT/manifest.json" 2>/dev/null || echo "")

assert_file "$INSTALL" "install.sh exists"
if [[ ! -f $INSTALL ]]; then
  report
  exit $?
fi

new_config_home() {
  mktemp -d "${TMPDIR:-/tmp}/cmf-plugin-test.XXXXXX"
}

# omarchy-shell is not running in a test, and install.sh must not care.
run_install() {
  local cfg="$1"
  shift
  XDG_CONFIG_HOME="$cfg" PATH="/usr/bin:/bin" bash "$INSTALL" "$@" 2>&1
}

# --- a development checkout ------------------------------------------------
cfg=$(new_config_home)
out=$(run_install "$cfg")
status=$?
dest="$cfg/omarchy/plugins/$PLUGIN_ID"
assert_eq 0 "$status" "installing from a checkout exits 0"

for f in manifest.json Panel.qml CmfService.qml NothingHeadphoneIcon.qml; do
  assert_file "$dest/$f" "installs $f"
done

# NothingHeadphoneIcon.qml is not an entry point. It arrives only because the
# file list sweeps root-level .qml as well as reading the manifest -- which is
# the bug pip-plugin hit when its list was hardcoded and quietly lost Panel.qml.
assert_contains "$out" "installed" "reports what it did"

# --- what must NOT travel --------------------------------------------------
# The installed directory is loaded by a long-lived shell process. It should
# hold what the shell reads and nothing else -- no history, no test suite.
strays=()
for unwanted in .git test docs tasks README.md install.sh; do
  [[ -e $dest/$unwanted ]] && strays+=("$unwanted")
done
if (( ${#strays[@]} == 0 )); then
  pass "nothing but the runtime files is installed"
else
  fail "nothing but the runtime files is installed" "found: ${strays[*]}"
fi
rm -rf "$cfg"

# --- running it twice ------------------------------------------------------
cfg=$(new_config_home)
run_install "$cfg" >/dev/null
before=$(find "$cfg" -type f -newermt '1970-01-01' -printf '%T@ %p\n' | sort)
out=$(run_install "$cfg")
status=$?
after=$(find "$cfg" -type f -printf '%T@ %p\n' | sort)
assert_eq 0 "$status" "re-running exits 0"
assert_contains "$out" "up to date" "re-running says it is already up to date"
assert_eq "$before" "$after" "re-running rewrites nothing"
rm -rf "$cfg"

# --- installed in place, as omarchy plugin add leaves it -------------------
# The critical case. `omarchy plugin add` clones the whole repo into the
# plugins directory, so install.sh is then running from its own destination.
# Copying there would be pointless at best; the real cost is that the user's
# checkout must stay a git checkout for `omarchy plugin update` to fast-forward.
cfg=$(new_config_home)
dest="$cfg/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$(dirname "$dest")"
cp -r "$ROOT" "$dest"
out=$(XDG_CONFIG_HOME="$cfg" PATH="/usr/bin:/bin" bash "$dest/install.sh" 2>&1)
status=$?
assert_eq 0 "$status" "running from the installed copy exits 0"
assert_contains "$out" "already the installed plugin" \
  "recognises it is already the installed plugin"
if [[ -d $dest/.git ]]; then
  pass "the installed checkout keeps its .git, so plugin update still works"
else
  fail "the installed checkout keeps its .git, so plugin update still works"
fi
rm -rf "$cfg"

# --- the script itself -----------------------------------------------------
src=$(cat "$INSTALL")
assert_contains "$src" "set -euo pipefail" "uses a strict shell"
if [[ $src == *sudo* ]]; then
  fail "never calls sudo" "found a sudo reference"
else
  pass "never calls sudo"
fi

# The file list has to come from the manifest. Hardcoding it is how a widget
# ships without the QML that draws it.
if [[ $src == *"entryPoints"* ]]; then
  pass "derives the file list from the manifest"
else
  fail "derives the file list from the manifest" "no reference to entryPoints"
fi

report
