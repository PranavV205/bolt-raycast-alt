import AppKit

// System actions: lock, sleep, dark mode, empty trash, restart, plus
// "quit <app>" / "force quit <app>" against running apps. Destructive
// ones require pressing Enter twice (PRD: confirmation for anything
// irreversible).
final class SystemCommandProvider: SearchProvider {
    let name = "System"

    private struct Command {
        let id: String
        let title: String
        let symbol: String
        let aliases: [String]
        let confirm: Bool
        let run: () -> ActionOutcome
    }

    private lazy var commands: [Command] = [
        Command(
            id: "sys:lock", title: "Lock Screen", symbol: "lock.fill",
            aliases: ["lock"], confirm: false,
            run: {
                Self.shell("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
                return .dismiss
            }
        ),
        Command(
            id: "sys:sleep", title: "Sleep", symbol: "moon.fill",
            aliases: ["suspend"], confirm: false,
            run: {
                Self.shell("/usr/bin/pmset", ["sleepnow"])
                return .dismiss
            }
        ),
        Command(
            id: "sys:screensaver", title: "Start Screen Saver", symbol: "sparkles.tv",
            aliases: ["saver"], confirm: false,
            run: {
                Self.shell("/usr/bin/open", ["-a", "ScreenSaverEngine"])
                return .dismiss
            }
        ),
        Command(
            id: "sys:darkmode", title: "Toggle Dark Mode", symbol: "circle.lefthalf.filled",
            aliases: ["dark", "light mode", "appearance"], confirm: false,
            run: {
                Self.appleScript(
                    "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
                )
                return .dismiss
            }
        ),
        Command(
            id: "sys:mute", title: "Toggle Mute", symbol: "speaker.slash.fill",
            aliases: ["mute", "unmute", "sound"], confirm: false,
            run: {
                Self.appleScript(
                    "set volume output muted not (output muted of (get volume settings))"
                )
                return .dismiss
            }
        ),
        Command(
            id: "sys:trash", title: "Empty Trash", symbol: "trash.fill",
            aliases: ["bin"], confirm: true,
            run: {
                Self.appleScript("tell application \"Finder\" to empty trash")
                return .toast("Trash emptied")
            }
        ),
        Command(
            id: "sys:hide-others", title: "Hide Other Apps", symbol: "eye.slash.fill",
            aliases: ["hide all"], confirm: false,
            run: {
                Self.appleScript(
                    "tell application \"System Events\" to set visible of (every process whose frontmost is false and visible is true) to false"
                )
                return .dismiss
            }
        ),
        Command(
            id: "sys:logout", title: "Log Out", symbol: "rectangle.portrait.and.arrow.right",
            aliases: ["sign out"], confirm: true,
            run: {
                Self.appleScript("tell application \"System Events\" to log out")
                return .dismiss
            }
        ),
        Command(
            id: "sys:restart", title: "Restart", symbol: "arrow.counterclockwise.circle.fill",
            aliases: ["reboot"], confirm: true,
            run: {
                Self.appleScript("tell application \"System Events\" to restart")
                return .dismiss
            }
        ),
        Command(
            id: "sys:shutdown", title: "Shut Down", symbol: "power.circle.fill",
            aliases: ["power off", "poweroff"], confirm: true,
            run: {
                Self.appleScript("tell application \"System Events\" to shut down")
                return .dismiss
            }
        ),
    ]

    func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty, query.trimmed.count >= 2 else { return [] }
        var items: [ResultItem] = []

        for cmd in commands {
            guard let score = FuzzyMatcher.score(
                query: query.lowercased, fields: [cmd.title] + cmd.aliases
            ) else { continue }
            items.append(ResultItem(
                id: cmd.id,
                title: cmd.title,
                subtitle: "System command",
                icon: .symbol(cmd.symbol),
                kind: .system,
                score: score * 0.85,
                needsConfirmation: cmd.confirm,
                action: { _ in cmd.run() }
            ))
        }

        items.append(contentsOf: quitCommands(for: query))
        return items
    }

    // "quit safari" / "force quit chrome" over running apps.
    private func quitCommands(for query: Query) -> [ResultItem] {
        let force: Bool
        let term: String
        if let arg = query.argument(afterKeyword: "force quit") {
            force = true
            term = arg
        } else if let arg = query.argument(afterKeyword: "quit") {
            force = false
            term = arg
        } else {
            return []
        }

        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }

        var items: [ResultItem] = []
        for app in running {
            let appName = app.localizedName ?? "Unknown"
            let score: Double
            if term.isEmpty {
                score = 0.6
            } else if let s = FuzzyMatcher.score(query: term, candidate: appName) {
                score = s
            } else {
                continue
            }

            let icon: ResultIcon = app.icon.map { .image($0) } ?? .symbol("xmark.circle")
            items.append(ResultItem(
                id: "sys:\(force ? "forcequit" : "quit"):\(app.bundleIdentifier ?? appName)",
                title: "\(force ? "Force Quit" : "Quit") \(appName)",
                subtitle: force ? "SIGKILL, unsaved changes are lost" : "Ask the app to quit",
                icon: icon,
                kind: .system,
                score: score * (force ? 0.8 : 0.9) + 0.5,
                needsConfirmation: force,
                action: { _ in
                    if force {
                        app.forceTerminate()
                    } else {
                        app.terminate()
                    }
                    return .toast("\(appName) \(force ? "force quit" : "quit")")
                }
            ))
        }
        return items
    }

    // MARK: helpers

    @discardableResult
    private static func shell(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        do {
            try process.run()
            return true
        } catch {
            NSLog("Bolt: shell command failed: \(error)")
            return false
        }
    }

    private static func appleScript(_ source: String) {
        DispatchQueue.main.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("Bolt: AppleScript error: \(error)")
                Toast.show("Command failed (check Automation permission)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}
