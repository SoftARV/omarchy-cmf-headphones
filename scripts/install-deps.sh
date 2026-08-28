#!/bin/bash

# Installs cmfctl, the CLI this widget renders.
#
# The widget owns no protocol: every reading it shows and every change it makes
# goes through `cmfctl`. Without it on PATH the popup can only say so. This
# fetches it, installs it, and checks the result.
#
# Safe to re-run: an existing checkout is updated rather than re-cloned, and a
# cmfctl already on PATH is left alone.

set -euo pipefail

# Overridable so the test suite can point at a local fixture instead of the
# network. Nothing else should need to change them.
CMFCTL_REPO="${CMFCTL_REPO:-https://github.com/SoftARV/cmfctl.git}"
CMFCTL_DIR="${CMFCTL_DIR:-$HOME/.local/share/cmfctl}"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  cat <<USAGE
Usage: ./scripts/install-deps.sh

Clones cmfctl to $CMFCTL_DIR and runs its installer, which symlinks the CLI
into ~/.local/bin. Re-running updates an existing checkout instead of
replacing it.
USAGE
  exit 0
fi

say() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

# Nothing here needs root, and running it as root would install cmfctl into
# root's home where the shell will never look for it.
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  warn "run this as your own user, not as root"
  warn "cmfctl belongs in your home directory, not root's"
  exit 1
fi

printf '\ncmfctl installer (dependency of the CMF Headphones widget)\n\n'

command -v git >/dev/null 2>&1 || {
  warn "git is required to fetch cmfctl"
  exit 1
}

# --- already there? --------------------------------------------------------
if command -v cmfctl >/dev/null 2>&1; then
  say "cmfctl: already on PATH at $(command -v cmfctl)"
  say "cmfctl: nothing to do"
  printf '\n'
  say "if the widget still cannot see it, restart the shell:  omarchy restart shell"
  printf '\n'
  exit 0
fi

# --- fetch -----------------------------------------------------------------
if [[ -d $CMFCTL_DIR/.git ]]; then
  say "cmfctl: updating the checkout at $CMFCTL_DIR"
  if ! git -C "$CMFCTL_DIR" pull --ff-only 2>&1 | sed 's/^/    /'; then
    warn "cmfctl: could not update $CMFCTL_DIR"
    warn "        fix it by hand, or remove it and re-run"
    exit 1
  fi
else
  say "cmfctl: cloning $CMFCTL_REPO"
  mkdir -p "$(dirname "$CMFCTL_DIR")"
  # Clone to a staging path first. A failed clone that leaves a half-populated
  # directory behind would make the next run take the "update" branch above and
  # fail differently.
  stage="$CMFCTL_DIR.tmp.$$"
  rm -rf "$stage"
  if ! git clone --depth 1 -- "$CMFCTL_REPO" "$stage" 2>&1 | sed 's/^/    /'; then
    rm -rf "$stage"
    warn "cmfctl: could not clone $CMFCTL_REPO"
    warn "        check the network, then re-run"
    exit 1
  fi
  rm -rf "$CMFCTL_DIR"
  mv "$stage" "$CMFCTL_DIR"
fi

# --- install ---------------------------------------------------------------
[[ -x $CMFCTL_DIR/install.sh ]] || {
  warn "cmfctl: $CMFCTL_DIR has no install.sh; is that really the cmfctl repo?"
  exit 1
}

if ! "$CMFCTL_DIR/install.sh" | sed 's/^/    /'; then
  warn "cmfctl: its installer failed; the output above says why"
  exit 1
fi

# --- check -----------------------------------------------------------------
if ! command -v cmfctl >/dev/null 2>&1; then
  warn "cmfctl: installed but still not on PATH"
  warn "        add ~/.local/bin to PATH and re-run"
  exit 1
fi

say "cmfctl: $(cmfctl --version 2>/dev/null || echo "installed") at $(command -v cmfctl)"

# Reporting the live state is useful, but "no headphones connected" is not an
# installation failure -- it usually means they are simply switched off.
if state=$(cmfctl status --json 2>&1); then
  say "cmfctl: $state"
else
  say "cmfctl: works, but no headphones are connected right now"
fi

printf '\n'
# The widget probes for cmfctl when it loads, so a shell that started without
# it goes on believing it is absent until it reloads.
say "now restart the shell so the widget notices:  omarchy restart shell"
printf '\n'
