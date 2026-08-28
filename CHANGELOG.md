# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While on `0.x`, the plugin id and settings schema may change between minor
versions.

## [Unreleased]

## [0.1.0] - 2026-08-28

Battery, noise mode and LDAC for a CMF Headphone Pro in the Omarchy bar, with
noise control and the codec switch in the popup. No phone app involved.

### Added

- **Bar widget and popup.** The bar carries Nothing's dot-matrix headphone
  mark, drawn as real QML circles so it takes the bar's foreground colour and
  dims when the headphones are off. The popup shows battery, the active noise
  mode and the negotiated codec.
- **Noise control across all six modes.** ANC, Transparency and Off, and while
  ANC is active a second row picks the level — Low, Mid, High, Adaptive,
  ordered as the phone app orders them. The level row is hidden in
  Transparency and Off, where the levels mean nothing.
- **An LDAC switch that shows what it costs.** Writing the codec flag
  power-cycles the headphones: they announce power-off, restart and re-pair
  over roughly 6–9 seconds. The panel reports "Restarting…" for that window
  rather than claiming the headphones are gone, and holds the switch inert
  until they return.
- **Refresh driven by BlueZ, not only by the clock.** The widget watches
  `org.bluez` on D-Bus for connect, disconnect and A2DP transport changes, so
  it reacts the moment the headphones come back instead of waiting out the
  poll interval. A blocked read also keeps the CPU in deeper idle states than
  a fast timer would.
- Keyboard control while the popup is focused: `a` ANC, `t` transparency,
  `o` off, `l` toggle LDAC, `r` refresh.
- Configurable poll intervals — one while the popup is closed, a faster one
  while it is open.
- `install.sh`, which copies the runtime files into the plugins directory. Run
  from an `omarchy plugin add` checkout it copies nothing, leaving that
  directory a git checkout so `omarchy plugin update` keeps working.

### Notes

- State is gathered with a single `cmfctl status --json` call. Each invocation
  opens a fresh RFCOMM link and the connect dominates the cost, so one call per
  value would be both slower and prone to `EBUSY`.
- The popup title uses the **Nothing Font** (SIL OFL). Without it installed the
  title falls back to the bar's font and nothing else changes.
- The widget is installed by **copying**, never symlinking:
  `omarchy plugin validate` rejects a plugin folder containing any symlink, so
  a linked install would validate as broken and the shell would quietly never
  load it.

[Unreleased]: https://github.com/SoftARV/omarchy-cmf-headphones/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/SoftARV/omarchy-cmf-headphones/releases/tag/v0.1.0
