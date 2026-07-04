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
