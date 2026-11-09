import Foundation
import SpaceMakerCore

/// A scriptable stand-in for macOS. Tests set `displays` and `windows` to describe the world.
@MainActor
final class FakeWindowSystem: WindowSystem {
    var displays: [WindowSystemDisplay] = []
    var windows: [WindowSystemWindow] = []

    /// Pin mirrors that exist, by source window ID.
    var mirrors: [UInt32: MirrorState] = [:]

    enum MirrorState: Equatable { case shown, hidden }

    /// Reads still to come while macOS is rearranging desktops after a reconfiguration. Each one sees
    /// a different half-finished set of desktops, and macOS refuses moves meanwhile.
    var unsettledReads = 0

    func readDisplays() -> [WindowSystemDisplay] {
        guard unsettledReads > 0, !displays.isEmpty else { return displays }
        unsettledReads -= 1
        var halfway = displays
        halfway[0].desktops.append(.regular(9000 + UInt64(unsettledReads)))
        return halfway
    }
    func readWindows() -> [WindowSystemWindow] { windows }
    func readFrontmostWindow() -> UInt32? { frontmostWindow }

    private(set) var focusedWindow: UInt32?
    /// The window the user is working in. Focusing a window makes it frontmost.
    var frontmostWindow: UInt32?

    var currentDesktops: [UInt64] { displays.flatMap { $0.desktops.filter(\.isCurrent).map(\.id) } }

    /// The user clicks a Pin's mirror.
    func clickMirror(of windowID: UInt32) {
        guard mirrors[windowID] == .shown else { return }
        onEvent?(.pinClicked(windowID))
    }

    func closeWindow(_ windowID: UInt32) {
        windows.removeAll { $0.id == windowID }
        onEvent?(.windowClosed(windowID))
    }

    /// Like macOS, focusing a window on another desktop switches to that desktop.
    func focusWindow(_ windowID: UInt32) {
        focusedWindow = windowID
        frontmostWindow = windowID
        if let desktop = windows.first(where: { $0.id == windowID })?.desktopID, !currentDesktops.contains(desktop) {
            switchTo(desktop: desktop)
        }
    }

    var onEvent: (@MainActor (WindowSystemEvent) -> Void)?

    /// Time in the fake world. It only moves when a test advances it; tests never sleep.
    let clock = FakeClock()

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        clock.schedule(after: delay, action)
    }

    /// macOS reports that displays were reconfigured (connected, disconnected or rearranged).
    func reconfigureDisplays() {
        onEvent?(.displaysReconfigured)
    }

    /// The user switches desktops, as with Ctrl-arrow: the display showing `desktop` now shows it.
    func switchTo(desktop: UInt64) {
        for index in displays.indices where displays[index].desktops.contains(where: { $0.id == desktop }) {
            for slot in displays[index].desktops.indices {
                displays[index].desktops[slot].isCurrent = displays[index].desktops[slot].id == desktop
            }
        }
        onEvent?(.activeSpaceChanged)
    }

    func showPinMirror(of windowID: UInt32) { mirrors[windowID] = .shown }
    func hidePinMirror(of windowID: UInt32) { mirrors[windowID] = .hidden }
    func stopPinMirror(of windowID: UInt32) { mirrors[windowID] = nil }

    /// Windows macOS refuses to move, as when the bridged move stops working.
    var unmovableWindows: Set<UInt32> = []

    func moveWindow(_ windowID: UInt32, toDesktop desktopID: UInt64) -> Bool {
        guard unsettledReads == 0, !unmovableWindows.contains(windowID),
              displays.contains(where: { $0.desktops.contains { $0.id == desktopID } })
        else { return false }
        move(windowID, to: desktopID)
        return true
    }

    /// The user (or macOS) moves a window by hand.
    func move(_ windowID: UInt32, to desktopID: UInt64) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        windows[index].desktopID = desktopID
    }

    /// macOS undocking: the display's first desktop collapses into the built-in display's first,
    /// taking its windows with it, and its other desktops are appended to the built-in display.
    func undock(_ displayID: String) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }),
              let builtIn = displays.firstIndex(where: \.isBuiltIn),
              let laptopFirst = displays[builtIn].desktops.first?.id
        else { return }
        let gone = displays.remove(at: index)
        let builtInIndex = displays.firstIndex(where: \.isBuiltIn)!
        if let first = gone.desktops.first {
            for window in windows.indices where windows[window].desktopID == first.id { windows[window].desktopID = laptopFirst }
        }
        displays[builtInIndex].desktops += gone.desktops.dropFirst().map { WindowSystemDesktop(id: $0.id, kind: $0.kind, isCurrent: false) }
    }

    /// macOS redocking, as unreliably as it does it: `display` comes back with its desktops in the order given.
    /// Desktops it lists that are on the built-in display move back, windows and all; the others are new and empty.
    func redock(_ display: WindowSystemDisplay) {
        let returning = Set(display.desktops.map(\.id))
        for index in displays.indices where displays[index].isBuiltIn {
            displays[index].desktops.removeAll { returning.contains($0.id) }
        }
        displays.append(display)
    }

    /// A Guest Display disconnects. Its windows land on the built-in display's current desktop.
    func disconnect(_ displayID: String) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else { return }
        let gone = Set(displays.remove(at: index).desktops.map(\.id))
        let landing = displays.first(where: \.isBuiltIn)?.desktops.first(where: \.isCurrent)?.id
        for window in windows.indices where windows[window].desktopID.map(gone.contains) == true {
            windows[window].desktopID = landing
        }
    }

    /// Windows macOS won't resize or reposition.
    var unresizableWindows: Set<UInt32> = []

    /// The user drags or resizes a window by hand.
    func place(_ windowID: UInt32, at frame: WindowFrame) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        windows[index].frame = frame
    }

    func setFrame(_ windowID: UInt32, to frame: WindowFrame) -> Bool {
        guard !unresizableWindows.contains(windowID), let index = windows.firstIndex(where: { $0.id == windowID }) else { return false }
        windows[index].frame = frame
        return true
    }

    func desktop(of windowID: UInt32) -> UInt64? {
        windows.first { $0.id == windowID }?.desktopID
    }

    func window(_ windowID: UInt32) -> WindowSystemWindow? {
        windows.first { $0.id == windowID }
    }

    /// Whether the user denied Space Maker Automation permission for Chrome.
    var chromeAutomationDenied = false

    /// Like Chrome, a named window's title becomes its name.
    func setChromeWindowName(_ windowID: UInt32, to name: String) -> WindowNamingResult {
        if chromeAutomationDenied { return .denied("Automation for Google Chrome isn't allowed.") }
        guard let index = windows.firstIndex(where: { $0.id == windowID && $0.chromeProfile != .notChrome }) else {
            return .failed("No such Chrome window.")
        }
        windows[index].name = name
        windows[index].title = name
        return .named
    }

    /// Quits and relaunches Chrome as macOS 15 does: session restore brings every window back one at a time,
    /// names included, with fresh window IDs (`id + offset`) and every normal window on the current desktop.
    /// Each window announces itself as it appears.
    func relaunchChrome(idOffset: UInt32 = 1000) {
        let current = displays.flatMap(\.desktops).first(where: \.isCurrent)?.id
        let chrome = windows.filter { $0.chromeProfile != .notChrome }
        windows.removeAll { $0.chromeProfile != .notChrome }
        for var window in chrome {
            window.id += idOffset
            if !window.isFullscreen { window.desktopID = current }
            openWindow(window)
        }
    }

    /// A window appears, as when the user opens one or an app launches.
    func openWindow(_ window: WindowSystemWindow) {
        windows.append(window)
        onEvent?(.windowAppeared(window.id))
    }

    /// macOS reports a window it already reported as appearing again, as when its app is unhidden.
    func announceAgain(_ windowID: UInt32) {
        onEvent?(.windowAppeared(windowID))
    }
}

