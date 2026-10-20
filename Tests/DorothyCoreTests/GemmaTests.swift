import XCTest
@testable import DorothyCore

final class GemmaTests: XCTestCase {
    func testDecodesFencedJSON() throws {
        let r = try Gemma.decodeItems(from: """
        ```json
        {"items": [{"title": "Pay rent", "priority": "high", "deadline": "2026-10-23", "list": null}]}
        ```
        """)
        XCTAssertEqual(r.items, [ParsedItem(title: "Pay rent", priority: .high, deadline: "2026-10-23")])
        XCTAssertEqual(r.transcript, "")
    }

    func testDecodesProseWrappedJSONWithTranscriptAndUnknownPriority() throws {
        let r = try Gemma.decodeItems(from: """
        Sure! Here you go: {"transcript": "call mom", "items": [{"title": "Call mom", "priority": "SUPER", "deadline": null, "list": "Work"}]} Hope that helps.
        """)
        XCTAssertEqual(r.transcript, "call mom")
        XCTAssertEqual(r.items, [ParsedItem(title: "Call mom", priority: .none, list: "Work")])
    }

    func testDecodeThrowsWithoutJSON() {
        XCTAssertThrowsError(try Gemma.decodeItems(from: "no json here"))
    }

    func testApplyListGuardAndDeadline() {
        let inbox = TodoList(name: "Inbox", color: "#FF4FA3")
        let errands = TodoList(name: "Errands", color: "#2E5BFF")
        let work = TodoList(name: "Work", color: "#22D39A")
        var data = DorothyData(lists: [inbox, errands, work])
        let parsed = [
            ParsedItem(title: "Buy milk", deadline: "2026-10-21", list: "errands"),  // named in source → Errands
            ParsedItem(title: "Call mom", list: "Work"),                             // not named → Inbox
            ParsedItem(title: "Dance", list: "Gym"),                                 // no such list → Inbox
            ParsedItem(title: "  ", list: "Errands"),                                // empty → skipped
        ]
        let r = Gemma.apply(parsed, sourceText: "Buy milk tomorrow for ERRANDS, call mom, dance", defaultListID: inbox.id, to: &data)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.list, "Inbox")
        XCTAssertEqual(data.lists[1].items.map(\.title), ["Buy milk"])
        XCTAssertEqual(data.lists[1].items[0].deadline, parseDay("2026-10-21"))
        XCTAssertEqual(data.lists[0].items.map(\.title), ["Call mom", "Dance"])
        XCTAssertNil(data.lists[0].items[0].deadline)
        XCTAssertTrue(data.lists[2].items.isEmpty)
    }

    func testListGuardIsWholeWord() {
        let inbox = TodoList(name: "Inbox", color: "#FF4FA3")
        var data = DorothyData(lists: [inbox, TodoList(name: "Work", color: "#2E5BFF"), TodoList(name: "Trip to Lisbon", color: "#22D39A")])
        Gemma.apply([ParsedItem(title: "Finish homework", list: "Work")], sourceText: "finish homework tonight", defaultListID: inbox.id, to: &data)
        Gemma.apply([ParsedItem(title: "Book hotel", list: "trip to lisbon")], sourceText: "book hotel for my TRIP TO LISBON", defaultListID: inbox.id, to: &data)
        Gemma.apply([ParsedItem(title: "Email Sam", list: "Work")], sourceText: "email Sam, for work.", defaultListID: inbox.id, to: &data)
        XCTAssertEqual(data.lists.map { $0.items.map(\.title) }, [["Finish homework"], ["Email Sam"], ["Book hotel"]])
    }

    func testHostURL() {
        XCTAssertEqual(Gemma.hostURL(nil).absoluteString, "http://127.0.0.1:11434")
        XCTAssertEqual(Gemma.hostURL("127.0.0.1:11434").absoluteString, "http://127.0.0.1:11434")
        XCTAssertEqual(Gemma.hostURL("0.0.0.0").absoluteString, "http://127.0.0.1:11434")
        XCTAssertEqual(Gemma.hostURL("0.0.0.0:9999").absoluteString, "http://127.0.0.1:9999")
        XCTAssertEqual(Gemma.hostURL("http://localhost").absoluteString, "http://localhost:11434")
        XCTAssertEqual(Gemma.hostURL("https://gpu.box:443").absoluteString, "https://gpu.box:443")
    }

    func testPromptHasComputedDates() {
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!  // Tuesday
        let p = Gemma.prompt(lists: ["Work"], now: now, audio: false, timeZone: TimeZone(identifier: "UTC")!)
        for s in ["Today is Tuesday 2026-10-20", "Tomorrow = 2026-10-21", "Next week = 2026-10-26 (Monday)",
                  "friday = 2026-10-23", "monday = 2026-10-26", "tuesday = 2026-10-27", "[\"Work\"]"] {
            XCTAssertTrue(p.contains(s), s)
        }
    }

    /// DOROTHY_LIVE=1 swift test --filter GemmaTests/testLivePriorityAndDates
    func testLivePriorityAndDates() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DOROTHY_LIVE"] == "1")
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        let cases: [(String, Priority, String?)] = [
            ("Work: prep slides next week", .none, "2026-10-26"),
            ("finish my homework tonight", .none, "2026-10-20"),
            ("buy milk", .none, nil),
            ("call the bank asap", .high, nil),
            ("clean the garage someday", .low, nil),
            ("renew passport, medium priority", .medium, nil),
            ("pay rent friday", .none, "2026-10-23"),
        ]
        for (text, priority, deadline) in cases {
            let items = try await Gemma.parse(text: text, lists: ["Errands", "Work"], now: now)
            print("LIVE \(text) →", items.map { "\($0.title) | \($0.priority) | \($0.deadline ?? "-") | \($0.list ?? "-")" })
            XCTAssertEqual(items.first?.priority, priority, text)
            XCTAssertEqual(items.first?.deadline, deadline, text)
        }
    }

    /// DOROTHY_LIVE=1 swift test --filter GemmaTests/testLive
    func testLive() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DOROTHY_LIVE"] == "1")
        let reachable = await Gemma.isReachable()
        XCTAssertTrue(reachable)
        let items = try await Gemma.parse(text: "pay rent friday urgent and call mom", lists: ["Errands", "Work"])
        print("LIVE text →", items)
        XCTAssertGreaterThanOrEqual(items.count, 2)
        let wav = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../.context/t.wav"))
        let audio = try await Gemma.parse(audioWAV: wav, lists: ["Errands", "Work"])
        print("LIVE audio →", audio.transcript, audio.items)
        XCTAssertFalse(audio.items.isEmpty)
    }
}
