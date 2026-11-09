import Foundation

/// What a menu bar item does, as the engine command it issues. The menu bar runs the same commands MCP does.
public enum MenuAction: Equatable, Sendable {
    case saveAll
    case restoreAll
    case saveWindow(handle: String)
    case restoreWindow(handle: String)
    case ignoreWindow(handle: String)
    case ignoreApp(ofWindow: String)
    case rememberDisplay(id: String)
    case renameSpace(String, to: String)
    case togglePause

    /// The command this action issues, given whether automatic behaviour is paused now.
    public func request(isPaused: Bool) -> CommandRequest {
        switch self {
        case .saveAll: CommandRequest(command: "save")
        case .restoreAll: CommandRequest(command: "restore")
        case .saveWindow(let handle): CommandRequest(command: "save", arguments: ["window": handle])
        case .restoreWindow(let handle): CommandRequest(command: "restore", arguments: ["window": handle])
        case .ignoreWindow(let handle): CommandRequest(command: "ignore", arguments: ["window": handle])
        case .ignoreApp(let handle): CommandRequest(command: "ignore", arguments: ["window": handle, "app": "true"])
        case .rememberDisplay(let id): CommandRequest(command: "remember_display", arguments: ["display": id])
        case .renameSpace(let space, let name): CommandRequest(command: "rename_space", arguments: ["space": space, "name": name])
        case .togglePause: CommandRequest(command: isPaused ? "resume" : "pause")
        }
    }
}

extension Engine {
    /// Runs a menu bar action through the command interface.
    public func perform(_ action: MenuAction) -> CommandReply {
        perform(action.request(isPaused: isPaused))
    }
}
