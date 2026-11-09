# 04: Chrome window identity

**What to build:** The user's Chrome windows (Work main fullscreen, Work second, Game main fullscreen, Personal main) each get their own stable Assignment.

Windows are matched by app, Chrome profile and whether they're fullscreen. A name is used only as a tiebreaker.

When those keys are ambiguous, Save names the Chrome window automatically through Chrome's scripting interface. The name survives a Chrome relaunch.

`name_window` on MCP lets the user or an agent set a meaningful name. Unnamed windows that have closed are dropped on the next Save. Named windows stay in the Layout.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Engine tests against the fake cover: two same-profile normal windows get auto-named on Save; a relaunch with fresh handles still matches every window; profile plus the fullscreen flag tells windows apart without any name; named and unnamed windows are pruned correctly.
- [ ] Save requests Automation permission for Chrome. If it's denied, auto-naming is skipped, Save still succeeds, and a Doctor finding records why.
- [ ] Apps other than Chrome fall back to matching on app plus title.
- [ ] Demo: `status` on the real Mac shows each Chrome window with its profile and its Assignment.
