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

    public init(title: String, priority: Priority = .none, deadline: Date? = nil) {
        self.title = title
        self.priority = priority
        self.deadline = deadline
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
