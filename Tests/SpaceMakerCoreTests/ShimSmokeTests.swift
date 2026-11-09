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
        let engine = Engine(windowSystem: world)
        let socket = Self.temporarySocketPath()
        let server = try CommandServer.start(socketPath: socket) { request in await engine.perform(request) }
        defer { server.stop() }

        let result = await MCPShim(socketPath: socket).callTool(named: "status")

        #expect(!result.isError)
        let status = try JSONDecoder().decode(Status.self, from: Data(result.text.utf8))
        #expect(status.windows.map(\.title) == ["Today"])
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
