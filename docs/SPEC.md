# Spec — hide the bar mark while the headphones are away

Status: approved · Target: `0.2.0` (behaviour change, `0.x`)
Branch: `feat/hide-when-disconnected`, one commit per logical change.

One capability, one module, no dependency graph: the change lives in
`Panel.qml` and nowhere else. `CmfService.qml` already exposes every state this
needs and is not touched.

## 1. Objective

The bar mark currently occupies its slot forever, dimmed when the headphones
are off. For a pair of headphones that spend most of the day in a bag, that is
a permanently lit icon reporting nothing. Collapse the widget when there is
nothing to report, so the bar closes the gap.

Target user: the person running the widget on their own bar — one device, often
off. Not a fleet, not a shared config.

This is the trade the `nec.pip` widget already makes for a window that is not
there (`~/.config/omarchy/plugins/nec.pip/Panel.qml:113-119`), and the shape
below is copied from it deliberately: `visible`, a collapsed `implicitWidth`,
and a popup that closes when its anchor goes away.

### Non-goals

- No new setting. Hiding is unconditional. `manifest.json` is untouched, so
  `defaults`, `schema` and the settings panel are all unchanged.
- No change to what the popup shows, to polling, or to any `cmfctl` call.
- No new subprocess. The "What this plugin runs" table stays as it is.

## 2. Behaviour

The widget is present when **any** of three things is true:

| State | Present? | Why |
|--|--|--|
| `connected` | yes | The normal case: there is something to report. |
| `cmfctlMissing` | **yes** | With no CLI installed `connected` is false forever. The popup is the only place that names the missing dependency and carries the path that installs it; hiding the mark makes that text permanently unreachable and leaves a user with a plugin they enabled and cannot find. |
| `restarting` | **yes** | Writing the LDAC flag power-cycles the headphones on purpose — a 6–9s disconnect the service already tracks separately. The mark must not vanish out from under the switch that caused it. |
| none of the above | no | Collapsed. |

Otherwise: hidden, and the bar reclaims the slot.

### The `restarting` row is a correction to the agreed scope

You selected `cmfctlMissing` alone. I am specifying `restarting` as present too,
because the repo has already decided this exact question once and answered it
the same way — `Panel.qml:130` reads `(cmf.connected || cmf.restarting)`, and
`CmfService.qml:222` keeps `restarting` alive across the disconnect with the
comment *"this disconnect is the restart we asked for … otherwise the panel
would claim they are gone mid-restart."* Excluding it means: you flip the LDAC
switch, and the popup you are looking at closes and the icon disappears, as a
direct result of the click. Say the word and I will drop it, but it would
contradict a rule already written into the file.

### Edge cases

- **Startup.** `connected` starts false, so the mark is absent until the first
  `cmfctl status` answers (~1s) and then appears. A brief pop-in with the
  headphones on; nothing at all with them off. Accepted — no first-poll guard,
  per your call.
- **Popup open when the headphones go.** `onPresentChanged: if (!present &&
  opened) close()`. A popup anchored to a collapsed button cannot be dismissed
  by clicking a button that is no longer there.
- **IPC while hidden.** `omarchy-shell softarv.cmf-headphones toggle` becomes
  inert, because `close()` above has already run and `open()` would anchor to a
  zero-width item. Documented in the README rather than special-cased.
- **`barTint` stays.** The dim binding now means "showing, but not usable" —
  which is exactly the two states that survive the hide.
- **Vertical bars.** Only `implicitWidth` collapses, matching `nec.pip`;
  `visible: false` is what removes the item from a vertical layout. Noted as a
  known limitation, not fixed here.

## 3. Commands

```bash
./test/run.sh                    # full suite; no compositor, no headphones
./test/run.sh bar                # just the new file
omarchy plugin validate .        # authoritative; must pass on the repo
omarchy plugin validate ~/.config/omarchy/plugins/softarv.cmf-headphones
omarchy restart shell            # NOT rescanPlugins -- see below
```

## 4. Project structure

| File | Change |
|--|--|
| `Panel.qml` | `present` property, `visible`, collapsed `implicitWidth`, `onPresentChanged` guard. ~10 lines including the comment. |
| `test/bar_test.sh` | New. Owns what the bar slot must do. |
| `test/deps_test.sh` | One added assertion: the missing-CLI escape hatch. That file already owns this invariant. |
| `README.md` | The line "dims when the headphones are off" is now wrong. Rewrite, and note the IPC behaviour. |
| `CHANGELOG.md` | Entry under `## [Unreleased]` → `### Changed`. The `[0.1.0]` entry is history and is not rewritten. |
| `docs/` | New; this file lives here. See §4b. |

`manifest.json`, `CmfService.qml`, `NothingHeadphoneIcon.qml`, `install.sh`:
untouched.

## 4b. Project organization

Structural tidying rides along with the feature that motivates it, rather than
happening as a separate errand. A reorganization done off to the side gets no
acceptance criteria and no review; folded in here it gets both, and a reader
can see what this work changes structurally and what it deliberately leaves
alone.

### Carried by this work

**Specs move to `docs/`.** The sibling `cmfctl` repo keeps its design under
`docs/SPEC.md` and `CLAUDE.md` already links there, so the same layout means
one place to look across both repos. Lands as its own commit, ahead of any
behaviour change.

