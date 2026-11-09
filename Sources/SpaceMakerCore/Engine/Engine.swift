import Foundation

/// The core of Space Maker: owns the latest view of the world and answers commands.
@MainActor
public final class Engine {
    private let windowSystem: WindowSystem
    private let runDoctor: (@MainActor () -> String)?

    /// Handles issued to live windows, by window ID.
    private var handles: [UInt32: String] = [:]
    private var lastHandle = 0

    /// Pinned windows, by window ID, in the order they were pinned. Never persisted.
    private var pins: [UInt32] = []
    /// Why Pins can't work, when the Doctor's screen capture check failed.
    private var pinsDisabledReason: String?

    /// `runDoctor` runs the Doctor and returns its markdown report.
    public init(windowSystem: WindowSystem, runDoctor: (@MainActor () -> String)? = nil) {
        self.windowSystem = windowSystem
        self.runDoctor = runDoctor
        windowSystem.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Reacts to an event from the `WindowSystem` port.
    private func handle(_ event: WindowSystemEvent) {
        switch event {
        case .activeSpaceChanged:
            refreshPins()
        case .pinClicked(let windowID):
            guard pins.contains(windowID) else { return }
            windowSystem.focusWindow(windowID)
        case .windowClosed(let windowID):
            unpin(windowID)
        }
    }

    /// The command interface the socket relay and the menu bar share.
    public func perform(_ request: CommandRequest) -> CommandReply {
        switch request.command {
        case "status":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return CommandReply(text: String(decoding: try! encoder.encode(status()), as: UTF8.self))
        case "pin":
            return pin(request.window)
        case "unpin":
            return unpinCommand(request.window)
        case "doctor":
            guard let runDoctor else { return CommandReply(text: "The Doctor isn't available here.", isError: true) }
            return CommandReply(text: runDoctor())
        default:
            return CommandReply(text: "Unknown command \"\(request.command)\".", isError: true)
        }
    }

    // MARK: - Pins

    /// The Doctor's screen capture check failed: removes every Pin and refuses new ones.
    public func disablePins(because reason: String) {
        pinsDisabledReason = reason
        for windowID in pins { unpin(windowID) }
    }

    public func enablePins() {
        pinsDisabledReason = nil
    }

    /// The menu bar's Pin/Unpin: pins the frontmost window, or unpins it if it's already pinned.
    public func togglePinOfFrontmostWindow() -> CommandReply {
        guard let windowID = windowSystem.readFrontmostWindow() else {
            return CommandReply(text: "No window is frontmost.", isError: true)
        }
        let handle = handle(for: windowID)
        return pins.contains(windowID) ? unpinCommand(handle) : pin(handle)
    }

    private func pin(_ handle: String?) -> CommandReply {
        if let pinsDisabledReason {
            return CommandReply(text: "Pins are disabled because the Doctor's screen capture check failed: \(pinsDisabledReason)", isError: true)
        }
        let window: WindowSystemWindow
        switch liveWindow(handle) {
        case .success(let found): window = found
        case .failure(let problem): return problem.reply
        }
        let name = "\(window.appName) \"\(window.title)\""
        guard !window.isFullscreen else {
            return CommandReply(text: "\(name) is fullscreen, and a fullscreen window can't be pinned. Take it out of fullscreen first.", isError: true)
        }
        if !pins.contains(window.id) { pins.append(window.id) }
        refreshPins()
        return CommandReply(text: "Pinned \(name) (\(self.handle(for: window.id))).")
    }

    private func unpinCommand(_ handle: String?) -> CommandReply {
        let window: WindowSystemWindow
        switch liveWindow(handle) {
        case .success(let found): window = found
        case .failure(let problem): return problem.reply
        }
        let name = "\(window.appName) \"\(window.title)\""
        guard pins.contains(window.id) else { return CommandReply(text: "\(name) isn't pinned.", isError: true) }
        unpin(window.id)
        return CommandReply(text: "Unpinned \(name).")
    }

    private struct CommandProblem: Error {
        let reply: CommandReply
    }

    /// The live window a handle from `status` names.
    private func liveWindow(_ handle: String?) -> Result<WindowSystemWindow, CommandProblem> {
        guard let handle, !handle.isEmpty else {
            return .failure(CommandProblem(reply: CommandReply(text: "Name a window by its handle from status, such as \"w1\".", isError: true)))
        }
        let windows = windowSystem.readWindows().filter(\.isStandard)
        guard let windowID = handles.first(where: { $0.value == handle })?.key,
              let window = windows.first(where: { $0.id == windowID })
        else {
            return .failure(CommandProblem(reply: CommandReply(text: "No open window has handle \"\(handle)\". Run status for current handles.", isError: true)))
        }
        return .success(window)
    }

    private func unpin(_ windowID: UInt32) {
        guard pins.contains(windowID) else { return }
        pins.removeAll { $0 == windowID }
        windowSystem.stopPinMirror(of: windowID)
    }

    /// Hides each mirror while its window is visible on the active Space, and shows it otherwise.
    private func refreshPins() {
        let current = Set(windowSystem.readDisplays().flatMap { $0.desktops.filter(\.isCurrent).map(\.id) })
        let windows = windowSystem.readWindows()
        for windowID in pins {
            // A window that vanished without a close event still loses its Pin.
            guard let window = windows.first(where: { $0.id == windowID }) else {
                unpin(windowID)
                continue
            }
            if let desktop = window.desktopID, current.contains(desktop) {
                windowSystem.hidePinMirror(of: windowID)
            } else {
                windowSystem.showPinMirror(of: windowID)
            }
        }
    }

    public func status() -> Status {
        let displays = windowSystem.readDisplays()
        var desktops: [UInt64: DesktopReference] = [:]
        for display in displays {
            for (index, desktop) in display.desktops.enumerated() {
                desktops[desktop.id] = DesktopReference(display: display.id, number: index + 1)
            }
        }

        let windows = windowSystem.readWindows().filter(\.isStandard)
        handles = handles.filter { id, _ in windows.contains { $0.id == id } }
        return Status(
            displaySetup: displays.filter(\.isBuiltIn).map(Self.displayStatus),
            // Until Display Setups can be remembered, only the built-in display is known.
            guestDisplays: displays.filter { !$0.isBuiltIn }.map(Self.displayStatus),
            windows: windows.map { window in
                WindowStatus(
                    handle: handle(for: window.id),
                    app: window.appName,
                    bundleID: window.bundleID,
                    chromeProfile: Self.profileText(window.chromeProfile),
                    isFullscreen: window.isFullscreen,
                    title: window.title,
                    desktop: window.desktopID.flatMap { desktops[$0] }
                )
            },
            pins: pins.compactMap { handles[$0] }
        )
    }

    private func handle(for windowID: UInt32) -> String {
        if let handle = handles[windowID] { return handle }
        lastHandle += 1
        let handle = "w\(lastHandle)"
        handles[windowID] = handle
        return handle
    }

    private static func profileText(_ profile: ChromeProfile) -> String? {
        switch profile {
        case .notChrome: nil
        case .known(let name): name
        case .unknown: "unknown"
        }
    }

    private static func displayStatus(_ display: WindowSystemDisplay) -> DisplayStatus {
        DisplayStatus(
            id: display.id,
            name: display.name,
            desktops: display.desktops.enumerated().map { index, desktop in
                DesktopStatus(number: index + 1, kind: desktop.kind, isCurrent: desktop.isCurrent)
            }
        )
    }
}
