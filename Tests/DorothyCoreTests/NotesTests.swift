import XCTest
import DorothyCore

final class NotesTests: XCTestCase {
    func tempStore() -> Store {
        Store(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("dorothy.json"))
    }

    func testNotesRoundTripThroughStore() throws {
        let store = tempStore()
        try store.mutate { $0.lists[0].items.append(Item(title: "Milk", notes: "2% from the corner shop")) }
        let item = try Store(url: store.url).load().lists[0].items[0]
        XCTAssertEqual(item.notes, "2% from the corner shop")
    }

    func testLegacyFileWithoutNotesDecodes() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"lists":[{"color":"#FF4FA3","groupBy":"priority","id":"\(UUID().uuidString)","items":[\
        {"createdAt":"2026-10-01T12:00:00Z","done":false,"id":"\(UUID().uuidString)","priority":"high","title":"Milk"}\
        ],"name":"Inbox"}]}
        """
        try Data(json.utf8).write(to: store.url)
        let data = try store.load()
        XCTAssertEqual(data.lists[0].items[0].title, "Milk")
        XCTAssertNil(data.lists[0].items[0].notes)
    }

    func testNormalizedNotesTrimsAndEmptiesToNil() {
        XCTAssertEqual(Item.normalizedNotes("  hi \n"), "hi")
        XCTAssertNil(Item.normalizedNotes("   "))
        XCTAssertNil(Item.normalizedNotes(nil))
        XCTAssertNil(Item(title: "x", notes: " \n ").notes)
    }

    func testNotesCappedAt250() {
        XCTAssertEqual(Item.notesLimit, 250)
        XCTAssertEqual(Item(title: "x", notes: String(repeating: "a", count: 300)).notes?.count, 250)
        let exact = String(repeating: "b", count: 250)
        XCTAssertEqual(Item(title: "x", notes: exact).notes, exact)
        XCTAssertEqual(Item.normalizedNotes(String(repeating: "é", count: 260))?.count, 250)
    }

    func testSettingNotesPersistsAndClears() throws {
        let store = tempStore()
        try store.mutate { $0.lists[0].items.append(Item(title: "Milk")) }
        try store.mutate { $0.lists[0].items[0].notes = "x" }
        XCTAssertEqual(try Store(url: store.url).load().lists[0].items[0].notes, "x")
        try store.mutate { $0.lists[0].items[0].notes = nil }
        XCTAssertNil(try Store(url: store.url).load().lists[0].items[0].notes)
    }
}
