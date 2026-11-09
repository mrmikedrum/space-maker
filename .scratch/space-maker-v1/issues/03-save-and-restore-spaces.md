# 03: Save and Restore Spaces

**What to build:** The user arranges windows across desktops and runs Save all from MCP or the menu bar. Space Maker writes the Layout file, and each desktop it hasn't seen before becomes a Space named after its main app.

After the user moves windows around, Restore all puts every window that has an Assignment back on its Space. Restore one does the same for a single window. Windows without an Assignment are never moved.

MCP gains `save`, `restore`, `move_window` (with an optional save) and `rename_space`. Hand edits to the Layout file are reloaded. For now, a window's identity is its app plus its title.

**Blocked by:** 02

**Status:** ready-for-agent

- [x] The Layout is one versioned, readable JSON file, written atomically and watched for hand edits.
- [x] Engine tests against the fake cover: Save → move → Restore round trips; Restore one; windows without an Assignment left alone; a new desktop auto-named on Save; rename; a desktop deleted and then Saved, which removes it from the Arrangement; a hand edit reloaded.
- [x] No tool accepts numeric coordinates. Windows are referred to by handles from `status`.
- [x] If the Doctor's move check fails, Restore and `move_window` are disabled and report why. Everything else keeps working.
- [ ] Demo on the real Mac: move two windows to other desktops by hand, then Restore all. Both return. (pending live demo)

## Comments

- Implemented test-first against the fake `WindowSystem` with a real Layout file in a temp folder (`SaveAndRestoreTests`, 13 tests). The port gained its first action, `moveWindow`; the macOS adapter issues the bridged move and polls up to 1 s for it to land.
- Layout v1 (`~/.config/space-maker/layout.json`): `spaces`, `displaySetups` (sorted known display IDs → per-display ordered Space names), `assignments` (bundle ID + title → Space). Written atomically, pretty-printed; the app watches its folder, and every command also re-reads a changed file. A broken hand edit is reported and never overwritten.
- Save keeps a desktop's Space when its windows' Assignments say so (positional first, then majority), so deleting a desktop drops the right Space; unclaimed new desktops are named after their main app ("Desktop" when empty), de-duplicated with " 2".
- `status` now shows each desktop's Space. Menu bar gained Save All and Restore All. A failed Doctor live move test disables Restore and `move_window` with the Doctor's reason; skipped doesn't.
- Deferred to their tickets: frames (09), fullscreen windows (10, skipped by Save/Restore/move_window), Display Setups beyond the built-in display (07), Chrome identity (04).
- `Engine.init` now requires `layoutURL` so tests never read the user's real Layout.
- Real-Mac demo: pending live demo (user away).
