import XCTest
import DorothyCore

final class MarkdownTests: XCTestCase {
    func testExportParseRoundTrip() {
        var rent = Item(title: "Pay rent", priority: .high, deadline: parseDay("2026-10-23"))
        rent.done = true
        var errands = TodoList(name: "Errands", color: "#FF4FA3")
        errands.items = [rent, Item(title: "Buy oat milk")]
        let data = DorothyData(lists: [errands, TodoList(name: "Empty", color: "#2E5BFF")])

        let md = MarkdownIO.export(data)
        XCTAssertTrue(md.hasPrefix("<!-- Dorothy export · "))
        XCTAssertTrue(md.contains("# Errands\n- [x] Pay rent !high due:2026-10-23\n- [ ] Buy oat milk\n\n# Empty\n"))

        let lists = MarkdownIO.parse(md)
        XCTAssertEqual(lists.map(\.name), ["Errands", "Empty"])
        let items = lists[0].items
        XCTAssertEqual(items.map(\.title), ["Pay rent", "Buy oat milk"])
        XCTAssertEqual(items.map(\.done), [true, false])
        XCTAssertEqual(items.map(\.priority), [.high, .none])
        XCTAssertEqual(items.map(\.deadline), [rent.deadline, nil])
    }

    func testTrailingTokens() {
        let md = """
        ## Work
        - [X] Ship it due:2026-10-21 !low
        * [ ] Ping Bob !medium
        - Say hi! to due:2026-10-22 team
        - Fix bug due:2026-13-01
        - Odd !urgent
        """
        let items = MarkdownIO.parse(md)[0].items
        XCTAssertEqual(items.map(\.title), ["Ship it", "Ping Bob", "Say hi! to due:2026-10-22 team", "Fix bug due:2026-13-01", "Odd !urgent"])
        XCTAssertEqual(items.map(\.priority), [.low, .medium, .none, .none, .none])
        XCTAssertEqual(items.map(\.done), [true, false, false, false, false])
        XCTAssertEqual(items[0].deadline, parseDay("2026-10-21"))
        XCTAssertEqual(items.dropFirst().compactMap(\.deadline), [])
    }

    func testSpacesAndNewlines() {
        let items = MarkdownIO.parse("- Call  Bob   now  !high\n- [ ]  \n- Tidy  up", calendar: dayCalendar)[0].items
        XCTAssertEqual(items.map(\.title), ["Call  Bob   now", "Tidy  up"])
        XCTAssertEqual(items[0].priority, .high)

        var list = TodoList(name: "Two\nLines", color: "#FF4FA3")
        list.items = [Item(title: "a\nb")]
        XCTAssertTrue(MarkdownIO.export(DorothyData(lists: [list])).hasSuffix("# Two Lines\n- [ ] a b\n"))
    }

    func testItemsBeforeHeadingGoToImported() {
        let lists = MarkdownIO.parse("<!-- x -->\n- one\nsome prose\n\n# Home\n- two")
        XCTAssertEqual(lists.map(\.name), ["Imported", "Home"])
        XCTAssertEqual(lists.map { $0.items.map(\.title) }, [["one"], ["two"]])
    }

    func testMergeDedupesAddsListsNeverDeletes() {
        var inbox = TodoList(name: "Inbox", color: TodoList.palette[0])
        inbox.items = [Item(title: "Milk"), Item(title: "Keep me")]
        var data = DorothyData(lists: [inbox])

        let imported = MarkdownIO.parse("# inbox\n- milk\n- Bread\n# Work\n- Ship\n- ship")
        let added = MarkdownIO.merge(imported, into: &data)

        XCTAssertEqual(added.lists, 1)
        XCTAssertEqual(added.items, 2)
        XCTAssertEqual(data.lists.map(\.name), ["Inbox", "Work"])
        XCTAssertEqual(data.lists[0].items.map(\.title), ["Milk", "Keep me", "Bread"])
        XCTAssertEqual(data.lists[1].items.map(\.title), ["Ship"])
        XCTAssertEqual(data.lists[1].color, TodoList.palette[1])
    }
}
