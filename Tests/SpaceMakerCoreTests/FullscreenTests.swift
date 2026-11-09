import Foundation
import SpaceMakerCore
import Testing

/// Fullscreen windows in Arrangements: "Game fullscreen, Tasks, Personal, Work, Work fullscreen".
@MainActor
struct FullscreenTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// Laptop alone: Game main fullscreen first, then TickTick, Personal main and Work second on their own
    /// desktops, then Work main fullscreen at the end.
    func laptopAlone() {
        world.displays = [.builtIn(desktops: [
            .fullscreen(901), .regular(11, current: true), .regular(12), .regular(13), .fullscreen(902),
        ])]
        world.windows = [
            .chrome(601, profile: .known("Game"), title: "Twitch", desktop: 901, fullscreen: true, name: "Twitch"),
            .app(501, "com.TickTick.task.mac", "TickTick", title: "Today", desktop: 11),
            .chrome(602, profile: .known("Personal"), title: "Mail", desktop: 12, name: "Mail"),
            .chrome(603, profile: .known("Work"), title: "Docs", desktop: 13, name: "Docs"),
            .chrome(604, profile: .known("Work"), title: "Calendar", desktop: 902, fullscreen: true, name: "Calendar"),
        ]
    }

    @Test func saveRecordsFullscreenWindowsInterleavedWithSpacesInOnScreenOrder() throws {
        laptopAlone()
        world.place(601, at: WindowFrame(x: 0, y: 0, width: 1512, height: 982))
        try engine().run("save")

        let layout = try savedLayout()
        #expect(layout.displaySetups[0].arrangement[0].order
            == ["Game fullscreen", "TickTick", "Google Chrome", "Google Chrome 2", "Work fullscreen"])
        #expect(layout.spaces == ["TickTick", "Google Chrome", "Google Chrome 2"])
        let fullscreen = layout.assignments.filter(\.window.isFullscreen).map { "\($0.window.chromeProfile ?? "") → \($0.space)" }
        #expect(fullscreen.sorted() == ["Game → Game fullscreen", "Work → Work fullscreen"])
        #expect(layout.assignments.filter(\.window.isFullscreen).allSatisfy { $0.frames.isEmpty })  // fullscreen fills the display
    }

    @Test func aFullscreenWindowWhoseProfileCantBeReadNamesItsPlaceAfterTheWindow() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .fullscreen(901)])]
        world.windows = [.chrome(601, profile: .unknown, title: "Game main", desktop: 901, fullscreen: true, name: "Game main")]

        try engine().run("save")

        #expect(try savedLayout().displaySetups[0].arrangement[0].order.contains("Game main fullscreen"))
    }

    @Test func restorePutsAWindowTakenOutOfFullscreenBackInItsPlace() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        _ = world.setFullscreen(604, false)  // Work main leaves fullscreen and lands on Work second's desktop
        world.move(604, to: 11)

        try engine.run("restore")

        let workMain = try #require(world.window(604))
        #expect(workMain.isFullscreen)
        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "12", "13", "fullscreen 604"])
        #expect(engine.status().drift.isEmpty)
        #expect(engine.status().softDrift.isEmpty)
    }

    @Test func takenOutOfFullscreenWhenItBelongsFirstComesBackAfterTheSpacesAsSoftDriftAndIsNotRetried() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        _ = world.setFullscreen(601, false)  // Game main leaves fullscreen

        try engine.run("restore")

        // macOS appends new fullscreen desktops at the end of the display, so Game main can't get back before
        // TickTick; Work main is cycled so the fullscreen windows keep their saved order.
        #expect(world.window(601)?.isFullscreen == true)
        #expect(world.order(of: "built-in") == ["11", "12", "13", "fullscreen 601", "fullscreen 604"])
        let status = engine.status()
        #expect(status.drift.isEmpty)
        let soft = try #require(status.softDrift.first { $0.title == "Twitch" })
        #expect(soft.problem.contains("before “TickTick”"))
        #expect(soft.hint.contains("Mission Control"))

        let changes = world.fullscreenChanges
        try engine.run("restore")
        try engine.run("restore")
        #expect(world.fullscreenChanges == changes)
        #expect(world.order(of: "built-in") == ["11", "12", "13", "fullscreen 601", "fullscreen 604"])
    }

    /// Game main fullscreen, TickTick, Work main fullscreen.
    func gameTickTickWork() {
        world.displays = [.builtIn(desktops: [.fullscreen(901), .regular(11, current: true), .fullscreen(902)])]
        world.windows = [
            .chrome(601, profile: .known("Game"), title: "Twitch", desktop: 901, fullscreen: true, name: "Twitch"),
            .app(501, "com.TickTick.task.mac", "TickTick", title: "Today", desktop: 11),
            .chrome(604, profile: .known("Work"), title: "Calendar", desktop: 902, fullscreen: true, name: "Calendar"),
        ]
    }

    @Test func restoringAFullscreenWindowCyclesTheLaterFullscreenWindowsOnItsDisplaySoTheirOrderMatchesTheArrangement() throws {
        gameTickTickWork()
        let engine = engine()
        try engine.run("save")
        _ = world.setFullscreen(601, false)  // Game main leaves fullscreen and lands on TickTick's desktop
        #expect(world.order(of: "built-in") == ["11", "fullscreen 604"])

        try engine.run("restore")

        #expect(world.order(of: "built-in") == ["11", "fullscreen 601", "fullscreen 604"])
        #expect(world.fullscreenChanges == [601: 2, 604: 2])  // Game main out (by hand) and back in; Work main out and in
        #expect(engine.status().drift.isEmpty)
        #expect(engine.status().softDrift.map(\.title) == ["Twitch"])  // it belongs before TickTick
        #expect(engine.status().softDrift.first?.problem.contains("before “TickTick”") == true)

        try engine.run("restore")  // nothing changed: nothing is cycled again
        #expect(world.fullscreenChanges == [601: 2, 604: 2])
        #expect(world.order(of: "built-in") == ["11", "fullscreen 601", "fullscreen 604"])
    }

    @Test func placingAFullscreenWindowCyclesTheLaterFullscreenWindowsOnItsDisplayToo() throws {
        gameTickTickWork()
        let engine = engine()
        try engine.run("save")

        // Game main closes, taking its fullscreen desktop with it, and comes back as a normal window.
        world.closeWindow(601)
        world.displays[0].desktops.removeAll { $0.id == 901 }
        world.openWindow(.chrome(1601, profile: .known("Game"), title: "Twitch", desktop: 11, name: "Twitch"))

        #expect(world.order(of: "built-in") == ["11", "fullscreen 1601", "fullscreen 604"])
        #expect(world.fullscreenChanges == [1601: 1, 604: 2])
        #expect(engine.status().drift.isEmpty)
    }

    @Test func twoFullscreenWindowsRestoredOnOneDisplayComeOutInArrangementOrder() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .fullscreen(901), .fullscreen(902)])]
        world.windows = [  // listed Work main first, so restoring in list order would put it before Game main
            .chrome(604, profile: .known("Work"), title: "Calendar", desktop: 902, fullscreen: true, name: "Calendar"),
            .app(501, "com.TickTick.task.mac", "TickTick", title: "Today", desktop: 11),
            .chrome(601, profile: .known("Game"), title: "Twitch", desktop: 901, fullscreen: true, name: "Twitch"),
        ]
        let engine = engine()
        try engine.run("save")
        _ = world.setFullscreen(604, false)
        _ = world.setFullscreen(601, false)

        try engine.run("restore")

        #expect(world.order(of: "built-in") == ["11", "fullscreen 601", "fullscreen 604"])
        #expect(world.fullscreenChanges == [601: 2, 604: 2])  // each out and back in once
        #expect(engine.status().drift.isEmpty)
        #expect(engine.status().softDrift.isEmpty)
    }

    @Test func aFullscreenWindowDraggedOutOfOrderOnItsDisplayIsSoftDriftAndLeftAlone() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        world.displays[0].desktops = [.fullscreen(901), .regular(11, current: true), .fullscreen(902), .regular(12), .regular(13)]

        try engine.run("restore")

        #expect(world.fullscreenChanges.isEmpty)
        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "fullscreen 604", "12", "13"])
        let soft = engine.status().softDrift
        #expect(soft.map(\.title) == ["Calendar"])
        #expect(soft.first?.problem.contains("after “Google Chrome 2”") == true)
        #expect(engine.status().drift.isEmpty)
    }

    @Test func aWindowMacOSWontPutBackInFullscreenIsSoftDriftUntilTheWorldChanges() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        _ = world.setFullscreen(604, false)
        world.unfullscreenableWindows = [604]

        let reply = try engine.run("restore")
        #expect(reply.contains("Couldn't restore"))
        #expect(engine.status().softDrift.map(\.title) == ["Calendar"])
        #expect(engine.status().drift.isEmpty)

        world.unfullscreenableWindows = []
        try engine.run("restore")  // nothing changed, so it isn't retried
        #expect(world.window(604)?.isFullscreen == false)

        world.move(604, to: 12)  // the world changes
        try engine.run("restore")
        #expect(world.window(604)?.isFullscreen == true)
        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "12", "13", "fullscreen 604"])
    }

    @Test func aWindowTakenOutOfFullscreenIsDriftUntilRestored() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        #expect(engine.status().drift.isEmpty)

        _ = world.setFullscreen(604, false)

        let drift = engine.status().drift
        #expect(drift.map(\.title) == ["Calendar"])
        #expect(drift.first?.kind == .moved)
        #expect(drift.first?.space == "Work fullscreen")
    }

    /// Saved laptop alone, then docked: Game main and TickTick and Personal main stay on the laptop; Work second and
    /// Work main fullscreen go to the Dell, after a scratch desktop.
    func savedLaptopThenDocked(_ engine: Engine) throws {
        laptopAlone()
        try engine.run("save")
        world.displays = [
            .builtIn(desktops: [.fullscreen(901), .regular(11, current: true), .regular(12)]),
            .dell(desktops: [.regular(21, current: true), .regular(22), .fullscreen(902)]),
        ]
        world.move(603, to: 22)
        try engine.run("remember_display", ["display": "dell-uuid"])
        try engine.run("save")
    }

    @Test func undockingThenRedockingEndsWithWorkMainAndGameMainFullscreenOnTheRightDisplay() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        world.undock("dell-uuid")  // the laptop now has Game, 11, 12, 22 (Work second), Work main
        try engine.run("restore")

        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "12", "22", "fullscreen 604"])
        #expect(world.fullscreenChanges.isEmpty)
        #expect(engine.status().drift.isEmpty)
        #expect(engine.status().softDrift.isEmpty)

        // macOS takes the Dell's regular desktops back (out of order, one of them new) but leaves Work main on the laptop.
        world.redock(.dell(desktops: [.regular(22, current: true), .regular(24)]))
        try engine.run("restore")

        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "12"])
        #expect(world.order(of: "dell-uuid") == ["22", "24", "fullscreen 604"])
        #expect(world.desktop(of: 603) == 24)
        #expect(world.window(604)?.isFullscreen == true)
        #expect(world.fullscreenChanges == [604: 2])  // out and back in, once; Game main never touched
        #expect(engine.status().drift.isEmpty)
        #expect(engine.status().softDrift.isEmpty)
    }

    @Test func aWindowAlreadyFullscreenInItsPlaceIsNeverReFullscreened() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        world.move(602, to: 13)

        try engine.run("restore")
        try engine.run("restore")

        #expect(world.desktop(of: 602) == 12)
        #expect(world.fullscreenChanges.isEmpty)
    }

    @Test func aSavedFullscreenChromeWindowThatComesBackNormalIsPlacedBackInFullscreenAtItsPlace() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")

        // Chrome quits, taking Work main and its fullscreen desktop with it, and brings it back as a normal window.
        world.closeWindow(604)
        world.displays[0].desktops.removeAll { $0.id == 902 }
        world.openWindow(.chrome(1604, profile: .known("Work"), title: "Calendar", desktop: 11, name: "Calendar"))

        #expect(world.window(1604)?.isFullscreen == true)
        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "12", "13", "fullscreen 1604"])
        #expect(engine.status().drift.isEmpty)
    }

    @Test func aWindowThatAppearsAlreadyFullscreenOnTheWrongDisplayIsPlacedOnItsOwn() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)  // Work main belongs fullscreen at the end of the Dell

        // Work main comes back fullscreen, but on the laptop.
        world.closeWindow(604)
        world.displays[1].desktops.removeAll { $0.id == 902 }
        world.displays[0].desktops.append(.fullscreen(903))
        world.openWindow(.chrome(1604, profile: .known("Work"), title: "Calendar", desktop: 903, fullscreen: true, name: "Calendar"))

        #expect(world.window(1604)?.isFullscreen == true)
        #expect(world.order(of: "dell-uuid") == ["21", "22", "fullscreen 1604"])
        #expect(engine.status().drift.isEmpty)
    }

    @Test func savingWhileANamedFullscreenWindowIsClosedKeepsItsAssignmentAndItsPlace() throws {
        laptopAlone()
        world.windows[4] = .chrome(604, profile: .known("Work"), title: "Calendar", desktop: 902, fullscreen: true, name: "Work main")
        let engine = engine()
        try engine.run("save")

        world.closeWindow(604)
        world.displays[0].desktops.removeAll { $0.id == 902 }
        try engine.run("save")

        let layout = try savedLayout()
        #expect(layout.displaySetups[0].arrangement[0].order
            == ["Game fullscreen", "TickTick", "Google Chrome", "Google Chrome 2", "Work fullscreen"])
        #expect(layout.assignments.contains { $0.window.name == "Work main" && $0.window.isFullscreen && $0.space == "Work fullscreen" })

        // It comes back as a normal window and goes back to its place.
        world.openWindow(.chrome(1604, profile: .known("Work"), title: "Calendar", desktop: 11, name: "Work main"))
        #expect(world.order(of: "built-in") == ["fullscreen 601", "11", "12", "13", "fullscreen 1604"])
    }

    @Test func aSpaceCantBeRenamedToAFullscreenWindowsPlace() throws {
        laptopAlone()
        let engine = engine()
        try engine.run("save")
        let before = try savedLayout()

        let reply = engine.perform(CommandRequest(command: "rename_space", arguments: ["space": "TickTick", "name": "Work fullscreen"]))

        #expect(reply.isError)
        #expect(reply.text.contains("“Work fullscreen”"))
        #expect(try savedLayout() == before)
    }

    func savedLayout() throws -> Layout {
        try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
    }
}

extension WindowSystemDesktop {
    static func fullscreen(_ id: UInt64, current: Bool = false) -> Self {
        Self(id: id, kind: .fullscreen, isCurrent: current)
    }
}
