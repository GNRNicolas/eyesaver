# Forking Eyesaver

Written for whoever picks this up next, human or agent. [SPECS.md](SPECS.md)
explains *why* the code is shaped the way it is; this file is about *changing*
it.

The whole app is **one file**, `Sources/main.swift`, about 950 lines, with no
dependencies and no package manager. `./build.sh` compiles it in a couple of
seconds. There is no test suite: the feedback loop is building and looking at
the thing.

## Make it yours first

Fork and rename before anything else, or your users will get update prompts
pointing at the upstream repo.

| What | Where |
|---|---|
| Update source | `Sources/main.swift`, `Updater.repository` (line ~189) |
| App name | `build.sh`, `NAME=` (line 6) |
| Bundle identifier | `build.sh`, `ID=` (line 7) |
| Version | `build.sh`, `CFBundleShortVersionString` (line ~48) |
| Icon | replace `Resources/icon.png`, a square 1024×1024 PNG |
| Copyright | `LICENSE` |
| Clone URL and screenshots | `README.md`, `docs/` |

`Updater.repository` is the one that matters. Leave it pointing here and your
build will tell people to update to *this* project.

## Where things are

Every tunable value is in `enum Settings` at the top of the file. You rarely
need to go further.

| To change | Edit |
|---|---|
| Default interval, default break length | `Settings.interval`, `Settings.breakLength` |
| The lists in the menu | `Settings.intervalPresets`, `Settings.breakPresets` |
| Border thickness, corner radius, blink speed | `Settings.borderWidth`, `borderInnerRadius`, `blinkPeriod` |
| Colours | `Settings.borderColor`, `Settings.ink` |
| Bar size and position | `Settings.pillWidth`, `pillHeight`, `pillRadius`, `pillBottomMargin` |
| The words in the bar | `Bar.showPrompt()` and `Bar.switchToCountdown()` |
| Shortcut presets | `Shortcut.spec`, one `switch`, one case per preset |
| Menu contents | `AppDelegate.buildMenu()` |
| Idle threshold presets | `Settings.idlePresets` |
| The share card | `Resources/streak.png`, plus the constants at the top of `Streak` |
| What a break does | `AppDelegate.trigger()`, `barDidSkip()`, `barDidGo()`, `finish()` |

The cycle is three phases (`idle`, `prompt`, `resting`) and four methods. If you
are adding behaviour, it almost certainly belongs in one of those four.

## Things that will bite you

Each of these cost a debugging session. Details in [SPECS.md](SPECS.md).

- **Do not swap `RegisterEventHotKey` for `CGEventTap`.** The tap needs two TCC
  permissions, and macOS revokes them on every rebuild because the ad-hoc
  signature changes. You will think your code is broken. It is not.
- **Do not round the pill with `layer.cornerRadius`.** In `.behindWindow`
  blending it leaves a visible rectangle. Use `maskImage`.
- **Do not stroke the border.** A stroke shares one radius on both edges and
  leaves a gap in the square bottom corners of the display. It is a filled
  even-odd ring on purpose.
- **Do not leave hotkeys registered outside an alert.** They are system-wide;
  you would confiscate the combination from every other app.
- **Do not consume a bare `space`.** Someone is mid-sentence when the break
  fires. This is why the default preset uses a modifier.
- **`build.sh` starts with `rm -rf build`.** Do not leave anything in there.
- **Never `defaults delete` a key while testing.** The break count lives in
  UserDefaults and there is no undo. Read it, set it back when you are done.

## Testing a change

```sh
./build.sh --install     # builds, installs to /Applications, launches
kill -USR1 $(pgrep -f "Eyesaver.app/Contents/MacOS")   # trigger a break now
kill -USR2 $(pgrep -f "Eyesaver.app/Contents/MacOS")   # render the streak card
tail -f ~/Library/Logs/eyesaver.log
```

`kill -USR1` is the fastest way to see an alert without waiting or clicking
through the menu. The log records launches, hotkey registration and update
checks.

If you are an agent without screenshot access, render the icon sizes or the bar
to a PNG and read that back rather than guessing at layout.

## House style

- **English** everywhere: identifiers, comments, commit messages, UI.
- **No dependencies.** AppKit and Carbon only. If something needs a package,
  it probably does not belong in this app.
- **Comments explain why, not what.** The code says what it does; the comment
  exists because the obvious approach was wrong.
- **One file.** Split it only when it genuinely stops fitting in your head.
- Keep the app permission-free. That is the point of the project, and any
  feature that needs a TCC grant deserves a hard look first.