extension WindowSystemDisplay {
    /// A 1512×982 laptop screen with a 25-point menu bar and the Dock hidden.
    static func builtIn(desktops: [WindowSystemDesktop], visibleFrame: WindowFrame = WindowFrame(x: 0, y: 25, width: 1512, height: 957)) -> Self {
        Self(id: "built-in", name: "Built-in Retina Display", isBuiltIn: true, desktops: desktops, visibleFrame: visibleFrame)
    }

    /// By default a 2560×1440 monitor to the right of the laptop.
    static func external(
        _ id: String, hardwareID: String? = nil, name: String, desktops: [WindowSystemDesktop],
        visibleFrame: WindowFrame = WindowFrame(x: 1512, y: 25, width: 2560, height: 1415)
    ) -> Self {
        Self(id: id, hardwareID: hardwareID, name: name, isBuiltIn: false, desktops: desktops, visibleFrame: visibleFrame)
    }
}

extension WindowSystemDesktop {
    static func regular(_ id: UInt64, current: Bool = false) -> Self {
        Self(id: id, kind: .regular, isCurrent: current)
    }
}

extension WindowSystemWindow {
    static func app(
        _ id: UInt32,
        _ bundleID: String,
        _ appName: String,
        title: String,
        desktop: UInt64?,
        fullscreen: Bool = false,
        chromeProfile: ChromeProfile = .notChrome,
        isStandard: Bool = true,
        name: String? = nil,
        frame: WindowFrame? = nil
    ) -> Self {
        Self(
            id: id, bundleID: bundleID, appName: appName, title: name ?? title, desktopID: desktop,
            isFullscreen: fullscreen, chromeProfile: chromeProfile, isStandard: isStandard, name: name, frame: frame
        )
    }

    static func chrome(
        _ id: UInt32, profile: ChromeProfile, title: String, desktop: UInt64?, fullscreen: Bool = false, name: String? = nil
    ) -> Self {
        app(id, "com.google.Chrome", "Google Chrome", title: title, desktop: desktop, fullscreen: fullscreen, chromeProfile: profile, name: name)
    }
}

extension URL {
    /// A Layout file location of its own, so tests never touch the user's real Layout.
    static func temporaryLayout() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("space-maker-tests-\(UUID().uuidString)/layout.json")
    }
}

/// A clock that runs scheduled work only when a test advances it.
@MainActor
final class FakeClock {
    private(set) var now: TimeInterval = 0
    private var pending: [(at: TimeInterval, order: Int, action: @MainActor () -> Void)] = []
    private var lastOrder = 0

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        lastOrder += 1
        pending.append((now + max(0, delay), lastOrder, action))
    }

    /// Moves time forward, running everything that falls due, in order, including work scheduled meanwhile.
    func advance(by interval: TimeInterval) {
        let end = now + interval
        while let next = pending.filter({ $0.at <= end }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
            pending.removeAll { $0.order == next.order }
            now = next.at
            next.action()
        }
        now = end
    }
}
