import Foundation

public struct ParsedItem: Codable, Equatable {
    public var title: String
    public var priority: Priority
    public var deadline: String?
    public var list: String?

    public init(title: String, priority: Priority = .none, deadline: String? = nil, list: String? = nil) {
        self.title = title
        self.priority = priority
        self.deadline = deadline
        self.list = list
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        priority = Priority(rawValue: ((try? c.decode(String.self, forKey: .priority)) ?? "").lowercased()) ?? .none
        deadline = try? c.decode(String.self, forKey: .deadline)
        list = try? c.decode(String.self, forKey: .list)
    }
}

public enum GemmaSetup { case noOllama, notRunning, noModel, ready }

/// One NDJSON line from /api/pull.
public struct PullProgress: Decodable, Equatable {
    public var status: String?
    public var digest: String?
    public var completed: Double?
    public var total: Double?
    public var error: String?
}

/// Whole-pull progress: Ollama reports each layer separately, so sum them; the fraction never goes backwards.
public struct PullTally: Sendable {
    public private(set) var status = ""
    public private(set) var fraction = 0.0
    private var totals: [String: Double] = [:], done: [String: Double] = [:]
    public var completedBytes: Double { done.values.reduce(0, +) }
    public var totalBytes: Double { totals.values.reduce(0, +) }

    public init() {}

    public mutating func add(_ p: PullProgress) {
        status = p.status ?? status
        guard let d = p.digest, let t = p.total, t > 0 else { return }
        totals[d] = t
        done[d] = max(done[d] ?? 0, p.completed ?? 0)
        fraction = max(fraction, completedBytes / totalBytes)
    }
}

public struct SetupError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public enum Gemma {
    public static var model: String { ProcessInfo.processInfo.environment["DOROTHY_MODEL"] ?? "gemma4:e4b" }
    public static var host: URL { hostURL(ProcessInfo.processInfo.environment["OLLAMA_HOST"]) }

    /// Accepts Ollama-style OLLAMA_HOST: optional scheme/port, 0.0.0.0 means local.
    static func hostURL(_ env: String?) -> URL {
        guard let env, !env.isEmpty else { return URL(string: "http://127.0.0.1:11434")! }
        var c = URLComponents(string: env.contains("://") ? env : "http://" + env) ?? URLComponents()
        if c.host == nil || c.host == "" || c.host == "0.0.0.0" { c.host = "127.0.0.1" }
        if c.port == nil { c.port = 11434 }
        return c.url ?? URL(string: "http://127.0.0.1:11434")!
    }

