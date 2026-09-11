# Eyesaver

A quiet break reminder for macOS. Every 20 minutes it pulses an orange border
around your screen and slides a small dark bar up from the bottom. Skip it, or
take a two-minute break while it counts down.

![An orange border pulsing around a full screen, with the Eyesaver bar at the bottom](docs/border.webp)

Most break reminders throw a full-screen overlay at you. That is effective and
infuriating. Eyesaver aims for the opposite — impossible to miss, never in the
way:

- The border window ignores mouse events, so **clicks pass straight through**.
- The bar is a non-activating panel: **clicking it never moves focus** away from
  your editor.
- Shortcuts are registered **only while the alert is up**, so no key combination
  is held hostage while you work.

![The bar: an eye, "Time to look away", "Rest your eyes for 2 min", and the Skip and Go buttons](docs/bar.webp)

**Skip** (`⌘esc`) dismisses everything. **Go** (`⌘return`) drops the border and
turns the bar into a countdown that disappears on its own. Either way the
interval restarts from the moment you pressed the key. Do nothing and the border
keeps pulsing — that is the point.

## Install

Needs macOS 13+ and the Xcode command line tools (`xcode-select --install`). No
dependencies.

```sh
git clone https://github.com/GNRNicolas/eyesaver.git
cd eyesaver
./build.sh --install
open /Applications/Eyesaver.app
```

Eyesaver lives in the menu bar as a timer icon and the minutes left before your
next break. No Dock icon, no window.

## Permissions

**None.** No Accessibility, no Input Monitoring.

That is deliberate. The obvious way to catch a global shortcut is `CGEventTap`,
which needs both — and loses the grant on every rebuild, since macOS identifies
an authorised app by its code signature. `RegisterEventHotKey` does the same job
with no permission at all and takes priority over other apps.

## Settings

![The menu bar menu, open](docs/menu.webp)

| Setting | Options |
|---|---|
| Break every | 1, 10, 15, 20, 25, 30, 45, 60 min, 2 h |
| Break length | 20 s, 30 s, 1 min, 1 min 30 s, 2 min, 3 min, 5 min |
| Shortcuts | `⌘esc / ⌘return` (default), `⌃esc / ⌃space`, `⌥esc / ⌥space`, bare `esc / space` |
| Open at Login | via `SMAppService` |

The default pair uses `return` because `⌘space` is Spotlight. The bare preset
swallows `space` while the alert is up, which stops you finishing a sentence
before you look away.

## Updates

Eyesaver checks the GitHub releases page once a day and tells you when a newer
version is out. It installs nothing — updating is `git pull && ./build.sh
--install`. One anonymous HTTPS request; nothing is sent about you. Turn it off
with **Check for Updates Automatically**.

## Forking

[SPECS.md](SPECS.md) covers the architecture and the AppKit traps this ran into.

## License

MIT
