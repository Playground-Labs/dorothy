import XCTest
@testable import DorothyCore

final class SetupTests: XCTestCase {
    func testHasModelNormalizesLatest() {
        let tags = Data(#"{"models":[{"name":"gemma4:e4b","model":"gemma4:e4b"},{"name":"llama3","model":"llama3:latest"},{"model":"localhost:5000/me/tiny"}]}"#.utf8)
        XCTAssertTrue(Gemma.hasModel(tags: tags, "gemma4:e4b"))
        XCTAssertTrue(Gemma.hasModel(tags: tags, "llama3"))
        XCTAssertTrue(Gemma.hasModel(tags: tags, "llama3:latest"))
        XCTAssertTrue(Gemma.hasModel(tags: tags, "localhost:5000/me/tiny:latest"))
        XCTAssertFalse(Gemma.hasModel(tags: tags, "gemma4"))
        XCTAssertFalse(Gemma.hasModel(tags: Data(#"{"models":[]}"#.utf8), "gemma4:e4b"))
        XCTAssertFalse(Gemma.hasModel(tags: Data("junk".utf8), "gemma4:e4b"))
    }

    func testPullLine() {
        let p = Gemma.pullLine(#"{"status":"pulling 4c27e0f5b5ad","digest":"sha256:4c27","total":2000,"completed":500}"#)
        XCTAssertEqual(p, PullProgress(status: "pulling 4c27e0f5b5ad", digest: "sha256:4c27", completed: 500, total: 2000))
        XCTAssertEqual(Gemma.pullLine(#"{"error":"pull model manifest: file does not exist"}"#)?.error, "pull model manifest: file does not exist")
        XCTAssertNil(Gemma.pullLine("not json"))
    }

    func testPullTallySumsLayersAndNeverGoesBackwards() {
        var t = PullTally()
        let lines = [
            #"{"status":"pulling manifest"}"#,
            #"{"status":"pulling aaa","digest":"a","total":900,"completed":450}"#,
            #"{"status":"pulling bbb","digest":"b","total":100}"#,                  // new layer grows the total: hold, don't drop
            #"{"status":"pulling bbb","digest":"b","total":100,"completed":100}"#,
            #"{"status":"pulling aaa","digest":"a","total":900,"completed":0}"#,    // stale per-layer reset: ignored
            #"{"status":"pulling aaa","digest":"a","total":900,"completed":900}"#,
            #"{"status":"verifying sha256 digest"}"#,
            #"{"status":"success"}"#,
        ]
        var seen: [Double] = []
        for l in lines { t.add(Gemma.pullLine(l)!); seen.append(t.fraction) }
        XCTAssertEqual(seen, [0, 0.5, 0.5, 0.55, 0.55, 1, 1, 1])
        XCTAssertEqual(t.totalBytes, 1000)
        XCTAssertEqual(t.status, "success")
    }
}
