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
        /// Where it comes among the display's fullscreen windows in the Arrangement, counting from 0.
        var rank: Int

        /// Such as "after “Work”", or "before “Tasks”" for one that comes first.
        var description: String {
            if spacesBefore > 0, spaces.indices.contains(spacesBefore - 1) { return "after “\(spaces[spacesBefore - 1])”" }
            if let first = spaces.first { return "before “\(first)”" }
            return "on \(display.name)"
        }

        /// The regular desktop just before the place, where the window goes before re-entering fullscreen, which puts
        /// it on the right display. macOS appends a new fullscreen desktop at the end of the display, so the window
        /// lands after every Space whatever its place; only its order among the fullscreen windows can be kept.
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
            let ordered = arrangement.fullscreenWindows.enumerated()
                .sorted { ($0.element.spacesBefore, $0.offset) < ($1.element.spacesBefore, $1.offset) }.map(\.element)
            for (rank, item) in ordered.enumerated() {
                let gap = ordered.filter { $0.spacesBefore == item.spacesBefore }.map(\.name)
                result[item.name] = FullscreenPlace(
                    name: item.name, display: display, spacesBefore: item.spacesBefore, spaces: arrangement.spaces, gap: gap, rank: rank
                )
            }
        }
        return result
    }

    /// One step of putting fullscreen windows back: `window` goes (back) into fullscreen at `place`.
    struct FullscreenStep {
        var window: WindowSystemWindow
        var place: FullscreenPlace
        /// Whether it was already fullscreen in place and is only cycled to come after a window put back before it.
        var keepsOrder: Bool
    }

    /// The steps that put `restoring` (windows with a fullscreen Assignment that are out of fullscreen or on the
    /// wrong display) back in fullscreen with each display's fullscreen windows in their Arrangement order.
    ///
    /// macOS appends every new fullscreen desktop at the end of its display. So on each display with a window to put
    /// back, the longest start of the display's fullscreen order that's already fullscreen there in that order stays;
    /// every later fullscreen window of the display, in order, goes out of and back into fullscreen (or just in, for
    /// one being put back), each landing after the one before. A display with nothing to put back is never touched,
    /// even if the user dragged its fullscreen windows out of order (Soft Drift).
    /// `inPlace` is every window already fullscreen on its place's display (see `fullscreenWindowsInPlace`).
    func fullscreenSteps(
        restoring: [(window: WindowSystemWindow, place: FullscreenPlace)], inPlace: [(window: WindowSystemWindow, place: FullscreenPlace)]
    ) -> [FullscreenStep] {
        var steps: [FullscreenStep] = []
        var displays: [String] = []
        for item in restoring where !displays.contains(item.place.display.id) { displays.append(item.place.display.id) }
        for displayID in displays {
            let back = restoring.filter { $0.place.display.id == displayID }
            let kept = inPlace.filter { $0.place.display.id == displayID }
            guard let display = back.first?.place.display else { continue }
            let wanted = (back.map { ($0, false) } + kept.map { ($0, true) }).sorted { $0.0.place.rank < $1.0.place.rank }
            // The start of the order that's already fullscreen here, in that order, stays.
            var stay = 0
            var lastIndex = -1
            for (item, isInPlace) in wanted {
                guard isInPlace, let index = display.desktops.firstIndex(where: { $0.id == item.window.desktopID }), index > lastIndex
                else { break }
                lastIndex = index
                stay += 1
            }
            steps += wanted.dropFirst(stay).map { FullscreenStep(window: $0.0.window, place: $0.0.place, keepsOrder: $0.1) }
        }
        return steps
    }

    /// The windows, not Ignored, whose Assignment is a fullscreen place and that are fullscreen on its display.
    func fullscreenWindowsInPlace(
        _ windows: [WindowSystemWindow], matches: [UInt32: Int], assignments: [Assignment], places: [String: FullscreenPlace]
    ) -> [(window: WindowSystemWindow, place: FullscreenPlace)] {
        windows.compactMap { window in
            guard !isIgnored(window), window.isFullscreen, let index = matches[window.id], assignments[index].window.isFullscreen,
                  let place = places[assignments[index].space], isOn(window, place.display)
            else { return nil }
            return (window, place)
        }
    }

    /// Restores one window whose Assignment is a fullscreen place. Returns nil if it was already in place,
    /// otherwise whether every step worked. A window fullscreen on the right display is left alone, even in the
    /// wrong order, unless `cycling` it (out of fullscreen and back in) to follow a window put back before it.
    func restoreFullscreen(_ window: WindowSystemWindow, to place: FullscreenPlace, cycling: Bool = false) -> Bool? {
        if window.isFullscreen, isOn(window, place.display), !cycling { return nil }
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
