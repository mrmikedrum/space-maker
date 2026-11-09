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
///
/// Only the user who runs the app may connect: the socket's folder is owner-only, the socket is owner-only, and a
/// peer running as anyone else is turned away. Clients that send too much, stall, or pile up are cut off, and one
/// that hangs up before its reply can't take the app down.
public final class CommandServer: @unchecked Sendable {
    public typealias Handler = @Sendable (CommandRequest) async -> CommandReply

    /// How much a connection may ask of the server.
    public struct Limits: Sendable {
        /// The longest request line accepted, in bytes.
        public var maxRequestBytes: Int
        /// How long a client gets to send its whole request, in seconds.
        public var readTimeout: TimeInterval
        /// How long writing the reply may block, in seconds.
        public var writeTimeout: TimeInterval
        /// How many connections may be open at once; more are turned away.
        public var maxConnections: Int

        public init(maxRequestBytes: Int = 64 * 1024, readTimeout: TimeInterval = 5, writeTimeout: TimeInterval = 5, maxConnections: Int = 8) {
            self.maxRequestBytes = maxRequestBytes
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
            self.maxConnections = maxConnections
        }
    }

    private let socketPath: String
    private let listener: Int32
    private let limits: Limits
    private let handler: Handler
    private let lock = NSLock()
    private var openConnections = 0

    private init(socketPath: String, listener: Int32, limits: Limits, handler: @escaping Handler) {
        self.socketPath = socketPath
        self.listener = listener
        self.limits = limits
        self.handler = handler
    }

    /// Starts listening at `socketPath`, replacing a stale socket file but refusing to replace a live one.
    public static func start(socketPath: String, limits: Limits = Limits(), handler: @escaping Handler) throws -> CommandServer {
        if (try? UnixSocket.connect(to: socketPath)).map({ close($0) }) != nil {
            throw CommandRelayError.alreadyRunning
        }
        let folder = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard chmod(folder, 0o700) == 0 else {
            throw CommandRelayError.socket("Couldn't make \(folder) private: \(String(cString: strerror(errno)))")
        }
        unlink(socketPath)
        let listener = try UnixSocket.listen(at: socketPath, mode: 0o600)
        let server = CommandServer(socketPath: socketPath, listener: listener, limits: limits, handler: handler)
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
                switch errno {
                case EINTR, ECONNABORTED: continue
                case EBADF, EINVAL, ENOTSOCK: return  // the listener was closed
                default:
                    // Out of descriptors or memory (EMFILE, ENFILE, ENOBUFS, ENOMEM): wait for some to free up, keep accepting.
                    usleep(Self.acceptBackoffMicroseconds)
                    continue
                }
            }
            // Darwin refuses socket options once the client has hung up, and then a reply would raise SIGPIPE.
            guard UnixSocket.prepare(connection, readTimeout: limits.readTimeout, writeTimeout: limits.writeTimeout),
                  UnixSocket.peerIsThisUser(connection)
            else {
                close(connection)
                continue
            }
            guard claimConnection() else {
                turnAway(connection)  // right here: an overflow connection never gets a worker of its own
                continue
            }
            DispatchQueue.global().async { self.serve(connection) }
        }
    }

    private func claimConnection() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard openConnections < limits.maxConnections else { return false }
        openConnections += 1
        return true
    }

    private func releaseConnection() {
        lock.lock()
        openConnections -= 1
        lock.unlock()
    }

    private func serve(_ connection: Int32) {
        let deadline = Date().addingTimeInterval(limits.readTimeout)
        switch UnixSocket.readLine(from: connection, maxBytes: limits.maxRequestBytes, deadline: deadline) {
        case .closed:
            close(connection)
            releaseConnection()
        case .tooLong:
            reply(CommandReply(text: "That request is too long (over \(limits.maxRequestBytes) bytes).", isError: true), on: connection)
            releaseConnection()
        case .line(let line):
            let handler = handler
            Task {
                let answer: CommandReply
                if let request = try? JSONDecoder().decode(CommandRequest.self, from: line) {
                    answer = await handler(request)
                } else {
                    answer = CommandReply(text: "Space Maker couldn't read that request.", isError: true)
                }
                self.reply(answer, on: connection)
                self.releaseConnection()
            }
        }
    }

    /// How long the accept loop waits before trying again when the process is out of descriptors.
    private static let acceptBackoffMicroseconds: useconds_t = 50_000

    private static let busyLine = try! JSONEncoder().encode(
        CommandReply(text: "Space Maker is busy with other requests. Try again in a moment.", isError: true))

    /// Says the server is busy and hangs up, without ever waiting on the client: whatever of the request has
    /// already arrived is drained, the reply is written only if it fits at once, and the connection is closed.
    /// The client reads the reply even if its own write then fails.
    private func turnAway(_ connection: Int32) {
        _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 4096)
        var drained = 0
        while drained < limits.maxRequestBytes {
            let count = read(connection, &buffer, buffer.count)
            guard count > 0 else { break }
            drained += count
        }
        _ = UnixSocket.writeLine(Self.busyLine, to: connection)
        close(connection)
    }

    /// Writes the reply and closes the connection. A client that already hung up just doesn't get it.
    private func reply(_ reply: CommandReply, on connection: Int32) {
        _ = UnixSocket.writeLine(try! JSONEncoder().encode(reply), to: connection)
        close(connection)
    }
}

