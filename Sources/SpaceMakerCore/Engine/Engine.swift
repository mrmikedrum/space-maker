import Foundation

/// The core of Space Maker: owns the latest view of the world and answers commands.
@MainActor
public final class Engine {
    let windowSystem: WindowSystem
    private let runDoctor: (@MainActor () -> String)?

    /// Handles issued to live windows, by window ID.
    var handles: [UInt32: String] = [:]
    private var lastHandle = 0

    let layoutURL: URL
    /// The Layout as last read from or written to `layoutURL`.
    var layout = Layout()
    /// The file's bytes when `layout` was last read or written, to notice hand edits.
    var layoutData: Data?
    /// Why the Layout file can't be used right now, if it can't.
    var layoutProblem: LayoutFileError?

    /// Why moving windows is disabled, if the Doctor says it doesn't work.
    var movesDisabledReason: String?

    /// `layoutURL` is where the Layout file lives (`LayoutFile.defaultURL` in the app).
    /// `runDoctor` runs the Doctor and returns its markdown report.
    public init(
        windowSystem: WindowSystem, layoutURL: URL,
        runDoctor: (@MainActor () -> String)? = nil
    ) {
        self.windowSystem = windowSystem
        self.layoutURL = layoutURL
        self.runDoctor = runDoctor
        reloadLayoutIfChanged()
    }

    /// The command interface the socket relay and the menu bar share.
    public func perform(_ request: CommandRequest) -> CommandReply {
        switch request.command {
        case "status":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return CommandReply(text: String(decoding: try! encoder.encode(status()), as: UTF8.self))
        case "save":
            return save()
        case "restore":
            return restore(handle: request.arguments["window"])
        case "move_window":
            return moveWindow(handle: request.arguments["window"], space: request.arguments["space"],
                              save: request.arguments["save"] == "true")
        case "rename_space":
            return renameSpace(request.arguments["space"], to: request.arguments["name"])
        case "name_window":
            return nameWindow(handle: request.arguments["window"], name: request.arguments["name"])
        case "doctor":
            guard let runDoctor else { return CommandReply(text: "The Doctor isn't available here.", isError: true) }
            return CommandReply(text: runDoctor())
        default:
            return CommandReply(text: "Unknown command \"\(request.command)\".", isError: true)
        }
    }

    public func status() -> Status {
        reloadLayoutIfChanged()
        let displays = windowSystem.readDisplays()
        let spaces = spaceNamesByDesktop(displays)
        var desktops: [UInt64: DesktopReference] = [:]
        for display in displays {
            for (index, desktop) in display.desktops.enumerated() {
                desktops[desktop.id] = DesktopReference(display: display.id, number: index + 1)
            }
        }

        let windows = windowSystem.readWindows().filter(\.isStandard)
        handles = handles.filter { id, _ in windows.contains { $0.id == id } }
        let matches = layoutProblem == nil ? Self.match(windows, to: layout.assignments) : [:]
        return Status(
            displaySetup: Self.knownDisplays(displays).map { Self.displayStatus($0, spaces: spaces) },
            guestDisplays: Self.guestDisplays(displays).map { Self.displayStatus($0, spaces: [:]) },
            windows: windows.map { window in
                WindowStatus(
                    handle: handle(for: window.id),
                    app: window.appName,
                    bundleID: window.bundleID,
                    chromeProfile: Self.profileText(window.chromeProfile),
                    isFullscreen: window.isFullscreen,
                    title: window.title,
                    name: window.name,
                    desktop: window.desktopID.flatMap { desktops[$0] },
                    assignment: matches[window.id].map { layout.assignments[$0].space }
                )
            }
        )
    }

    func handle(for windowID: UInt32) -> String {
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

    private static func displayStatus(_ display: WindowSystemDisplay, spaces: [UInt64: String]) -> DisplayStatus {
        DisplayStatus(
            id: display.id,
            name: display.name,
            desktops: display.desktops.enumerated().map { index, desktop in
                DesktopStatus(number: index + 1, kind: desktop.kind, isCurrent: desktop.isCurrent, space: spaces[desktop.id])
            }
        )
    }

    /// Until Display Setups can be remembered, only the built-in display is known.
    static func knownDisplays(_ displays: [WindowSystemDisplay]) -> [WindowSystemDisplay] {
        displays.filter(\.isBuiltIn)
    }

    static func guestDisplays(_ displays: [WindowSystemDisplay]) -> [WindowSystemDisplay] {
        displays.filter { !$0.isBuiltIn }
    }
}
