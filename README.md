# CMF Headphones — Omarchy bar widget

Battery, active noise mode and LDAC status for a **CMF Headphone Pro** in the
Omarchy bar, with ANC switching in the popup. No phone app involved.

The bar icon is Nothing's dot-matrix headphone mark, drawn as real QML circles
so it takes the bar's foreground colour and dims when the headphones are off.

## Requires

**[cmfctl](https://github.com/miguelrincon/cmfctl)** on `PATH` — it owns the
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

## Keys, while the popup is focused

`a` ANC · `t` transparency · `o` off · `r` refresh

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
