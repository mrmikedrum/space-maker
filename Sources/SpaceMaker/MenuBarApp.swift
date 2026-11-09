import AppKit
import ServiceManagement
import SpaceMakerCore

/// The menu bar shell: a thin client of the engine. It owns the command socket the MCP server talks to.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let skyLight = SkyLight()
    private lazy var windowSystem = MacWindowSystem(skyLight: skyLight)
    private lazy var engine = Engine(windowSystem: windowSystem, layoutURL: LayoutFile.defaultURL) { [unowned self] in self.runDoctorForReport() }
    private var statusItem: NSStatusItem?
    private var server: CommandServer?
    private var layoutWatcher: LayoutWatcher?
    private var doctorFailed = false
    /// Until the port delivers window events, Drift is checked on a timer.
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
            server = try CommandServer.start(socketPath: CommandSocket.defaultPath) { request in
                await engine.perform(request)
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
        registerLoginItem()
        installStatusItem()
        driftTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        // Doctor at launch, once the menu bar item is showing.
        DispatchQueue.main.async { _ = self.runDoctor() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: - Menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Space Maker")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshIcon()
    }

    /// Rebuilt each time it opens, so Drift is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = engine.status()
        showIcon(driftCount: status.drift.count)
        menu.removeAllItems()
        menu.addItem(menuItem("Save All", #selector(saveAllClicked)))
        menu.addItem(menuItem("Restore All", #selector(restoreAllClicked)))

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
        }
        let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        let actions = NSMenu()
        if drift.kind == .moved {
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
        perform("restore", ["window": sender.representedObject as? String ?? ""], failureTitle: "Space Maker couldn't Restore that window")
    }

    @objc private func saveWindowClicked(_ sender: NSMenuItem) {
        perform("save", ["window": sender.representedObject as? String ?? ""], failureTitle: "Space Maker couldn't Save that window")
    }

    @objc private func ignoreWindowClicked(_ sender: NSMenuItem) {
        perform("ignore", ["window": sender.representedObject as? String ?? ""], failureTitle: "Space Maker couldn't Ignore that window")
    }

    @objc private func ignoreAppClicked(_ sender: NSMenuItem) {
        perform("ignore", ["window": sender.representedObject as? String ?? "", "app": "true"], failureTitle: "Space Maker couldn't Ignore that app")
    }

    @objc private func saveAllClicked() {
        perform("save", failureTitle: "Space Maker couldn't Save")
    }

    @objc private func restoreAllClicked() {
        perform("restore", failureTitle: "Space Maker couldn't Restore everything")
    }

    /// Runs a command through the engine, as MCP would, and only speaks up when something went wrong.
    private func perform(_ command: String, _ arguments: [String: String] = [:], failureTitle: String) {
        let reply = engine.perform(CommandRequest(command: command, arguments: arguments))
        refreshIcon()
        guard reply.isError || reply.text.contains("Couldn't") else { return }
        let alert = NSAlert()
        alert.messageText = failureTitle
        alert.informativeText = reply.text
        NSApp.activate()
        alert.runModal()
    }

    @objc private func doctorClicked() {
        if let report = runDoctor() { NSWorkspace.shared.open(report) }
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

    /// Runs the Doctor, turns the icon red if any check failed, and returns the report's location.
    private func runDoctor() -> URL? {
        let doctor = Self.makeDoctor(skyLight: skyLight, windowSystem: windowSystem)
        do {
            let results = try doctor.run()
            engine.setMovesDisabled(because: StandardDoctor.moveFailure(in: results))
            showDoctorFailed(results.contains(where: \.failed))
            return doctor.reportURL
        } catch {
            log("The Doctor couldn't write its report: \(error)")
            showDoctorFailed(true)
            return nil
        }
    }

    private func runDoctorForReport() -> String {
        guard let report = runDoctor() else { return "The Doctor couldn't write its report to \(StandardDoctor.defaultLogsDirectory.path)." }
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

    /// Red when the Doctor failed, otherwise a dot and count for Drift, otherwise plain. Red wins.
    /// Soft Drift never lights the dot.
    private func showIcon(driftCount: Int) {
        guard let button = statusItem?.button else { return }
        if doctorFailed {
            button.contentTintColor = .systemRed
            button.title = ""
            button.toolTip = "Space Maker: the Doctor found a problem"
        } else if driftCount > 0 {
            button.contentTintColor = nil
            button.title = "●\(driftCount)"
            button.toolTip = "Space Maker: \(driftCount) window\(driftCount == 1 ? "" : "s") drifted"
        } else {
            button.contentTintColor = nil
            button.title = ""
            button.toolTip = "Space Maker"
        }
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
        FileHandle.standardError.write(Data("Space Maker: \(message)\n".utf8))
    }
}
