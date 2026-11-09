# Space Maker v1

Status: ready-for-agent

Vocabulary: `GLOSSARY.md`. Decisions: `docs/adr/0001`–`0003`.

## Problem Statement

I run macOS with several Spaces across a MacBook display (on the left) and, some of the time, a 4K external monitor (on the right). Particular windows live in particular places:
- Chrome has three profiles (Work, Game, Personal). Work main and Game main are fullscreen; Work second and Personal main are normal windows.
- TickTick has its own desktop on the laptop.
- I like fullscreen windows at the edges of a display.

macOS does not keep any of this stable:
- Undocking piles the external monitor's desktops onto the laptop, and redocking moves them back unreliably and in a shuffled order.
- Quitting and relaunching Chrome drops every window onto whichever desktop I'm on.
- Nothing keeps a window I'm watching in view while I switch Spaces, the way Picture in Picture does.

Fixing it by hand every time is tedious, and macOS gives me no way to describe the setup I want.

## Solution

Space Maker is a small menu bar utility that runs locally. I arrange my windows the way I like and **Save** them into a **Layout**. Space Maker then **Restores** that Layout, so I mostly don't have to think about it:
- **Placement:** windows return to their Space when they appear, e.g. after a Chrome relaunch.
- **Display changes:** Space Maker Restores everything when the displays change. Each **Display Setup** has its own **Arrangement** and window positions, and I never type a number.
- **Guest Displays:** temporary displays, such as AirPlay or Sidecar, are left alone. Whatever I moved onto one goes home when it disconnects.
- **Drift:** anything that doesn't match the Layout shows as Drift, which I can Restore, Save or Ignore. Anything Space Maker can't fix itself shows as **Soft Drift**, with a hint.
- **Pins:** I can Pin a window to get a live mirror of it that floats on every Space. Clicking the mirror takes me to the real window.

The main interface is an MCP server, so an agent can inspect, Save, Restore, move, Pin and rename on my behalf. The menu bar covers one-click actions. A **Doctor** checks that all the macOS internals Space Maker depends on still work. When something breaks, it writes a report I can hand straight to an agent.

## User Stories

### Saving and restoring
1. As the user, I want to arrange my windows by hand and then Save, so that I never write configuration or type coordinates.
2. As the user, I want to Save a single window from the menu bar, so that I can update one Assignment without touching the rest.
3. As the user, I want Save to record each window's Space, so that it goes back there later.
4. As the user, I want Save to record each window's position and size for the current Display Setup only, so that saving while docked never changes my laptop-only positions.
5. As the user, I want Save to record the current Display Setup's Arrangement, so that the order of Spaces and fullscreen windows on each display is remembered.
6. As the user, I want Restore all, so that one action puts everything back where it belongs.
7. As the user, I want to Restore a single window, so that I can fix one window without moving the others.
8. As the user, I want Restore to apply saved positions only when there is one for the current Display Setup, so that windows without one only get moved to the right Space.
9. As the user, I want a window to be placed on its Space as soon as it appears, so that a relaunched Chrome sorts itself out.
10. As the user, I want windows without an Assignment never to be moved, so that Space Maker doesn't interfere with things I haven't saved.
11. As the user, I want to pause and resume automatic Restore and Placement, so that I can rearrange freely for a while.
12. As the user, I want the Layout in a readable file that I can edit by hand, so that I can inspect, version, or tweak it outside the app.
13. As the user, I want Space Maker to pick up hand edits to the Layout file automatically, so that I don't need to restart it.

### Window identity
14. As the user, I want each window to have its own Assignment, even when an app has several windows, so that my four Chrome windows can each live somewhere different.
15. As the user, I want Chrome windows recognized by profile and by whether they're fullscreen, so that "the Work fullscreen window" and "the Work normal window" are understood without extra effort from me.
16. As the user, I want Space Maker to name Chrome windows automatically when profile and fullscreen aren't enough to tell them apart, so that their identity survives a relaunch without me naming them.
17. As the user, I want to name a window through MCP, so that I can give a window a meaningful name if I want to.
18. As the user, I want unnamed windows that have closed to be dropped from the Layout on my next Save, so that stale temporary windows don't pile up.
19. As the user, I want named windows to stay in the Layout even while they're closed, so that they find their place when they reopen.
20. As the user, I want system panels, dialogs and sheets ignored automatically, so that they never show up as Drift.

