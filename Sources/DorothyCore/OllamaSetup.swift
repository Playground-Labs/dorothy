import Foundation

/// First-run helper: is Ollama installed, running, and does it have Dorothy's model?
public enum OllamaSetup {
    public enum State: Equatable { case checking, notInstalled, notRunning, missingModel, ready }

    /// A running server counts as installed (brew, a custom path, or a remote OLLAMA_HOST).
    public static func state(installed: Bool, running: Bool, hasModel: Bool) -> State {
        if running { return hasModel ? .ready : .missingModel }
        return installed ? .notRunning : .notInstalled
    }

    private struct Tags: Decodable {
        struct Model: Decodable { var name: String?; var model: String? }
        var models: [Model]?
    }

    /// Reads GET /api/tags. A tagless model name also matches `<name>:latest`; case-insensitive.
    public static func hasModel(tagsJSON: Data, model: String) -> Bool {
        guard let tags = try? JSONDecoder().decode(Tags.self, from: tagsJSON) else { return false }
        let want = model.lowercased()
        let wanted: Set<String> = want.contains(":") ? [want] : [want, want + ":latest"]
        return (tags.models ?? []).contains { m in
            [m.name, m.model].contains { $0.map { wanted.contains($0.lowercased()) } ?? false }
        }
    }

    /// One line of POST /api/pull's streamed NDJSON.
    public struct PullProgress: Equatable {
        public var status: String
        public var completed: Int64?
        public var total: Int64?
        public var error: String?

        public init(status: String, completed: Int64? = nil, total: Int64? = nil, error: String? = nil) {
            self.status = status
            self.completed = completed
            self.total = total
            self.error = error
        }

        public var fraction: Double? {
            guard let total, total > 0, let completed else { return nil }
            return min(1, max(0, Double(completed) / Double(total)))
        }

        public var isSuccess: Bool { status == "success" }
    }

    private struct PullLine: Decodable {
        var status: String?
        var completed: Int64?
        var total: Int64?
        var error: String?
    }

    public static func parsePullLine(_ line: String) -> PullProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let l = try? JSONDecoder().decode(PullLine.self, from: Data(trimmed.utf8)),
              l.status != nil || l.error != nil else { return nil }
        return PullProgress(status: l.status ?? "", completed: l.completed, total: l.total, error: l.error)
    }

    public static let downloadPage = URL(string: "https://ollama.com/download/mac")!

    public static let appCandidates = [
        URL(fileURLWithPath: "/Applications/Ollama.app"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ollama.app"),
    ]

    public static func appURL(candidates: [URL] = appCandidates,
                              exists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> URL? {
        candidates.first { exists($0.path) }
    }

    public static func isInstalled(exists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> Bool {
        appURL(exists: exists) != nil || ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"].contains(where: exists)
    }

    /// UserDefaults key: the user closed the first-open setup modal once.
    public static let dismissedKey = "ollamaSetupDismissed"

    public static func shouldOfferOnLaunch(_ state: State, dismissed: Bool) -> Bool {
        !dismissed && state != .ready && state != .checking
    }

    // MARK: Network

    /// GET /api/tags body, or nil when the server isn't answering 200.
    public static func fetchTags() async -> Data? {
        var req = URLRequest(url: Gemma.host.appendingPathComponent("api/tags"))
        req.timeoutInterval = 1.5
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    public static func check() async -> State {
        let tags = await fetchTags()
        return state(installed: isInstalled(), running: tags != nil,
                     hasModel: tags.map { hasModel(tagsJSON: $0, model: Gemma.model) } ?? false)
    }

    /// Streams POST /api/pull; throws on a non-200 reply, an `error` line, or a stream that ends without success.
    public static func pull(model: String = Gemma.model, onProgress: @escaping @Sendable (PullProgress) -> Void) async throws {
        var req = URLRequest(url: Gemma.host.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        req.timeoutInterval = 3600
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
            throw failure("Ollama couldn't download \(model) (HTTP \(code)).")
        }
        var succeeded = false
        for try await line in bytes.lines {
            guard let p = parsePullLine(line) else { continue }
            if let e = p.error { throw failure(e) }
            onProgress(p)
            if p.isSuccess { succeeded = true }
        }
        if !succeeded { throw failure("Download of \(model) stopped early.") }
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "OllamaSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
