#!/bin/bash
# What the widget's bar slot must do.
#
# The mark earns its place in the bar only while it has something to report;
# with the headphones away it collapses and the bar closes the gap. Two states
# survive that hide, and both are load-bearing enough to pin here.
#
# Like the QML checks in deps_test.sh these are structural, not behavioural.
# Quickshell needs a compositor, so nothing here proves the widget renders --
# only that it is wired the way docs/SPEC.md says. The manual checkpoint in
# that file is what proves it behaves.
set -uo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TEST_DIR")
# shellcheck source-path=SCRIPTDIR source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

PANEL="$ROOT/Panel.qml"

# The single condition the whole feature hangs off. Named rather than repeated
# so the three states below are stated once and cannot drift apart.
if grep -qE '^\s*readonly property bool present:' "$PANEL"; then
  pass "the present condition is declared once, not repeated per binding"
else
  fail "the present condition is declared once, not repeated per binding" \
       "expected: readonly property bool present:"
fi

present=$(grep -E '^\s*readonly property bool present:' "$PANEL")

# --- the widget can collapse at all ----------------------------------------
if grep -qE '^\s*visible: present\b' "$PANEL"; then
  pass "the widget hides itself rather than staying dimmed"
else
  fail "the widget hides itself rather than staying dimmed" \
       "expected a top-level: visible: present"
fi

# visible alone leaves the slot reserved on a horizontal bar. Collapsing the
# width is what actually closes the gap, which is the point of the exercise.
if grep -qE '^\s*implicitWidth: present \? .* : 0' "$PANEL"; then
  pass "the width collapses, so the bar reclaims the slot"
else
  fail "the width collapses, so the bar reclaims the slot" \
       "expected: implicitWidth: present ? <button> : 0"
fi

# --- the states that survive the hide --------------------------------------
# cmfctl absent means connected is false forever. The popup is the only place
# that names the missing dependency and carries the path that installs it, so
# hiding the mark would strand a user with a plugin they enabled and cannot
# find. deps_test.sh owns the other half of this invariant.
assert_contains "$present" "cmfctlMissing" \
  "a missing CLI keeps the mark, so its install path stays reachable"

# Writing the LDAC flag power-cycles the headphones on purpose: a 6-9s
# disconnect CmfService tracks separately for exactly this reason. Without this
# term, flipping the switch makes the widget vanish as a result of the click.
assert_contains "$present" "restarting" \
  "the LDAC power-cycle keeps the mark, so the switch does not erase itself"

assert_contains "$present" "connected" \
  "the ordinary connected case keeps the mark"

# --- the popup cannot outlive its anchor -----------------------------------
# A popup anchored to a collapsed button cannot be dismissed by clicking a
# button that is no longer there.
if grep -qE 'onPresentChanged:.*close\(\)' "$PANEL"; then
  pass "an open popup closes when the widget goes away"
else
  fail "an open popup closes when the widget goes away" \
       "expected: onPresentChanged: if (!present && opened) close()"
fi

# --- the mechanism the LDAC term above depends on --------------------------
# Lives here rather than with the rest of CmfService because the bar term is
# why it matters: `restarting` is the only thing holding the mark up during the
# power-cycle, so clearing it early hides the widget mid-flip.
#
# The device acks the write, applies it, and only then power-cycles, so the
# settle poll answers about a second later from headphones that have not left
# yet. Measured: write t+0, confirmed t+1, dropped t+3, back at t+8. Believing
# that first confirmation ended the restart two seconds before the disconnect.
service="$ROOT/CmfService.qml"

if grep -qE 'pendingLdac !== -1 && ldac === \(pendingLdac === 1\) && _restartDropSeen' "$service"; then
  pass "a restart ends only once the disconnect has actually been seen"
else
  fail "a restart ends only once the disconnect has actually been seen" \
       "expected _restartDropSeen to gate the clear in applyStatus"
fi

if grep -qE 'if \(root\.restarting\) root\._restartDropSeen = true' "$service"; then
  pass "the failed status during a restart is what records the drop"
else
  fail "the failed status during a restart is what records the drop" \
       "expected the drop to be recorded in statusProc.onExited"
fi

# Every path that abandons a restart must disarm the flag too, or the next
# power-cycle inherits a drop it never saw and ends on the first poll again.
clears=$(grep -c '_restartDropSeen = false' "$service")
if (( clears >= 3 )); then
  pass "every path that abandons a restart disarms the flag ($clears sites)"
else
  fail "every path that abandons a restart disarms the flag" \
       "expected at least 3 reset sites (setLdac, restartGuard, actionProc); found $clears"
fi

# --- the README still describes what the bar does --------------------------
# The 0.1.0 README said the mark "dims when the headphones are off". That is
# now only true of the two states above, and a stale sentence here is the kind
# a reader trusts.
readme=$(cat "$ROOT/README.md")
if [[ $readme == *"dims when the headphones are off"* ]]; then
  fail "the README describes the current bar behaviour" \
       "still claims the mark dims when the headphones are off"
else
  pass "the README describes the current bar behaviour"
fi

report
