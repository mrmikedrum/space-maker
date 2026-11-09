import Foundation

/// Where the engine is between a display change and the automatic Restore that follows it.
struct DisplayChangeProgress {
    /// Bumped by every reconfiguration event, so work scheduled for an earlier event lapses.
    var generation = 0
    /// The desktops as last polled, waiting for a second read that matches.
    var lastRead: [DesktopsRead]?
    var reads = 0
    /// The last display change never settled, so no automatic Restore ran: Soft Drift until a later one settles or the user Restores.
    var neverSettled = false
    /// Where windows were, by window ID, at the first reconfiguration event since the last automatic Restore.
    var framesBefore: [UInt32: FrameBefore]?
}

/// A window's position before a display change, and the display it was on.
struct FrameBefore {
    var display: String
    var frame: WindowFrame
}

/// One display's desktops as a settle poll sees them.
struct DesktopsRead: Equatable {
    var display: String
    var desktops: [UInt64]
    var kinds: [DesktopKind]
}

/// Automatic Restore on display change: debounce the reconfiguration events, wait until two consecutive
/// reads of the desktops match, then run a full Restore. Desktops that never settle get no Restore.
/// Windows with no saved position for the Display Setup go back to where they were before the change,
/// if they're still on the same display.
extension Engine {
    /// How long reconfiguration events must stop before Space Maker looks at the desktops.
    static let displayChangeDebounce: TimeInterval = 1
    /// How often the desktops are read while waiting for them to settle.
    static let desktopSettlePollInterval: TimeInterval = 0.5
    /// Reads after which Space Maker stops waiting, without Restoring, until the next display change.
    static let desktopSettleMaxReads = 20

    func displaysReconfigured() {
        if displayChange.framesBefore == nil { displayChange.framesBefore = currentFrames() }
        displayChange.generation += 1
        displayChange.lastRead = nil
        displayChange.reads = 0
        let generation = displayChange.generation
        windowSystem.schedule(after: Self.displayChangeDebounce) { [weak self] in
            self?.pollDesktopsUntilSettled(generation)
        }
    }

    private func pollDesktopsUntilSettled(_ generation: Int) {
        guard generation == displayChange.generation else { return }  // a later event restarted the wait
        let read = windowSystem.readDisplays().map {
            DesktopsRead(display: $0.id, desktops: $0.desktops.map(\.id), kinds: $0.desktops.map(\.kind))
        }
        displayChange.reads += 1
        if read == displayChange.lastRead {
            displayChange.lastRead = nil
            displayChange.neverSettled = false
            restoreAutomatically()
            return
        }
        // A Restore on a half-finished read would send windows to the wrong desktops, so give up and say so.
        if displayChange.reads >= Self.desktopSettleMaxReads {
            displayChange.lastRead = nil
            displayChange.neverSettled = true
            onChange?()
            return
        }
        displayChange.lastRead = read
        windowSystem.schedule(after: Self.desktopSettlePollInterval) { [weak self] in
            self?.pollDesktopsUntilSettled(generation)
        }
    }

    /// A full Restore nobody asked for: it runs only while automatic behaviour isn't paused.
    /// A change that settles while paused is not replayed on resume; Restore all catches up.
    private func restoreAutomatically() {
        let framesBefore = displayChange.framesBefore ?? [:]
        displayChange.framesBefore = nil
        guard !isPaused else { return }
        _ = restore(handle: nil)
        putBackFrames(framesBefore)
    }

    /// Every normal window's position and display, keyed by window ID.
    private func currentFrames() -> [UInt32: FrameBefore] {
        let displays = windowSystem.readDisplays()
        var result: [UInt32: FrameBefore] = [:]
        for window in windowSystem.readWindows() where window.isStandard && !window.isFullscreen {
            guard let frame = window.frame, let display = Self.display(of: window, in: displays) else { continue }
            result[window.id] = FrameBefore(display: display, frame: frame)
        }
        return result
    }

    private static func display(of window: WindowSystemWindow, in displays: [WindowSystemDisplay]) -> String? {
        displays.first { $0.desktops.contains { $0.id == window.desktopID } }?.id
    }

    /// Puts windows that macOS moved during the change back where they were, if they're still on the same display
    /// and Restore doesn't own their position (they have no saved position for this Display Setup).
    private func putBackFrames(_ framesBefore: [UInt32: FrameBefore]) {
        guard !framesBefore.isEmpty, layoutProblem == nil, movesDisabledReason == nil else { return }
        let displays = windowSystem.readDisplays()
        guard resolvedSpaces(displays) != nil else { return }  // an unknown Display Setup gets no automatic Restore
        let setup = displaySetupKey(displays)
        let windows = windowSystem.readWindows().filter(\.isStandard)
        let matches = Self.match(windows, to: layout.assignments)
        for window in windows where !window.isFullscreen && !isIgnored(window) {
            guard let before = framesBefore[window.id], Self.display(of: window, in: displays) == before.display,
                  !Self.isAt(window.frame, before.frame),
                  matches[window.id].map({ layout.assignments[$0].frame(in: setup) == nil }) ?? true
            else { continue }
            _ = windowSystem.setFrame(window.id, to: before.frame)
        }
    }

    /// Soft Drift for a display change whose desktops never settled, if the last one didn't.
    var unsettledDisplayChangeNote: SoftDriftStatus? {
        guard displayChange.neverSettled else { return nil }
        return SoftDriftStatus(
            handle: nil, app: nil, title: nil,
            problem: "After the last display change, macOS kept rearranging desktops and they never settled, so Space Maker didn't Restore.",
            hint: "Once the desktops look settled, use Restore all. Space Maker tries again on the next display change."
        )
    }
}
