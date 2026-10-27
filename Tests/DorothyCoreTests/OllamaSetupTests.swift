import XCTest
@testable import DorothyCore

final class OllamaSetupTests: XCTestCase {
    func testStateCombinations() {
        XCTAssertEqual(OllamaSetup.state(installed: false, running: false, hasModel: false), .notInstalled)
        XCTAssertEqual(OllamaSetup.state(installed: true, running: false, hasModel: false), .notRunning)
        XCTAssertEqual(OllamaSetup.state(installed: true, running: true, hasModel: false), .missingModel)
        XCTAssertEqual(OllamaSetup.state(installed: false, running: true, hasModel: false), .missingModel)
        XCTAssertEqual(OllamaSetup.state(installed: true, running: true, hasModel: true), .ready)
        XCTAssertEqual(OllamaSetup.state(installed: false, running: true, hasModel: true), .ready)
    }

    private func tags(_ json: String) -> Data { Data(json.utf8) }

    func testHasModelMatchesName() {
        XCTAssertTrue(OllamaSetup.hasModel(tagsJSON: tags(#"{"models":[{"name":"gemma4:e4b"}]}"#), model: "gemma4:e4b"))
        XCTAssertTrue(OllamaSetup.hasModel(tagsJSON: tags(#"{"models":[{"name":"Gemma4:E4B"}]}"#), model: "gemma4:e4b"))
    }

    func testHasModelMatchesModelField() {
        XCTAssertTrue(OllamaSetup.hasModel(tagsJSON: tags(#"{"models":[{"name":"x","model":"gemma4:e4b"}]}"#), model: "gemma4:e4b"))
    }

    func testHasModelUntaggedMatchesLatest() {
        XCTAssertTrue(OllamaSetup.hasModel(tagsJSON: tags(#"{"models":[{"name":"llama3:latest"}]}"#), model: "llama3"))
    }

    func testHasModelRejectsOtherTag() {
        XCTAssertFalse(OllamaSetup.hasModel(tagsJSON: tags(#"{"models":[{"name":"gemma4:e2b","model":"gemma4:e2b"}]}"#), model: "gemma4:e4b"))
    }

    func testHasModelEmptyAndGarbage() {
        XCTAssertFalse(OllamaSetup.hasModel(tagsJSON: tags(#"{"models":[]}"#), model: "gemma4:e4b"))
        XCTAssertFalse(OllamaSetup.hasModel(tagsJSON: Data([0xFF, 0x00, 0x13]), model: "gemma4:e4b"))
    }

    func testParsePullLines() throws {
        let manifest = try XCTUnwrap(OllamaSetup.parsePullLine(#"{"status":"pulling manifest"}"#))
        XCTAssertEqual(manifest.status, "pulling manifest")
        XCTAssertNil(manifest.fraction)
        XCTAssertFalse(manifest.isSuccess)

        let dl = try XCTUnwrap(OllamaSetup.parsePullLine(#"{"status":"downloading","digest":"sha","total":200,"completed":50}"#))
        XCTAssertEqual(dl.fraction ?? -1, 0.25, accuracy: 0.0001)

        XCTAssertTrue(try XCTUnwrap(OllamaSetup.parsePullLine(#"{"status":"success"}"#)).isSuccess)

        let err = try XCTUnwrap(OllamaSetup.parsePullLine(#"{"error":"pull model manifest: file does not exist"}"#))
        XCTAssertEqual(err.error, "pull model manifest: file does not exist")

        XCTAssertNil(OllamaSetup.parsePullLine(""))
        XCTAssertNil(OllamaSetup.parsePullLine("not json"))

        XCTAssertNil(try XCTUnwrap(OllamaSetup.parsePullLine(#"{"status":"downloading","total":0,"completed":0}"#)).fraction)
    }

    func testAppURLAndInstalled() {
        let a = URL(fileURLWithPath: "/A/Ollama.app"), b = URL(fileURLWithPath: "/B/Ollama.app")
        XCTAssertEqual(OllamaSetup.appURL(candidates: [a, b], exists: { $0 == b.path }), b)
        XCTAssertNil(OllamaSetup.appURL(candidates: [a, b], exists: { _ in false }))
        XCTAssertTrue(OllamaSetup.isInstalled(exists: { $0 == "/opt/homebrew/bin/ollama" }))
        XCTAssertFalse(OllamaSetup.isInstalled(exists: { _ in false }))
    }

    func testShouldOfferOnLaunch() {
        for s in [OllamaSetup.State.notInstalled, .notRunning, .missingModel] {
            XCTAssertTrue(OllamaSetup.shouldOfferOnLaunch(s, dismissed: false), "\(s)")
        }
        XCTAssertFalse(OllamaSetup.shouldOfferOnLaunch(.ready, dismissed: false))
        XCTAssertFalse(OllamaSetup.shouldOfferOnLaunch(.checking, dismissed: false))
        for s in [OllamaSetup.State.checking, .notInstalled, .notRunning, .missingModel, .ready] {
            XCTAssertFalse(OllamaSetup.shouldOfferOnLaunch(s, dismissed: true), "\(s)")
        }
    }
}
