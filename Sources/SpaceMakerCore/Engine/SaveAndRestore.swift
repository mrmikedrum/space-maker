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
        let data = LayoutFile.readData(at: layoutURL)
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
            let displays = Self.knownDisplays(windowSystem.readDisplays())
            var windows = windowSystem.readWindows().filter(\.isStandard)
            let setupKey = displays.map(\.id).sorted()
            let previous = layout.displaySetups.first { $0.displays == setupKey }

            let matches = Self.match(windows, to: layout.assignments)
            var taken = Set<String>()
            var arrangement: [DisplayArrangement] = []
            var newSpaces: [String] = []
            var namesByDesktop: [UInt64: String] = [:]

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
                arrangement.append(DisplayArrangement(display: display.id, spaces: resolved))
                for (desktop, name) in zip(desktops, resolved) { namesByDesktop[desktop.id] = name }
            }

            // This Display Setup's Arrangement is replaced; other Display Setups are untouched.
            layout.displaySetups.removeAll { $0.displays == setupKey }
            layout.displaySetups.append(DisplaySetupLayout(displays: setupKey, arrangement: arrangement))
            layout.displaySetups.sort { $0.displays.lexicographicallyPrecedes($1.displays) }

            // A Space no Arrangement mentions any more (its desktop was deleted) is gone.
            let arranged = layout.displaySetups.flatMap { $0.arrangement.flatMap(\.spaces) }
            layout.spaces = layout.spaces.filter(arranged.contains) + arranged.filter { !layout.spaces.contains($0) }.uniqued()

            let saving = Set(windows.filter { !$0.isFullscreen && $0.desktopID.flatMap { namesByDesktop[$0] } != nil }.map(\.id))
            let namingNotes = autoNameAmbiguousChromeWindows(&windows, saving: saving)

            // Every window on a Space gets an Assignment. A live window's old Assignment is kept only if it isn't on a
            // Space now; a closed window's is kept only if it's named.
            var assignments: [Assignment] = []
            var saved = 0
            var resaved = Set<Int>()
            for window in windows where !window.isFullscreen {
                guard let space = window.desktopID.flatMap({ namesByDesktop[$0] }) else { continue }
                var identity = Self.identity(of: window)
                if let old = matches[window.id] {
                    resaved.insert(old)
                    // A profile that can't be read now (the window is on a hidden desktop) is remembered from before.
                    if identity.isChrome, identity.chromeProfile == nil {
                        identity.chromeProfile = layout.assignments[old].window.chromeProfile
                    }
                }
                assignments.append(Assignment(window: identity, space: space))
                saved += 1
            }
            let live = Set(matches.values)
            for (index, assignment) in layout.assignments.enumerated() where !resaved.contains(index) {
                guard layout.spaces.contains(assignment.space), live.contains(index) || assignment.window.name != nil else { continue }
                assignments.append(assignment)
            }
            layout.assignments = assignments.sorted { $0.window.sortKey.lexicographicallyPrecedes($1.window.sortKey) }

            var summary = "Saved \(saved) window\(saved == 1 ? "" : "s") on \(arranged.count) Space\(arranged.count == 1 ? "" : "s"): \(arranged.joined(separator: ", "))."
            if !newSpaces.isEmpty { summary += " New: \(newSpaces.joined(separator: ", "))." }
            summary += namingNotes.map { "\n\($0)" }.joined()
            return committing(summary)
        }
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

            var targets = windows.filter { !$0.isFullscreen }
            if let handle {
                guard let window = window(withHandle: handle, in: windows) else { return Self.unknownHandleReply(handle) }
                guard spaceOf(window) != nil else {
                    return CommandReply(text: "\(handle) has no Assignment, so Space Maker leaves it where it is. Save first, or use move_window with save.", isError: true)
                }
                targets = [window]
            }

            var moved: [String] = []
            var problems: [String] = []
            for window in targets {
                guard let space = spaceOf(window) else { continue }  // no Assignment: never moved
                let label = "\(self.handle(for: window.id)) (\(window.appName) “\(window.title)”)"
                guard let target = desktops[space] else {
                    problems.append("\(label): Space “\(space)” has no desktop in this Display Setup.")
                    continue
                }
                if window.desktopID == target { continue }
                if windowSystem.moveWindow(window.id, toDesktop: target) {
                    moved.append("\(label) → \(space)")
                } else {
                    problems.append("\(label): macOS didn't move it to \(space).")
                }
            }

            var lines = [moved.isEmpty ? "Everything was already on its Space." : "Moved \(moved.count) window\(moved.count == 1 ? "" : "s"):"]
            lines += moved.map { "- \($0)" }
            if !problems.isEmpty { lines += ["Couldn't restore:"] + problems.map { "- \($0)" } }
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
                return CommandReply(text: "\(handle) is fullscreen; Space Maker doesn't move fullscreen windows yet.", isError: true)
            }
            if window.desktopID != target, !windowSystem.moveWindow(window.id, toDesktop: target) {
                return CommandReply(text: "macOS didn't move \(handle) to \(space).", isError: true)
            }
            guard save else { return CommandReply(text: "Moved \(handle) to \(space).") }

            var identity = Self.identity(of: window)
            if let old = Self.match(windows, to: layout.assignments)[window.id] {
                if identity.isChrome, identity.chromeProfile == nil { identity.chromeProfile = layout.assignments[old].window.chromeProfile }
                layout.assignments.remove(at: old)
            }
            layout.assignments.append(Assignment(window: identity, space: space))
            layout.assignments.sort { $0.window.sortKey.lexicographicallyPrecedes($1.window.sortKey) }
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

    /// Each Space's native desktop in the current Display Setup (ADR 0003), or nil if nothing is saved for it.
    func resolvedSpaces(_ displays: [WindowSystemDisplay]) -> [String: UInt64]? {
        let known = Self.knownDisplays(displays)
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
        text: "Nothing is saved for this Display Setup yet. Save first.", isError: true
    )

    static func unknownHandleReply(_ handle: String) -> CommandReply {
        CommandReply(text: "No window has the handle “\(handle)”. Handles come from status.", isError: true)
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
