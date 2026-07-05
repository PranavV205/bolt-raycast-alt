import AppKit

// "kill <name>": search running processes, Enter sends SIGTERM,
// Cmd+Enter sends SIGKILL. Sorted by CPU so the runaway one is on top.
// "kill <port>" and "servers" answer from a cached TCP-listener snapshot
// that is scanned off the main thread; lsof is far too slow to run per
// keystroke on the UI thread.
final class ProcessProvider {

    private struct ProcInfo {
        let pid: Int32
        let cpu: Double
        let rssMB: Double
        let command: String
        var name: String { (command as NSString).lastPathComponent }
    }

    // MARK: - Listener snapshot (shared by "servers" and "kill <port>")

    private struct ServerInfo {
        let pid: Int32
        let ports: Set<Int>
        let cwd: String
        let cmdline: String
    }

    private var snapshot: [ServerInfo] = []
    private var snapshotTime = Date.distantPast
    private var scanning = false
    private var pendingRefresh: (() -> Void)?
    private let snapshotMaxAge: TimeInterval = 5

    static func portNumber(in term: String) -> Int? {
        let t = term.hasPrefix(":") ? String(term.dropFirst()) : term
        guard let port = Int(t), (1...65535).contains(port) else { return nil }
        return port
    }

    // MARK: - Name search (synchronous; one fast ps call)

    func search(_ term: String) -> [ResultItem] {
        let processes = list()
        var items: [ResultItem] = []

        for proc in processes {
            let score: Double
            if term.isEmpty {
                score = proc.cpu / 100.0
            } else if let s = FuzzyMatcher.score(query: term, fields: [proc.name, proc.command]) {
                score = s + proc.cpu / 200.0
            } else {
                continue
            }

            items.append(ResultItem(
                id: "proc:\(proc.pid)",
                title: proc.name,
                subtitle: "PID \(proc.pid)  ·  \(proc.command)",
                icon: .symbol("cpu"),
                kind: .process,
                score: score,
                accessory: String(format: "%.1f%% · %.0f MB", proc.cpu, proc.rssMB),
                action: { modifiers in
                    let signal: Int32 = modifiers.contains(.command) ? SIGKILL : SIGTERM
                    let result = kill(proc.pid, signal)
                    if result == 0 {
                        return .toast("\(proc.name) killed (\(signal == SIGKILL ? "SIGKILL" : "SIGTERM"))")
                    }
                    return .toast("Could not kill \(proc.name) (not permitted)")
                }
            ))
        }

        items.sort { $0.score > $1.score }
        if items.isEmpty {
            items.append(infoRow(
                id: "proc:none",
                title: "No processes match \"\(term)\"",
                subtitle: "kill <name>, Enter = SIGTERM, Cmd+Enter = SIGKILL",
                symbol: "cpu"
            ))
        }
        return Array(items.prefix(25))
    }

    // MARK: - Servers and ports (answered from the snapshot)

    // Returns rows immediately from the current snapshot. If the snapshot is
    // stale, a background scan starts and onRefresh fires when it lands so
    // the coordinator can rebuild.
    func serverItems(filter: String, onRefresh: @escaping () -> Void) -> [ResultItem] {
        let fresh = ensureFreshSnapshot(onRefresh: onRefresh)
        let needle = filter.lowercased()

        var items: [ResultItem] = []
        for server in snapshot.sorted(by: { ($0.ports.min() ?? 0) < ($1.ports.min() ?? 0) }) {
            let shortName = shortName(of: server)
            let project = (server.cwd as NSString).lastPathComponent
            let ports = server.ports.sorted().map { ":\($0)" }.joined(separator: " ")

            if !needle.isEmpty {
                let haystack = "\(shortName) \(project) \(ports) \(server.cmdline)".lowercased()
                guard haystack.contains(needle) else { continue }
            }
            items.append(serverRow(server, title: "\(shortName)  ·  \(ports)\(project.isEmpty ? "" : "  ·  \(project)")"))
        }

        if items.isEmpty {
            if !fresh && scanning {
                items.append(infoRow(id: "proc:servers:scan", title: "Scanning ports...",
                                     subtitle: "Listing TCP listeners", symbol: "server.rack"))
            } else {
                items.append(infoRow(
                    id: "proc:servers:none",
                    title: needle.isEmpty ? "No dev servers listening" : "No servers match \"\(filter)\"",
                    subtitle: "Lists TCP listeners with their working directory. Enter kills.",
                    symbol: "server.rack"
                ))
            }
        }
        return items
    }

    func portItems(port: Int, onRefresh: @escaping () -> Void) -> [ResultItem] {
        let fresh = ensureFreshSnapshot(onRefresh: onRefresh)

        var items: [ResultItem] = []
        for server in snapshot where server.ports.contains(port) {
            items.append(serverRow(server, title: "\(shortName(of: server))  ·  listening on :\(port)"))
        }

        if items.isEmpty {
            if !fresh && scanning {
                items.append(infoRow(id: "proc:port:scan", title: "Scanning port \(port)...",
                                     subtitle: "Checking TCP listeners", symbol: "network"))
            } else {
                items.append(infoRow(
                    id: "proc:port:none",
                    title: "Nothing listening on port \(port)",
                    subtitle: "kill <port> checks TCP listeners, kill <name> searches processes",
                    symbol: "network.slash"
                ))
            }
        }
        return items
    }

