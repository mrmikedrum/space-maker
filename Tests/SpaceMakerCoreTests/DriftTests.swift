import Foundation
import SpaceMakerCore
import Testing

@MainActor
struct DriftTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// Three regular desktops on the built-in display, saved with a Terminal window on the first.
    func savedWorld() throws -> Engine {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .regular, isCurrent: false),
            .init(id: 13, kind: .regular, isCurrent: false),
        ])]
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")
        return engine
    }

    func handle(of windowID: UInt32, _ engine: Engine) throws -> String {
        let title = world.windows.first { $0.id == windowID }.map(\.title)
        return try #require(engine.status().windows.first { $0.title == title }?.handle)
    }

    @Test func nothingDriftsRightAfterASave() throws {
        let engine = try savedWorld()

        #expect(engine.status().drift == [])
    }

    @Test func aWindowAwayFromItsAssignmentIsDrift() throws {
        let engine = try savedWorld()
        world.move(501, to: 13)

        let drift = engine.status().drift
        #expect(drift.map(\.kind) == [.moved])
        #expect(drift.map(\.title) == ["zsh"])
        #expect(drift.map(\.space) == ["Terminal"])
    }

    @Test func aNewWindowThatMatchesNoAssignmentIsDrift() throws {
        let engine = try savedWorld()
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "News", desktop: 12))

        let drift = engine.status().drift
        #expect(drift.map(\.kind) == [.new])
        #expect(drift.map(\.title) == ["News"])
        #expect(drift.map(\.space) == [nil])
    }

    @Test func panelsDialogsAndSheetsNeverDrift() throws {
        let engine = try savedWorld()
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "Downloads", desktop: 12, isStandard: false))
        world.windows.append(.app(504, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 13, isStandard: false))

        #expect(engine.status().drift == [])
    }

    @Test func ignoringAWindowRemovesItsDriftUntilItCloses() throws {
        let engine = try savedWorld()
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "News", desktop: 12))
        let news = try handle(of: 503, engine)

        try engine.run("ignore", ["window": news])
        #expect(engine.status().drift == [])

        // The window closes, and a window like it opens: it's new again.
        world.windows.removeAll { $0.id == 503 }
        #expect(engine.status().drift == [])
        world.windows.append(.app(504, "com.apple.Safari", "Safari", title: "News", desktop: 12))
        #expect(engine.status().drift.map(\.title) == ["News"])
    }

    @Test func anIgnoredWindowIsLeftOutOfSaveAndRestore() throws {
        let engine = try savedWorld()
        let terminal = try handle(of: 501, engine)
        try engine.run("ignore", ["window": terminal])
        world.move(501, to: 13)

        try engine.run("restore")
        #expect(world.desktop(of: 501) == 13)
        #expect(engine.status().drift == [])

        try engine.run("save")
        let saved = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
        #expect(saved.assignments.map(\.space) == ["Terminal", "Slack"])  // the old Assignment stays as it was
    }

    @Test func ignoringAnAppAlwaysPersistsAcrossReloads() throws {
        let engine = try savedWorld()
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "News", desktop: 12))
        try engine.run("ignore", ["window": try handle(of: 503, engine), "app": "true"])

        // Space Maker relaunches, and Safari opens another window.
        let relaunched = self.engine()
        world.windows.append(.app(504, "com.apple.Safari", "Safari", title: "Mail", desktop: 13))

        #expect(relaunched.status().drift == [])
        let saved = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
        #expect(saved.ignoredApps == ["com.apple.Safari"])
    }

    @Test func aLayoutWrittenBeforeIgnoreExistedStillLoads() throws {
        _ = try savedWorld()
        let old = try String(contentsOf: layoutURL, encoding: .utf8)
            .replacingOccurrences(of: "\"ignoredApps\" : [\n\n  ],\n  ", with: "")
        #expect(!old.contains("ignoredApps"))
        try old.write(to: layoutURL, atomically: true, encoding: .utf8)

        world.move(501, to: 13)
        #expect(engine().status().drift.map(\.title) == ["zsh"])
    }

    @Test func aWindowRestoreCantMoveBecomesSoftDriftWithAHint() throws {
        let engine = try savedWorld()
        world.move(501, to: 13)
        world.unmovableWindows = [501]

        try engine.run("restore")

        let status = engine.status()
        #expect(status.drift == [])
        #expect(status.softDrift.map(\.title) == ["zsh"])
        #expect(status.softDrift.allSatisfy { !$0.hint.isEmpty })
    }

    @Test func softDriftIsNotRetriedUntilTheWorldChanges() throws {
        let engine = try savedWorld()
        world.move(501, to: 13)
        world.unmovableWindows = [501]
        try engine.run("restore")

        // macOS would now allow the move, but nothing Space Maker can see has changed: no retry.
        world.unmovableWindows = []
        try engine.run("restore")
        #expect(world.desktop(of: 501) == 13)

        // A window opens: the world changed, so it's Drift again and Restore tries again.
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "News", desktop: 12))
        #expect(engine.status().softDrift == [])
        #expect(engine.status().drift.map(\.title).contains("zsh"))
        try engine.run("restore")
        #expect(world.desktop(of: 501) == 11)
    }

    @Test func aSpaceWithNoDesktopIsSoftDrift() throws {
        let engine = try savedWorld()
        try engine.run("move_window", ["window": try handle(of: 502, engine), "space": "Desktop", "save": "true"])

        // The user deletes the third desktop in Mission Control; macOS moves its window to the first.
        world.displays[0].desktops.removeLast()
        world.move(502, to: 11)

        let status = engine.status()
        #expect(status.drift == [])
        #expect(status.softDrift.count == 1)
        #expect(status.softDrift[0].problem.contains("Desktop"))
        #expect(!status.softDrift[0].hint.isEmpty)
    }

    @Test func savingOneDriftedWindowKeepsItWhereItIsAndLeavesTheRestAlone() throws {
        let engine = try savedWorld()
        world.move(501, to: 13)
        world.move(502, to: 13)
        world.windows.append(.app(503, "com.apple.Safari", "Safari", title: "News", desktop: 12))

        try engine.run("save", ["window": try handle(of: 501, engine)])
        try engine.run("save", ["window": try handle(of: 503, engine)])

        let drift = engine.status().drift
        #expect(drift.map(\.title) == ["general"])
        try engine.run("restore")
        #expect(world.desktop(of: 501) == 13)
        #expect(world.desktop(of: 502) == 12)
    }
}
