import DorothyCore
import Foundation
import MCP

struct ToolError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

let store = Store()

// MARK: - Schemas

func prop(_ type: String, _ description: String, enum values: [String]? = nil) -> Value {
    var p: [String: Value] = ["type": .string(type), "description": .string(description)]
    if let values { p["enum"] = .array(values.map { .string($0) }) }
    return .object(p)
}

func schema(_ props: [String: Value] = [:], required: [String] = []) -> Value {
    ["type": "object", "properties": .object(props), "required": .array(required.map { .string($0) })]
}

let listArg = prop("string", "List name (case-insensitive) or id")
let priorityArg = prop("string", "Priority", enum: Priority.allCases.map(\.rawValue))

let tools = [
    Tool(name: "list_lists", description: "List all to-do lists with open/done counts.", inputSchema: schema()),
    Tool(name: "create_list", description: "Create a new to-do list.",
         inputSchema: schema(["name": prop("string", "List name")], required: ["name"])),
    Tool(name: "get_list", description: "Get a list's items, grouped by priority or deadline.",
         inputSchema: schema([
             "list": listArg,
             "group_by": prop("string", "Grouping; defaults to the list's own setting", enum: ["priority", "deadline"]),
         ], required: ["list"])),
    Tool(name: "add_item", description: "Add an item to a list (defaults to the first list).",
         inputSchema: schema([
             "list": listArg,
             "title": prop("string", "Item title"),
             "priority": priorityArg,
             "deadline": prop("string", "Due date, YYYY-MM-DD"),
             "notes": prop("string", "Notes, at most 250 characters"),
         ], required: ["title"])),
    Tool(name: "update_item", description: "Update an item's title, done state, priority, deadline, or notes.",
         inputSchema: schema([
             "id": prop("string", "Item id"),
             "title": prop("string", "New title"),
             "done": prop("boolean", "Done state"),
             "priority": priorityArg,
             "deadline": prop("string", "Due date YYYY-MM-DD, or \"\" to clear"),
             "notes": prop("string", "Notes, at most 250 characters, or \"\" to clear"),
         ], required: ["id"])),
    Tool(name: "delete_item", description: "Delete an item.",
         inputSchema: schema(["id": prop("string", "Item id")], required: ["id"])),
]

// MARK: - Helpers

func json(_ item: Item) -> Value {
    [
        "id": .string(item.id.uuidString), "title": .string(item.title), "done": .bool(item.done),
        "priority": .string(item.priority.rawValue),
        "deadline": item.deadline.map { .string(formatDay($0)) } ?? .null,
        "notes": item.notes.map { .string($0) } ?? .null,
    ]
}

func json(_ list: TodoList) -> Value {
    [
        "id": .string(list.id.uuidString), "name": .string(list.name), "color": .string(list.color),
        "group_by": .string(list.groupBy.rawValue),
    ]
}

func listIndex(_ key: String?, in data: DorothyData) throws -> Int {
    guard let key else {
        guard !data.lists.isEmpty else { throw ToolError("There are no lists. Create one with create_list.") }
        return 0
    }
    if let i = data.lists.firstIndex(where: {
        $0.name.lowercased() == key.lowercased() || $0.id.uuidString == key.uppercased()
    }) { return i }
    throw ToolError("No list named or with id \"\(key)\". Use list_lists to see available lists.")
}

func itemIndex(_ id: String?, in data: DorothyData) throws -> (Int, Int) {
    guard let id else { throw ToolError("Missing required argument \"id\".") }
    for (l, list) in data.lists.enumerated() {
        if let i = list.items.firstIndex(where: { $0.id.uuidString == id.uppercased() }) { return (l, i) }
    }
    throw ToolError("No item with id \"\(id)\".")
}

/// Typed argument accessors: absent/null → nil, wrong JSON type → error.
func string(_ args: [String: Value], _ key: String) throws -> String? {
    guard let v = args[key], !v.isNull else { return nil }
    guard let s = v.stringValue else { throw ToolError("Argument \"\(key)\" must be a string.") }
    return s
}

func bool(_ args: [String: Value], _ key: String) throws -> Bool? {
    guard let v = args[key], !v.isNull else { return nil }
    guard let b = v.boolValue else { throw ToolError("Argument \"\(key)\" must be a boolean (true or false).") }
    return b
}

/// Single line, trimmed: internal newlines collapse to spaces.
func clean(_ s: String?) -> String? {
    s.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
}

