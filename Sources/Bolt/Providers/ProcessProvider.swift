import AppKit

// "kill <name>": search running processes, Enter sends SIGTERM,
// Cmd+Enter sends SIGKILL. Sorted by CPU so the runaway one is on top.
final class ProcessProvider {

    private struct ProcInfo {
        let pid: Int32
        let cpu: Double
        let rssMB: Double
        let command: String
        var name: String { (command as NSString).lastPathComponent }
    }

    func search(_ term: String) -> [ResultItem] {
        // "kill 3000" (or "kill :3000"): what is listening on that port.
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        let portTerm = trimmed.hasPrefix(":") ? String(trimmed.dropFirst()) : trimmed
        if let port = Int(portTerm), (1...65535).contains(port) {
            return portResults(port: port)
        }

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
            items.append(ResultItem(
                id: "proc:none",
                title: "No processes match \"\(term)\"",
                subtitle: "kill <name>, Enter = SIGTERM, Cmd+Enter = SIGKILL",
                icon: .symbol("cpu"),
                kind: .process,
                score: 0.1,
                action: { _ in .stay }
            ))
        }
        return Array(items.prefix(25))
    }

    // "servers": every TCP listener that is not a /System daemon, with its
    // working directory shown as the project name. "servers vite" filters.
    func servers(filter: String) -> [ResultItem] {
        var items: [ResultItem] = []
        let needle = filter.lowercased()

        var listeners = allListeners()
        let cwds = workingDirectories(pids: listeners.map(\.pid))

        listeners.sort { ($0.ports.min() ?? 0) < ($1.ports.min() ?? 0) }
        for listener in listeners {
            let cmdline = fullCommand(pid: listener.pid)
            let binary = cmdline.split(separator: " ", maxSplits: 1).first.map(String.init) ?? cmdline
            if binary.hasPrefix("/System") || binary.hasPrefix("/usr/libexec") { continue }
            let shortName = (binary as NSString).lastPathComponent

            let cwd = cwds[listener.pid] ?? ""
            let project = (cwd as NSString).lastPathComponent
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let tildeCwd = cwd.replacingOccurrences(of: home, with: "~")
            let ports = listener.ports.sorted().map { ":\($0)" }.joined(separator: " ")

            if !needle.isEmpty {
                let haystack = "\(shortName) \(project) \(ports) \(cmdline)".lowercased()
                guard haystack.contains(needle) else { continue }
            }

            let pid = listener.pid
            items.append(ResultItem(
                id: "proc:\(pid)",
                title: "\(shortName)  ·  \(ports)\(project.isEmpty ? "" : "  ·  \(project)")",
                subtitle: "PID \(pid)  ·  \(tildeCwd)  ·  \(cmdline)",
                icon: .symbol("server.rack"),
                kind: .process,
                score: 1.0,
                accessory: "kills",
                action: { modifiers in
                    let signal: Int32 = modifiers.contains(.command) ? SIGKILL : SIGTERM
                    if kill(pid, signal) == 0 {
                        return .toast("\(shortName) (\(ports)) killed (\(signal == SIGKILL ? "SIGKILL" : "SIGTERM"))")
                    }
                    return .toast("Could not kill \(shortName) (not permitted)")
                }
            ))
        }

        if items.isEmpty {
            items.append(ResultItem(
                id: "proc:servers:none",
                title: needle.isEmpty ? "No dev servers listening" : "No servers match \"\(filter)\"",
                subtitle: "Lists TCP listeners with their working directory. Enter kills.",
                icon: .symbol("server.rack"),
                kind: .process,
                score: 0.1,
                action: { _ in .stay }
            ))
        }
        return items
    }

    private struct Listener {
        let pid: Int32
        var ports: Set<Int>
    }

    // All TCP LISTEN sockets, grouped by pid.
    private func allListeners() -> [Listener] {
        guard let output = runLsof(["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]) else { return [] }
        var byPid: [Int32: Set<Int>] = [:]
        var currentPid: Int32?

        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                // n*:3000, n127.0.0.1:3000, n[::1]:3000 -> port after last ":"
                if let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                    byPid[pid, default: []].insert(port)
                }
            }
        }
        return byPid.map { Listener(pid: $0.key, ports: $0.value) }
    }

    // cwd per pid in one lsof call.
    private func workingDirectories(pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty,
              let output = runLsof(["-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","), "-Fpn"])
        else { return [:] }
        var result: [Int32: String] = [:]
        var currentPid: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    private func runLsof(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
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

    // What is listening on this TCP port (lsof), with the full command line
    // so you can tell dev servers apart. Enter kills it.
    private func portResults(port: Int) -> [ResultItem] {
        var items: [ResultItem] = []

        for pid in listeningPIDs(port: port) {
            let cmdline = fullCommand(pid: pid)
            let name = (cmdline.split(separator: " ", maxSplits: 1).first.map(String.init) ?? cmdline)
            let shortName = (name as NSString).lastPathComponent

            items.append(ResultItem(
                id: "proc:\(pid)",
                title: "\(shortName)  ·  listening on :\(port)",
                subtitle: "PID \(pid)  ·  \(cmdline)",
                icon: .symbol("network"),
                kind: .process,
                score: 1.0,
                accessory: "kills",
                action: { modifiers in
                    let signal: Int32 = modifiers.contains(.command) ? SIGKILL : SIGTERM
                    if kill(pid, signal) == 0 {
                        return .toast("\(shortName) on :\(port) killed (\(signal == SIGKILL ? "SIGKILL" : "SIGTERM"))")
                    }
                    return .toast("Could not kill \(shortName) (not permitted)")
                }
            ))
        }

        if items.isEmpty {
            items.append(ResultItem(
                id: "proc:port:none",
                title: "Nothing listening on port \(port)",
                subtitle: "kill <port> checks TCP listeners, kill <name> searches processes",
                icon: .symbol("network.slash"),
                kind: .process,
                score: 0.1,
                action: { _ in .stay }
            ))
        }
        return items
    }

    private func listeningPIDs(port: Int) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var pids: [Int32] = []
        for line in output.split(separator: "\n") where line.hasPrefix("p") {
            if let pid = Int32(line.dropFirst()), !pids.contains(pid) {
                pids.append(pid)
            }
        }
        return pids
    }

    private func fullCommand(pid: Int32) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "args=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe

        guard (try? process.run()) != nil else { return "PID \(pid)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "PID \(pid)"
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
