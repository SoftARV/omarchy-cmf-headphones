# Working on the CMF Headphones widget

Rules this repo actually runs on. Most were learned the expensive way during
the 0.1.0 reorganisation; the reasoning is kept because a rule without its
reason gets dropped the first time it is inconvenient.

This widget owns no protocol. Every reading it shows and every change it makes
goes through [`cmfctl`](https://github.com/SoftARV/cmfctl); the design lives in
that repo's `docs/SPEC.md`.

## The load-bearing things

**Install by copying, never symlinking.** `omarchy-plugin-validate` rejects a
plugin folder containing **any** symlink, so a linked install validates as
broken and the shell quietly never loads it. This also means **no test may
create a symlink inside the repo** — test scratch belongs in `$TMPDIR`.

**`install.sh` is dual-mode, and must stay that way.** Run from a checkout it
copies. Run from inside the plugins directory — where `omarchy plugin add`
leaves the whole repo — it copies **nothing**, because that directory is the
user's git checkout and overwriting it breaks `omarchy plugin update`.

**The install file list comes from `manifest.json`** plus a sweep of root-level
`.qml`, never a hardcoded list. `NothingHeadphoneIcon.qml` is not an entry point
and travels only because of the sweep; a hardcoded list is how `pip-plugin`
shipped without the QML that drew it, the only symptom being a line on the
shell's console.

**`manifest.json` stays at the repo root.** `omarchy plugin add` clones a repo
and reads it from there. Move it into a subdirectory and the only supported
install path stops working.

**The plugin id is fixed.** `softarv.cmf-headphones` is public from first
publication and referenced literally from `shell.json`. It also appears in
`Panel.qml` twice, as `moduleName` and `ipcTarget` — a rename missing those is
silent: the widget loads while `omarchy-shell <id> toggle` addresses nothing.
The suite checks all three against each other.

## Honesty in the manifest

The shell hands every field on a `shell.json` entry straight to the plugin, so
what the manifest declares is a promise:

- **Every settings key must be read by the QML.** `showBattery` was declared and
  read by nothing, which put a switch in the settings panel that did nothing.
- **Descriptions may not name a capability with no control behind it.** Both
  descriptions advertised spatial audio and EQ, neither of which exists here.
- `defaults` and `schema` declare the same keys; every key carries a
  `description`, as first-party manifests do.

All four are enforced by `test/manifest_test.sh`.

## The README is part of the contract

Omarchy's docs warn that plugins are unsandboxed code inside a long-lived shell
process and tell people to review a repo before enabling it. **Every subprocess
the QML spawns is listed in "What this plugin runs"**, and the suite fails if
one is added without being declared. A disclosure that can go stale is not worth
reading.

## QML

Comments in `CmfService.qml` record runtime facts that cost real time to
learn — `StdioCollector` ordering, `EBUSY` on fan-out, the LDAC power-cycle.
They are load-bearing; do not reword or drop them while moving code.

**Detect a missing binary by probing, not by inferring.** Quickshell reports no
dependable exit code for a process that fails to *start*, which is exactly how a
missing `cmfctl` came to be reported as "headphones not connected". Probe with
`sh -c 'command -v ...'` — `sh` always starts.

**Hide controls that cannot work; do not grey them out.** A disabled row implies
the headphones are the obstacle when nothing is installed to drive them.

## Testing and the reload trap

`./test/run.sh` — needs neither a compositor nor headphones.

**`omarchy restart shell` is required, not `rescanPlugins`.** Rescanning reloads
plugin *code* but keeps the existing widget instance, so `Component.onCompleted`
never re-runs. A probe added there will appear not to work, and the first live
check of exactly that change showed the old behaviour for this reason alone.

`omarchy plugin validate <dir>` is authoritative and must pass against **both**
the repo and the installed copy. `test/manifest_test.sh` mirrors a subset of it
in `jq` so CI can run on a machine without Omarchy — that is a mirror, not a
replacement, and it once failed on a bug of its own while the real validator
passed.

Other conventions — derive expected values rather than hardcoding, skips name
the task that removes them, missing linters skip loudly — match
[cmfctl's `CLAUDE.md`](https://github.com/SoftARV/cmfctl/blob/main/CLAUDE.md).