### Drift and Ignore
21. As the user, I want a new window that matches no Assignment to show as Drift, so that I notice it and decide what to do with it.
22. As the user, I want a window I've moved away from its Assignment to show as Drift, so that I can see what's out of place.
23. As the user, I want to Restore, Save or Ignore each drifted window from the menu bar, so that resolving Drift takes one click.
24. As the user, I want to Ignore a single window until it closes, so that temporary windows stop nagging me.
25. As the user, I want to always Ignore an app, so that apps like Finder or System Settings are never tracked.
26. As the user, I want the menu bar icon to show a dot and a count when there's Drift, so that I can tell at a glance.
27. As the user, I want Drift that Space Maker can't fix to be Soft Drift, with a hint on how to fix it, so that it's visible without nagging me.
28. As the user, I want Soft Drift not to light up the Drift dot, so that the dot only means "one click fixes this".
29. As the user, I want Space Maker never to keep retrying a fix that can't succeed, so that windows don't thrash.

### Display Setups
30. As the user, I want "laptop alone" and "laptop plus my 4K monitor" to be separate Display Setups, each with its own Arrangement and positions, so that each one looks the way I want.
31. As the user, I want a Space to mean a position in the current Display Setup's Arrangement, so that macOS shuffling desktops around doesn't matter.
32. As the user, I want a full Restore to run automatically once a display change has settled, so that docking and undocking need nothing from me.
33. As the user, I want Space Maker to wait until macOS has finished rearranging desktops before it Restores, so that it doesn't act on a half-finished state.
34. As the user, I want to remember a display into a Display Setup explicitly, so that random monitors don't change my Display Setups.
35. As the user, I want unremembered displays (AirPlay, Sidecar, a hotel monitor) to be Guest Displays that Space Maker never puts anything on, so that screen sharing doesn't scramble my Spaces.
36. As the user, I want windows I moved onto a Guest Display to return home when it disconnects, so that the drift from presenting is reconciled automatically.
37. As the user, I want to be told when the current Display Setup has no saved Arrangement, instead of Space Maker guessing, so that nothing moves unexpectedly.
38. As the user, I want to be told when a display has too few desktops for its Arrangement, so that I know to add one in Mission Control.
39. As the user, I want extra desktops beyond the Arrangement to be left alone, so that my scratch desktops are safe.
40. As the user, I want a new desktop I've created to get an automatic name from its main app when I Save, so that I don't have to name it.
41. As the user, I want to rename a Space through MCP or the menu bar, so that names make sense to me.
42. As the user, I want deleting a desktop in Mission Control and then Saving to remove it from the current Arrangement, so that the Layout keeps up with my changes.

### Fullscreen windows
43. As the user, I want fullscreen windows to be part of the Arrangement, interleaved with Spaces, so that "Game fullscreen, Tasks, Personal, Work, Work fullscreen" can be saved.
44. As the user, I want Restore to put a fullscreen window back in fullscreen on the right display, so that undocking doesn't strand Game or Work main.
45. As the user, I want Restore to re-fullscreen a window only when it's actually out of place, so that I don't sit through needless animations.
46. As the user, I want a fullscreen window that's on the right display but in the wrong order to be Soft Drift with a "drag it in Mission Control" hint, so that I can fix what macOS won't let Space Maker fix.

### Pins
47. As the user, I want to Pin the frontmost window from the menu bar, so that I can keep an eye on it while I switch Spaces.
48. As the user, I want to Pin and unpin windows through MCP, so that an agent can do it for me.
49. As the user, I want a Pin to appear on every regular Space and float above other windows, so that I can always see it.
50. As the user, I want to drag and resize a Pin, so that it sits where there's room.
51. As the user, I want a Pin to hide while the real window is visible, so that I don't see two copies.
52. As the user, I want clicking a Pin to take me to the real window's Space and focus it, so that I can interact with it.
53. As the user, I want Pins not to appear over fullscreen-app desktops, so that fullscreen stays clean.
54. As the user, I want pinning a fullscreen window to be refused with a clear reason, so that I understand why.
55. As the user, I want several Pins at once, so that I can watch more than one thing.
56. As the user, I want a Pin to go away when its window closes, so that I'm not left with an orphaned mirror.

