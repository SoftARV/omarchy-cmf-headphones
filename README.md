# CMF Headphones — Omarchy bar widget

Battery, active noise mode and LDAC status for a **CMF Headphone Pro** in the
Omarchy bar, with ANC switching in the popup. No phone app involved.

The bar icon is Nothing's dot-matrix headphone mark, drawn as real QML circles
so it takes the bar's foreground colour and dims when the headphones are off.

## Requires

**[cmfctl](https://github.com/SoftARV/cmfctl)** on `PATH` — it owns the
Bluetooth protocol; this widget only renders what it reports.

```bash
ln -s ~/Projects/cmfctl/cmfctl.py ~/.local/bin/cmfctl
cmfctl status --json     # should print battery, anc, ldac
```

The popup title uses the **Nothing Font** (SIL OFL). Without it installed the
title falls back to the bar's font; everything else is unaffected.

## Install

```bash
git clone <this repo> ~/.config/omarchy/plugins/nec.cmf-headphones
omarchy bar put nec.cmf-headphones --before omarchy.audio
omarchy restart shell
```

`omarchy restart shell` matters: `rescanPlugins` reloads plugin code but keeps
the existing widget instance, so geometry changes appear not to apply.

## Settings

| key | default | |
|-----|---------|--|
| `idlePollSec` | 120 | refresh interval while the popup is closed |
| `activePollSec` | 5 | refresh interval while it is open |
| `showBattery` | true | reserved; the bar currently shows the mark only |

Toggling LDAC restarts the headphones — they power-cycle to apply the codec
change and re-pair themselves after ~6-9 seconds. The panel shows "Restarting…"
for that window rather than reporting them as disconnected, and the switch is
held inert until they return.

## Keys, while the popup is focused

`a` ANC · `t` transparency · `o` off · `l` toggle LDAC · `r` refresh

While ANC is active a second row picks the level — Low, Mid, High, Adaptive.
It is hidden in transparency and off, where the levels mean nothing, matching
the phone app.

## Notes

State is gathered with a single `cmfctl status --json` call. Each invocation
opens a fresh RFCOMM link and the connect dominates the cost, so fanning out
into one call per value would be both slow and prone to `EBUSY`.

## Files

| | |
|--|--|
| `manifest.json` | plugin manifest and settings schema |
| `Panel.qml` | bar button and popup |
| `CmfService.qml` | polling, state, and the `cmfctl` calls |
| `NothingHeadphoneIcon.qml` | the dot-matrix mark |
