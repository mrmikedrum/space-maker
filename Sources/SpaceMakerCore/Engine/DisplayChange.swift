import Foundation

/// Where the engine is between a display change and the automatic Restore that follows it.
struct DisplayChangeProgress {
    /// Bumped by every reconfiguration event, so work scheduled for an earlier event lapses.
    var generation = 0
    /// The desktops as last polled, waiting for a second read that matches.
    var lastRead: [DesktopsRead]?
    var reads = 0
}

/// One display's desktops as a settle poll sees them.
struct DesktopsRead: Equatable {
    var display: String
    var desktops: [UInt64]
    var kinds: [DesktopKind]
}

/// Automatic Restore on display change: debounce the reconfiguration events, wait until two consecutive
/// reads of the desktops match, then run a full Restore.
extension Engine {
    /// How long reconfiguration events must stop before Space Maker looks at the desktops.
    static let displayChangeDebounce: TimeInterval = 1
    /// How often the desktops are read while waiting for them to settle.
    static let desktopSettlePollInterval: TimeInterval = 0.5
    /// Reads after which Space Maker stops waiting and Restores anyway.
    static let desktopSettleMaxReads = 20

    func displaysReconfigured() {
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
        if read == displayChange.lastRead || displayChange.reads >= Self.desktopSettleMaxReads {
            displayChange.lastRead = nil
            restoreAutomatically()
            return
        }
        displayChange.lastRead = read
        windowSystem.schedule(after: Self.desktopSettlePollInterval) { [weak self] in
            self?.pollDesktopsUntilSettled(generation)
        }
    }

    /// A full Restore nobody asked for: it runs only while automatic behaviour is on.
    private func restoreAutomatically() {
        // Pause (ticket 05) belongs here, the one place automatic Restore runs: `guard !isPaused else { return }`.
        _ = restore(handle: nil)
    }
}