    private func shortName(of server: ServerInfo) -> String {
        let binary = server.cmdline.split(separator: " ", maxSplits: 1).first.map(String.init) ?? server.cmdline
        return (binary as NSString).lastPathComponent
    }

    private func serverRow(_ server: ServerInfo, title: String) -> ResultItem {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let tildeCwd = server.cwd.replacingOccurrences(of: home, with: "~")
        let pid = server.pid
        let name = shortName(of: server)
        // Electron apps carry kilobytes of flags; do not make SwiftUI lay
        // that out in a one-line subtitle.
        let cmdline = server.cmdline.count > 180 ? server.cmdline.prefix(180) + "..." : Substring(server.cmdline)

        return ResultItem(
            id: "proc:\(pid)",
            title: title,
            subtitle: "PID \(pid)  ·  \(tildeCwd)  ·  \(cmdline)",
            icon: .symbol("server.rack"),
            kind: .process,
            score: 1.0,
            accessory: "kills",
            action: { [weak self] modifiers in
                let signal: Int32 = modifiers.contains(.command) ? SIGKILL : SIGTERM
                if kill(pid, signal) == 0 {
                    self?.snapshotTime = .distantPast  // dead process: snapshot is stale
                    return .toast("\(name) killed (\(signal == SIGKILL ? "SIGKILL" : "SIGTERM"))")
                }
                return .toast("Could not kill \(name) (not permitted)")
            }
        )
    }

    private func infoRow(id: String, title: String, subtitle: String, symbol: String) -> ResultItem {
        ResultItem(id: id, title: title, subtitle: subtitle, icon: .symbol(symbol),
                   kind: .process, score: 0.1, action: { _ in .stay })
    }

    // True if the snapshot is fresh enough to trust. Otherwise kicks one
    // background scan; onRefresh (the latest one wins) fires on completion.
    private func ensureFreshSnapshot(onRefresh: @escaping () -> Void) -> Bool {
        if Date().timeIntervalSince(snapshotTime) < snapshotMaxAge { return true }
        pendingRefresh = onRefresh
        guard !scanning else { return false }
        scanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let servers = Self.scanListeners()
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot = servers
                self.snapshotTime = Date()
                self.scanning = false
                let refresh = self.pendingRefresh
                self.pendingRefresh = nil
                refresh?()
            }
        }
        return false
    }

    // The expensive part, always off the main thread: one lsof for all TCP
    // listeners, one ps for all command lines, one lsof for the cwds.
    private static func scanListeners() -> [ServerInfo] {
        guard let output = runTool("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]) else { return [] }
        var portsByPid: [Int32: Set<Int>] = [:]
        var currentPid: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                if let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                    portsByPid[pid, default: []].insert(port)
                }
            }
        }
        guard !portsByPid.isEmpty else { return [] }

        // One ps for every command line.
        var cmdlines: [Int32: String] = [:]
        if let psOut = runTool("/bin/ps", ["-axo", "pid=,args="]) {
            for line in psOut.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2, let pid = Int32(parts[0]), portsByPid[pid] != nil else { continue }
                cmdlines[pid] = String(parts[1])
            }
        }

        // One lsof for every cwd.
        var cwds: [Int32: String] = [:]
        let pidList = portsByPid.keys.map(String.init).joined(separator: ",")
        if let cwdOut = runTool("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pidList, "-Fpn"]) {
            var pid: Int32?
            for line in cwdOut.split(separator: "\n") {
                if line.hasPrefix("p") {
                    pid = Int32(line.dropFirst())
                } else if line.hasPrefix("n"), let p = pid {
                    cwds[p] = String(line.dropFirst())
                }
            }
        }

        var servers: [ServerInfo] = []
        for (pid, ports) in portsByPid {
            let cmdline = cmdlines[pid] ?? "PID \(pid)"
            let binary = cmdline.split(separator: " ", maxSplits: 1).first.map(String.init) ?? cmdline
            // Dev servers, not system daemons.
            if binary.hasPrefix("/System") || binary.hasPrefix("/usr/libexec") { continue }
            servers.append(ServerInfo(pid: pid, ports: ports, cwd: cwds[pid] ?? "", cmdline: cmdline))
        }
        return servers
    }

    private static func runTool(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func list() -> [ProcInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var result: [ProcInfo] = []

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }
            let command = String(parts[3])
            // Hide kernel workers and our own process.
            if pid == ProcessInfo.processInfo.processIdentifier { continue }
            result.append(ProcInfo(pid: pid, cpu: cpu, rssMB: rssKB / 1024.0, command: command))
        }
        return result
    }
}
