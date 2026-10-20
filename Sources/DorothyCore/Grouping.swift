import Foundation

public struct ItemGroup: Identifiable, Equatable {
    public var id: String { title }
    public let title: String
    public let items: [Item]
}

/// Priority mode: "High","Medium","Low","No priority". Deadline mode: "Overdue","Today","This week","Later","No date".
/// Undone items in buckets (empty buckets omitted), sorted by deadline then createdAt. Done items in a final "Done" group.
/// Deadlines are day stamps (see `dayCalendar`); "today" is the user's local date in `timeZone`.
public func groups(_ items: [Item], by: GroupBy, now: Date = Date(), timeZone: TimeZone = .current) -> [ItemGroup] {
    let todayStamp = today(now, timeZone: timeZone)
    let tomorrow = dayCalendar.date(byAdding: .day, value: 1, to: todayStamp)!
    let weekEnd = dayCalendar.date(byAdding: .day, value: 8, to: todayStamp)!  // today+1 ... today+7 inclusive

    func bucket(_ item: Item) -> String {
        switch by {
        case .priority:
            switch item.priority {
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            case .none: return "No priority"
            }
        case .deadline:
            guard let d = item.deadline else { return "No date" }
            if d < todayStamp { return "Overdue" }
            if d < tomorrow { return "Today" }
            if d < weekEnd { return "This week" }
            return "Later"
        }
    }

    let titles = by == .priority
        ? ["High", "Medium", "Low", "No priority"]
        : ["Overdue", "Today", "This week", "Later", "No date"]
    let sorted = items.sorted {
        ($0.deadline ?? .distantFuture, $0.createdAt) < ($1.deadline ?? .distantFuture, $1.createdAt)
    }
    let open = sorted.filter { !$0.done }
    var result = titles.compactMap { title -> ItemGroup? in
        let g = open.filter { bucket($0) == title }
        return g.isEmpty ? nil : ItemGroup(title: title, items: g)
    }
    let done = sorted.filter(\.done)
    if !done.isEmpty { result.append(ItemGroup(title: "Done", items: done)) }
    return result
}

/// Deadlines are calendar days, stored as midnight UTC (Gregorian) so they never shift with timezone or system calendar.
public let dayCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Day stamp for the user's local (Gregorian) date at `now`.
public func today(_ now: Date = Date(), timeZone: TimeZone = .current) -> Date {
    var local = Calendar(identifier: .gregorian)
    local.timeZone = timeZone
    return dayCalendar.date(from: local.dateComponents([.year, .month, .day], from: now))!
}

/// "YYYY-MM-DD" → start-of-day Date in calendar.
public func parseDay(_ s: String, calendar: Calendar = dayCalendar) -> Date? {
    let parts = s.split(separator: "-").compactMap { Int($0) }
    guard s.count == 10, parts.count == 3 else { return nil }
    let c = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    guard c.isValidDate(in: calendar), let d = calendar.date(from: c) else { return nil }
    return calendar.startOfDay(for: d)
}

/// Date → "YYYY-MM-DD" in calendar.
public func formatDay(_ d: Date, calendar: Calendar = dayCalendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
