import Foundation
import SpaceMakerCore
import Testing

/// The menu bar issues the same engine commands as MCP.
@MainActor
struct MenuSmokeTests {
    @Test func restoreAllFromTheMenuPutsAWindowBackOnItsSpace() throws {
        let world = FakeWindowSystem()
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        #expect(!engine.perform(.saveAll).isError)

        world.move(501, to: 12)
        let reply = engine.perform(.restoreAll)

        #expect(!reply.isError)
        #expect(world.desktop(of: 501) == 11)
    }
}
