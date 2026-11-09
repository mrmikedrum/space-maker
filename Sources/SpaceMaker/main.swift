import AppKit
import SpaceMakerCore

let usage = """
usage: SpaceMaker [--doctor]

  (no arguments)  Run as the menu bar app, serving commands to the MCP server.
  --doctor        Run the Doctor, write a report to ~/Library/Logs/SpaceMaker/, print its path,
                  and exit 0 if every check passed (1 otherwise).

Run the Doctor through scripts/doctor.sh so macOS attributes permissions to Space Maker itself.
"""

let arguments = CommandLine.arguments.dropFirst()

MainActor.assumeIsolated {
    _ = NSApplication.shared  // SkyLight expects an AppKit connection to WindowServer.

    if arguments.isEmpty {
        let delegate = MenuBarApp()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
        exit(0)
    }

    guard arguments.contains("--doctor") else {
        print(usage)
        exit(64)
    }
    let doctor = MenuBarApp.makeDoctor(skyLight: SkyLight())
    do {
        let results = try doctor.run()
        print(doctor.reportURL.path)
        exit(results.allSatisfy(\.passed) ? 0 : 1)
    } catch {
        FileHandle.standardError.write(Data("Doctor could not write its report: \(error.localizedDescription)\n".utf8))
        exit(2)
    }
}
