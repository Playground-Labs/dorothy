import Foundation

public final class Store {
    public static let defaultURL: URL = {
        if let path = ProcessInfo.processInfo.environment["DOROTHY_DATA"] { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dorothy/dorothy.json")
    }()

    public struct Corrupt: LocalizedError {
        public let path: String
        public var errorDescription: String? { "Dorothy data file is unreadable or corrupt: \(path)" }
    }

    public let url: URL

    public init(url: URL = Store.defaultURL) { self.url = url }

    /// Missing file → seed DorothyData with one list "Inbox" (palette[0]) and write it. Undecodable file → throws `Corrupt`.
    public func load() throws -> DorothyData {
        if let data = try read() { return data }
        return try mutate { _ in }
    }

    /// Cross-process safe: flock() a sibling ".lock" file, re-read from disk, apply f, atomic write, return new data.
    /// Throws `Corrupt` (without writing) if the existing file can't be decoded, so a corrupt file is never overwritten.
    @discardableResult
    public func mutate(_ f: (inout DorothyData) throws -> Void) throws -> DorothyData {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }  // closing releases the flock
        flock(fd, LOCK_EX)
        var data = try read() ?? Self.seed()
        try f(&data)
        try Self.encoder.encode(data).write(to: url, options: .atomic)
        return data
    }

    /// Watches the file's directory (DispatchSource), calls onChange on main queue (debounced ~100ms) when file changes. Keep the returned object alive.
    public func watch(_ onChange: @escaping () -> Void) -> AnyObject {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Atomic writes replace the file's inode, so watch the directory instead of the file.
        let fd = open(dir.path, O_EVTONLY)
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        var pending: DispatchWorkItem?
        source.setEventHandler {
            pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return Watcher(source)
    }

    /// nil if the file doesn't exist; throws `Corrupt` if it exists but can't be read/decoded.
    private func read() throws -> DorothyData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Self.decoder.decode(DorothyData.self, from: Data(contentsOf: url))
        } catch {
            throw Corrupt(path: url.path)
        }
    }

    private static func seed() -> DorothyData {
        DorothyData(lists: [TodoList(name: "Inbox", color: TodoList.palette[0])])
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private final class Watcher {
    let source: DispatchSourceFileSystemObject
    init(_ source: DispatchSourceFileSystemObject) { self.source = source }
    deinit { source.cancel() }
}
