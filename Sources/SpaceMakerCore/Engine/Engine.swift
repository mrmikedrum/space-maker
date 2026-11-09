import Foundation

/// The core of Space Maker: owns the latest view of the world and answers commands.
@MainActor
public final class Engine {
    private let windowSystem: WindowSystem
    private let runDoctor: (@MainActor () -> String)?

    /// Handles issued to live windows, by window ID.
    private var handles: [UInt32: String] = [:]
    private var lastHandle = 0

    /// `runDoctor` runs the Doctor and returns its markdown report.
    public init(windowSystem: WindowSystem, runDoctor: (@MainActor () -> String)? = nil) {
        self.windowSystem = windowSystem
        self.runDoctor = runDoctor
    }

    /// The command interface the socket relay and the menu bar share.
    public func perform(_ request: CommandRequest) -> CommandReply {
        switch request.command {
        case "status":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return CommandReply(text: String(decoding: try! encoder.encode(status()), as: UTF8.self))
        case "doctor":
            guard let runDoctor else { return CommandReply(text: "The Doctor isn't available here.", isError: true) }
            return CommandReply(text: runDoctor())
        default:
            return CommandReply(text: "Unknown command \"\(request.command)\".", isError: true)
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
            }
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
