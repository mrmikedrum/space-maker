import Foundation

/// Display Setups and Guest Displays: which connected displays Space Maker arranges, and which it leaves alone.
extension Engine {
    /// The connected known displays: the built-in one and every remembered one. Each is named by its
    /// remembered ID, even if WindowServer has since given it a new UUID.
    func knownDisplays(_ displays: [WindowSystemDisplay]) -> [WindowSystemDisplay] {
        displays.compactMap { display in
            if display.isBuiltIn { return display }
            guard let known = knownDisplay(matching: display) else { return nil }
            var display = display
            display.id = known.id
            return display
        }
    }

    /// Connected displays the user hasn't remembered. Space Maker never puts anything on them.
    func guestDisplays(_ displays: [WindowSystemDisplay]) -> [WindowSystemDisplay] {
        displays.filter { !$0.isBuiltIn && knownDisplay(matching: $0) == nil }
    }

    /// The current Display Setup's key: its known displays' IDs, sorted.
    func displaySetupKey(_ displays: [WindowSystemDisplay]) -> [String] {
        knownDisplays(displays).map(\.id).sorted()
    }

    /// Displays are recognised by UUID, falling back to vendor, model and serial number.
    private func knownDisplay(matching display: WindowSystemDisplay) -> KnownDisplay? {
        layout.knownDisplays.first { $0.id == display.id }
            ?? display.hardwareID.flatMap { hardwareID in layout.knownDisplays.first { $0.hardwareID == hardwareID } }
    }

    /// Remembers a Guest Display, so it joins the Display Setups. `display` is its ID from `status`;
    /// it may be omitted when exactly one Guest Display is connected.
    func rememberDisplay(_ id: String?) -> CommandReply {
        withLayout {
            let displays = windowSystem.readDisplays()
            let guests = guestDisplays(displays)
            let display: WindowSystemDisplay
            if let id, !id.isEmpty {
                guard let found = guests.first(where: { $0.id == id }) else {
                    if knownDisplays(displays).contains(where: { $0.id == id }) {
                        return CommandReply(text: "Display \(id) is already known.")
                    }
                    return CommandReply(text: "No Guest Display has the ID “\(id)”. \(Self.guestList(guests))", isError: true)
                }
                display = found
            } else {
                guard guests.count == 1 else {
                    return CommandReply(text: "remember_display needs a display ID. \(Self.guestList(guests))", isError: true)
                }
                display = guests[0]
            }
            layout.knownDisplays.append(KnownDisplay(id: display.id, hardwareID: display.hardwareID, name: display.name))
            layout.knownDisplays.sort { $0.id < $1.id }
            let hint = resolvedSpaces(displays) == nil
                ? " Nothing is saved for this Display Setup yet: arrange things the way you want them, then Save."
                : ""
            return committing("Remembered \(display.name).\(hint)")
        }
    }

    private static func guestList(_ guests: [WindowSystemDisplay]) -> String {
        guests.isEmpty
            ? "No Guest Display is connected."
            : "Guest Displays: " + guests.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") + "."
    }
}
