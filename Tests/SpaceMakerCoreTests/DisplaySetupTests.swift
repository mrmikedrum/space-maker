import Foundation
import SpaceMakerCore
import Testing

/// Display Setups and Guest Displays: "laptop alone" versus "laptop plus the Dell", undock and redock.
@MainActor
struct DisplaySetupTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    @Test func rememberingADisplayMakesANewDisplaySetupThatRestoresNothingUntilSaved() throws {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .regular, isCurrent: false),
        ])]
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")

        world.displays.append(.external("dell-uuid", name: "DELL U2723QE", desktops: [.init(id: 21, kind: .regular, isCurrent: true)]))
        try engine.run("remember_display", ["display": "dell-uuid"])
        world.move(501, to: 12)
        let reply = engine.perform(CommandRequest(command: "restore"))

        #expect(reply.isError && reply.text.contains("Display Setup"))
        #expect(world.desktop(of: 501) == 12)
        let status = engine.status()
        #expect(status.displaySetup.map(\.id) == ["built-in", "dell-uuid"])
        #expect(status.guestDisplays.isEmpty)
        #expect(status.softDrift.contains { $0.problem.contains("Display Setup") })
    }

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

    @Test func afterUndockingRestorePutsWindowsInTheLaptopSlotsWhereverMacOSMergedTheDesktops() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        world.undock("dell-uuid")  // the laptop now has 11 (with Safari), 12, 22 (Music), 23
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 12)
        #expect(world.desktop(of: 503) == 22)
        #expect(world.desktop(of: 504) == 23)
        #expect(engine.status().drift.isEmpty)
    }

    @Test func afterARedockInShuffledOrderRestorePutsWindowsInTheDockedSlots() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        world.undock("dell-uuid")
        try engine.run("restore")  // laptop: 11 Terminal, 12 Slack, 22 Safari, 23 Music

        // macOS brings the Dell's desktops back out of order, and makes a new one for the desktop it collapsed.
        world.redock(.dell(desktops: [.regular(23, current: true), .regular(22), .regular(24)]))
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 12)
        #expect(world.desktop(of: 503) == 23)
        #expect(world.desktop(of: 504) == 22)
        #expect(engine.status().drift.isEmpty)
    }

    @Test func aDisplayWithTooFewDesktopsIsSoftDriftAndItsOtherSpacesAreStillRestored() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        world.undock("dell-uuid")
        try engine.run("restore")

        world.redock(.dell(desktops: [.regular(23, current: true)]))  // the Dell comes back with one desktop of three
        try engine.run("restore")

        #expect(world.desktop(of: 503) == 23)  // Safari's Space is the Dell's first
        let softDrift = engine.status().softDrift.map(\.problem)
        #expect(softDrift.contains { $0.contains("Music") })
        #expect(softDrift.contains { $0.contains("Desktop") })
    }

    @Test func extraDesktopsBeyondTheArrangementAreLeftAlone() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        world.displays[1].desktops.append(.regular(25))
        world.windows.append(.app(505, "com.apple.Notes", "Notes", title: "Scratch", desktop: 25))
        world.move(501, to: 25)

        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 505) == 25)
        #expect(engine.status().softDrift.isEmpty)
    }

    @Test func aGuestDisplayIsLeftOutOfTheDisplaySetupAndItsWindowsAreDrift() throws {
        world.displays = [.builtIn(desktops: [.regular(11, current: true), .regular(12)])]
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.apple.Keynote", "Keynote", title: "Talk", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")
        let laptop = try savedLayout().displaySetups

        // AirPlay to a TV; the user moves Keynote onto it, and opens a new window there.
        world.displays.append(.external("airplay-uuid", name: "Living Room TV", desktops: [.regular(31, current: true)]))
        world.move(502, to: 31)
        world.windows.append(.app(503, "com.apple.Preview", "Preview", title: "Notes.pdf", desktop: 31))

        let status = engine.status()
        #expect(status.displaySetup.map(\.id) == ["built-in"])
        #expect(status.guestDisplays.map(\.id) == ["airplay-uuid"])
        #expect(status.guestDisplays[0].desktops.allSatisfy { $0.space == nil })
        #expect(status.drift.map(\.kind) == [.moved, .new])
        #expect(status.drift.map(\.app) == ["Keynote", "Preview"])

        try engine.run("save")  // still the laptop's Display Setup; Keynote keeps its Assignment
        #expect(try savedLayout().displaySetups == laptop)
        try engine.run("restore")
        #expect(world.desktop(of: 502) == 12)
        #expect(world.desktop(of: 503) == 31)
    }

    @Test func savingOnOneDisplaySetupLeavesTheOthersArrangementUntouched() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)
        let saved = try savedLayout().displaySetups

        #expect(saved.map(\.displays) == [["built-in"], ["built-in", "dell-uuid"]])
        #expect(saved[0].arrangement == [DisplayArrangement(display: "built-in", spaces: ["Terminal", "Slack", "Safari", "Music"])])
        #expect(saved[1].arrangement == [
            DisplayArrangement(display: "built-in", spaces: ["Terminal", "Slack"]),
            DisplayArrangement(display: "dell-uuid", spaces: ["Safari", "Music", "Desktop"]),
        ])

        // Docked, the user swaps Safari and Music and Saves: only the docked Arrangement changes.
        world.move(503, to: 22)
        world.move(504, to: 21)
        try engine.run("save")
        let resaved = try savedLayout().displaySetups
        #expect(resaved[0] == saved[0])
        #expect(resaved[1].arrangement[1].spaces == ["Music", "Safari", "Desktop"])
    }

    @Test func aRememberedDisplayWithANewUUIDIsRecognisedByVendorModelAndSerial() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        // WindowServer hands the same Dell a different UUID.
        world.displays[1] = .dell(id: "dell-uuid-2", desktops: [.regular(21, current: true), .regular(22), .regular(23)])
        world.move(503, to: 22)
        try engine.run("restore")

        let status = engine.status()
        #expect(status.guestDisplays.isEmpty)
        #expect(status.displaySetup.map(\.id) == ["built-in", "dell-uuid"])
        #expect(world.desktop(of: 503) == 21)
    }

    @Test func anotherMonitorOfTheSameModelIsAGuestDisplay() throws {
        let engine = engine()
        try savedLaptopThenDocked(engine)

        world.displays[1] = .external("other-uuid", hardwareID: "4268:41234:999", name: "DELL U2723QE", desktops: [.regular(41, current: true)])

        let status = engine.status()
        #expect(status.guestDisplays.map(\.id) == ["other-uuid"])
        #expect(status.displaySetup.map(\.id) == ["built-in"])  // so it's the laptop's Display Setup
    }

    @Test func aLayoutWrittenBeforeDisplaysCouldBeRememberedStillLoads() throws {
        try FileManager.default.createDirectory(at: layoutURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "assignments" : [ { "space" : "Code", "window" : { "bundleID" : "com.apple.Terminal", "title" : "zsh" } } ],
          "displaySetups" : [ { "arrangement" : [ { "display" : "built-in", "spaces" : [ "Code", "Web" ] } ], "displays" : [ "built-in" ] } ],
          "spaces" : [ "Code", "Web" ],
          "version" : 1
        }
        """.write(to: layoutURL, atomically: true, encoding: .utf8)
        world.displays = [
            .builtIn(desktops: [.regular(11, current: true), .regular(12)]),
            .dell(desktops: [.regular(21, current: true)]),
        ]
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 12)]
        let engine = engine()

        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(engine.status().guestDisplays.map(\.id) == ["dell-uuid"])
        try engine.run("remember_display")  // the only Guest Display
        #expect(try savedLayout().knownDisplays == [KnownDisplay(id: "dell-uuid", hardwareID: "4268:41234:808464432", name: "DELL U2723QE")])
    }

    func savedLayout() throws -> Layout {
        try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
    }
}

extension WindowSystemDisplay {
    static func dell(id: String = "dell-uuid", desktops: [WindowSystemDesktop]) -> Self {
        .external(id, hardwareID: "4268:41234:808464432", name: "DELL U2723QE", desktops: desktops)
    }
}
