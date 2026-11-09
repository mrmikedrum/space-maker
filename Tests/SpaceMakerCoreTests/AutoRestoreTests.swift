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
        world.reconfigureDisplays()  // the docking's last event: the world is settled and Space Maker knows it
        world.clock.advance(by: 30)
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

    @Test func desktopsThatNeverSettleGetNoRestoreAndSaySoUntilTheNextChange() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        let moves = world.moveAttempts

        world.undock("dell-uuid")
        world.unsettledReads = 1000  // macOS never stops shuffling desktops
        world.reconfigureDisplays()
        world.clock.advance(by: 120)

        #expect(world.moveAttempts == moves)  // nothing was moved on a half-finished read
        #expect(world.desktop(of: 503) == 11)
        let note = try #require(engine.status().softDrift.first { $0.handle == nil && $0.problem.contains("settle") })
        #expect(note.hint.contains("Restore"))

        // The next change settles, and Restores as usual.
        world.unsettledReads = 0
        world.reconfigureDisplays()
        world.clock.advance(by: 30)
        #expect(world.desktop(of: 503) == 22)
        #expect(!engine.status().softDrift.contains { $0.problem.contains("settle") })
    }

    @Test func anAssignedWindowWithoutASavedPositionThatMacOSShovedBeforeTheEventGoesBackWhereItWas() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)  // no positions were saved: the windows had none
        let before = WindowFrame(x: 1700, y: 100, width: 800, height: 600)
        world.place(503, at: before)
        let textEdit = WindowFrame(x: 100, y: 100, width: 600, height: 400)
        world.windows.append(.app(506, "com.apple.TextEdit", "TextEdit", title: "List", desktop: 11, frame: textEdit))
        _ = engine.status()  // Space Maker sees the world as it is

        // An AirPlay screen connects. macOS shoves Safari into a corner of the Dell, and TextEdit (no Assignment)
        // aside on the laptop, before it says anything about the change.
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        let shoved = WindowFrame(x: 1512, y: 25, width: 800, height: 600)
        world.place(503, at: shoved)
        let textEditShoved = WindowFrame(x: 0, y: 25, width: 600, height: 400)
        world.place(506, at: textEditShoved)
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.window(503)?.frame == before)  // back where it was on the same display
        #expect(world.window(506)?.frame == textEditShoved)  // no Assignment: never moved
    }

    @Test func aWindowShovedBeforeTheEventGoesBackEvenIfSpaceMakerLooksAtTheWorldBeforeTheEventArrives() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)  // no positions were saved: the windows had none
        let before = WindowFrame(x: 1700, y: 100, width: 800, height: 600)
        world.place(503, at: before)
        _ = engine.status()

        // An AirPlay screen connects and macOS shoves Safari. The menu bar's status refresh runs before the event.
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        world.place(503, at: WindowFrame(x: 1512, y: 25, width: 800, height: 600))
        _ = engine.status()
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.window(503)?.frame == before)
    }

    @Test func aWindowShovedByAResolutionChangeGoesBackEvenIfSpaceMakerLooksAtTheWorldBeforeTheEventArrives() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)  // no positions were saved: the windows had none
        let before = WindowFrame(x: 1700, y: 100, width: 800, height: 600)
        world.place(503, at: before)
        _ = engine.status()

        // The monitor's resolution changes (same displays, new geometry) and macOS shoves Safari before saying so.
        world.displays[1].visibleFrame = WindowFrame(x: 1512, y: 25, width: 1920, height: 1055)
        world.place(503, at: WindowFrame(x: 1512, y: 25, width: 800, height: 600))
        _ = engine.status()
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.window(503)?.frame == before)
    }

    @Test func afterAChangeThatNeverSettledRestoreAllMakesTheUsersLaterMovesTheOnesAChangePutsBack() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)  // no positions were saved: the windows had none
        world.place(503, at: WindowFrame(x: 1700, y: 100, width: 800, height: 600))
        _ = engine.status()

        // A display change whose desktops never settle, then the user's Restore all once they have.
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        world.unsettledReads = 1000
        world.reconfigureDisplays()
        world.clock.advance(by: 120)
        world.unsettledReads = 0
        try engine.run("restore")

        // The user moves Safari, then the TV disconnects and macOS shoves Safari before saying so.
        let moved = WindowFrame(x: 2000, y: 300, width: 800, height: 600)
        world.place(503, at: moved)
        _ = engine.status()
        world.disconnect("airplay-uuid")
        world.place(503, at: WindowFrame(x: 1512, y: 25, width: 800, height: 600))
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.window(503)?.frame == moved)
    }

    @Test func windowsWithoutAnAssignmentAreNeverPutBackAfterADisplayChange() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        let before = WindowFrame(x: 1700, y: 100, width: 800, height: 600)
        world.openWindow(.app(505, "com.apple.Preview", "Preview", title: "Notes.pdf", desktop: 21, frame: before))

        world.reconfigureDisplays()
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        let shoved = WindowFrame(x: 1512, y: 25, width: 800, height: 600)
        world.place(505, at: shoved)
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.window(505)?.frame == shoved)
    }

    @Test func windowsOnAGuestDisplayAreNotPutBackAfterADisplayChange() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [.app(502, "com.apple.Keynote", "Keynote", title: "Talk", desktop: 12)]
        let engine = engine()
        try engine.run("save")

        // The user presents Keynote on the TV, and macOS won't let it be moved off it.
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        world.reconfigureDisplays()
        world.clock.advance(by: 30)
        world.move(502, to: 31)
        world.unmovableWindows = [502]
        world.place(502, at: WindowFrame(x: 1600, y: 100, width: 1000, height: 700))
        _ = engine.status()

        // Sidecar connects too; while macOS rearranges, it nudges Keynote on the TV.
        world.reconfigureDisplays()
        let nudged = WindowFrame(x: 1512, y: 25, width: 1000, height: 700)
        world.place(502, at: nudged)
        world.displays.append(.external("sidecar-uuid", name: "iPad", desktops: [.regular(41, current: true)],
                                        visibleFrame: WindowFrame(x: -1024, y: 0, width: 1024, height: 768)))
        world.reconfigureDisplays()
        world.clock.advance(by: 30)

        #expect(world.window(502)?.frame == nudged)  // Space Maker never puts anything on a Guest Display
    }

    @Test func aRestoreWaitingForAMoveToFinishLapsesWhenANewerDisplayChangeArrives() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        world.move(501, to: 12)  // so Restore all has a move to make

        // While Restore all's move lands, a display change settles (its Restore waits for the move), and then
        // the Dell drops out and macOS starts shuffling desktops that never settle.
        world.whileNextMoveLands = { [world] in
            world.reconfigureDisplays()
            world.clock.advance(by: 2)
            world.undock("dell-uuid")
            world.unsettledReads = 1000
            world.reconfigureDisplays()
        }
        _ = engine.perform(CommandRequest(command: "restore"))
        let moves = world.moveAttempts

        world.clock.advance(by: 120)
        #expect(world.moveAttempts == moves)  // no Restore against desktops that never settled
        #expect(engine.status().softDrift.contains { $0.problem.contains("settle") })
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

    @Test func noAutomaticRestoreWhilePausedAndNoneOwedAfterResume() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        try engine.run("pause")

        world.undock("dell-uuid")
        world.reconfigureDisplays()
        world.clock.advance(by: 30)
        #expect(world.desktop(of: 503) == 11)  // where macOS merged it

        try engine.run("resume")
        world.clock.advance(by: 600)
        #expect(world.desktop(of: 503) == 11)  // resuming doesn't replay the change; Restore all does

        world.redock(.dell(desktops: [.regular(22, current: true), .regular(23), .regular(24)]))
        world.reconfigureDisplays()
        world.clock.advance(by: 30)
        #expect(world.desktop(of: 503) == 22)  // the next change after resuming Restores as usual
    }
}
