import Foundation
import SpaceMakerCore
import Testing

/// The command socket against clients that misbehave: they hang up early, send too much, stall, or pile up.
/// Real sockets, so these wait on real I/O, but never longer than a few seconds.
struct RelayRobustnessTests {
    static let ok = CommandReply(text: "ok")

    @Test func aClientThatHangsUpBeforeTheReplyDoesntTakeTheAppDown() async throws {
        let socket = ShimSmokeTests.temporarySocketPath()
        let gate = Gate()
        let server = try CommandServer.start(socketPath: socket) { request in
            if request.command == "slow" { await gate.enterAndWait() }
            return Self.ok
        }
        defer { server.stop() }

        let early = try RawClient(socket)
        early.send(#"{"command":"slow"}"# + "\n")
        await gate.waitUntilEntered()  // the server is working on it
        early.close()
        await gate.open()  // so the reply goes to a socket nobody is reading

        let reply = try CommandClient.send(CommandRequest(command: "status"), socketPath: socket)
        #expect(reply == Self.ok)
    }

    @Test func anOversizedRequestIsRefusedAndTheServerKeepsGoing() throws {
        let socket = ShimSmokeTests.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket, limits: .init(maxRequestBytes: 1024)) { _ in Self.ok }
        defer { server.stop() }

        let client = try RawClient(socket)
        client.send(String(repeating: "x", count: 4096))
        let (reply, closed) = client.readUntilClosed()
        client.close()

        #expect(closed)
        #expect(String(decoding: reply, as: UTF8.self).contains("too long"))
        #expect(try CommandClient.send(CommandRequest(command: "status"), socketPath: socket) == Self.ok)
    }

    @Test func aClientThatStallsIsDisconnected() throws {
        let socket = ShimSmokeTests.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket, limits: .init(readTimeout: 0.2)) { _ in Self.ok }
        defer { server.stop() }

        let client = try RawClient(socket)
        client.send(#"{"command":"#)  // and then nothing more
        let (_, closed) = client.readUntilClosed()
        client.close()

        #expect(closed)  // the server hung up, rather than the client's own 3 s timeout expiring
    }

    @Test func connectionsBeyondTheCapAreTurnedAwayUntilOthersFinish() throws {
        let socket = ShimSmokeTests.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket, limits: .init(readTimeout: 0.5, maxConnections: 2)) { _ in Self.ok }
        defer { server.stop() }

        let stalled = try [RawClient(socket), RawClient(socket)]
        let third = try CommandClient.send(CommandRequest(command: "status"), socketPath: socket)
        #expect(third.isError)
        #expect(third.text.contains("busy"))

        for client in stalled { _ = client.readUntilClosed(); client.close() }  // the server times them out
        var later = third
        let deadline = Date().addingTimeInterval(3)
        while later != Self.ok, Date() < deadline {
            later = try CommandClient.send(CommandRequest(command: "status"), socketPath: socket)
        }
        #expect(later == Self.ok)
    }

    @Test func theSocketAndItsFolderAreTheOwnersAlone() throws {
        let socket = ShimSmokeTests.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket) { _ in Self.ok }
        defer { server.stop() }

        let folder = URL(fileURLWithPath: socket).deletingLastPathComponent().path
        let folderMode = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? Int
        let socketMode = try FileManager.default.attributesOfItem(atPath: socket)[.posixPermissions] as? Int
        #expect(folderMode == 0o700)
        #expect(socketMode == 0o600)
    }
}

/// Lets a test hold a request in the handler until it says so.
actor Gate {
    private var hasEntered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the handler: says it has the request, then waits for `open()`.
    func enterAndWait() async {
        hasEntered = true
        for waiter in entryWaiters { waiter.resume() }
        entryWaiters = []
        if !isOpen { await withCheckedContinuation { openWaiters.append($0) } }
    }

    func waitUntilEntered() async {
        if !hasEntered { await withCheckedContinuation { entryWaiters.append($0) } }
    }

    func open() {
        isOpen = true
        for waiter in openWaiters { waiter.resume() }
        openWaiters = []
    }
}

/// A bare client that can do what `CommandClient` won't: hang up early, send junk, or stall.
final class RawClient {
    private let fd: Int32

    init(_ path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let bytes = Array(path.utf8)
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw CommandRelayError.notRunning }
    }

    func send(_ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// Everything the server sends, and whether it then hung up (false if this client's 3 s timeout expired first).
    func readUntilClosed() -> (Data, Bool) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 { data.append(contentsOf: buffer[..<count]); continue }
            return (data, count == 0 || errno == ECONNRESET)
        }
    }

    func close() {
        Darwin.close(fd)
    }
}
