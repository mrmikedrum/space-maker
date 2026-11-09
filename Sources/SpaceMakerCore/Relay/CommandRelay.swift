import Foundation

/// One command sent to the app over the local socket, as one line of JSON (ADR 0002).
public struct CommandRequest: Codable, Equatable, Sendable {
    public var command: String
    /// Named arguments, such as a window handle or a Space name. Never coordinates.
    public var arguments: [String: String]

    public init(command: String, arguments: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
    }
}

/// The app's answer: text for an agent to read, and whether the command failed.
public struct CommandReply: Codable, Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public enum CommandSocket {
    /// Where the app listens.
    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpaceMaker/command.sock").path
    }
}

public enum CommandRelayError: Error, Equatable {
    /// Nothing is listening: the app isn't running.
    case notRunning
    case socket(String)
    case alreadyRunning
}

/// The app side of the socket: accepts connections and answers one request per connection.
public final class CommandServer: @unchecked Sendable {
    public typealias Handler = @Sendable (CommandRequest) async -> CommandReply

    private let socketPath: String
    private let listener: Int32
    private let handler: Handler

    private init(socketPath: String, listener: Int32, handler: @escaping Handler) {
        self.socketPath = socketPath
        self.listener = listener
        self.handler = handler
    }

    /// Starts listening at `socketPath`, replacing a stale socket file but refusing to replace a live one.
    public static func start(socketPath: String, handler: @escaping Handler) throws -> CommandServer {
        if (try? UnixSocket.connect(to: socketPath)).map({ close($0) }) != nil {
            throw CommandRelayError.alreadyRunning
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: socketPath).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        unlink(socketPath)
        let listener = try UnixSocket.listen(at: socketPath)
        let server = CommandServer(socketPath: socketPath, listener: listener, handler: handler)
        let thread = Thread { server.acceptLoop() }
        thread.name = "Space Maker command socket"
        thread.start()
        return server
    }

    public func stop() {
        shutdown(listener, SHUT_RDWR)
        close(listener)
        unlink(socketPath)
    }

    private func acceptLoop() {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else {
                if errno == EINTR { continue }
                return  // the listener was closed
            }
            DispatchQueue.global().async { self.serve(connection) }
        }
    }

    private func serve(_ connection: Int32) {
        guard let line = UnixSocket.readLine(from: connection) else {
            close(connection)
            return
        }
        let handler = handler
        Task {
            let reply: CommandReply
            if let request = try? JSONDecoder().decode(CommandRequest.self, from: line) {
                reply = await handler(request)
            } else {
                reply = CommandReply(text: "Space Maker couldn't read that request.", isError: true)
            }
            UnixSocket.writeLine(try! JSONEncoder().encode(reply), to: connection)
            close(connection)
        }
    }
}

/// The client side: one request, one reply, one connection.
public enum CommandClient {
    public static func send(_ request: CommandRequest, socketPath: String) throws -> CommandReply {
        let connection = try UnixSocket.connect(to: socketPath)
        defer { close(connection) }
        UnixSocket.writeLine(try JSONEncoder().encode(request), to: connection)
        guard let line = UnixSocket.readLine(from: connection) else {
            throw CommandRelayError.socket("Space Maker closed the connection without replying.")
        }
        return try JSONDecoder().decode(CommandReply.self, from: line)
    }
}

/// Thin POSIX wrappers for newline-delimited JSON over a Unix domain socket.
enum UnixSocket {
    static func listen(at path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CommandRelayError.socket("socket: \(String(cString: strerror(errno)))") }
        var address = try self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw CommandRelayError.socket("bind/listen \(path): \(reason)")
        }
        return fd
    }

    static func connect(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CommandRelayError.socket("socket: \(String(cString: strerror(errno)))") }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = try self.address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let code = errno
            close(fd)
            if code == ENOENT || code == ECONNREFUSED { throw CommandRelayError.notRunning }
            throw CommandRelayError.socket("connect \(path): \(String(cString: strerror(code)))")
        }
        return fd
    }

    static func readLine(from fd: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == UInt8(ascii: "\n") { return data }
            data.append(byte)
        }
        return data.isEmpty ? nil : data
    }

    static func writeLine(_ data: Data, to fd: Int32) {
        var bytes = [UInt8](data)
        bytes.append(UInt8(ascii: "\n"))
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard written > 0 else { return }
            offset += written
        }
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw CommandRelayError.socket("Socket path too long: \(path)") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }
}
