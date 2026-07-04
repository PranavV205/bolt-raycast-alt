import AppKit

// File search over the Spotlight index via mdfind (FR-6). Async because
// mdfind takes tens of milliseconds; results merge into the list when
// they arrive. Enter opens, Cmd+Enter reveals in Finder.
final class FileProvider {

    private var runningProcess: Process?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "bolt.mdfind", qos: .userInitiated)

    func search(query: Query, completion: @escaping ([ResultItem]) -> Void) {
        debounceWork?.cancel()
        let term = query.trimmed
        let work = DispatchWorkItem { [weak self] in
            self?.run(term: term, completion: completion)
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func run(term: String, completion: @escaping ([ResultItem]) -> Void) {
        runningProcess?.terminate()

        let escaped = term
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "")
        guard !escaped.isEmpty else { return }

        let home = NSHomeDirectory()
        let mdQuery = "kMDItemFSName == \"*\(escaped)*\"cd"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "mdfind -onlyin \(shellQuote(home)) \(shellQuote(mdQuery)) 2>/dev/null | head -n 60"]
        let pipe = Pipe()
        process.standardOutput = pipe
        runningProcess = process

        do {
            try process.run()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 13 else { return }

        let paths = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init) ?? []

        var items: [ResultItem] = []
        for path in paths {
            // Applications are already covered by AppProvider.
            if path.hasSuffix(".app") { continue }
            let url = URL(fileURLWithPath: path)
            let fileName = url.lastPathComponent
            guard let match = FuzzyMatcher.score(query: term, candidate: fileName) else { continue }

            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 32, height: 32)

            let parent = url.deletingLastPathComponent().path
                .replacingOccurrences(of: NSHomeDirectory(), with: "~")

            items.append(ResultItem(
                id: "file:\(path)",
                title: fileName,
                subtitle: parent,
                icon: .image(icon),
                kind: .file,
                score: match * 0.62,   // files rank below apps at equal match
                accessory: nil,
                action: { modifiers in
                    if modifiers.contains(.command) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                    return .dismiss
                }
            ))
        }

        items.sort { $0.score > $1.score }
        let top = Array(items.prefix(12))
        DispatchQueue.main.async {
            completion(top)
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
