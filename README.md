# Space Maker

A small macOS menu bar utility that keeps your windows where they belong across Spaces and display changes, driven mainly through an MCP server so an AI agent can manage it for you.

- **Save and Restore.** Arrange your windows across Spaces, Save, and Space Maker puts them back: when a window appears (a Chrome relaunch, say), when you dock or undock a monitor, or when you ask.
- **Display Setups.** "Laptop alone" and "laptop plus monitor" each keep their own arrangement and window positions. Temporary displays (AirPlay, Sidecar, a hotel monitor) are left alone, and whatever you moved onto them comes home when they disconnect.
- **Fullscreen windows** are part of the arrangement, and are put back in fullscreen, in order, on the right display.
- **Chrome profiles.** Each Chrome window keeps its own identity, by profile and by a name Space Maker gives it, so they survive a relaunch.
- **Drift.** The menu bar shows what's out of place, with one-click Restore, Save, or Ignore.
- **Pins.** Pin a window to keep a live, floating mirror of it on every Space, like Picture in Picture. Click the mirror to jump to the real window.
- **Doctor.** A self-check of everything Space Maker relies on in macOS, writing a report you can hand to an agent when something breaks.

It works with SIP enabled. Nothing asks you to disable System Integrity Protection.

## How it works, and what to expect

macOS has no public API for Spaces. Space Maker uses a private SkyLight call to move other apps' windows between desktops (the same one [yabai](https://github.com/asmvik/yabai) uses with SIP on), plus private Accessibility calls to reach windows on desktops you aren't looking at. Apple has broken earlier versions of these calls twice, so a future macOS update may break them again. The Doctor checks them on every launch and tells you exactly what stopped working.

Some things macOS doesn't allow with SIP on, so Space Maker doesn't do them:

- It can't create, delete or reorder desktops; you do that in Mission Control and then Save.
- It can't make another app's window truly always-on-top or sticky. A Pin is a mirror of the window, not the window itself.
- New fullscreen desktops always go at the end of a display, so a fullscreen window that belongs before your first regular desktop can't be put there. Space Maker reports it (Soft Drift) with a hint to drag it in Mission Control.

The vocabulary (Space, Display Setup, Arrangement, Assignment, Drift, and so on) is defined in [GLOSSARY.md](GLOSSARY.md), and the main design decisions are recorded in [docs/adr](docs/adr).

## Requirements

- macOS 15 or later (developed on 15.4.1, Apple Silicon)
- Xcode 16 / Swift 6
- An Apple Development signing identity, so macOS permission grants survive rebuilds

## Build and run

```sh
scripts/build-app.sh            # builds and signs "build/Space Maker.app"
open "build/Space Maker.app"
```

`build-app.sh` signs with the first "Apple Development" identity in your keychain; set `SPACE_MAKER_SIGN_IDENTITY` to choose another.

Space Maker runs in the menu bar only (no Dock icon) and registers itself to launch at login. On first run, grant it these in System Settings → Privacy & Security:

- **Accessibility**, to read and move windows
- **Screen & System Audio Recording**, for window titles and Pin mirrors (then quit and reopen Space Maker)
- **Automation → Google Chrome**, asked for on the first Save, so Space Maker can name Chrome windows

Then check everything with the Doctor:

```sh
scripts/doctor.sh               # prints the report; also in ~/Library/Logs/SpaceMaker/
```

## Use it from an AI agent (MCP)

The app owns all state and permissions; `space-maker-mcp` is a small stdio MCP server that relays to it. Register it with Claude Code:

```sh
claude mcp add --scope user space-maker -- "$PWD/build/Space Maker.app/Contents/MacOS/space-maker-mcp"
```

Tools: `status`, `save`, `restore`, `move_window`, `ignore`, `rename_space`, `remember_display`, `name_window`, `pin`, `unpin`, `pause`, `resume`, `doctor`. Windows are referred to by the short handles `status` returns; no tool takes coordinates.

A typical first session: arrange your windows, then ask the agent to "remember my monitor and Save".

## Your Layout

Everything you Save lives in one readable JSON file, `~/.config/space-maker/layout.json`. You can edit it by hand; Space Maker reloads it when it changes.

## Logs

Space Maker logs to macOS unified logging, with timings. Anything that holds up the menu bar for more than 200 ms is logged as `SLOW`.

```sh
log stream --level debug --predicate 'subsystem == "com.mdrum.space-maker"'
log show --last 1h --info --debug --predicate 'subsystem == "com.mdrum.space-maker"'
```

## Development

```sh
swift build
swift test
```

The engine is tested against a fake window system that simulates macOS's behaviour (undock merging, Chrome relaunches, fullscreen desktops, Guest Displays); the real macOS adapter is checked by the Doctor on a real Mac. The original spec and tickets are in [.scratch/space-maker-v1](.scratch/space-maker-v1).

## License

[MIT](LICENSE)
