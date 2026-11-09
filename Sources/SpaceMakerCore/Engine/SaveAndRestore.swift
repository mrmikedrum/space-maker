import Foundation

/// Save, Restore, `move_window` and `rename_space`: the engine commands that read and write the Layout.
extension Engine {
    // MARK: - Layout file

    /// Called when the Layout file changes on disk, such as after a hand edit.
    public func layoutFileChanged() {
        reloadLayoutIfChanged()
    }

    /// Re-reads the Layout file if its bytes differ from what the engine last read or wrote.
    /// Every command calls this first, so a hand edit is honoured even if the watcher missed it.
    func reloadLayoutIfChanged() {
        let data: Data?
        switch LayoutFile.read(at: layoutURL) {
        case .data(let bytes): data = bytes
        case .absent: data = nil
        case .failed(let reason):
            layoutData = nil
            layoutProblem = .unreadable(layoutURL, reason)
            return
        }
        guard data != layoutData || layoutProblem != nil else { return }
        layoutData = data
        guard let data else {
            layout = Layout()
            layoutProblem = nil
            return
        }
        do {
            layout = try LayoutFile.decode(data, from: layoutURL)
            layoutProblem = nil
        } catch let error as LayoutFileError {
            layoutProblem = error
        } catch {
            layoutProblem = .unreadable(layoutURL, error.localizedDescription)
        }
    }

    private func writeLayout() throws {
        let data = LayoutFile.encode(layout)
        try LayoutFile.write(data, to: layoutURL)
        layoutData = data
    }

    /// Runs `body` with the current Layout, refusing if the file is unusable.
    func withLayout(_ body: () -> CommandReply) -> CommandReply {
        reloadLayoutIfChanged()
        if let layoutProblem { return CommandReply(text: layoutProblem.description, isError: true) }
        return body()
    }

