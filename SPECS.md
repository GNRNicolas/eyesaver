# Implementation notes

Everything lives in one file, `Sources/main.swift`, with no dependencies. This
is what is worth knowing before changing it.

## Shape of the app

| Type | Job |
|---|---|
| `Settings` | Every tunable value and preset list, in one place |
| `Shortcut` | The four shortcut presets, as one `Spec` table |
| `GlobalShortcuts` | Registers and unregisters the system hotkeys |
| `Borders` | One click-through window per display |
| `Bar` | The floating pill, its two states and its animations |
| `Updater` | The daily version check |
| `AppDelegate` | Menu bar, timers, and the break cycle |

The cycle has three phases (`idle`, `prompt`, `resting`), and every transition
goes through `trigger()`, `barDidSkip()`, `barDidGo()` or `finish()`.

## Global shortcuts without permissions

`RegisterEventHotKey` (Carbon) is the API app launchers use. It consumes the
keystroke, takes priority over every application, and needs **no TCC
permission**. Two alternatives were tried first and both failed:

- `NSEvent.addGlobalMonitorForEvents` is an observer by design. Its closure
  returns `Void`, so it *cannot* consume the event: the action fires, and the
  key still reaches the frontmost app.
- `CGEventTap` can consume, but needs **two** grants: Accessibility, and Input
  Monitoring, which macOS never asks for on its own. Worse, TCC identifies an
  authorised app by its code signature, and an ad-hoc signature changes on every
  build, so the grant dies each time you recompile.

Hotkeys are registered in `trigger()` and released in `finish()`. Leaving them
registered would confiscate the combination system-wide.

## The border is a filled ring, not a stroke

A stroke is centred on its path, so both its edges share one corner radius.
Displays have square bottom corners, so a rounded outer edge leaves a visible
gap. `BorderView` builds an even-odd path instead: a square outer rectangle and
a rounded inner one, filled.

## The pill uses `maskImage`, not `cornerRadius`

In `.behindWindow` blending, the blur of an `NSVisualEffectView` is composited
by the window server across the view's whole rectangle and **ignores the layer
mask**. `layer.cornerRadius` therefore rounds the content and leaves a visible
box around it. `maskImage` is the only clip that compositing respects: a
rounded-corner `NSImage` with `resizingMode .stretch` and `capInsets` equal to
the radius. The window shadow follows the mask too.

For the hairline outline, a separate `CAShapeLayer` is needed;
`layer.borderWidth` would stay rectangular.

## Windows

- **Borders**: `.borderless`, level `.screenSaver`, `ignoresMouseEvents = true`,
  joining all spaces. One per `NSScreen`, rebuilt when displays change.
- **Bar**: an `NSPanel` with `.nonactivatingPanel`, so it accepts clicks without
  activating the app. Appearance forced to `.vibrantDark` regardless of theme.
  The frame is recomputed from `fittingSize`, so the pill hugs its content.

## Colours

Three values, everything else is an alpha of them. Neither pure white nor pure
black appears anywhere visible.

| | Hex |
|---|---|
| Border orange | `#FF8C0E` (declared as calibrated RGB `1.0, 0.47, 0.06`) |
| Off-white, all text and buttons | `#FBFBF2` (`Settings.ink`) |
| Near-black, text on the Go button | `#1E1E1C` (`Settings.night`) |

The pill background has no value: it is the `.hudWindow` material, so it takes
its colour from whatever is behind it.

## Build

`build.sh` compiles, assembles the bundle, and signs it ad-hoc with a stable
identifier. It generates the icon from `Resources/icon.png` when present (a
square 1024×1024 PNG with the rounded square already drawn in, since macOS does
not round app icons for you), and falls back to rendering the 👀 emoji.

`--install` copies to `/Applications`. Note the script starts with `rm -rf
build`.

## Debugging

`~/Library/Logs/eyesaver.log` records launches, hotkey registration and update
checks, and truncates past 256 KB. `kill -USR1 <pid>` triggers a break.
