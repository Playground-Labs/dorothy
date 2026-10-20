import XCTest
import DorothyCore

final class StoreGroupingTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    func tempStore() -> Store {
        Store(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("dorothy.json"))
    }

    func testSeedsInboxWhenMissing() throws {
        let store = tempStore()
        let data = try store.load()
        XCTAssertEqual(data.lists.map(\.name), ["Inbox"])
        XCTAssertEqual(data.lists[0].color, TodoList.palette[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertEqual(try store.load().lists[0].id, data.lists[0].id)  // seed persisted, not regenerated
    }

    func testMutateRoundTrip() throws {
        let store = tempStore()
        let due = parseDay("2026-10-22")!
        try store.mutate { $0.lists[0].items.append(Item(title: "Milk", priority: .high, deadline: due)) }
        let item = try Store(url: store.url).load().lists[0].items[0]
        XCTAssertEqual(item.title, "Milk")
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.deadline, due)
    }

    func testCorruptFileIsNotOverwritten() throws {
        let store = tempStore()
        _ = try store.load()
        try Data("nope".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual(($0 as? Store.Corrupt)?.path, store.url.path) }
        XCTAssertThrowsError(try store.mutate { _ in })
        XCTAssertEqual(try String(contentsOf: store.url), "nope")
    }

    func testWatchFiresOnMutate() throws {
        let store = tempStore()
        _ = try store.load()
        let fired = expectation(description: "onChange")
        let token = store.watch { fired.fulfill() }
        try store.mutate { $0.lists[0].name = "Renamed" }
        wait(for: [fired], timeout: 2)
        withExtendedLifetime(token) {}
    }

    func testDayRoundTrip() {
        XCTAssertEqual(formatDay(parseDay("2026-03-08")!), "2026-03-08")
        XCTAssertNil(parseDay("2026-02-30"))
        XCTAssertNil(parseDay("tomorrow"))
    }

    func testDayStampsIgnoreLocalTimeZone() {
        // Absolute UTC-midnight stamp: independent of the machine's TimeZone.current and Calendar.current.
        XCTAssertEqual(parseDay("2026-10-23"), Date(timeIntervalSince1970: 1_792_713_600))
        XCTAssertEqual(formatDay(Date(timeIntervalSince1970: 1_792_713_600)), "2026-10-23")
        let noonUTC = Date(timeIntervalSince1970: 1_792_497_600)  // 2026-10-20 12:00 UTC
        XCTAssertEqual(formatDay(today(noonUTC, timeZone: TimeZone(identifier: "Pacific/Kiritimati")!)), "2026-10-21")
        XCTAssertEqual(formatDay(today(noonUTC, timeZone: TimeZone(identifier: "Pacific/Honolulu")!)), "2026-10-20")
    }

    func testDeadlineBuckets() {
        // Tue 2026-10-20 23:30 Chicago — late in the day to catch UTC/local mixups.
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 30))!
        func item(_ title: String, _ day: String?, done: Bool = false) -> Item {
            var i = Item(title: title, deadline: day.map { parseDay($0)! })
            i.done = done
            return i
        }
        let items = [
            item("later", "2026-10-28"), item("week-end", "2026-10-27"), item("tomorrow", "2026-10-21"),
            item("today", "2026-10-20"), item("yesterday", "2026-10-19"), item("none", nil),
            item("finished", "2026-10-19", done: true),
        ]
        let g = groups(items, by: .deadline, now: now, timeZone: cal.timeZone)
        XCTAssertEqual(g.map(\.title), ["Overdue", "Today", "This week", "Later", "No date", "Done"])
        XCTAssertEqual(g.map { $0.items.map(\.title) },
                       [["yesterday"], ["today"], ["tomorrow", "week-end"], ["later"], ["none"], ["finished"]])

        // Same instant is already Oct 21 in Tokyo: everything shifts one day.
        let tokyo = groups(items, by: .deadline, now: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(tokyo.map { $0.items.map(\.title) },
                       [["yesterday", "today"], ["tomorrow"], ["week-end", "later"], ["none"], ["finished"]])
    }

    func testPriorityBucketsOmitEmptyAndDoneLast() {
        var done = Item(title: "d", priority: .high)
        done.done = true
        let items = [Item(title: "n"), done, Item(title: "h", priority: .high), Item(title: "l", priority: .low)]
        let g = groups(items, by: .priority)
        XCTAssertEqual(g.map(\.title), ["High", "Low", "No priority", "Done"])
        XCTAssertEqual(g.map { $0.items.map(\.title) }, [["h"], ["l"], ["n"], ["d"]])
    }
}