    func committing(_ success: String) -> CommandReply {
        do {
            try writeLayout()
            return CommandReply(text: success)
        } catch {
            return CommandReply(text: "Couldn't write the Layout file at \(layoutURL.path): \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Doctor

    /// Disables Restore and `move_window` while the Doctor says windows can't be moved; nil re-enables them.
    public func setMovesDisabled(because reason: String?) {
        movesDisabledReason = reason
    }

    private func movesDisabledReply() -> CommandReply? {
        movesDisabledReason.map {
            CommandReply(text: "Moving windows is disabled because the Doctor's move check failed: \($0)", isError: true)
        }
    }

    // MARK: - Save

    func save() -> CommandReply {
        withLayout {
            let displays = knownDisplays(windowSystem.readDisplays())
            let standard = windowSystem.readWindows().filter(\.isStandard)
            var windows = standard.filter { !isIgnored($0) }  // Ignored windows keep whatever Assignment they had
            let setupKey = displays.map(\.id).sorted()
            let previous = layout.displaySetups.first { $0.displays == setupKey }

            let matches = Self.match(standard, to: layout.assignments)
            var taken = Set<String>()
            var arrangement: [DisplayArrangement] = []
            var newSpaces: [String] = []
            var namesByDesktop: [UInt64: String] = [:]
            var fullscreenPlaces: [UInt32: String] = [:]  // fullscreen window ID → its place's name

            // A fullscreen Assignment that Save keeps without re-saving it (its window is closed but named, or open
            // but Ignored or not on a known display) keeps its place in this Display Setup's Arrangement too.
            let live = Set(matches.values)
            let kinds = Dictionary(displays.flatMap(\.desktops).map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
            let resaving = Set(windows.filter { window in
                window.desktopID.flatMap { kinds[$0] } == (window.isFullscreen ? .fullscreen : .regular)
            }.compactMap { matches[$0.id] })
            let keptPlaces = Set(layout.assignments.indices.filter { index in
                let assignment = layout.assignments[index]
                return assignment.window.isFullscreen && !resaving.contains(index) && (live.contains(index) || assignment.window.name != nil)
            }.map { layout.assignments[$0].space })
            taken.formUnion(keptPlaces)

            // Name every regular desktop, display by display, keeping existing Spaces where the evidence allows.
            for display in displays {
                let desktops = display.desktops.filter { $0.kind == .regular }
                let previousNames = previous?.arrangement.first { $0.display == display.id }?.spaces ?? []
                var names = [String?](repeating: nil, count: desktops.count)

                // Which Spaces the windows now on each desktop were assigned to.
                let votes = desktops.map { desktop in
                    windows.filter { $0.desktopID == desktop.id && !$0.isFullscreen }
                        .compactMap { matches[$0.id].map { layout.assignments[$0].space } }
                }
                // 1. A desktop holding windows of its positional Space keeps it; otherwise the Space most of its windows belong to.
                for index in desktops.indices {
                    let positional = previousNames.indices.contains(index) ? previousNames[index] : nil
                    if let positional, votes[index].contains(positional), !taken.contains(positional) {
                        names[index] = positional
                    } else if let winner = Self.plurality(votes[index].filter { !taken.contains($0) && layout.spaces.contains($0) }) {
                        names[index] = winner
                    }
                    if let name = names[index] { taken.insert(name) }
                }
                // 2. Otherwise a desktop keeps its positional Space, if no other desktop claimed it.
                for index in desktops.indices where names[index] == nil {
                    if previousNames.indices.contains(index), !taken.contains(previousNames[index]) {
                        names[index] = previousNames[index]
                        taken.insert(previousNames[index])
                    }
                }
                // 3. A desktop Space Maker hasn't seen before becomes a Space named after its main app.
                for index in desktops.indices where names[index] == nil {
                    let onDesktop = windows.filter { $0.desktopID == desktops[index].id }
                    let name = Self.uniqueName(Self.mainApp(of: onDesktop) ?? "Desktop", avoiding: taken.union(layout.spaces))
                    names[index] = name
                    taken.insert(name)
                    newSpaces.append(name)
                }

                let resolved = names.map { $0! }
                for (desktop, name) in zip(desktops, resolved) { namesByDesktop[desktop.id] = name }

                // Fullscreen windows take their place between the Spaces, keeping the name they were saved with.
                var arranged: [ArrangedFullscreenWindow] = []
                var spacesBefore = 0
                for desktop in display.desktops {
                    guard desktop.kind == .fullscreen else { spacesBefore += 1; continue }
                    for window in windows where window.isFullscreen && window.desktopID == desktop.id {
                        let old = matches[window.id].map { layout.assignments[$0] }
                        let name: String
                        if let old, old.window.isFullscreen, !taken.contains(old.space), !layout.spaces.contains(old.space) {
                            name = old.space
                        } else {
                            name = Self.uniqueName(Self.fullscreenPlaceName(of: window), avoiding: taken.union(layout.spaces))
                        }
                        taken.insert(name)
                        fullscreenPlaces[window.id] = name
                        arranged.append(ArrangedFullscreenWindow(name: name, spacesBefore: spacesBefore))
                    }
                }
                let kept = (previous?.arrangement.first { $0.display == display.id }?.fullscreenWindows ?? [])
                    .filter { keptPlaces.contains($0.name) }
                    .map { ArrangedFullscreenWindow(name: $0.name, spacesBefore: min(max($0.spacesBefore, 0), resolved.count)) }
                arranged = (arranged + kept).enumerated()
                    .sorted { ($0.element.spacesBefore, $0.offset) < ($1.element.spacesBefore, $1.offset) }
                    .map(\.element)
                arrangement.append(DisplayArrangement(display: display.id, spaces: resolved, fullscreenWindows: arranged))
            }

            // This Display Setup's Arrangement is replaced; other Display Setups are untouched.
            layout.displaySetups.removeAll { $0.displays == setupKey }
            layout.displaySetups.append(DisplaySetupLayout(displays: setupKey, arrangement: arrangement))
            layout.displaySetups.sort { $0.displays.lexicographicallyPrecedes($1.displays) }

            // A Space no Arrangement mentions any more (its desktop was deleted) is gone.
            let arranged = layout.displaySetups.flatMap { $0.arrangement.flatMap(\.spaces) }
            layout.spaces = layout.spaces.filter(arranged.contains) + arranged.filter { !layout.spaces.contains($0) }.uniqued()

            let placeOf = { (window: WindowSystemWindow) -> String? in
                window.isFullscreen ? fullscreenPlaces[window.id] : window.desktopID.flatMap { namesByDesktop[$0] }
            }
            let saving = Set(windows.filter { placeOf($0) != nil }.map(\.id))
            let namingNotes = autoNameAmbiguousChromeWindows(&windows, saving: saving)

            // Every window on a Space gets an Assignment. A live window's old Assignment is kept only if it isn't on a
            // Space now; a closed window's is kept only if it's named.
            var assignments: [Assignment] = []
            var saved = 0
            var resaved = Set<Int>()
            for window in windows {
                guard let space = placeOf(window) else { continue }
                var identity = Self.identity(of: window)
                var frames: [SavedFrame] = []
                if let old = matches[window.id] {
                    resaved.insert(old)
                    // A profile that can't be read now (the window is on a hidden desktop) is remembered from before.
                    if identity.isChrome, identity.chromeProfile == nil {
                        identity.chromeProfile = layout.assignments[old].window.chromeProfile
                    }
                    frames = layout.assignments[old].frames  // other Display Setups' positions are kept
                }
                var assignment = Assignment(window: identity, space: space, frames: frames)
                // A fullscreen window fills its display, so it has no position to save.
                if !window.isFullscreen, let frame = Self.relativeFrame(of: window, in: displays) { assignment.setFrame(frame, in: setupKey) }
                assignments.append(assignment)
                saved += 1
            }
            let places = Set(layout.spaces).union(fullscreenPlaceNames)
            for (index, assignment) in layout.assignments.enumerated() where !resaved.contains(index) {
                guard places.contains(assignment.space), live.contains(index) || assignment.window.name != nil else { continue }
                assignments.append(assignment)
            }
            layout.assignments = assignments.sorted { $0.window.sortKey.lexicographicallyPrecedes($1.window.sortKey) }

            var summary = "Saved \(saved) window\(saved == 1 ? "" : "s") on \(arranged.count) Space\(arranged.count == 1 ? "" : "s"): \(arranged.joined(separator: ", "))."
            if !newSpaces.isEmpty { summary += " New: \(newSpaces.joined(separator: ", "))." }
            summary += namingNotes.map { "\n\($0)" }.joined()
            return committing(summary)
        }
    }

    /// Saves one window's Assignment as the Space it's on now, leaving every other Assignment alone.
    func save(handle: String) -> CommandReply {
        withLayout {
            let displays = windowSystem.readDisplays()
            guard resolvedSpaces(displays) != nil else { return Self.unknownDisplaySetupReply }
            guard let window = window(withHandle: handle, in: windowSystem.readWindows().filter(\.isStandard)) else {
                return Self.unknownHandleReply(handle)
            }
            guard !window.isFullscreen else {
                return CommandReply(text: "\(handle) is fullscreen. A fullscreen window's place is part of the Arrangement, so use Save all to record it.", isError: true)
            }
            guard let space = window.desktopID.flatMap({ spaceNamesByDesktop(displays)[$0] }) else {
                return CommandReply(text: "\(handle) isn't on a Space. Save everything to make its desktop a Space.", isError: true)
            }
            assign(window, to: space, frame: Self.relativeFrame(of: window, in: knownDisplays(displays)), in: displaySetupKey(displays))
            return committing("Saved \(handle) (\(window.appName) “\(window.title)”) on \(space).")
        }
    }

    /// Replaces the window's Assignment, if it has one, with one for `space`, keeping its saved positions.
    /// `frame`, if given, becomes its position in the Display Setup `displaySetup`.
    func assign(_ window: WindowSystemWindow, to space: String, frame: RelativeFrame? = nil, in displaySetup: [String] = []) {
        var identity = Self.identity(of: window)
        var frames: [SavedFrame] = []
        let windows = windowSystem.readWindows().filter(\.isStandard)
        if let old = Self.match(windows, to: layout.assignments)[window.id] {
            // A profile that can't be read now (the window is on a hidden desktop) is remembered from before.
            if identity.isChrome, identity.chromeProfile == nil { identity.chromeProfile = layout.assignments[old].window.chromeProfile }
            frames = layout.assignments[old].frames
            layout.assignments.remove(at: old)
        }
        var assignment = Assignment(window: identity, space: space, frames: frames)
        if let frame { assignment.setFrame(frame, in: displaySetup) }
        layout.assignments.append(assignment)
        layout.assignments.sort { $0.window.sortKey.lexicographicallyPrecedes($1.window.sortKey) }
    }

    // MARK: - Restore

    /// Restores every window with an Assignment, or just the window with `handle`.
    func restore(handle: String?) -> CommandReply {
        withLayout {
            if let disabled = movesDisabledReply() { return disabled }
            let displays = windowSystem.readDisplays()
            guard let desktops = resolvedSpaces(displays) else { return Self.unknownDisplaySetupReply }
            let windows = windowSystem.readWindows().filter(\.isStandard)
            let matches = Self.match(windows, to: layout.assignments)
            let spaceOf = { (window: WindowSystemWindow) in matches[window.id].map { self.layout.assignments[$0].space } }
            let known = knownDisplays(displays)
            forgetSoftDriftIfWorldChanged(displays: displays, windows: windows)
            defer { rememberWorldForSoftDrift() }

            let places = fullscreenPlaces(displays)
            var targets = windows.filter { !isIgnored($0) }
            if let handle {
                guard let window = window(withHandle: handle, in: windows) else { return Self.unknownHandleReply(handle) }
                guard spaceOf(window) != nil else {
                    return CommandReply(text: "\(handle) has no Assignment, so Space Maker leaves it where it is. Save first, or use move_window with save.", isError: true)
                }
                targets = [window]
            }

            var moved: [String] = []
            var problems: [String] = []
            var notRetried: [String] = []
            for window in targets {
                guard let index = matches[window.id] else { continue }  // no Assignment: never moved
                let space = layout.assignments[index].space
                let label = "\(self.handle(for: window.id)) (\(window.appName) “\(window.title)”)"
                if layout.assignments[matches[window.id]!].window.isFullscreen {
                    guard let place = places[space] else {
                        problems.append("\(label): “\(space)” has no place in this Display Setup's Arrangement.")
                        continue
                    }
                    if handle == nil, failedMoves.contains(window.id), !(window.isFullscreen && place.display.desktops.contains { $0.id == window.desktopID }) {
                        notRetried.append(label)
                        continue
                    }
                    switch restoreFullscreen(window, to: place) {
                    case nil: continue
                    case true?:
                        moved.append("\(label) → fullscreen \(place.description)")
                        failedMoves.remove(window.id)
                    case false?:
                        problems.append("\(label): macOS didn't put it back in fullscreen \(place.description).")
                        failedMoves.insert(window.id)
                    }
                    continue
                }
                guard !window.isFullscreen else { continue }
                guard let target = desktops[space] else {
                    problems.append("\(label): Space “\(space)” has no desktop in this Display Setup.")
                    continue
                }
                let plan = plan(window, layout.assignments[index], on: target, displays: known)
                if !plan.isNeeded { continue }
                // Soft Drift: a move that already failed isn't retried until the world changes, unless asked for by handle.
                if handle == nil, failedMoves.contains(window.id) || failedFrames.contains(window.id) {
                    notRetried.append(label)
                    continue
                }
                switch carryOut(plan, for: window.id) {
                case .moveFailed:
                    problems.append("\(label): macOS didn't move it to \(space).")
                    continue
                case .frameFailed:
                    problems.append("\(label): macOS didn't put it back at its saved position.")
                    continue
                case .done: break
                }
                moved.append(plan.needsMove ? "\(label) → \(space)" : "\(label) → its saved position")
            }

            var lines = [moved.isEmpty ? "Everything was already on its Space." : "Moved \(moved.count) window\(moved.count == 1 ? "" : "s"):"]
            lines += moved.map { "- \($0)" }
            if !problems.isEmpty { lines += ["Couldn't restore:"] + problems.map { "- \($0)" } }
            if !notRetried.isEmpty {
                lines += ["Not retried until windows or desktops change (Soft Drift):"] + notRetried.map { "- \($0)" }
            }
            return CommandReply(text: lines.joined(separator: "\n"), isError: handle != nil && !problems.isEmpty)
        }
    }

    // MARK: - move_window

    func moveWindow(handle: String?, space: String?, save: Bool) -> CommandReply {
        withLayout {
            if let disabled = movesDisabledReply() { return disabled }
            guard let handle, let space else {
                return CommandReply(text: "move_window needs a window handle (from status) and a Space name.", isError: true)
            }
            let displays = windowSystem.readDisplays()
            guard let desktops = resolvedSpaces(displays) else { return Self.unknownDisplaySetupReply }
            let windows = windowSystem.readWindows().filter(\.isStandard)
            guard let window = window(withHandle: handle, in: windows) else {
                return Self.unknownHandleReply(handle)
            }
            guard let target = desktops[space] else {
                let known = desktops.keys.sorted().joined(separator: ", ")
                return CommandReply(text: "There's no Space “\(space)” here. Spaces: \(known.isEmpty ? "none" : known).", isError: true)
            }
            guard !window.isFullscreen else {
                return CommandReply(text: "\(handle) is fullscreen, so it has no Space to move to. Put it in place in Mission Control, then Save.", isError: true)
            }
            if window.desktopID != target, !windowSystem.moveWindow(window.id, toDesktop: target) {
                return CommandReply(text: "macOS didn't move \(handle) to \(space).", isError: true)
            }
            guard save else { return CommandReply(text: "Moved \(handle) to \(space).") }

            assign(window, to: space)
            return committing("Moved \(handle) to \(space) and saved its Assignment.")
        }
    }

    // MARK: - rename_space

    func renameSpace(_ space: String?, to newName: String?) -> CommandReply {
        withLayout {
            let newName = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let space, !newName.isEmpty else {
                return CommandReply(text: "rename_space needs the Space's current name and a new name.", isError: true)
            }
            guard layout.spaces.contains(space) else {
                return CommandReply(text: "There's no Space “\(space)”. Spaces: \(layout.spaces.joined(separator: ", ")).", isError: true)
            }
            if newName == space { return CommandReply(text: "“\(space)” already has that name.") }
            guard !layout.spaces.contains(newName) else {
                return CommandReply(text: "There's already a Space “\(newName)”.", isError: true)
            }
            guard !fullscreenPlaceNames.contains(newName) else {
                return CommandReply(text: "“\(newName)” is already a fullscreen window's place in an Arrangement. Pick another name.", isError: true)
            }
            let rename = { (name: String) in name == space ? newName : name }
            layout.spaces = layout.spaces.map(rename)
            for setup in layout.displaySetups.indices {
                for display in layout.displaySetups[setup].arrangement.indices {
                    layout.displaySetups[setup].arrangement[display].spaces =
                        layout.displaySetups[setup].arrangement[display].spaces.map(rename)
                }
            }
            for index in layout.assignments.indices {
                layout.assignments[index].space = rename(layout.assignments[index].space)
            }
            return committing("Renamed “\(space)” to “\(newName)”.")
        }
    }

    // MARK: - Resolution

    /// Every fullscreen window's place named in any Display Setup's Arrangement.
    var fullscreenPlaceNames: Set<String> {
        Set(layout.displaySetups.flatMap { $0.arrangement.flatMap(\.fullscreenWindows).map(\.name) })
    }

    /// Each Space's native desktop in the current Display Setup (ADR 0003), or nil if nothing is saved for it.
    func resolvedSpaces(_ displays: [WindowSystemDisplay]) -> [String: UInt64]? {
        let known = knownDisplays(displays)
        guard let setup = layout.displaySetups.first(where: { $0.displays == known.map(\.id).sorted() }) else { return nil }
        var result: [String: UInt64] = [:]
        for display in setup.arrangement {
            let desktops = known.first { $0.id == display.display }?.desktops.filter { $0.kind == .regular } ?? []
            for (name, desktop) in zip(display.spaces, desktops) { result[name] = desktop.id }
        }
        return result
    }

    /// Which Space each native desktop holds, for `status`.
    func spaceNamesByDesktop(_ displays: [WindowSystemDisplay]) -> [UInt64: String] {
        Dictionary((resolvedSpaces(displays) ?? [:]).map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    func window(withHandle handle: String, in windows: [WindowSystemWindow]) -> WindowSystemWindow? {
        windows.first { handles[$0.id] == handle }
    }

    private static let unknownDisplaySetupReply = CommandReply(
        text: "Nothing is saved for this Display Setup yet, so nothing was moved. Arrange things the way you want them here, then Save.",
        isError: true
    )

    static func unknownHandleReply(_ handle: String) -> CommandReply {
        CommandReply(text: "No window has the handle “\(handle)”. Handles come from status.", isError: true)
    }

    /// What a fullscreen window's place is called when first Saved, such as "Work fullscreen".
    static func fullscreenPlaceName(of window: WindowSystemWindow) -> String {
        if case .known(let profile) = window.chromeProfile { return "\(profile) fullscreen" }
        return "\(window.appName) fullscreen"
    }

    /// The app with the most windows; the first such window's app on a tie.
    static func mainApp(of windows: [WindowSystemWindow]) -> String? {
        plurality(windows.map(\.appName))
    }

    /// The most frequent value; the earliest on a tie.
    static func plurality(_ values: [String]) -> String? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return values.max { counts[$0]! < counts[$1]! || (counts[$0]! == counts[$1]! && values.firstIndex(of: $0)! > values.firstIndex(of: $1)!) }
    }

    static func uniqueName(_ base: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