### MCP
57. As the user, I want an MCP `status` tool that reports the Display Setup, Guest Displays, the Arrangement, every window with its Assignment, and Drift, so that an agent can reason about my setup.
58. As the user, I want MCP tools for save, restore, move_window, pin, unpin, ignore, rename_space, name_window, remember_display and doctor, so that an agent can do everything the menu bar does and more.
59. As the user, I want MCP tools to refer to windows by short handles from `status`, so that an agent never deals with raw IDs.
60. As the user, I want no MCP tool to take numeric coordinates, so that positions only ever come from Save.
61. As the user, I want `move_window` to optionally Save the move, so that "put this on Work and remember it" is one call.
62. As the user, I want the MCP server to report clearly when Space Maker isn't running, so that the agent can tell me instead of failing silently.
63. As the user, I want the MCP server to work from any MCP client (Claude Code, Claude Desktop) without granting that client extra permissions, so that permissions stay with Space Maker.

### Health and running
64. As the user, I want Space Maker to launch at login as a menu-bar-only app, so that it's always there without a Dock icon.
65. As the user, I want the Doctor to run at launch and on demand (menu bar, MCP, command line), so that I always know whether things work.
66. As the user, I want the Doctor to test a real window move between desktops, so that I find out right away if macOS has broken the move.
67. As the user, I want the Doctor to write a self-contained markdown report, so that I can hand it to an agent to fix.
68. As the user, I want the menu bar icon to turn red when the Doctor finds a problem, so that I notice.
69. As the user, I want features that depend on a failed check to switch off while everything else keeps working, so that one broken part doesn't take down the whole app.
70. As the user, I want Space Maker never to ask me to disable SIP, so that my Mac stays secure.

## Implementation Decisions

- **Platform:** native Swift, built with SwiftPM, macOS 15+.
  - The app is signed with the user's Apple Development identity, so TCC grants survive rebuilds.
  - It runs only on this Mac; no notarization.
  - It launches at login as a menu-bar-only agent (`LSUIElement`, `SMAppService`).
- **Process model (ADR 0002):**
  - One app process owns all state and all TCC grants (Accessibility, Screen Recording, Automation for Chrome).
  - The MCP server is a separate, stateless stdio executable built on the official `modelcontextprotocol/swift-sdk`. It relays each tool call to the app over a local Unix domain socket using newline-delimited JSON.
  - The menu bar UI is a thin client of the same commands.
- **Engine:** the core, deep module. It holds the Layout, the latest view of the world, and Ignore state. It exposes one command interface (status, save, restore, move_window, pin, unpin, ignore, rename_space, name_window, remember_display, doctor, pause/resume) and consumes events from the `WindowSystem` port. Drift, Soft Drift, matching windows to Assignments, and Restore planning are all engine logic.
- **`WindowSystem` port:** the single seam between the engine and macOS.
  - **Reads:** displays (stable identity, built-in flag), desktops per display in order (regular or fullscreen), windows (handle, app, Chrome profile, fullscreen flag, name/title, frame, desktop, standard-window flag).
  - **Actions:** move a window to a desktop, set its frame, set fullscreen, set a Chrome window's name, focus a window, switch to a desktop, show/hide/stop a Pin mirror.
  - **Events:** window appeared, window closed, displays reconfigured, active Space changed.
  - **Clock:** used for debouncing and settle-polling.
- **macOS adapter:** the real implementation of `WindowSystem`. Private API use is confined here (ADR 0001):
  - **SkyLight:** read-only calls to list desktops and look up a window's desktop; the bridged move operation, with its non-exported symbol resolved at runtime.
  - **Accessibility:** frames, fullscreen, observers, focus, Chrome's profile button.
  - **`_AXUIElementGetWindow`:** maps an Accessibility window to its window ID.
  - **Chrome AppleScript:** the `given name` property.
  - **ScreenCaptureKit:** the `desktopIndependentWindow` mirror, drawn in a non-activating `.canJoinAllSpaces` floating `NSPanel`.
  - **Space switching:** synthetic input.
  - **Failures:** every symbol lookup can fail independently and reports through the Doctor.
