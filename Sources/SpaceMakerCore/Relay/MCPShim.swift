import Foundation

/// What the stateless stdio MCP server does with a tool call: relay it to the app (ADR 0002).
/// The `space-maker-mcp` executable only adapts this to the MCP SDK.
public struct MCPShim: Sendable {
    public struct Tool: Sendable {
        public let name: String
        public let description: String
        public var parameters: [Parameter] = []
    }

    /// A tool argument. Windows are named by handle and Spaces by name; nothing takes coordinates.
    public struct Parameter: Sendable {
        public enum Kind: String, Sendable {
            case string, boolean
        }

        public let name: String
        public let kind: Kind
        public let description: String
        public let isRequired: Bool
    }

    public struct Result: Equatable, Sendable {
        public let text: String
        public let isError: Bool
    }

    public static let notRunning = "Space Maker isn't running."

    public static let tools = [
        Tool(name: "status", description: "Report the displays, their desktops in Mission Control order (regular and fullscreen), and every window with its handle, app, Chrome profile, fullscreen flag, title, name, current desktop and Assignment (the Space it belongs on), which Space each desktop holds, and the handles of pinned windows, and whether automatic behaviour is paused. The Display Setup is the built-in display plus every connected remembered display; any other display is a Guest Display, which Space Maker never puts anything on. Also lists Drift (windows away from their Assignment, and new windows that match no Assignment) and Soft Drift (what Space Maker can't fix itself, with a hint). Ignored windows and apps never count as Drift."),
        Tool(name: "save", description: "Save: record which Space every window is on, and the order of Spaces on each display, into the Layout. A desktop Space Maker hasn't seen before becomes a new Space named after its main app. Give a window handle to save just that window's Assignment as the Space it's on now.", parameters: [
            Parameter(name: "window", kind: .string, description: "A window handle from status, such as \"w3\". Omit to save everything.", isRequired: false),
        ]),
        Tool(name: "restore", description: "Restore: move every window that has an Assignment back to its Space. Give a window handle to restore just that window. Windows without an Assignment are never moved.", parameters: [
            Parameter(name: "window", kind: .string, description: "A window handle from status, such as \"w3\". Omit to restore every window.", isRequired: false),
        ]),
        Tool(name: "move_window", description: "Move one window to a Space, optionally saving that as its Assignment.", parameters: [
            Parameter(name: "window", kind: .string, description: "A window handle from status, such as \"w3\".", isRequired: true),
            Parameter(name: "space", kind: .string, description: "The name of the Space to move it to, as status shows it.", isRequired: true),
            Parameter(name: "save", kind: .boolean, description: "Also save this as the window's Assignment, so Restore keeps it there.", isRequired: false),
        ]),
        Tool(name: "ignore", description: "Ignore a window so it never counts as Drift and Save and Restore leave it alone, until it closes. With app, always Ignore its app; that is saved in the Layout.", parameters: [
            Parameter(name: "window", kind: .string, description: "A window handle from status, such as \"w3\".", isRequired: true),
            Parameter(name: "app", kind: .boolean, description: "Always Ignore this window's app, not just this window.", isRequired: false),
        ]),
        Tool(name: "rename_space", description: "Rename a Space. Its windows stay assigned to it.", parameters: [
            Parameter(name: "space", kind: .string, description: "The Space's current name.", isRequired: true),
            Parameter(name: "name", kind: .string, description: "Its new name.", isRequired: true),
        ]),
        Tool(name: "remember_display", description: "Remember a Guest Display, so it joins the Display Setups: with it connected, Space Maker uses that Display Setup's own Arrangement. A new Display Setup has nothing saved, so Space Maker moves nothing until you arrange things there and Save.", parameters: [
            Parameter(name: "display", kind: .string, description: "The Guest Display's id from status. Omit when exactly one Guest Display is connected.", isRequired: false),
        ]),
        Tool(name: "name_window", description: "Name a Chrome window, so Space Maker can tell it apart from other windows of the same profile, even after Chrome relaunches. Chrome shows the name as the window's title. A named window keeps its Assignment while it's closed.", parameters: [
            Parameter(name: "window", kind: .string, description: "A Chrome window's handle from status, such as \"w3\".", isRequired: true),
            Parameter(name: "name", kind: .string, description: "The name, such as \"Work main\".", isRequired: true),
        ]),
        Tool(name: "pin", description: "Pin a window: a live mirror of it floats above other windows on every regular Space, hidden while the window itself is visible. Clicking the mirror switches to the window. Fullscreen windows can't be pinned. Pins are temporary and never saved.", parameters: [
            Parameter(name: "window", kind: .string, description: "A window handle from status, such as \"w3\".", isRequired: true),
        ]),
        Tool(name: "unpin", description: "Remove a window's Pin.", parameters: [
            Parameter(name: "window", kind: .string, description: "A window handle from status, such as \"w3\".", isRequired: true),
        ]),
        Tool(name: "pause", description: "Pause automatic behaviour: windows that appear (such as after Chrome relaunches) stay where they are instead of going to their Space, and display changes don't trigger a Restore. Commands still work. status reports isPaused."),
        Tool(name: "resume", description: "Resume automatic behaviour after pause. Windows that appeared, and display changes that happened, while paused stay as they are until restored."),
        Tool(name: "doctor", description: "Run Space Maker's Doctor, a self-check of the macOS internals it relies on, and return its markdown report."),
    ]

    public let socketPath: String

    public init(socketPath: String = CommandSocket.defaultPath) {
        self.socketPath = socketPath
    }

    /// Never throws: every failure becomes an error result an agent can read.
    /// Runs off the caller's actor because the socket I/O blocks.
    public func callTool(named name: String, arguments: [String: String] = [:]) async -> Result {
        do {
            let reply = try CommandClient.send(CommandRequest(command: name, arguments: arguments), socketPath: socketPath)
            return Result(text: reply.text, isError: reply.isError)
        } catch CommandRelayError.notRunning {
            return Result(text: Self.notRunning, isError: true)
        } catch {
            return Result(text: "Couldn't reach Space Maker: \(error)", isError: true)
        }
    }
}
