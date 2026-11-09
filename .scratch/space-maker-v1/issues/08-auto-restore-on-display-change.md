# 08: Automatic Restore on display change

**What to build:** When displays are connected or disconnected, Space Maker waits for the change to settle, then runs a full Restore by itself. Settling means debouncing the reconfiguration events, snapshotting window frames before the change, and polling desktops until two consecutive reads match.

Docking and undocking need nothing from the user. When an AirPlay or Sidecar Guest Display disconnects, any window the user moved onto it returns home. Pausing (ticket 05) also pauses this.

**Blocked by:** 07

**Status:** ready-for-agent

- [x] Tests use the fake clock and never sleep. They cover: flapping reconfiguration events causing exactly one Restore; desktops that stay unsettled for several reads delaying Restore; a Guest Display session ending with windows back home; no automatic Restore while paused or on an unknown Display Setup.
- [ ] Demo on the real Mac: undock and redock with no further action. Everything ends up in its slot. (pending live demo)

## Comments

- Built test-first against the fake `WindowSystem` and a real Layout in a temp folder (`AutoRestoreTests`, 6 tests): undock with no further action; flapping events causing exactly one Restore (a dragged window isn't moved back later); desktops unsettled for several reads delaying Restore (the fake refuses moves while unsettled, so an early Restore would leave Soft Drift); an AirPlay Guest Display session ending with Keynote back home and an unassigned window left alone; an unknown Display Setup getting no automatic Restore; nothing while paused, with the next change after resume Restoring as usual.
- The `WindowSystem` port gains the clock (`schedule(after:_:)`) and a `displaysReconfigured` event. The macOS adapter posts it from `NSApplication.didChangeScreenParametersNotification` (public API) and schedules with `DispatchQueue.main.asyncAfter`. The fake gains `FakeClock` (`advance(by:)` runs due work in order; tests never sleep), `reconfigureDisplays()` and `unsettledReads`.
- Engine (`DisplayChange.swift`): every event restarts a 1 s debounce; then desktops are read every 0.5 s until two consecutive reads match (giving up after 20 reads and Restoring anyway), then a full Restore runs. A Guest Display needs nothing special: Restore sends every assigned window to its slot.
- Pause: ticket 05 landed while this was in progress and was merged in. `Engine.restoreAutomatically()`, the only place automatic Restore runs, checks `isPaused`. A change that settles while paused isn't replayed on resume; Restore all catches up. The pause wording (MCP tools, reply, menu item, tooltip) now mentions display changes too.
- Deferred: "snapshot window frames before the change" needs frames in the port, which ticket 09 adds; it belongs with saved positions. Real-Mac demo is pending live demo (user away).
- Frame snapshot now implemented (review round 2, R2–R5): the engine keeps a rolling cache of window frames on known displays from the last stable topology, refreshed whenever it looks at the world (commands, `status`, window events) while no display change is under way, and freezes it when a reconfiguration burst begins, since macOS can shove windows before it reports the change. After the automatic Restore, windows with an Assignment but no saved position for the Display Setup go back to their frozen frame if still on the same known display. Windows without an Assignment, and windows on Guest Displays, are never moved. A Restore waiting for a move to finish lapses if a newer display change arrives meanwhile. Tests in `AutoRestoreTests`.