    public static let ollamaApps = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
    public static let ollamaCLIs = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]

    /// Server answers → model pulled? Otherwise: is Ollama installed at all?
    public static func setupState() async -> GemmaSetup {
        var req = URLRequest(url: host.appendingPathComponent("api/tags"))
        req.timeoutInterval = 1.5
        if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 {
            return hasModel(tags: data, model) ? .ready : .noModel
        }
        return (ollamaApps + ollamaCLIs).contains { FileManager.default.fileExists(atPath: $0) } ? .notRunning : .noOllama
    }

    /// /api/tags lists "name:tag"; a bare name means ":latest".
    static func hasModel(tags: Data, _ model: String) -> Bool {
        struct Tags: Decodable { struct M: Decodable { var name: String?; var model: String? }; var models: [M] }
        func norm(_ s: String) -> String { s.split(separator: "/").last?.contains(":") == true ? s : s + ":latest" }
        guard let tags = try? JSONDecoder().decode(Tags.self, from: tags) else { return false }
        return tags.models.contains { m in [m.name, m.model].compactMap { $0 }.contains { norm($0) == norm(model) } }
    }

    /// Streams POST /api/pull; throws Ollama's error text, or if the stream ends without "success". Cancel the task to stop.
    public static func pull(_ onProgress: @Sendable @MainActor (PullTally) -> Void) async throws {
        var req = URLRequest(url: host.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        var tally = PullTally()
        for try await line in bytes.lines {
            guard let p = pullLine(line) else { continue }
            if let e = p.error { throw SetupError(e) }
            tally.add(p)
            await onProgress(tally)
        }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard tally.status == "success" else { throw SetupError("The download stopped early. Try again to resume it.") }
    }

    static func pullLine(_ line: String) -> PullProgress? { try? JSONDecoder().decode(PullProgress.self, from: Data(line.utf8)) }

    public static func parse(text: String, lists: [String], now: Date = Date()) async throws -> [ParsedItem] {
        let content = try await chat(system: prompt(lists: lists, now: now, audio: false),
                                     user: ["role": "user", "content": text])
        return try decodeItems(from: content).items
    }

    public static func parse(audioWAV: Data, lists: [String], now: Date = Date()) async throws -> (transcript: String, items: [ParsedItem]) {
        let content = try await chat(system: prompt(lists: lists, now: now, audio: true),
                                     user: ["role": "user", "content": "Transcribe the audio, then extract to-do items.",
                                            "images": [audioWAV.base64EncodedString()]])
        return try decodeItems(from: content)
    }

    @discardableResult
    public static func apply(_ parsed: [ParsedItem], sourceText: String, defaultListID: UUID, to data: inout DorothyData) -> (count: Int, list: String) {
        var counts: [Int: Int] = [:]
        for p in parsed {
            let title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let named = p.list.flatMap { name in
                sourceText.range(of: "(?<!\\w)" + NSRegularExpression.escapedPattern(for: name) + "(?!\\w)",
                                 options: [.regularExpression, .caseInsensitive]) != nil
                    ? data.lists.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame } : nil
            }
            guard let i = named ?? data.lists.firstIndex(where: { $0.id == defaultListID }) else { continue }
            data.lists[i].items.append(Item(title: title, priority: p.priority, deadline: p.deadline.flatMap { parseDay($0) }))
            counts[i, default: 0] += 1
        }
        let top = counts.max { $0.value < $1.value }?.key ?? data.lists.firstIndex { $0.id == defaultListID }
        return (counts.values.reduce(0, +), top.map { data.lists[$0].name } ?? "")
    }

    struct Reply: Decodable { var transcript: String?; var items: [ParsedItem] }

    /// Tolerant: ignores fences/prose around the JSON object.
    static func decodeItems(from content: String) throws -> (transcript: String, items: [ParsedItem]) {
        guard let a = content.firstIndex(of: "{"), let b = content.lastIndex(of: "}"), a < b else {
            throw URLError(.cannotParseResponse)
        }
        let r = try JSONDecoder().decode(Reply.self, from: Data(content[a...b].utf8))
        return (r.transcript ?? "", r.items)
    }

    static func prompt(lists: [String], now: Date, audio: Bool, timeZone: TimeZone = .current) -> String {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let t = today(now, timeZone: timeZone)
        let days = (0...7).map { dayCalendar.date(byAdding: .day, value: $0, to: t)! }
        func name(_ d: Date) -> String { names[dayCalendar.component(.weekday, from: d) - 1] }
        let nextMonday = days.dropFirst().first { name($0) == "monday" }!
        let upcoming = days.dropFirst().map { "\(name($0)) = \(formatDay($0))" }.joined(separator: ", ")
        let listJSON = String(data: (try? JSONEncoder().encode(lists)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let transcript = audio ? "\"transcript\": string, " : ""
        return """
        You turn spoken or typed to-do input into items. Today is \(name(t).capitalized) \(formatDay(t)). \
        Tomorrow = \(formatDay(days[1])). Next week = \(formatDay(nextMonday)) (Monday). Upcoming days: \(upcoming). \
        Existing lists: \(listJSON). \
        Reply with ONLY JSON, no prose, no code fences: {\(transcript)"items": [{"title": string, "priority": "none"|"high"|"medium"|"low", \
        "deadline": "YYYY-MM-DD" or null, "list": string or null}]}. Rules: split separate tasks into separate items. \
        title = short imperative, capitalized, without date or priority words. \
        priority defaults to "none"; almost every item is "none". Only change it if the user literally says one of these words: \
        urgent/asap/important/critical → "high"; "medium"/"normal priority" → "medium"; "low priority"/"whenever"/"someday" → "low". \
        Deadlines, lists and the kind of task never imply a priority. \
        deadline only if a time is said, using the dates above (tonight = today). \
        list = an existing list name ONLY if the user explicitly mentions that list by name, otherwise null.
        """
    }

    static func chat(system: String, user: [String: Any]) async throws -> String {
        var req = URLRequest(url: host.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false, "think": false, "options": ["temperature": 0],
            "messages": [["role": "system", "content": system], user],
        ] as [String: Any])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["message"] as? [String: Any])?["content"] as? String
        else { throw URLError(.badServerResponse) }
        return content
    }
}
