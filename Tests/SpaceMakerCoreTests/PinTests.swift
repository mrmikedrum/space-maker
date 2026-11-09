import SpaceMakerCore
import Testing

@MainActor
struct PinTests {
    let world = FakeWindowSystem()

    init() {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .regular, isCurrent: false),
            .init(id: 13, kind: .fullscreen, isCurrent: false),
        ])]
        world.windows = [
            .app(501, "com.apple.Notes", "Notes", title: "List", desktop: 11),
            .chrome(502, profile: .known("Work"), title: "Build", desktop: 12),
            .app(503, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 13, fullscreen: true),
        ]
    }

    /// Issues handles the way an agent gets them: from `status`.
    func engineWithHandles() -> Engine {
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        _ = engine.status()  // w1 = Notes, w2 = Chrome, w3 = Terminal
        return engine
    }

    @Test func pinningAWindowOnAnotherSpaceShowsItsMirror() {
        let engine = engineWithHandles()

        let reply = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))

        #expect(!reply.isError)
        #expect(world.mirrors == [502: .shown])
    }

    @Test func pinningAWindowVisibleOnTheActiveSpaceKeepsItsMirrorHidden() {
        let engine = engineWithHandles()

        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w1"]))

        #expect(world.mirrors == [501: .hidden])
    }

    @Test func aMirrorHidesWhileItsWindowsSpaceIsActiveAndShowsAgainWhenTheUserLeaves() {
        let engine = engineWithHandles()
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))

        world.switchTo(desktop: 12)
        #expect(world.mirrors == [502: .hidden])

        world.switchTo(desktop: 11)
        #expect(world.mirrors == [502: .shown])
    }

    @Test func clickingAMirrorSwitchesToTheWindowsSpaceAndFocusesIt() {
        let engine = engineWithHandles()
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))

        world.clickMirror(of: 502)

        #expect(world.focusedWindow == 502)
        #expect(world.currentDesktops == [12])
        #expect(world.mirrors == [502: .hidden])
    }

    @Test func closingTheWindowRemovesItsPin() {
        let engine = engineWithHandles()
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))

        world.closeWindow(502)
        world.switchTo(desktop: 12)

        #expect(world.mirrors.isEmpty)
        #expect(engine.status().pins.isEmpty)
    }

    @Test func pinningAFullscreenWindowIsRefusedWithAReason() {
        let engine = engineWithHandles()

        let reply = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w3"]))

        #expect(reply.isError)
        #expect(reply.text == "Terminal \"zsh\" is fullscreen, and a fullscreen window can't be pinned. Take it out of fullscreen first.")
        #expect(world.mirrors.isEmpty)
        #expect(engine.status().pins.isEmpty)
    }

    @Test func severalWindowsCanBePinnedAndUnpinnedIndependently() {
        world.windows.append(.app(504, "com.apple.Mail", "Mail", title: "Inbox", desktop: 12))
        let engine = engineWithHandles()  // w4 = Mail
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w1"]))
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w4"]))
        #expect(engine.status().pins == ["w1", "w2", "w4"])
        #expect(world.mirrors == [501: .hidden, 502: .shown, 504: .shown])

        let reply = engine.perform(CommandRequest(command: "unpin", arguments: ["window": "w2"]))

        #expect(!reply.isError)
        #expect(engine.status().pins == ["w1", "w4"])
        #expect(world.mirrors == [501: .hidden, 504: .shown])
        world.switchTo(desktop: 12)
        #expect(world.mirrors == [501: .shown, 504: .hidden])
    }

    @Test func unpinningAWindowThatIsntPinnedSaysSo() {
        let engine = engineWithHandles()

        let reply = engine.perform(CommandRequest(command: "unpin", arguments: ["window": "w1"]))

        #expect(reply.isError)
        #expect(reply.text == "Notes \"List\" isn't pinned.")
    }

    @Test func theMenuBarPinsTheFrontmostWindowAndUnpinsItOnTheNextClick() {
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        world.frontmostWindow = 501

        let pinned = engine.togglePinOfFrontmostWindow()
        #expect(!pinned.isError)
        #expect(world.mirrors == [501: .hidden])

        let unpinned = engine.togglePinOfFrontmostWindow()
        #expect(!unpinned.isError)
        #expect(world.mirrors.isEmpty)
    }

    @Test func theMenuBarSaysSoWhenNoWindowIsFrontmost() {
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        world.frontmostWindow = nil

        let reply = engine.togglePinOfFrontmostWindow()

        #expect(reply.isError)
        #expect(reply.text == "No window is frontmost.")
    }

    @Test func whenTheDoctorFindsScreenCaptureBrokenPinIsDisabledAndSaysWhy() {
        let engine = engineWithHandles()
        _ = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))

        engine.disablePins(because: "Screen Recording isn't granted.")

        #expect(world.mirrors.isEmpty)
        #expect(engine.status().pins.isEmpty)
        let reply = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w1"]))
        #expect(reply.isError)
        #expect(reply.text == "Pins are disabled because the Doctor's screen capture check failed: Screen Recording isn't granted.")
        #expect(world.mirrors.isEmpty)
    }

    @Test func pinWorksAgainOnceTheDoctorPasses() {
        let engine = engineWithHandles()
        engine.disablePins(because: "Screen Recording isn't granted.")

        engine.enablePins()
        let reply = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w2"]))

        #expect(!reply.isError)
        #expect(world.mirrors == [502: .shown])
    }

    @Test func pinningAnUnknownHandleSaysSo() {
        let engine = engineWithHandles()

        let reply = engine.perform(CommandRequest(command: "pin", arguments: ["window": "w9"]))

        #expect(reply.isError)
        #expect(reply.text == "No open window has handle \"w9\". Run status for current handles.")
    }
}
