import Foundation
import SpaceMakerCore
import Testing

/// Automatic Restore once a display change has settled: docking and undocking need nothing from the user.
@MainActor
struct AutoRestoreTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// Laptop alone: Terminal, Slack, Safari and Music each on their own desktop, Saved.
    /// Then docked: Terminal and Slack on the laptop, Safari and Music on the Dell, the Dell remembered and Saved.
    func savedLaptopThenDocked(_ engine: Engine) throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12), .regular(13), .regular(14)])]
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
            .app(503, "com.apple.Safari", "Safari", title: "News", desktop: 13),
            .app(504, "com.apple.Music", "Music", title: "Music", desktop: 14),
        ]
        try engine.run("save")

        world.displays = [
            .builtIn(desktops: [.regular(11, current: true), .regular(12)]),
            .dell(desktops: [.regular(21, current: true), .regular(22), .regular(23)]),
        ]
        world.move(503, to: 21)
        world.move(504, to: 22)
        try engine.run("remember_display", ["display": "dell-uuid"])
        try engine.run("save")
    }

    @Test func undockingRestoresTheLaptopSlotsWithNoFurtherAction() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        world.undock("dell-uuid")  // the laptop now has 11 (with Safari), 12, 22 (Music), 23
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 12)
        #expect(world.desktop(of: 503) == 22)
        #expect(world.desktop(of: 504) == 23)
        #expect(engine.status().drift.isEmpty)
    }

    @Test func flappingReconfigurationEventsCauseExactlyOneRestore() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        // A loose cable: the Dell drops out and comes back over a few seconds, with events all the while.
        world.undock("dell-uuid")
        world.reconfigureDisplays()
        for _ in 0..<6 {
            world.clock.advance(by: 0.4)
            world.reconfigureDisplays()
        }
        world.redock(.dell(desktops: [.regular(22, current: true), .regular(23), .regular(24)]))
        world.reconfigureDisplays()
        #expect(world.desktop(of: 503) == 11)  // nothing has moved while the events keep coming

        world.clock.advance(by: 30)
        #expect(world.desktop(of: 503) == 22)  // Safari's Space is the Dell's first
        #expect(world.desktop(of: 504) == 23)

        // The user drags Safari elsewhere afterwards. No second Restore is waiting to undo that.
        world.move(503, to: 12)
        world.clock.advance(by: 600)
        #expect(world.desktop(of: 503) == 12)
    }

    @Test func desktopsThatStayUnsettledForSeveralReadsDelayRestore() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        world.undock("dell-uuid")
        world.unsettledReads = 6  // macOS keeps shuffling desktops after its last event
        world.reconfigureDisplays()

        world.clock.advance(by: 2)
        #expect(world.unsettledReads > 0)
        #expect(world.desktop(of: 503) == 11)  // still waiting

        world.clock.advance(by: 30)
        #expect(world.desktop(of: 503) == 22)
        #expect(world.desktop(of: 504) == 23)
        let status = engine.status()
        #expect(status.drift.isEmpty)
        #expect(status.softDrift.isEmpty)
    }

    @Test func whenAGuestDisplaySessionEndsWindowsMovedOntoItGoHome() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.apple.Keynote", "Keynote", title: "Talk", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")

        // AirPlay to a TV. The user presents from it, then opens a new window there too.
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        world.reconfigureDisplays()
        world.clock.advance(by: 30)
        world.move(502, to: 31)
        world.windows.append(.app(503, "com.apple.Preview", "Preview", title: "Notes.pdf", desktop: 31))
        world.clock.advance(by: 600)
        #expect(world.desktop(of: 502) == 31)  // nothing fights the user during the session

        world.disconnect("airplay-uuid")  // macOS drops both windows on the laptop's current desktop
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 12)
        #expect(world.desktop(of: 503) == 11)  // no Assignment: left where macOS put it
        #expect(engine.status().drift.map(\.app) == ["Preview"])
    }

    @Test func anUnknownDisplaySetupGetsNoAutomaticRestore() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")

        // The Dell is remembered but nothing was Saved for laptop plus Dell. Meanwhile the user moved Terminal.
        world.displays.append(.dell(desktops: [.regular(21, current: true)]))
        try engine.run("remember_display", ["display": "dell-uuid"])
        world.move(501, to: 12)
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.desktop(of: 501) == 12)
        #expect(engine.status().softDrift.contains { $0.problem.contains("Display Setup") })
    }
}
