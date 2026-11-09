# 03: Save and Restore Spaces

**What to build:** The user arranges windows across desktops and runs Save all from MCP or the menu bar. Space Maker writes the Layout file, and each desktop it hasn't seen before becomes a Space named after its main app.

After the user moves windows around, Restore all puts every window that has an Assignment back on its Space. Restore one does the same for a single window. Windows without an Assignment are never moved.

MCP gains `save`, `restore`, `move_window` (with an optional save) and `rename_space`. Hand edits to the Layout file are reloaded. For now, a window's identity is its app plus its title.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] The Layout is one versioned, readable JSON file, written atomically and watched for hand edits.
- [ ] Engine tests against the fake cover: Save → move → Restore round trips; Restore one; windows without an Assignment left alone; a new desktop auto-named on Save; rename; a desktop deleted and then Saved, which removes it from the Arrangement; a hand edit reloaded.
- [ ] No tool accepts numeric coordinates. Windows are referred to by handles from `status`.
- [ ] If the Doctor's move check fails, Restore and `move_window` are disabled and report why. Everything else keeps working.
- [ ] Demo on the real Mac: move two windows to other desktops by hand, then Restore all. Both return.
