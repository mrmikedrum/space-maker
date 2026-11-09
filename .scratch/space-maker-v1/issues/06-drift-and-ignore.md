# 06: Drift and Ignore

**What to build:** These count as Drift, and `status` and the menu bar report it:
- a window that is away from its Assignment;
- a new window that matches no Assignment.

The menu bar icon shows a dot and a count. Each drifted window is listed with Restore, Save and Ignore.

The user can Ignore a single window until it closes, or always Ignore an app, which is saved in the Layout. `ignore` is available on MCP. System panels, dialogs and sheets are ignored automatically.

This ticket also adds Soft Drift: Drift that Space Maker can't fix. Soft Drift is listed with a hint, never lights the dot, and is never retried in a loop.

**Blocked by:** 03

**Status:** ready-for-agent

- [x] Engine tests against the fake cover: moved and new windows show as Drift; per-window Ignore ends when the window closes; app Ignore persists across reloads; panels and dialogs are excluded; a failed Restore action becomes Soft Drift and is not retried until the world changes.
- [ ] The menu bar is red when the Doctor fails, shows the dot when there is Drift, and is plain otherwise. Red takes precedence over the dot.
- [ ] Demo: open a new window. It appears as "new" in the menu. Ignore removes it.

## Comments

- Built test-first against the fake `WindowSystem` with a real Layout in a temp folder (`DriftTests`, 11 tests). `status` gains `drift` (kind `moved` with its Space, or `new`) and `softDrift` (problem + hint). Fullscreen windows don't drift yet (ticket 10); with no Arrangement saved for the current Display Setup nothing drifts.
- `ignore` (engine + MCP): `window` handle Ignores that window until it closes (never persisted); `app: true` adds its bundle ID to the Layout's new `ignoredApps` (a Layout without the key still loads). Ignored windows are skipped by Drift, Save (their old Assignment is kept) and Restore all. Panels, dialogs and sheets were already excluded via the standard-window flag.
- `save` takes an optional `window` handle to save just that window's Assignment as its current Space (the menu's per-window Save).
- Soft Drift: a window Restore couldn't move, and a Space this Display Setup's Arrangement has no desktop for. Restore all doesn't retry a failed move until displays, desktops or window places change; Restore by handle always tries.
- Menu bar: red on Doctor failure, else `●N` for Drift, else plain; menu rebuilt on open with Drift (Restore / Save Where It Is / Ignore This Window / Always Ignore App) and Soft Drift with hints. Drift is polled every 5 s until window events exist. Implemented and builds; the icon/menu criterion and the demo are pending live demo (user away).

