#!/bin/bash

# Installs the CMF Headphones widget into the Omarchy shell.
#
# Two modes, chosen by where this script is sitting:
#
#   * from a development checkout -- copies the runtime files into
#     ~/.config/omarchy/plugins/<id>/
#   * from inside that directory, which is where `omarchy plugin add` leaves
#     the whole repo -- copies nothing, because that directory *is* the user's
#     git checkout and overwriting it is what breaks `omarchy plugin update`
#
# Copied rather than symlinked: omarchy-plugin-validate rejects a plugin folder
# containing any symlink, so a linked install would validate as broken and the
# shell would quietly never load it.
#
# Safe to re-run. Files identical to what is already installed are left alone.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MANIFEST="$REPO/manifest.json"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  cat <<USAGE
Usage: ./install.sh

Copies the widget into \$XDG_CONFIG_HOME/omarchy/plugins/<id>/ and asks the
shell to rescan. Run from the installed copy it does nothing but confirm.

Re-running is safe: unchanged files are not rewritten.
USAGE
  exit 0
fi

say() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

command -v jq >/dev/null 2>&1 || {
  warn "jq is required to read the manifest"
  exit 1
}

[[ -f $MANIFEST ]] || {
  warn "no manifest.json beside this script; is this the plugin repo?"
  exit 1
}

PLUGIN_ID=$(jq -r '.id // ""' "$MANIFEST")
[[ -n $PLUGIN_ID ]] || {
  warn "manifest.json declares no id"
  exit 1
}
PLUGIN_DIR="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"

printf '\n%s installer\n\n' "$PLUGIN_ID"

# --- which mode ------------------------------------------------------------
if [[ $(readlink -f "$REPO") == "$(readlink -f "$PLUGIN_DIR" 2>/dev/null || echo "")" ]]; then
  say "plugin: this checkout is already the installed plugin"
else
  # The file list is read from the manifest rather than written out here. A
  # hardcoded list is how pip-plugin silently shipped without Panel.qml when a
  # bar widget was added, and the only symptom was a line on the shell's
  # console. Root-level .qml is swept in too, so helper components travel --
  # NothingHeadphoneIcon.qml is not an entry point and would otherwise be left
  # behind, taking the bar icon with it.
  files=(manifest.json)
  while IFS= read -r entry; do
    [[ -n $entry ]] && files+=("$entry")
  done < <(jq -r '.entryPoints[]?' "$MANIFEST" 2>/dev/null)
  for extra in "$REPO"/*.qml "$REPO"/*.js; do
    [[ -e $extra ]] && files+=("$(basename "$extra")")
  done

  # An entry point is usually also a root-level .qml.
  mapfile -t files < <(printf '%s\n' "${files[@]}" | awk '!seen[$0]++')

  mkdir -p "$PLUGIN_DIR"
  changed=0
  for file in "${files[@]}"; do
    [[ -f $REPO/$file ]] || {
      warn "plugin: $file is declared but missing"
      continue
    }
    if ! cmp -s "$REPO/$file" "$PLUGIN_DIR/$file"; then
      cp "$REPO/$file" "$PLUGIN_DIR/$file"
      changed=1
    fi
  done

  if (( changed )); then
    say "plugin: installed to $PLUGIN_DIR"
  else
    say "plugin: already up to date at $PLUGIN_DIR"
  fi
fi

# --- the dependency --------------------------------------------------------
# The widget renders what cmfctl reports and does nothing without it, so point
# at the fix here rather than leaving it to be discovered from the popup.
if ! command -v cmfctl >/dev/null 2>&1; then
  warn "cmfctl is not on PATH; the widget will say so and little else"
  if [[ -x $REPO/scripts/install-deps.sh ]]; then
    say "installing it now"
    if "$REPO/scripts/install-deps.sh"; then
      :
    else
      warn "could not install cmfctl; run scripts/install-deps.sh by hand"
    fi
  fi
fi

# --- tell the shell --------------------------------------------------------
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if command -v omarchy-plugin-list >/dev/null 2>&1; then
  if omarchy-plugin-list 2>/dev/null | grep -q "$PLUGIN_ID"; then
    say "plugin: known to the shell"
  else
    say "plugin: add it to the bar with:  omarchy bar put $PLUGIN_ID --before omarchy.audio"
  fi
fi

printf '\n'
# rescanPlugins reloads plugin code but keeps the existing widget instance, so
# geometry and property changes appear not to apply until the shell restarts.
say "if the widget looks unchanged, run:  omarchy restart shell"
printf '\n'
