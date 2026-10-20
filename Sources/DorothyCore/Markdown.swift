import Foundation

/// Limitation: a title that itself ends in a token ("!high", "due:2026-01-01") re-imports with it parsed as a token; there is no escaping.
public enum MarkdownIO {
    public static func export(_ data: DorothyData, calendar: Calendar = dayCalendar) -> String {
        let oneLine = { (s: String) in s.split(whereSeparator: \.isNewline).joined(separator: " ") }
        var out = ["<!-- Dorothy export · \(formatDay(today())) -->"]
        for list in data.lists {
            out += ["", "# \(oneLine(list.name))"]
            for item in list.items {
                var line = "- [\(item.done ? "x" : " ")] \(oneLine(item.title))"
                if item.priority != .none { line += " !\(item.priority.rawValue)" }
                if let d = item.deadline { line += " due:\(formatDay(d, calendar: calendar))" }
                out.append(line)
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    public static func parse(_ markdown: String, calendar: Calendar = dayCalendar) -> [TodoList] {
        var lists: [TodoList] = []
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let name = heading(line) {
                lists.append(TodoList(name: name, color: TodoList.palette[0]))
                continue
            }
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            var rest = line.dropFirst(2)
            var done = false
            if ["[ ]", "[x]", "[X]"].contains(rest.prefix(3)), rest.dropFirst(3).first ?? " " == " " {
                done = rest.dropFirst().first != " "
                rest = rest.dropFirst(3)
            }

            // Pop trailing !priority / due:YYYY-MM-DD tokens (any order, each at most once); stop at anything else.
            // Empty pieces keep runs of spaces in the title; they are only dropped when they precede a popped token.
            var words = rest.split(separator: " ", omittingEmptySubsequences: false)
            var priority: Priority?
            var deadline: Date?
            while words.count > 1, let last = words.last {
                if last.isEmpty {
                    // trailing gap left by a popped token
                } else if priority == nil, last.hasPrefix("!"), let p = Priority(rawValue: String(last.dropFirst())), p != .none {
                    priority = p
                } else if deadline == nil, last.hasPrefix("due:"), let d = parseDay(String(last.dropFirst(4)), calendar: calendar) {
                    deadline = d
                } else { break }
                words.removeLast()
            }
            let title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }

            var item = Item(title: title, priority: priority ?? .none, deadline: deadline)
            item.done = done
            if lists.isEmpty { lists.append(TodoList(name: "Imported", color: TodoList.palette[0])) }
            lists[lists.count - 1].items.append(item)
        }
        return lists
    }

    /// Merge: same-name list (case-insensitive) gets items appended, skipping items whose title already exists there (case-insensitive);
    /// new lists created with color = palette[data.lists.count % palette.count]. Never deletes. Returns counts added.
    @discardableResult
    public static func merge(_ imported: [TodoList], into data: inout DorothyData) -> (lists: Int, items: Int) {
        var added = (lists: 0, items: 0)
        for list in imported {
            let i: Int
            if let existing = data.lists.firstIndex(where: { $0.name.lowercased() == list.name.lowercased() }) {
                i = existing
            } else {
                data.lists.append(TodoList(name: list.name, color: TodoList.palette[data.lists.count % TodoList.palette.count]))
                i = data.lists.count - 1
                added.lists += 1
            }
            for item in list.items where !data.lists[i].items.contains(where: { $0.title.lowercased() == item.title.lowercased() }) {
                data.lists[i].items.append(item)
                added.items += 1
            }
        }
        return added
    }

    private static func heading(_ line: String) -> String? {
        for prefix in ["# ", "## "] where line.hasPrefix(prefix) {
            let name = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return nil
    }
}
