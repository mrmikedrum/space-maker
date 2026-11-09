/// Placement: Restoring a single window at the moment it appears.
extension Engine {
    func pause() -> CommandReply {
        guard !isPaused else { return CommandReply(text: "Space Maker is already paused.") }
        isPaused = true
        return CommandReply(text: "Paused: windows that appear stay where they are, and display changes don’t Restore, until you resume.")
    }

    func resume() -> CommandReply {
        guard isPaused else { return CommandReply(text: "Space Maker isn't paused.") }
        isPaused = false
        return CommandReply(text: "Resumed: windows that appear go to their Space again.")
    }

    /// Moves a window that just appeared to the Space its Assignment names, and to its saved position there,
    /// or for a fullscreen Assignment back into fullscreen at its place in the Arrangement.
    /// A window with no Assignment, an Ignored window, or one already in place is left alone.
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
        let matches = Self.match(windows, to: layout.assignments)
        guard let desktops = resolvedSpaces(displays), !isIgnored(window), let index = matches[windowID] else { return }
        let assignment = layout.assignments[index]

        // A fullscreen Assignment goes back to its place in the Arrangement, whether the window came back
        // fullscreen (perhaps on the wrong display) or as a normal window.
        if assignment.window.isFullscreen {
            let places = fullscreenPlaces(displays)
            guard let place = places[assignment.space],
                  !(window.isFullscreen && place.display.desktops.contains { $0.id == window.desktopID })
            else { return }
            forgetSoftDriftIfWorldChanged(displays: displays, windows: windows)
            // Like Restore, later fullscreen windows of the display are cycled so the order among them holds.
            let inPlace = fullscreenWindowsInPlace(windows, matches: matches, assignments: layout.assignments, places: places)
            movingWindows {
                for step in fullscreenSteps(restoring: [(window, place)], inPlace: inPlace) {
                    if restoreFullscreen(step.window, to: step.place, cycling: step.keepsOrder) == false {
                        failedMoves.insert(step.window.id)
                    } else {
                        failedMoves.remove(step.window.id)
                    }
                }
            }
            rememberWorldForSoftDrift()
            return
        }
        guard !window.isFullscreen, let target = desktops[assignment.space] else { return }
        let plan = plan(window, assignment, on: target, displays: knownDisplays(displays))
        guard plan.isNeeded else { return }
        forgetSoftDriftIfWorldChanged(displays: displays, windows: windows)
        _ = movingWindows { carryOut(plan, for: windowID) }  // a failure is Soft Drift, like a failed Restore
        rememberWorldForSoftDrift()
    }
}