/// The client side: one request, one reply, one connection.
public enum CommandClient {
    public static func send(_ request: CommandRequest, socketPath: String) throws -> CommandReply {
        let connection = try UnixSocket.connect(to: socketPath)
        defer { close(connection) }
        // A failed write still reads on: Space Maker may have said why it hung up (such as being busy).
        let sent = UnixSocket.writeLine(try JSONEncoder().encode(request), to: connection)
        guard case .line(let line) = UnixSocket.readLine(from: connection, maxBytes: 64 * 1024 * 1024, deadline: nil) else {
            throw CommandRelayError.socket(sent ? "Space Maker closed the connection without replying." : "Space Maker closed the connection before reading the request.")
        }
        return try JSONDecoder().decode(CommandReply.self, from: line)
    }
}

/// Thin POSIX wrappers for newline-delimited JSON over a Unix domain socket.
enum UnixSocket {
    /// Binds and listens, with the socket file's permissions set to `mode` before anyone can connect.
    static func listen(at path: String, mode: mode_t) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CommandRelayError.socket("socket: \(String(cString: strerror(errno)))") }
        var address = try self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, mode) == 0, Darwin.listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw CommandRelayError.socket("bind/listen \(path): \(reason)")
        }
        return fd
    }

    /// Makes an accepted connection never raise SIGPIPE, and block no longer than the timeouts.
    /// Returns false if that couldn't be done, as when the client already hung up; the connection must then be closed unused.
    static func prepare(_ fd: Int32, readTimeout: TimeInterval, writeTimeout: TimeInterval) -> Bool {
        var on: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
        for (option, seconds) in [(SO_RCVTIMEO, readTimeout), (SO_SNDTIMEO, writeTimeout)] {
            var timeout = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
            guard setsockopt(fd, SOL_SOCKET, option, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else { return false }
        }
        return true
    }

    /// Whether the process at the other end runs as the same user as this one.
    static func peerIsThisUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == geteuid()
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

    enum ReadOutcome {
        case line(Data)
        case tooLong
        /// The other end hung up or stalled past its deadline before sending a whole line.
        case closed
    }

    /// Reads one newline-terminated line of at most `maxBytes`, giving up at `deadline`.
    /// A final line the other end closed without a newline still counts.
    static func readLine(from fd: Int32, maxBytes: Int, deadline: Date?) -> ReadOutcome {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            if let deadline, Date() >= deadline { return .closed }
            let count = read(fd, &byte, 1)
            if count == 1 {
                if byte == UInt8(ascii: "\n") { return .line(data) }
                guard data.count < maxBytes else { return .tooLong }
                data.append(byte)
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count == 0, !data.isEmpty { return .line(data) }
            return .closed  // EOF, a timeout (EAGAIN) or an error
        }
    }

    /// Returns false if the line couldn't all be written, such as when the other end hung up.
    @discardableResult
    static func writeLine(_ data: Data, to fd: Int32) -> Bool {
        var bytes = [UInt8](data)
        bytes.append(UInt8(ascii: "\n"))
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { return false }
            offset += written
        }
        return true
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
