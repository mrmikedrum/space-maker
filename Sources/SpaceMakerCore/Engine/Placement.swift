/// Placement: Restoring a single window at the moment it appears.
extension Engine {
    func pause() -> CommandReply {
        guard !isPaused else { return CommandReply(text: "Space Maker is already paused.") }
        isPaused = true
        return CommandReply(text: "Paused: windows that appear stay where they are until you resume.")
    }

    func resume() -> CommandReply {
        guard isPaused else { return CommandReply(text: "Space Maker isn't paused.") }
        isPaused = false
        return CommandReply(text: "Resumed: windows that appear go to their Space again.")
    }

    /// Moves a window that just appeared to the Space its Assignment names.
    /// A window with no Assignment, an Ignored window, or one already on its Space is left alone.
    /// Each window gets one chance in its life, even if macOS reports it again, so a window the user
    /// moves after it was placed (or that appeared while paused) is never moved back automatically.
    func place(_ windowID: UInt32) {
        let windows = windowSystem.readWindows().filter(\.isStandard)
        appearedWindows = appearedWindows.filter { id in windows.contains { $0.id == id } }
        // A window macOS doesn't list yet can be announced again once it does.
        guard let window = windows.first(where: { $0.id == windowID }),
              appearedWindows.insert(windowID).inserted, !isPaused
        else { return }
        reloadLayoutIfChanged()
        guard layoutProblem == nil, movesDisabledReason == nil else { return }
        let displays = windowSystem.readDisplays()
        guard let desktops = resolvedSpaces(displays), !window.isFullscreen, !isIgnored(window),
              let index = Self.match(windows, to: layout.assignments)[windowID],
              let target = desktops[layout.assignments[index].space], window.desktopID != target
        else { return }
        forgetSoftDriftIfWorldChanged(displays: displays, windows: windows)
        if windowSystem.moveWindow(windowID, toDesktop: target) {
            failedMoves.remove(windowID)
        } else {
            failedMoves.insert(windowID)  // Soft Drift, like a failed Restore
        }
        rememberWorldForSoftDrift()
    }
}