Only specs move. `README.md`, `CHANGELOG.md` and `LICENSE` are read from the
repo root by tooling — `test/docs_test.sh` among it — and `CLAUDE.md` /
`CLAUDE.local.md` are only loaded from the root.

### Deferred, with the reason

Both of these are real and worth doing; neither is in scope here, and the first
blocks the second.

**Harden the `install.sh` file sweep.** `install.sh:73` sweeps root-level
`*.qml` and `*.js` only. Any component moved into a subdirectory would be
dropped from a dev-checkout install with nothing to catch it — `install_test.sh`
checks the four current filenames, so it would pass. This is the same silent
failure `CLAUDE.md` records against `pip-plugin`, where a hardcoded list
shipped without the QML that drew the widget and the only symptom was a line on
the shell's console. Needs a recursive sweep plus a test proving a nested file
actually lands.

**Split `Panel.qml`.** At 283 lines it is the largest file in the repo, and
the popup `Column` opening at line 132 runs to the end of the file, nested
three deep inside the bar-button file. Extracting the popup body would leave `Panel.qml` as what it claims to
be: bar slot, service wiring, popup mount. Peer plugins already do this —
`yeleticc.vpn` and `io.github.rawritude.dgpu-control` both split theirs. Blocked
on the sweep above if the extracted file goes in `components/`; unblocked if it
stays at the root, which the sweep already handles.

**Not deferred, rejected:** moving `manifest.json` out of the root. `omarchy
plugin add` clones a repo and reads it from there, so moving it breaks the only
supported install path.

## 5. Code style

- Match the file. Comments record *why*, in prose, and the existing comments in
  `Panel.qml` and `CmfService.qml` are load-bearing — none are reworded or moved.
- One `readonly property bool present`, not the condition repeated three times.
- Derive expected values in tests rather than hardcoding, per `CLAUDE.md`.

## 6. Testing strategy

Quickshell needs a compositor, so QML has no runtime coverage in this suite —
`test/deps_test.sh` says so in its header. The assertions are **structural**:
they check the panel is wired the way this document says. Runtime is a manual
checkpoint.

`test/bar_test.sh` asserts:

1. `Panel.qml` binds `visible` to a connection-derived condition — the widget
   can collapse at all.
2. `implicitWidth` collapses to `0`, so the bar closes the gap rather than
   keeping an invisible hole.
3. `restarting` appears in the present condition — the LDAC power-cycle does
   not blank the widget mid-flip.
4. An open popup is closed when the widget goes away.

`test/deps_test.sh` gains:

5. `cmfctlMissing` appears in the present condition, so the install path stays
   reachable. This sits next to the existing "controls are hidden when the CLI
   is missing" check, which it complements: the *controls* hide, the *mark* does
   not.

Existing tests that must stay green unmodified: `manifest_test.sh` (no manifest
change, so the id/schema/description checks are untouched), `install_test.sh`,
`validate_test.sh`, `docs_test.sh` (no new subprocess; the README edit must keep
`gdbus` and every relative link resolving).

### Manual checkpoint — requires the headphones

Run after `omarchy restart shell`, **not** `rescanPlugins`: rescanning reloads
plugin code but keeps the widget instance, so `Component.onCompleted` never
re-runs and a change looks like it did not work.

- Headphones off → no mark in the bar, no gap.
- Turn them on → mark appears within the BlueZ debounce (~1.5s), not a poll.
- Turn them off with the popup open → popup closes, mark goes.
- Flip LDAC → mark and popup **stay** for the whole 6–9s restart.
- `mv $(command -v cmfctl){,.bak}` → mark stays, popup names the missing CLI.

## 7. Boundaries

**Always**

- Keep `manifest.json` at the repo root, and the id `softarv.cmf-headphones`
  in sync across `manifest.json`, `moduleName` and `ipcTarget`.
- Keep test scratch in `$TMPDIR`. No symlink may ever appear inside the repo —
  `omarchy-plugin-validate` rejects the whole plugin folder if one does.
- Branch first, one logical change per commit, conventional format via the
  commit helper. Changelog updated in the same series.

**Ask first**

- Any change to `CmfService.qml`. This spec should not need one; if it does,
  the design is wrong and worth re-reading before typing.
- Dropping the `restarting` row from §2.
- Adding a setting after all.

**Never**

- Reword or drop the runtime-fact comments in `CmfService.qml` — `StdioCollector`
  ordering, `EBUSY` on fan-out, the LDAC power-cycle.
- Grey out a control instead of hiding it.
- Add a subprocess without adding it to the README table.
- Rewrite the released `[0.1.0]` changelog entry.
- Commit to `main`.

## 8. Acceptance criteria

- [x] `./test/run.sh` green — 93 assertions across 6 files.
- [x] `omarchy plugin validate` passes on both the repo and the installed copy.
- [x] README no longer claims the mark dims when the headphones are off.
- [x] `## [Unreleased]` describes the change and why.
- [x] The docs move is its own commit, with no behaviour change in it.
- [x] The organization this work carries is written down, and what it defers
      says why — §4b.
- [ ] CI green on the branch.
- [ ] The manual checkpoint above passes on real headphones. **Partial.** Step 1
      is confirmed on hardware: with the headphones off the mark is absent from
      the bar and leaves no gap, and the shell loads the widget with no QML
      warning. Steps 2-5 need the headphones switched on and are untested.
