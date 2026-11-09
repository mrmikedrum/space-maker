/// Which live window each Assignment describes (spec, Window identity).
extension Engine {
    static func identity(of window: WindowSystemWindow) -> WindowIdentity {
        switch window.chromeProfile {
        case .notChrome:
            WindowIdentity(bundleID: window.bundleID, isFullscreen: window.isFullscreen, title: window.title)
        case .known(let profile):
            WindowIdentity(bundleID: window.bundleID, chromeProfile: profile, isFullscreen: window.isFullscreen, name: window.name)
        case .unknown:
            WindowIdentity(bundleID: window.bundleID, isFullscreen: window.isFullscreen, name: window.name)
        }
    }

    /// Pairs live windows with Assignments, as the index into `assignments` for each matched window ID.
    ///
    /// 1. A name (Chrome) or title (other apps) that matches exactly wins.
    /// 2. An unnamed Chrome Assignment takes a window with the same profile and fullscreen flag, the oldest first.
    ///    When either side's profile is unknown, only a name can match.
    /// 3. Another app's Assignment takes the one remaining window of its app and fullscreen flag, whatever its title.
    ///    Extra windows of a kind match nothing.
    static func match(_ windows: [WindowSystemWindow], to assignments: [Assignment]) -> [UInt32: Int] {
        var windowFor: [Int: UInt32] = [:]
        var matched: [UInt32: Int] = [:]
        let windows = windows.sorted { $0.id < $1.id }

        func pair(_ index: Int, _ window: WindowSystemWindow) {
            windowFor[index] = window.id
            matched[window.id] = index
        }
        func unmatched(_ identity: WindowIdentity) -> [WindowSystemWindow] {
            windows.filter {
                matched[$0.id] == nil && $0.bundleID == identity.bundleID && $0.isFullscreen == identity.isFullscreen
            }
        }

        // 1. Names and titles.
        for (index, assignment) in assignments.enumerated() {
            let identity = assignment.window
            let found = unmatched(identity).first { window in
                if identity.isChrome {
                    guard let name = identity.name, window.name == name else { return false }
                    if case .known(let profile) = window.chromeProfile, let saved = identity.chromeProfile { return profile == saved }
                    return true
                }
                return identity.title == window.title
            }
            if let found { pair(index, found) }
        }

        // 2. Unnamed Chrome Assignments, by profile.
        for (index, assignment) in assignments.enumerated() where windowFor[index] == nil {
            let identity = assignment.window
            guard identity.isChrome, identity.name == nil, let saved = identity.chromeProfile else { continue }
            let candidates = unmatched(identity)
                .filter { $0.chromeProfile == .known(saved) }
                .sorted { ($0.name == nil ? 0 : 1, $0.id) < ($1.name == nil ? 0 : 1, $1.id) }
            if let found = candidates.first { pair(index, found) }
        }

        // 3. Other apps, when only one window and one Assignment of the kind are left.
        for (index, assignment) in assignments.enumerated() where windowFor[index] == nil {
            let identity = assignment.window
            guard !identity.isChrome else { continue }
            let rivals = assignments.indices.filter { other in
                windowFor[other] == nil && assignments[other].window.bundleID == identity.bundleID
                    && assignments[other].window.isFullscreen == identity.isFullscreen
            }
            let candidates = unmatched(identity)
            if rivals.count == 1, candidates.count == 1 { pair(index, candidates[0]) }
        }
        return matched
    }

    /// Names the Chrome windows Save is about to assign that their profile and fullscreen flag can't tell apart,
    /// including any whose profile is unknown, so that they keep their identity across a relaunch. Updates `windows` and returns what happened, for Save's reply.
    func autoNameAmbiguousChromeWindows(_ windows: inout [WindowSystemWindow], saving: Set<UInt32>) -> [String] {
        struct Kind: Hashable {
            var profile: String?
            var isFullscreen: Bool
        }
        var kinds: [Kind: [Int]] = [:]
        for (index, window) in windows.enumerated() where saving.contains(window.id) && window.name == nil {
            switch window.chromeProfile {
            case .notChrome: continue
            case .known(let profile): kinds[Kind(profile: profile, isFullscreen: window.isFullscreen), default: []].append(index)
            case .unknown: kinds[Kind(profile: nil, isFullscreen: window.isFullscreen), default: []].append(index)
            }
        }
        var taken = Set(windows.compactMap(\.name) + layout.assignments.compactMap(\.window.name))
        var named: [String] = []
        var problems: [String] = []
        // A window whose profile can't be read (it's on a hidden desktop) can only be told apart by a name.
        let ambiguous = kinds.filter { $0.key.profile == nil || $0.value.count > 1 }.sorted { ($0.key.profile ?? "", $0.key.isFullscreen ? 1 : 0) < ($1.key.profile ?? "", $1.key.isFullscreen ? 1 : 0) }
        naming: for (kind, indices) in ambiguous {
            for index in indices.sorted(by: { windows[$0].id < windows[$1].id }) {
                let base = kind.profile ?? "Chrome"
                let name = (1...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
                switch windowSystem.setChromeWindowName(windows[index].id, to: name) {
                case .named:
                    taken.insert(name)
                    named.append("\(handle(for: windows[index].id)) “\(name)”")
                    windows[index].name = name
                    windows[index].title = name
                case .denied(let reason):
                    problems.append("Couldn't name Chrome windows that look alike, so they may be mixed up after Chrome relaunches: \(reason)")
                    break naming
                case .failed(let reason):
                    problems.append("Couldn't name \(handle(for: windows[index].id)): \(reason)")
                }
            }
        }
        var lines: [String] = []
        if !named.isEmpty { lines.append("Named \(named.count) Chrome window\(named.count == 1 ? "" : "s") that looked alike: \(named.joined(separator: ", ")).") }
        return lines + problems
    }

    // MARK: - name_window

    /// Names a Chrome window. If it has an Assignment, the Assignment takes the name and outlives the window.
    func nameWindow(handle: String?, name: String?) -> CommandReply {
        withLayout {
            let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let handle, !name.isEmpty else {
                return CommandReply(text: "name_window needs a window handle (from status) and a name.", isError: true)
            }
            let windows = windowSystem.readWindows().filter(\.isStandard)
            guard let window = window(withHandle: handle, in: windows) else { return Self.unknownHandleReply(handle) }
            guard window.chromeProfile != .notChrome else {
                return CommandReply(text: "Only Chrome windows can be named; \(window.appName) windows are recognised by their title.", isError: true)
            }
            if let other = windows.first(where: { $0.id != window.id && $0.chromeProfile != .notChrome && $0.name == name }) {
                return CommandReply(text: "\(self.handle(for: other.id)) is already named “\(name)”.", isError: true)
            }
            let old = Self.match(windows, to: layout.assignments)[window.id]
            switch windowSystem.setChromeWindowName(window.id, to: name) {
            case .named: break
            case .denied(let reason), .failed(let reason):
                return CommandReply(text: "Couldn't name \(handle): \(reason)", isError: true)
            }
            guard let old else { return CommandReply(text: "Named \(handle) “\(name)”. Save to give it an Assignment.") }
            layout.assignments[old].window.name = name
            if case .known(let profile) = window.chromeProfile { layout.assignments[old].window.chromeProfile = profile }
            layout.assignments.sort { $0.window.sortKey.lexicographicallyPrecedes($1.window.sortKey) }
            return committing("Named \(handle) “\(name)”.")
        }
    }
}
