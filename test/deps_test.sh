#!/bin/bash
# scripts/install-deps.sh, and the panel's handling of a missing cmfctl.
#
# The dependency script is exercised against a local fixture repo rather than
# GitHub, so the suite needs no network and cannot be broken by one. It honours
# CMFCTL_REPO and CMFCTL_DIR for exactly that reason.
#
# The QML half has no automated coverage -- Quickshell needs a compositor, and
# what it does with a binary that fails to start is the very thing being
# guessed at. The assertions here are structural: they check the panel is wired
# the way the design says, and Checkpoint E checks that it behaves.
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
# shellcheck source-path=SCRIPTDIR source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

DEPS="$ROOT/scripts/install-deps.sh"

assert_file "$DEPS" "scripts/install-deps.sh exists"
if [[ ! -f $DEPS ]]; then
  report
  exit $?
fi

# A stand-in for the cmfctl repo: a git repo whose install.sh drops a working
# `cmfctl` onto PATH. Enough to prove the clone-and-install path end to end.
make_fixture_repo() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat >"$dir/bin/cmfctl" <<'STUB'
#!/bin/bash
[[ ${1:-} == --version ]] && { echo "0.1.0"; exit 0; }
[[ ${1:-} == status ]] && { echo "No connected CMF/Nothing device found." >&2; exit 1; }
exit 0
STUB
  chmod +x "$dir/bin/cmfctl"
  cat >"$dir/install.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$HOME/.local/bin"
ln -sfn "$repo/bin/cmfctl" "$HOME/.local/bin/cmfctl"
echo "linked"
STUB
  chmod +x "$dir/install.sh"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm "fixture"
}

run_deps() {
  local home="$1" repo="$2" dest="$3"
  shift 3
  HOME="$home" CMFCTL_REPO="$repo" CMFCTL_DIR="$dest" \
    PATH="$home/.local/bin:/usr/bin:/bin" bash "$DEPS" "$@" 2>&1
}

# --- a machine without cmfctl ----------------------------------------------
home=$(mktemp -d "${TMPDIR:-/tmp}/cmf-deps.XXXXXX")
fixture="$home/fixture"
make_fixture_repo "$fixture"
out=$(run_deps "$home" "$fixture" "$home/.local/share/cmfctl")
status=$?
assert_eq 0 "$status" "installing the dependency exits 0"
if [[ -x $home/.local/bin/cmfctl ]]; then
  pass "cmfctl ends up on PATH"
else
  fail "cmfctl ends up on PATH"
fi
assert_contains "$out" "omarchy restart shell" \
  "ends by telling you to restart the shell"

# --- running it again ------------------------------------------------------
# A second run must not fail, and must not re-clone over a good checkout.
out=$(run_deps "$home" "$fixture" "$home/.local/share/cmfctl")
status=$?
assert_eq 0 "$status" "re-running exits 0"
if [[ -d $home/.local/share/cmfctl/.git ]]; then
  pass "the checkout survives a second run"
else
  fail "the checkout survives a second run"
fi
rm -rf "$home"

# --- no network, or no such repo -------------------------------------------
# Failure has to be legible. A clone that dies leaving a half-populated
# directory and exit 0 is the worst of both.
home=$(mktemp -d "${TMPDIR:-/tmp}/cmf-deps.XXXXXX")
out=$(run_deps "$home" "$home/does-not-exist" "$home/.local/share/cmfctl")
status=$?
if [[ $status -ne 0 ]]; then
  pass "an unreachable repo exits non-zero"
else
  fail "an unreachable repo exits non-zero" "exit 0 with nothing installed"
fi
assert_contains "$out" "cmfctl" "says what it was trying to install"
rm -rf "$home"

# --- the script itself -----------------------------------------------------
src=$(cat "$DEPS")
assert_contains "$src" "set -euo pipefail" "uses a strict shell"
if [[ $src == *sudo* ]]; then
  fail "never calls sudo" "found a sudo reference"
else
  pass "never calls sudo"
fi
if grep -q 'EUID\|id -u' <<<"$src"; then
  pass "refuses to run as root"
else
  fail "refuses to run as root" "no EUID check"
fi

# install.sh should reach for this rather than leaving the user to find it.
assert_contains "$(cat "$ROOT/install.sh")" "install-deps.sh" \
  "install.sh delegates the dependency to it"

# --- how the panel handles the dependency being absent ---------------------
service=$(cat "$ROOT/CmfService.qml")
panel=$(cat "$ROOT/Panel.qml")

# Detection must be a probe, not an inference. Quickshell reports no usable
# exit code for a binary that fails to start, and `sh` always starts.
assert_contains "$service" "command -v cmfctl" \
  "presence is probed explicitly, not inferred from an exit code"

assert_contains "$service" "cmfctlMissing" "the service exposes the missing state"

assert_contains "$panel" "not found on PATH" \
  "the panel names the missing dependency instead of blaming the connection"

assert_contains "$panel" "install-deps.sh" "the panel shows the command that fixes it"

# Hidden, not disabled: a greyed-out ANC row suggests the headphones are the
# problem. There is nothing to grey out when the CLI behind every control is
# absent.
if grep -q 'visible:.*!cmf.cmfctlMissing\|visible:.*cmfctlMissing === false' "$ROOT/Panel.qml"; then
  pass "the controls are hidden when the CLI is missing"
else
  fail "the controls are hidden when the CLI is missing" \
       "expected a visible: binding on cmfctlMissing"
fi

# The distinction this whole task exists to preserve.
assert_contains "$panel" "Not connected" \
  "the headphones-are-off message still exists for its own case"

report
