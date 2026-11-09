import Foundation
import SpaceMakerCore
import Testing

@MainActor
struct PlacementTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// Three regular desktops (11 current, 12, 13) on the built-in display.
    func desktops() {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .regular, isCurrent: false),
            .init(id: 13, kind: .regular, isCurrent: false),
        ])]
    }

    @Test func aChromeRelaunchSendsEveryTrackedWindowBackToItsSpace() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .chrome(602, profile: .known("Work"), title: "Calendar", desktop: 13),
            .chrome(603, profile: .known("Personal"), title: "News", desktop: 11),
        ]
        let engine = engine()
        try engine.run("save")

        world.relaunchChrome()

        #expect(world.desktop(of: 1601) == 12)
        #expect(world.desktop(of: 1602) == 13)
        #expect(world.desktop(of: 1603) == 11)
        #expect(engine.status().drift == [])
    }

    @Test func aWindowWithNoAssignmentThatAppearsIsLeftAlone() throws {
        desktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 12)]
        let engine = engine()
        try engine.run("save")

        world.openWindow(.app(502, "com.apple.Safari", "Safari", title: "News", desktop: 11))
        world.openWindow(.app(503, "com.apple.Terminal", "Terminal", title: "logs", desktop: 13))  // an extra of its kind

        #expect(world.desktop(of: 502) == 11)
        #expect(world.desktop(of: 503) == 13)
        #expect(world.desktop(of: 501) == 12)
    }

    @Test func nothingIsPlacedWhilePausedAndPlacementResumesAfterResume() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .chrome(602, profile: .known("Personal"), title: "News", desktop: 13),
        ]
        let engine = engine()
        try engine.run("save")

        try engine.run("pause")
        #expect(engine.status().isPaused)
        world.relaunchChrome()
        #expect(world.desktop(of: 1601) == 11)
        #expect(world.desktop(of: 1602) == 11)

        try engine.run("resume")
        #expect(!engine.status().isPaused)
        // A window that appeared while paused stays where it is until the user Restores it.
        #expect(world.desktop(of: 1601) == 11)
        world.relaunchChrome()
        #expect(world.desktop(of: 2601) == 12)
        #expect(world.desktop(of: 2602) == 13)
    }

    @Test func pauseAndResumeSayWhatChanged() throws {
        desktops()
        let engine = engine()

        #expect(try engine.run("pause").contains("Paused"))
        #expect(try engine.run("pause").contains("already paused"))
        #expect(try engine.run("resume").contains("Resumed"))
        #expect(try engine.run("resume").contains("isn't paused"))
    }

    @Test func aWindowTheUserMovesAfterItWasPlacedIsNotMovedBack() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .chrome(602, profile: .known("Personal"), title: "News", desktop: 13),
        ]
        let engine = engine()
        try engine.run("save")
        world.relaunchChrome()
        #expect(world.desktop(of: 1601) == 12)

        world.move(1601, to: 11)
        world.openWindow(.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11))
        world.announceAgain(1601)

        #expect(world.desktop(of: 1601) == 11)
        #expect(engine.status().drift.map(\.kind) == [.moved, .new])  // still Drift, for the user to settle
    }
}
