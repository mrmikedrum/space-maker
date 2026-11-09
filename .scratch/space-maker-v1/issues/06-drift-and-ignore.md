# 06: Drift and Ignore

**What to build:** These count as Drift, and `status` and the menu bar report it:
- a window that is away from its Assignment;
- a new window that matches no Assignment.

The menu bar icon shows a dot and a count. Each drifted window is listed with Restore, Save and Ignore.

The user can Ignore a single window until it closes, or always Ignore an app, which is saved in the Layout. `ignore` is available on MCP. System panels, dialogs and sheets are ignored automatically.

This ticket also adds Soft Drift: Drift that Space Maker can't fix. Soft Drift is listed with a hint, never lights the dot, and is never retried in a loop.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Engine tests against the fake cover: moved and new windows show as Drift; per-window Ignore ends when the window closes; app Ignore persists across reloads; panels and dialogs are excluded; a failed Restore action becomes Soft Drift and is not retried until the world changes.
- [ ] The menu bar is red when the Doctor fails, shows the dot when there is Drift, and is plain otherwise. Red takes precedence over the dot.
- [ ] Demo: open a new window. It appears as "new" in the menu. Ignore removes it.
