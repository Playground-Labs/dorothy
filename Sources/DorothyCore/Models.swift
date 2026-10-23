import Foundation

public enum Priority: String, Codable, CaseIterable, Sendable {
    case high, medium, low, none
}

public enum GroupBy: String, Codable, Sendable {
    case priority, deadline
}

public struct Item: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var done = false
    public var priority: Priority = .none
    /// Start of the due day in the user's calendar, or nil.
    public var deadline: Date?
    public var createdAt = Date()
    /// Free-form notes, at most `Item.notesLimit` characters; nil when empty.
    public var notes: String?

    public static let notesLimit = 250

    /// Trimmed and capped at `notesLimit` characters; empty becomes nil.
    public static func normalizedNotes(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(notesLimit))
    }

    public init(title: String, priority: Priority = .none, deadline: Date? = nil, notes: String? = nil) {
        self.title = title
        self.priority = priority
        self.deadline = deadline
        self.notes = Item.normalizedNotes(notes)
    }
}

public struct TodoList: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    /// Hex like "#FF4FA3"; picked from `TodoList.palette`.
    public var color: String
    public var groupBy: GroupBy = .priority
    public var items: [Item] = []

    public static let palette = ["#FF4FA3", "#2E5BFF", "#22D39A", "#FF7A1A", "#9B5CFF"]

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct DorothyData: Codable, Equatable, Sendable {
    public var lists: [TodoList] = []
    public init(lists: [TodoList] = []) { self.lists = lists }
}
