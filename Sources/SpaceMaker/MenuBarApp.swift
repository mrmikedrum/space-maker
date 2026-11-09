import AppKit
import ServiceManagement
import SpaceMakerCore

/// The menu bar shell: a thin client of the engine. It owns the command socket the MCP server talks to.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let skyLight = SkyLight()
    private lazy var windowSystem = MacWindowSystem(skyLight: skyLight)
    private lazy var engine = Engine(windowSystem: windowSystem, layoutURL: LayoutFile.defaultURL)
    private var statusItem: NSStatusItem?
    private var server: CommandServer?
    private var layoutWatcher: LayoutWatcher?
    private var doctorFailed = false
    /// The port has no event for a window the user moves, so Drift is also checked on a timer.
    private var driftTimer: Timer?

    static func makeDoctor(skyLight: SkyLight, windowSystem: MacWindowSystem? = nil) -> Doctor {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let helper = executable.deletingLastPathComponent().appendingPathComponent("space-maker-move-helper")
        return StandardDoctor.make(
            skyLight: skyLight, windowSystem: windowSystem, helperExecutable: helper,
            logsDirectory: StandardDoctor.defaultLogsDirectory
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = engine
        do {
            server = try CommandServer.start(socketPath: CommandSocket.defaultPath) { [weak self] request in
                // The Doctor is asynchronous (it awaits ScreenCaptureKit), so it's served here rather than by the engine.
                if request.command == "doctor", let self { return CommandReply(text: await self.runDoctorForReport()) }
                return await engine.perform(request)
            }
        } catch CommandRelayError.alreadyRunning {
            log("Another Space Maker is already running; quitting.")
            NSApp.terminate(nil)
            return
        } catch {
            log("Couldn't open the command socket, so MCP won't work: \(error)")
        }

        layoutWatcher = LayoutWatcher(url: LayoutFile.defaultURL) { [weak self] in
            self?.engine.layoutFileChanged()
            self?.refreshIcon()
        }
        engine.onChange = { [weak self] in self?.refreshIcon() }
        registerLoginItem()
        installStatusItem()
        driftTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        // Doctor at launch, once the menu bar item is showing.
        Task { _ = await self.runDoctor() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: - Menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.icon(problem: false)
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshIcon()
    }

    /// Rebuilt each time it opens, so Drift is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = Log.timed(Log.menu, "menu status") { engine.status() }
        showIcon(driftCount: status.drift.count)
        menu.removeAllItems()
        menu.addItem(menuItem("Save All", #selector(saveAllClicked)))
        menu.addItem(menuItem("Restore All", #selector(restoreAllClicked)))
        menu.addItem(menuItem("Pin or Unpin Frontmost Window", #selector(pinFrontmostClicked)))
        menu.addItem(menuItem(status.isPaused ? "Resume Automatic Placement and Restore" : "Pause Automatic Placement and Restore", #selector(pauseClicked)))

        if !status.drift.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("Drift"))
            for drift in status.drift { menu.addItem(driftItem(drift)) }
        }
        if !status.softDrift.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("Soft Drift (only you can fix)"))
            for soft in status.softDrift {
                let window = soft.title.map { "\(soft.app ?? "") “\($0)”: " } ?? ""
                let item = NSMenuItem(title: window + soft.problem, action: nil, keyEquivalent: "")
                item.toolTip = soft.hint
                menu.addItem(item)
                let hint = NSMenuItem(title: soft.hint, action: nil, keyEquivalent: "")
                hint.indentationLevel = 1
                hint.isEnabled = false
                menu.addItem(hint)
            }
        }

        if !status.guestDisplays.isEmpty {
            menu.addItem(.separator())
            for guest in status.guestDisplays {
                let title = status.guestDisplays.count == 1 ? "Remember This Display (\(guest.name))" : "Remember \(guest.name)"
                let item = menuItem(title, #selector(rememberDisplayClicked))
                item.representedObject = guest.id
                menu.addItem(item)
            }
        }

        let spaces = status.displaySetup.flatMap(\.desktops).compactMap(\.space)
        if !spaces.isEmpty {
            menu.addItem(.separator())
            let rename = NSMenuItem(title: "Rename Space", action: nil, keyEquivalent: "")
            let names = NSMenu()
            for space in spaces {
                let item = menuItem("\(space)…", #selector(renameSpaceClicked))
                item.representedObject = space
                names.addItem(item)
            }
            rename.submenu = names
            menu.addItem(rename)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Run Doctor", #selector(doctorClicked)))
        menu.addItem(menuItem("Open Layout File", #selector(openLayoutClicked)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Space Maker", #selector(quitClicked), key: "q"))
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A drifted window, with Restore, Save and Ignore.
    private func driftItem(_ drift: DriftStatus) -> NSMenuItem {
        let label = switch drift.kind {
        case .new: "New: \(drift.app) “\(drift.title)”"
        case .moved: "Moved: \(drift.app) “\(drift.title)” (belongs on \(drift.space ?? "?"))"
        case .position: "Out of place: \(drift.app) “\(drift.title)” (away from its saved position)"
        }
        let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        let actions = NSMenu()
        if drift.kind != .new {
            actions.addItem(windowItem("Restore", #selector(restoreWindowClicked), drift.handle))
        }
        actions.addItem(windowItem("Save Where It Is", #selector(saveWindowClicked), drift.handle))
        actions.addItem(windowItem("Ignore This Window", #selector(ignoreWindowClicked), drift.handle))
        actions.addItem(windowItem("Always Ignore \(drift.app)", #selector(ignoreAppClicked), drift.handle))
        item.submenu = actions
        return item
    }

    private func windowItem(_ title: String, _ action: Selector, _ handle: String) -> NSMenuItem {
        let item = menuItem(title, action)
        item.representedObject = handle
        return item
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func restoreWindowClicked(_ sender: NSMenuItem) {
        perform(.restoreWindow(handle: sender.representedObject as? String ?? ""), failureTitle: "Space Maker couldn't Restore that window")
    }

    @objc private func saveWindowClicked(_ sender: NSMenuItem) {
        perform(.saveWindow(handle: sender.representedObject as? String ?? ""), failureTitle: "Space Maker couldn't Save that window")
    }

    @objc private func ignoreWindowClicked(_ sender: NSMenuItem) {
        perform(.ignoreWindow(handle: sender.representedObject as? String ?? ""), failureTitle: "Space Maker couldn't Ignore that window")
    }

    @objc private func ignoreAppClicked(_ sender: NSMenuItem) {
        perform(.ignoreApp(ofWindow: sender.representedObject as? String ?? ""), failureTitle: "Space Maker couldn't Ignore that app")
    }

    @objc private func rememberDisplayClicked(_ sender: NSMenuItem) {
        perform(.rememberDisplay(id: sender.representedObject as? String ?? ""), failureTitle: "Space Maker couldn't remember that display")
    }

    /// Asks for the Space's new name in a simple prompt, then renames it as `rename_space` would.
    @objc private func renameSpaceClicked(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Rename “\(space)”"
        alert.informativeText = "Its windows stay assigned to it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = space
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(.renameSpace(space, to: field.stringValue), failureTitle: "Space Maker couldn't rename “\(space)”")
    }

    @objc private func saveAllClicked() {
        perform(.saveAll, failureTitle: "Space Maker couldn't Save")
    }

    @objc private func restoreAllClicked() {
        perform(.restoreAll, failureTitle: "Space Maker couldn't Restore everything")
    }

    /// Runs a command through the engine, as MCP would, and only speaks up when something went wrong.
    private func perform(_ action: MenuAction, failureTitle: String) {
        let reply = engine.perform(action)
        refreshIcon()
        guard reply.isError || reply.text.contains("Couldn't") else { return }
        let alert = NSAlert()
        alert.messageText = failureTitle
        alert.informativeText = reply.text
        NSApp.activate()
        alert.runModal()
    }

    @objc private func pauseClicked() {
        perform(.togglePause, failureTitle: "Couldn't pause or resume")
    }

    @objc private func pinFrontmostClicked() {
        let reply = engine.togglePinOfFrontmostWindow()
        guard reply.isError else { return }
        let alert = NSAlert()
        alert.messageText = "Space Maker couldn't Pin"
        alert.informativeText = reply.text
        NSApp.activate()
        alert.runModal()
    }

    @objc private func doctorClicked() {
        Task { if let report = await runDoctor() { NSWorkspace.shared.open(report) } }
    }

    @objc private func openLayoutClicked() {
        let layout = LayoutFile.defaultURL
        if FileManager.default.fileExists(atPath: layout.path) {
            NSWorkspace.shared.open(layout)
        } else {
            // No Layout until the first Save: show where it will be.
            let folder = layout.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: - Doctor

    /// The Doctor run in progress, if any: overlapping requests (launch, menu, MCP) share it rather than racing
    /// each other's reports and feature switches.
    private var doctorRun: Task<URL?, Never>?

    /// Runs the Doctor (or joins the run in progress), shows a warning icon if any check failed, and returns
    /// the report's location.
    private func runDoctor() async -> URL? {
        if let doctorRun { return await doctorRun.value }
        let run = Task { await runDoctorOnce() }
        doctorRun = run
        defer { doctorRun = nil }
        return await run.value
    }

    private func runDoctorOnce() async -> URL? {
        let doctor = Self.makeDoctor(skyLight: skyLight, windowSystem: windowSystem)
        do {
            let results = try await doctor.run()
            engine.setMovesDisabled(because: StandardDoctor.moveFailure(in: results))
            showDoctorFailed(results.contains(where: \.failed))
            updatePins(from: results)
            return doctor.reportURL
        } catch {
            log("The Doctor couldn't write its report: \(error)")
            showDoctorFailed(true)
            return nil
        }
    }

    /// A failed screen capture check disables only Pins.
    private func updatePins(from results: [CheckResult]) {
        guard let capture = results.first(where: { $0.title == StandardDoctor.screenCaptureTitle }) else { return }
        if capture.failed {
            engine.disablePins(because: capture.outcome.summary)
        } else {
            engine.enablePins()
        }
    }

    private func runDoctorForReport() async -> String {
        guard let report = await runDoctor() else { return "The Doctor couldn't write its report to \(StandardDoctor.defaultLogsDirectory.path)." }
        return (try? String(contentsOf: report, encoding: .utf8)) ?? "The Doctor wrote its report to \(report.path) but it couldn't be read back."
    }

    private func showDoctorFailed(_ failed: Bool) {
        doctorFailed = failed
        refreshIcon()
    }

    private func refreshIcon() {
        guard statusItem != nil else { return }
        showIcon(driftCount: engine.status().drift.count)
    }

    /// A warning symbol when the Doctor failed, otherwise a dot and count for Drift, otherwise plain.
    /// The Doctor's warning wins. Soft Drift never lights the dot. Icons are always template images, never
    /// tinted, so they follow the menu bar's light or dark appearance like every other menu bar icon.
    private func showIcon(driftCount: Int) {
        guard let button = statusItem?.button else { return }
        button.image = Self.icon(problem: doctorFailed)
        if doctorFailed {
            button.title = ""
            button.toolTip = "Space Maker: the Doctor found a problem"
        } else if driftCount > 0 {
            button.title = "●\(driftCount)"
            button.toolTip = "Space Maker: \(driftCount) window\(driftCount == 1 ? "" : "s") drifted"
        } else {
            button.title = ""
            button.toolTip = "Space Maker"
        }
        if engine.isPaused { button.toolTip = (button.toolTip ?? "Space Maker") + " (automatic placement and restore paused)" }
    }

    private static func icon(problem: Bool) -> NSImage? {
        let name = problem ? "exclamationmark.triangle" : "rectangle.3.group"
        let description = problem ? "Space Maker: the Doctor found a problem" : "Space Maker"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    // MARK: - Login item

    private func registerLoginItem() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            log("Couldn't register to launch at login (\(service.status.rawValue)): \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        Log.menu.error("\(message, privacy: .public)")
    }
}