- **Window identity:**
  - **Match keys:** app bundle ID, plus (for Chrome) profile, plus the fullscreen flag. A name breaks ties.
  - **Auto-naming:** Save auto-names Chrome windows only when the other keys are ambiguous. For apps other than Chrome, the title is used as a best-effort tiebreaker.
  - **Unmatched windows:** a window that is an extra of its kind and unnamed matches nothing and counts as "new" Drift.
  - **Handles:** short, stable for as long as the window lives, and issued by the engine.
- **Layout schema:** one versioned JSON file in `~/.config/space-maker/`. It contains:
  - **Spaces:** names.
  - **Known displays:** identity is UUID, with vendor/model/serial as fallback; the built-in display is implicit.
  - **Display Setups:** keyed by their set of known displays. Each holds an Arrangement: per display, an ordered list of Space names and fullscreen-window references.
  - **Assignments:** window identity, target (a Space, or fullscreen), and optional frames per Display Setup, relative to the display's visible frame.
  - **Ignored apps.**
  - **File handling:** writes are atomic, the app watches the file for hand edits, and Pins and per-window Ignores are never persisted.
- **Space resolution (ADR 0003):** a Space resolves to "the Nth regular desktop on display D" in the current Display Setup's Arrangement. It is never bound to a native desktop's UUID or ManagedSpaceID.
- **Display Setup resolution:**
  - The current Display Setup is the set of connected known displays. All other displays are Guest Displays and are excluded.
  - An unknown Display Setup (no saved Arrangement) suppresses automatic Restore and is surfaced to the user.
- **Display-change handling:**
  1. Debounce reconfiguration events.
  2. Snapshot window frames before the change.
  3. Poll desktops until two consecutive reads match.
  4. Run a full Restore.
- **Save semantics:**
  - Updates every non-Ignored window's Assignment, and the Arrangement and frames of the current Display Setup only.
  - Drops unnamed Assignments whose window is gone, and keeps named ones.
  - A newly seen desktop becomes a Space named after its main app.
- **Restore semantics:**
  - **Normal windows:** move to the resolved desktop, then apply the saved frame if there is one.
  - **Fullscreen windows:** leave them alone if they are fullscreen on the right display. Otherwise exit fullscreen, move the window to the desktop just before its place in the Arrangement, and re-enter fullscreen.
  - **Soft Drift:** anything that can't be achieved is recorded as Soft Drift and not retried until the world changes. Examples: desktop order, a fullscreen window that should come first, missing desktops.
- **Position Drift:** a window on its Space but away from its saved frame for the current Display Setup counts as Drift. A window with no saved frame for that Display Setup never drifts by position.
- **Placement:** a window-appeared event Restores just that window, unless automatic behaviour is paused.
- **Pins:** an engine-level list of pinned window handles; nothing is persisted.
  - The engine hides a mirror while its window is visible on the active Space.
  - A click focuses the window and switches to its Space.
  - Pinning a fullscreen window is refused.
  - Closing the source window removes its Pin.
- **Doctor:** runs against the real adapter.
  - **Checks:** OS build, TCC grants, every private symbol and class, display/desktop enumeration, a ScreenCaptureKit capture, and a live move test.
  - **Live move test:** a separate helper executable owns a window, which is moved to another regular desktop and back, with each move verified.
  - **Report:** markdown in `~/Library/Logs/SpaceMaker/`, written so an agent can act on it.
  - **Failures:** a failed check disables only the features that depend on it.
- **Menu bar:**
  - **Icon:** plain, a dot and count for Drift, or red for a Doctor failure (red wins).
  - **Menu:** Save all; Restore all; drifted windows with Restore, Save and Ignore; Soft Drift with hints; Pin/Unpin frontmost; Remember this display (when a Guest Display is connected); rename Space; pause/resume; Doctor; Open Layout file.
  - **Not included:** notifications and global shortcuts.

## Testing Decisions

- **One seam:** tests drive the engine through its command interface and events, against a **fake `WindowSystem`**. The Layout file is real, written to a temp directory.
- **What tests check:** a good test asserts only externally observable behaviour: command results, where the fake world's windows end up, Drift and Soft Drift as reported by `status`, and Layout file contents after Save. Tests never inspect engine internals.
- **What the fake must simulate:** the macOS behaviours that matter:
  - undock merging (the external's first desktop collapses into the laptop's first; the rest are appended);
  - redock restoring desktops in a shuffled order or with a missing desktop;
  - desktops staying unsettled for several reads after a reconfiguration;
  - a Chrome relaunch putting every window on the current desktop and generating fresh handles;
  - a fullscreen window entering fullscreen just after the desktop it was on;
  - Guest Displays appearing and disappearing;
  - actions that fail (to exercise Soft Drift and Doctor-disabled features).
