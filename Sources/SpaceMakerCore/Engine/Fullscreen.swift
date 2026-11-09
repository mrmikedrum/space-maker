/// Fullscreen windows in Arrangements: where each one's place is, putting it back, and its Drift.
extension Engine {
    /// A fullscreen window's place in the current Display Setup's Arrangement.
    struct FullscreenPlace {
        var name: String
        /// The known display it belongs on, named by its remembered ID.
        var display: WindowSystemDisplay
        var spacesBefore: Int
        /// The display's Spaces, to describe the place.
        var spaces: [String]
        /// The names of the fullscreen windows sharing its gap between Spaces, in order.
        var gap: [String]

        /// Such as "after “Work”", or "before “Tasks”" for one that comes first.
        var description: String {
            if spacesBefore > 0, spaces.indices.contains(spacesBefore - 1) { return "after “\(spaces[spacesBefore - 1])”" }
            if let first = spaces.first { return "before “\(first)”" }
            return "on \(display.name)"
        }

        /// The regular desktop just before the place, where the window goes before re-entering fullscreen.
        /// For a place before the first Space that's the first desktop, so it lands one place late.
        var desktopBefore: UInt64? {
            let regular = display.desktops.filter { $0.kind == .regular }
            return spacesBefore == 0 ? regular.first?.id : (regular.indices.contains(spacesBefore - 1) ? regular[spacesBefore - 1].id : nil)
        }
    }

    /// Every fullscreen window's place in the current Display Setup, by name.
    func fullscreenPlaces(_ displays: [WindowSystemDisplay]) -> [String: FullscreenPlace] {
        let known = knownDisplays(displays)
        guard let setup = layout.displaySetups.first(where: { $0.displays == known.map(\.id).sorted() }) else { return [:] }
        var result: [String: FullscreenPlace] = [:]
        for arrangement in setup.arrangement {
            guard let display = known.first(where: { $0.id == arrangement.display }) else { continue }
            for item in arrangement.fullscreenWindows {
                let gap = arrangement.fullscreenWindows.filter { $0.spacesBefore == item.spacesBefore }.map(\.name)
                result[item.name] = FullscreenPlace(
                    name: item.name, display: display, spacesBefore: item.spacesBefore, spaces: arrangement.spaces, gap: gap
                )
            }
        }
        return result
    }

    /// Restores one window whose Assignment is a fullscreen place. Returns nil if it was already in place,
    /// otherwise whether every step worked. A window fullscreen on the right display is left alone, even in the
    /// wrong order: only the user can fix that (Soft Drift).
    func restoreFullscreen(_ window: WindowSystemWindow, to place: FullscreenPlace) -> Bool? {
        if window.isFullscreen, isOn(window, place.display) { return nil }
        guard let target = place.desktopBefore else { return false }
        if window.isFullscreen, !windowSystem.setFullscreen(window.id, false) { return false }
        let desktop = windowSystem.readWindows().first { $0.id == window.id }?.desktopID
        if desktop != target, !windowSystem.moveWindow(window.id, toDesktop: target) { return false }
        return windowSystem.setFullscreen(window.id, true)
    }

    /// Drift for a window whose Assignment is a fullscreen place: out of fullscreen or on the wrong display is
    /// Drift Restore fixes; in the wrong order on the right display is Soft Drift.
    func fullscreenDrift(
        _ window: WindowSystemWindow, place: FullscreenPlace, matches: [UInt32: Int], windows: [WindowSystemWindow]
    ) -> (DriftStatus?, SoftDriftStatus?) {
        let handle = handle(for: window.id)
        if failedMoves.contains(window.id) {
            return (nil, SoftDriftStatus(
                handle: handle, app: window.appName, title: window.title,
                problem: "macOS wouldn't put it back in fullscreen \(place.description) on \(place.display.name).",
                hint: "Put it there by hand, or Save to keep it where it is. Space Maker tries again when windows or desktops change."
            ))
        }
        guard window.isFullscreen, isOn(window, place.display) else {
            return (DriftStatus(kind: .moved, handle: handle, app: window.appName, title: window.title, space: place.name), nil)
        }
        if spacesBefore(window, on: place.display) != place.spacesBefore || !inGapOrder(window, place, matches: matches, windows: windows) {
            return (nil, SoftDriftStatus(
                handle: handle, app: window.appName, title: window.title,
                problem: "It's fullscreen on \(place.display.name), but out of order: it belongs \(place.description).",
                hint: "Drag it into place in Mission Control, or Save to keep this order. macOS doesn't let Space Maker reorder desktops."
            ))
        }
        return (nil, nil)
    }

    private func isOn(_ window: WindowSystemWindow, _ display: WindowSystemDisplay) -> Bool {
        display.desktops.contains { $0.id == window.desktopID }
    }

    /// How many regular desktops come before the window's desktop on the display.
    private func spacesBefore(_ window: WindowSystemWindow, on display: WindowSystemDisplay) -> Int {
        display.desktops.prefix { $0.id != window.desktopID }.filter { $0.kind == .regular }.count
    }

    /// Whether the fullscreen windows sharing the window's gap between Spaces are in their saved order.
    private func inGapOrder(
        _ window: WindowSystemWindow, _ place: FullscreenPlace, matches: [UInt32: Int], windows: [WindowSystemWindow]
    ) -> Bool {
        guard place.gap.count > 1 else { return true }
        let gapDesktops = place.display.desktops.filter { desktop in
            desktop.kind == .fullscreen
                && place.display.desktops.prefix { $0.id != desktop.id }.filter { $0.kind == .regular }.count == place.spacesBefore
        }
        let actual = gapDesktops.flatMap { desktop in
            windows.filter { $0.isFullscreen && $0.desktopID == desktop.id }
                .compactMap { matches[$0.id].map { layout.assignments[$0].space } }
        }.filter(place.gap.contains)
        return actual == place.gap.filter(actual.contains)
    }
}
