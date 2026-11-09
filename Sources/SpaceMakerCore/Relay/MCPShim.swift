import Foundation

/// What the stateless stdio MCP server does with a tool call: relay it to the app (ADR 0002).
/// The `space-maker-mcp` executable only adapts this to the MCP SDK.
public struct MCPShim: Sendable {
    public struct Tool: Sendable {
        public let name: String
        public let description: String
    }

    public struct Result: Equatable, Sendable {
        public let text: String
        public let isError: Bool
    }

    public static let notRunning = "Space Maker isn't running."

    public static let tools = [
        Tool(name: "status", description: "Report the displays, their desktops in Mission Control order (regular and fullscreen), and every window with its handle, app, Chrome profile, fullscreen flag, title and current desktop. Displays other than the built-in one are Guest Displays for now."),
        Tool(name: "doctor", description: "Run Space Maker's Doctor, a self-check of the macOS internals it relies on, and return its markdown report."),
    ]

    public let socketPath: String

    public init(socketPath: String = CommandSocket.defaultPath) {
        self.socketPath = socketPath
    }

    /// Never throws: every failure becomes an error result an agent can read.
    /// Runs off the caller's actor because the socket I/O blocks.
    public func callTool(named name: String) async -> Result {
        do {
            let reply = try CommandClient.send(CommandRequest(command: name), socketPath: socketPath)
            return Result(text: reply.text, isError: reply.isError)
        } catch CommandRelayError.notRunning {
            return Result(text: Self.notRunning, isError: true)
        } catch {
            return Result(text: "Couldn't reach Space Maker: \(error)", isError: true)
        }
    }
}