- **Time:** settle and debounce behaviour is tested with the fake clock; tests never sleep.
- **Main scenarios:**
  - a Chrome relaunch round-trip;
  - undock, then redock;
  - an AirPlay Guest Display session;
  - a new window, then Ignore;
  - auto-naming of an ambiguous Chrome window;
  - Save on one Display Setup leaving the other untouched;
  - restoring and refusing fullscreen windows;
  - Pin hide/show/click/close;
  - an unknown Display Setup suppressing Restore;
  - hand-editing and reloading the Layout file.
- **Real macOS adapter:** not unit tested. The **Doctor is its test suite**, run live on the user's Mac.
- **MCP shim and menu bar:** each gets a single smoke test (a round-trip of a command through the socket). They contain no logic to test.
- **Prior art:** none; this is a greenfield repo. Use Swift Testing.

## Out of Scope

- Pins that survive a relaunch ("pin a pin")
- Global keyboard shortcuts
- Tiling or automatic window layout
- A GUI for editing rules or the Layout
- Profiles for browsers other than Chrome
- Space Maker creating, deleting or reordering native desktops (the user does this in Mission Control and then Saves)
- Disabling SIP or injecting code into the Dock
- Real per-window sticky or always-on-top for other apps' windows (a Pin is a mirror)
- Recognizing a Display Setup by display count alone

## Further Notes

- The first build step must be the Doctor's live move test on macOS 15.4.1. If the SIP-on bridged move fails there, the user upgrades to Tahoe 26.x, where it is confirmed. One known issue on Tahoe: moving a window to an *empty* desktop fails on 26.4.1–26.6.
- Platform facts (researched 2026-11-09):
  - **Bridged move:** `SLSBridgedMoveWindowsToManagedSpaceOperation`, run through the non-exported `SLSPerformAsynchronousBridgedWindowManagementOperation`.
    - Prior art: yabai v7.1.25 and https://github.com/asmvik/yabai/issues/2788.
    - Earlier methods broke: `SLSMoveWindowsToManagedSpace` in 14.5, and the compat-ID fallback in 15.0.
    - Fallback: a synthetic title-bar drag combined with a desktop switch. It switches the user's view and can't reach inactive desktops.
  - **Read-only calls** (work with SIP on): `SLSCopyManagedDisplaySpaces`, `SLSCopySpacesForWindows`, `SLSManagedDisplayGetCurrentSpace`.
  - **Active Space changes:** `NSWorkspace.activeSpaceDidChangeNotification` carries no Space ID.
  - **Space switching:** no public API. Use synthetic Ctrl+N or the DockSwipe gesture (yabai #2780).
  - **Undock and redock:** on undock, the external's first desktop collapses into the laptop's first and the rest are appended. Redock usually moves them back, unreliably (yabai #238, #1237).
    - Desktop identity surviving this is unproven, hence ADR 0003.
    - In `com.apple.spaces` the main display can appear as the literal `"Main"`.
  - **Displays:** built-in display UUIDs are deterministic. External UUIDs are assigned by WindowServer, and one monitor can have several; hence the serial-number fallback.
  - **Chrome:**
    - The macOS title is the given name, otherwise the active tab's title; it never includes the profile.
    - The profile is readable from the toolbar avatar button's accessible name. This is unverified locally.
    - AppleScript `given name` is read/write and persisted by session restore.
    - AppleScript window `id` is not stable across a relaunch.
    - On macOS 15, a normal relaunch puts every window on the current desktop.
  - **ScreenCaptureKit:** `desktopIndependentWindow` keeps delivering frames for windows that are off-screen or on another Space, and pauses for minimized windows. Frames may go stale if the app stops redrawing hidden windows. Sequoia periodically asks the user to re-approve Screen Recording.
- The existing files under `issues/` were drafted before this spec. `/to-tickets` should replace them.
