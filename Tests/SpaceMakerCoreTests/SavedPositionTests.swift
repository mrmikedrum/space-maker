import Foundation
import SpaceMakerCore
import Testing

/// Saved positions: each window's position and size, per Display Setup, relative to the display it's on.
@MainActor
struct SavedPositionTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// The laptop alone, with Terminal on the first desktop and Slack on the second, Saved.
    func savedLaptop() throws -> Engine {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11, frame: WindowFrame(x: 100, y: 125, width: 600, height: 400)),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12, frame: WindowFrame(x: 0, y: 25, width: 756, height: 957)),
        ]
        let engine = engine()
        try engine.run("save")
        return engine
    }

    @Test func restorePutsAWindowBackAtItsSavedPositionAndSize() throws {
        let engine = try savedLaptop()
        world.place(501, at: WindowFrame(x: 700, y: 300, width: 300, height: 200))

        try engine.run("restore")

        #expect(world.window(501)?.frame == WindowFrame(x: 100, y: 125, width: 600, height: 400))
        #expect(world.window(502)?.frame == WindowFrame(x: 0, y: 25, width: 756, height: 957))
    }

    /// Docks to the Dell, keeps Terminal on the laptop but makes it bigger, puts Slack on the Dell, and Saves.
    func dock(_ engine: Engine) throws {
        world.displays = [
            .builtIn(desktops: [.regular(11, current: true), .regular(12)]),
            .dell(desktops: [.regular(21, current: true)]),
        ]
        world.move(502, to: 21)
        world.place(502, at: WindowFrame(x: 1512, y: 25, width: 1280, height: 1415))
        world.place(501, at: WindowFrame(x: 0, y: 25, width: 1512, height: 957))
        try engine.run("remember_display", ["display": "dell-uuid"])
        try engine.run("save")
    }

    @Test func savingWhileDockedLeavesTheLaptopPositionsUntouched() throws {
        let engine = try savedLaptop()
        try dock(engine)

        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.move(502, to: 12)
        try engine.run("restore")

        #expect(world.window(501)?.frame == WindowFrame(x: 100, y: 125, width: 600, height: 400))
        #expect(world.window(502)?.frame == WindowFrame(x: 0, y: 25, width: 756, height: 957))
    }

    @Test func restoreAppliesTheCurrentDisplaySetupsPosition() throws {
        let engine = try savedLaptop()
        try dock(engine)
        world.place(501, at: WindowFrame(x: 100, y: 125, width: 600, height: 400))
        world.place(502, at: WindowFrame(x: 2000, y: 200, width: 800, height: 600))

        try engine.run("restore")

        #expect(world.window(501)?.frame == WindowFrame(x: 0, y: 25, width: 1512, height: 957))
        #expect(world.window(502)?.frame == WindowFrame(x: 1512, y: 25, width: 1280, height: 1415))
    }

    @Test func aWindowWithoutASavedPositionKeepsItsSizeAndPositionWhenRestored() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]  // frame unreadable when Saved
        let engine = engine()
        try engine.run("save")
        world.move(501, to: 12)
        world.place(501, at: WindowFrame(x: 300, y: 200, width: 500, height: 300))

        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.window(501)?.frame == WindowFrame(x: 300, y: 200, width: 500, height: 300))
    }

    @Test func aSavedPositionSurvivesAResolutionChangeBecauseItIsRelativeToTheDisplay() throws {
        let engine = try savedLaptop()  // Terminal at (100, 125) 600×400 on a 1512×957 visible frame from (0, 25)

        // "More Space": the same laptop screen now shows 1800×1169, 25 of it the menu bar.
        world.displays[0].visibleFrame = WindowFrame(x: 0, y: 25, width: 1800, height: 1144)
        try engine.run("restore")

        #expect(world.window(501)?.frame == WindowFrame(x: 119, y: 145, width: 714, height: 478))
        #expect(engine.status().drift.isEmpty)
    }

    @Test func aWindowOnItsSpaceButAwayFromItsSavedPositionIsDrift() throws {
        let engine = try savedLaptop()
        world.place(501, at: WindowFrame(x: 101, y: 126, width: 600, height: 400))  // within a point or two: not Drift
        #expect(engine.status().drift.isEmpty)

        world.place(501, at: WindowFrame(x: 700, y: 300, width: 300, height: 200))

        let drift = engine.status().drift
        #expect(drift.map(\.kind) == [.position])
        #expect(drift.map(\.title) == ["zsh"])
        #expect(drift.map(\.space) == ["Terminal"])

        try engine.run("restore")
        #expect(engine.status().drift.isEmpty)
    }

    @Test func aWindowWithNoSavedPositionForThisDisplaySetupNeverDriftsByPosition() throws {
        let engine = try savedLaptop()
        world.displays.append(.dell(desktops: [.regular(21, current: true)]))
        try engine.run("remember_display", ["display": "dell-uuid"])
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "News", desktop: 21))
        try engine.run("save")  // Safari's frame couldn't be read, so it has no position here

        world.place(503, at: WindowFrame(x: 2000, y: 300, width: 900, height: 700))

        #expect(engine.status().drift.isEmpty)
    }

    @Test func savingOneWindowWhereItIsKeepsItsNewPosition() throws {
        let engine = try savedLaptop()
        world.place(501, at: WindowFrame(x: 700, y: 300, width: 300, height: 200))
        let zsh = try #require(engine.status().drift.first?.handle)

        try engine.run("save", ["window": zsh])

        #expect(engine.status().drift.isEmpty)
        try engine.run("restore")
        #expect(world.window(501)?.frame == WindowFrame(x: 700, y: 300, width: 300, height: 200))
    }

    @Test func aPositionMacOSWontApplyIsSoftDriftAndNotRetriedUntilTheWorldChanges() throws {
        let engine = try savedLaptop()
        world.place(501, at: WindowFrame(x: 700, y: 300, width: 300, height: 200))
        world.unresizableWindows = [501]

        let reply = engine.perform(CommandRequest(command: "restore"))

        #expect(reply.text.contains("saved position"))
        let status = engine.status()
        #expect(status.drift.isEmpty)
        #expect(status.softDrift.map(\.title) == ["zsh"])
        #expect(engine.perform(CommandRequest(command: "restore")).text.contains("Not retried"))

        world.unresizableWindows = []
        world.place(501, at: WindowFrame(x: 650, y: 300, width: 300, height: 200))  // the user nudges it: the world changed
        try engine.run("restore")
        #expect(world.window(501)?.frame == WindowFrame(x: 100, y: 125, width: 600, height: 400))
    }

    @Test func theLayoutRecordsPositionsPerDisplaySetupRelativeToTheDisplay() throws {
        let engine = try savedLaptop()
        try dock(engine)

        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
        let terminal = try #require(layout.assignments.first { $0.window.bundleID == "com.apple.Terminal" })
        #expect(terminal.frames.map(\.displaySetup) == [["built-in"], ["built-in", "dell-uuid"]])
        #expect(terminal.frame(in: ["built-in", "dell-uuid"]) == RelativeFrame(x: 0, y: 0, width: 1, height: 1))
        let slack = try #require(layout.assignments.first { $0.window.bundleID == "com.tinyspeck.slackmacgap" })
        #expect(slack.frame(in: ["built-in"]) == RelativeFrame(x: 0, y: 0, width: 0.5, height: 1))
        #expect(slack.frame(in: ["built-in", "dell-uuid"]) == RelativeFrame(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test func placementPutsAnAppearingWindowAtItsSavedPositionOnItsSpace() throws {
        let engine = try savedLaptop()
        world.closeWindow(502)

        // Slack reopens on the current desktop at the size it likes.
        world.openWindow(.app(503, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 11, frame: WindowFrame(x: 200, y: 200, width: 900, height: 700)))

        #expect(world.desktop(of: 503) == 12)
        #expect(world.window(503)?.frame == WindowFrame(x: 0, y: 25, width: 756, height: 957))
        #expect(engine.status().drift.isEmpty)
    }

    @Test func placementPutsAnAppearingWindowAlreadyOnItsSpaceAtItsSavedPosition() throws {
        let engine = try savedLaptop()
        world.closeWindow(501)

        world.openWindow(.app(503, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11, frame: WindowFrame(x: 200, y: 200, width: 900, height: 700)))

        #expect(world.window(503)?.frame == WindowFrame(x: 100, y: 125, width: 600, height: 400))
        #expect(engine.status().drift.isEmpty)
    }
}
