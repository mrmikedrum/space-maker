import Foundation
import SpaceMakerCore
import Testing

/// The MCP shim has no logic of its own; these only prove a command survives the trip
/// shim → socket → app → engine and back.
@MainActor
struct ShimSmokeTests {
    @Test func statusMakesARoundTripThroughTheSocketToTheShim() async throws {
        let world = FakeWindowSystem()
        world.displays = [.builtIn(desktops: [.init(id: 11, kind: .regular, isCurrent: true)])]
        world.windows = [.app(7, "com.ticktick.task.mac", "TickTick", title: "Today", desktop: 11)]
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        let socket = Self.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket) { request in await engine.perform(request) }
        defer { server.stop() }

        let result = await MCPShim(socketPath: socket).callTool(named: "status")

        #expect(!result.isError)
        let status = try JSONDecoder().decode(Status.self, from: Data(result.text.utf8))
        #expect(status.windows.map(\.title) == ["Today"])
    }

    @Test func pinCarriesItsWindowHandleThroughTheSocket() async throws {
        let world = FakeWindowSystem()
        world.displays = [.builtIn(desktops: [.init(id: 11, kind: .regular, isCurrent: true), .init(id: 12, kind: .regular, isCurrent: false)])]
        world.windows = [.app(7, "com.ticktick.task.mac", "TickTick", title: "Today", desktop: 12)]
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        _ = engine.status()
        let socket = Self.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket) { request in await engine.perform(request) }
        defer { server.stop() }

        let result = await MCPShim(socketPath: socket).callTool(named: "pin", arguments: ["window": "w1"])

        #expect(!result.isError)
        #expect(result.text == "Pinned TickTick \"Today\" (w1).")
        #expect(world.mirrors == [7: .shown])
    }

    @Test func theShimSaysSoWhenSpaceMakerIsntRunning() async {
        let result = await MCPShim(socketPath: Self.temporarySocketPath()).callTool(named: "status")

        #expect(result.isError)
        #expect(result.text == "Space Maker isn't running.")
    }

    /// Unix socket paths are capped at 104 bytes, so keep it short.
    static func temporarySocketPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("sm-\(UUID().uuidString.prefix(8)).sock").path
    }
}

extension ShimSmokeTests {
    @Test func toolArgumentsMakeTheTripToo() async throws {
        let world = FakeWindowSystem()
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        let socket = Self.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket) { request in await engine.perform(request) }
        defer { server.stop() }

        let result = await MCPShim(socketPath: socket).callTool(named: "rename_space", arguments: ["space": "Nowhere", "name": "Code"])

        #expect(result.isError)
        #expect(result.text.contains("“Nowhere”"))
    }
}
