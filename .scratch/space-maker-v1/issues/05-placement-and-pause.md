# 05: Placement and pause

**What to build:** A window that matches an Assignment is restored to its Space the moment it appears. The menu bar has a pause/resume toggle for automatic behaviour.

The headline demo: the user quits Chrome and relaunches it, and every tracked Chrome window returns to its Space without any action from the user.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Engine tests against the fake cover: a Chrome relaunch that drops every window on the current desktop ends with each window on its Space; a window with no Assignment that appears is left alone; nothing moves while paused; behaviour resumes after resume.
- [ ] Placement never fights the user. A window the user moves after it was placed is not moved back automatically.
- [ ] Demo on the real Mac: quit and relaunch Chrome. All tracked windows go home.