func priority(_ s: String?) throws -> Priority? {
    guard let s else { return nil }
    guard let p = Priority(rawValue: s.lowercased()) else {
        throw ToolError("Bad priority \"\(s)\"; expected high, medium, low, or none.")
    }
    return p
}

/// Rejects over-long notes rather than silently cutting them.
func notes(_ s: String?) throws -> String? {
    if let s, s.trimmingCharacters(in: .whitespacesAndNewlines).count > Item.notesLimit {
        throw ToolError("Notes must be at most \(Item.notesLimit) characters.")
    }
    return Item.normalizedNotes(s)
}

func day(_ s: String) throws -> Date {
    guard let d = parseDay(s) else { throw ToolError("Bad date \"\(s)\"; expected YYYY-MM-DD.") }
    return d
}

// MARK: - Tools

func call(_ name: String, _ args: [String: Value]) throws -> Value {
    let str = { try string(args, $0) }
    switch name {
    case "list_lists":
        return .array(try store.load().lists.map { list in
            [
                "id": .string(list.id.uuidString), "name": .string(list.name),
                "open_count": .int(list.items.filter { !$0.done }.count),
                "done_count": .int(list.items.filter(\.done).count),
                "group_by": .string(list.groupBy.rawValue),
            ]
        })

    case "create_list":
        guard let name = clean(try str("name")), !name.isEmpty else {
            throw ToolError("Missing required argument \"name\".")
        }
        var created: TodoList!
        try store.mutate { data in
            if data.lists.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                throw ToolError("A list named \"\(name)\" already exists.")
            }
            created = TodoList(name: name, color: TodoList.palette[data.lists.count % TodoList.palette.count])
            data.lists.append(created)
        }
        return json(created)

    case "get_list":
        guard let key = try str("list") else { throw ToolError("Missing required argument \"list\".") }
        let data = try store.load()
        let list = data.lists[try listIndex(key, in: data)]
        var by = list.groupBy
        if let g = try str("group_by") {
            guard let parsed = GroupBy(rawValue: g) else { throw ToolError("Bad group_by \"\(g)\"; expected priority or deadline.") }
            by = parsed
        }
        return [
            "list": json(list),
            "groups": .array(groups(list.items, by: by).map { g in
                ["title": .string(g.title), "items": .array(g.items.map(json))]
            }),
        ]

    case "add_item":
        guard let title = clean(try str("title")), !title.isEmpty else {
            throw ToolError("Missing required argument \"title\".")
        }
        let item = Item(title: title, priority: try priority(str("priority")) ?? .none, deadline: try str("deadline").map(day),
                        notes: try notes(str("notes")))
        try store.mutate { data in
            data.lists[try listIndex(try str("list"), in: data)].items.append(item)
        }
        return json(item)

    case "update_item":
        let title = clean(try str("title"))
        if title?.isEmpty == true { throw ToolError("Title can't be empty.") }
        let done = try bool(args, "done")
        let newPriority = try priority(str("priority"))
        let deadline = try str("deadline")
        let notesArg = try str("notes")
        let newNotes = try notes(notesArg)
        var updated: Item!
        try store.mutate { data in
            let (l, i) = try itemIndex(try str("id"), in: data)
            if let title { data.lists[l].items[i].title = title }
            if let done { data.lists[l].items[i].done = done }
            if let newPriority { data.lists[l].items[i].priority = newPriority }
            if notesArg != nil { data.lists[l].items[i].notes = newNotes }
            if let d = deadline { data.lists[l].items[i].deadline = d.isEmpty ? nil : try day(d) }
            updated = data.lists[l].items[i]
        }
        return json(updated)

    case "delete_item":
        try store.mutate { data in
            let (l, i) = try itemIndex(try str("id"), in: data)
            data.lists[l].items.remove(at: i)
        }
        return ["deleted": true]

    default:
        throw ToolError("Unknown tool \"\(name)\".")
    }
}

// MARK: - Server

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

let server = Server(name: "dorothy", version: "0.1.0", capabilities: .init(tools: .init(listChanged: false)))
await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
await server.withMethodHandler(CallTool.self) { params in
    do {
        let out = try call(params.name, params.arguments ?? [:])
        return .init(content: [.text(text: String(decoding: try encoder.encode(out), as: UTF8.self), annotations: nil, _meta: nil)])
    } catch {
        return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
    }
}
try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
