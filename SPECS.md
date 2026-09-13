# Implementation notes

Everything lives in one file, `Sources/main.swift`, with no dependencies. This
is what is worth knowing before changing it.

## Shape of the app

| Type | Job |
|---|---|
| `Settings` | Every preference, with the key it is stored under |
| `Style` | Colours and geometry, none of it persisted |
| `Format` | The two ways a number is written on screen |
| `Shortcut` | The four shortcut presets, as one `Spec` table |
| `GlobalShortcuts` | Registers and unregisters the system hotkeys |
| `Borders` | One click-through window per display, pulsing then steady |
| `Bar` | The floating pill, its two states and its animations |
| `BreakCard` | The shareable card, drawn over a bundled template |
| `Updater` | The daily version check |
| `AppDelegate` | Menu bar, timers, and the break cycle |

The cycle has three phases (`idle`, `prompt`, `resting`), and every transition
goes through `startPrompt()`, `barDidSkip()`, `barDidGo()` or `dismiss()`.

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

Hotkeys are registered in `startPrompt()` and released in `dismiss()`. Leaving
them registered would confiscate the combination system-wide.

### Conflicts cannot be detected, only limited

`RegisterEventHotKey` hands the same combination to every app that asks for it
and returns `noErr` to all of them. Measured on macOS 15, from a signed bundle:
a second app registering a combination the first already holds is accepted, and
so are ⌘space and ⌘tab, which the system itself uses. There is therefore **no
API that answers "is this combination free"**, and a menu that claimed to know
would be guessing.

What limits the damage instead:

- The keys are held for the seconds an alert is on screen, not for the session.
  Outside that window Eyesaver registers nothing at all.
- The default preset is ⌘esc / ⌘return, neither of which macOS reserves.
- Skip and Go are buttons first. If something upstream eats the keystroke, the
  bar still works with the mouse, which is why it is never the only way out.
- A refused registration is written to `~/Library/Logs/eyesaver.log`, and the
  line after it reports how many of the two keys were obtained.

## The bar is rebuilt for every break

The window is thrown away on dismissal and built again on the next prompt,
rather than kept and re-shown. It costs nothing: breaks are minutes apart.

What it buys is a window with no history. A reused panel was measured, on a
bar that had stopped appearing, as fully opaque, correctly placed, and not
composited, with nothing in the app having ordered it out. A window that has
lived through Space changes, full-screen apps and interrupted animations
carries state that cannot be inspected or reset from here. The border has
never once failed to appear, and the border is rebuilt every time.

`startPrompt()` also checks, a second later, that the window really came up,
and rebuilds it once if it did not. A border with no bar leaves no way to
answer the prompt, which is the one failure worth a safety net. The check runs
once per prompt on purpose: rebuilding restarts the entry animation, so a
check on its own timer would measure a bar still fading in and rebuild it
again, and again, for as long as the prompt lasted.

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
| Off-white, all text and buttons | `#FBFBF2` (`Style.ink`) |
| Near-black, text on the Go button | `#1E1E1C` (`Style.night`) |

The pill background has no value: it is the `.hudWindow` material, so it takes
its colour from whatever is behind it.

## The share card

`Resources/card.jpg` is the background; the count is drawn into its empty
top-right corner. Every constant in `BreakCard` is expressed in the design's own
939x536 units and scaled to the template's real pixels, so re-exporting the
template at a different resolution needs no code change.

The template is exported at 144 dpi. `NSImage.size` therefore reports half the
pixel count, in points, and rendering against it silently halved the card's
resolution. Read the dimensions off an `NSBitmapImageRep` instead. The template
is a JPEG, which carries no alpha, so the rounded corners are clipped back out
at draw time.

Two traps in placing that number, both measured against a reference card:

- `NSAttributedString.draw(at:)` takes the bottom-left of the **text box**, not
  the baseline. The font's descender has to be added back to land on the
  baseline.
- `size().width` includes the font's side bearing, which left the digits five
  units shy of the margin. `CTLineGetImageBounds` measures the glyphs
  themselves.

Jersey 15 ships with the app (`Resources/Jersey15-Regular.ttf`, SIL Open Font
License) and is registered at runtime with `CTFontManagerRegisterFontsForURL`.
It is on no Mac by default, so assuming it would silently fall back to the
system font.

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
