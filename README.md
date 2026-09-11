# Eyesaver

A quiet break reminder for macOS. Every 20 minutes it pulses an orange border
around your screen and slides a small dark bar up from the bottom. You either
skip it, or take a two-minute break while it counts down.

It never steals focus, never covers your work, and never takes a keystroke you
were about to use.

## Why another one

Most break reminders throw a full-screen overlay at you. That is effective and
infuriating: it interrupts whatever you were in the middle of. Eyesaver aims for
the opposite — impossible to miss, but never in the way.

- The border window ignores mouse events, so **every click passes straight
  through** to whatever is underneath.
- The bar is a non-activating panel: **clicking it does not move focus** away
  from your editor.
- Shortcuts are registered **only while the alert is on screen**, so Eyesaver
  never holds a key combination hostage while you work.

## Install

Requires macOS 13 or later and the Xcode command line tools (`xcode-select
--install`). No dependencies, no package manager.

```sh
git clone https://github.com/GNRNicolas/eyesaver.git
cd eyesaver
./build.sh --install     # builds, then copies to /Applications
open /Applications/Eyesaver.app
```

`./build.sh` alone leaves the app in `build/` without installing it.

Eyesaver lives in the menu bar as a timer icon followed by the number of minutes
before your next break. It has no Dock icon and no window.

## Permissions

**None.** Eyesaver asks for no Accessibility access and no Input Monitoring
access.

This is deliberate, and it is the main reason the code looks the way it does.
The obvious way to catch a global shortcut is `CGEventTap`, which needs both of
those permissions — and, because macOS identifies an authorised app by its code
signature, an unsigned or ad-hoc-signed build loses the grant on every rebuild.
`RegisterEventHotKey` does the same job with no permission at all, takes
priority over other applications, and survives rebuilds.

## Settings

Everything is in the menu bar menu.

| Setting | Options |
|---|---|
| Break every | 1, 10, 15, 20, 25, 30, 45, 60 min, 2 h |
| Break length | 20 s, 30 s, 1 min, 1 min 30 s, 2 min, 3 min, 5 min |
| Shortcuts | `⌘esc / ⌘return` (default), `⌃esc / ⌃space`, `⌥esc / ⌥space`, or bare `esc / space` |
| Open at Login | on/off, via `SMAppService` |

Also: **Take a Break Now**, **Reset Timer**, **Pause**.

The default shortcut pair uses `return` rather than `space` because `⌘space` is
Spotlight. The bare `esc / space` preset is available, but be aware it swallows
`space` while the alert is showing — which stops you finishing a sentence before
you look away.

## How a break goes

1. The border pulses and the bar appears: **Skip** and **Go**.
2. **Skip** (`⌘esc`) dismisses everything.
3. **Go** (`⌘return`) drops the border and turns the bar into a countdown, which
   disappears on its own when it reaches zero. `⌘esc` ends it early.
4. Either way, the interval restarts **from the moment you pressed the key** —
   not from when the alert first appeared.

If you do nothing, the border keeps pulsing. That is the point.

## Notes on the implementation

A few things that were less obvious than they look, in case you read the source:

- **The border is a filled ring, not a stroke.** A stroke is centred on its
  path, so both edges share one corner radius. Displays have square bottom
  corners, so a rounded outer edge leaves a visible gap. The ring is an
  even-odd path: square outer rectangle, rounded inner one.
- **The pill uses `maskImage`, not `layer.cornerRadius`.** With
  `.behindWindow` blending the blur is composited by the window server across
  the view's whole rectangle and ignores the layer mask, which leaves a visible
  box around the pill.
- **Logs** go to `~/Library/Logs/eyesaver.log`.
- `kill -USR1 <pid>` triggers a break, which is handy when testing.

## License

MIT
