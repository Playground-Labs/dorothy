import XCTest
import DorothyCore

final class MCPSetupTests: XCTestCase {
    func testServerURLIsSiblingOfAppExecutable() {
        let url = MCPSetup.serverURL(appExecutable: URL(fileURLWithPath: "/Applications/Dorothy.app/Contents/MacOS/Dorothy"))
        XCTAssertEqual(url.path, "/Applications/Dorothy.app/Contents/MacOS/dorothy-mcp")
    }

    func testClaudeCodeCommandQuotesPath() {
        XCTAssertEqual(MCPSetup.claudeCodeCommand(serverPath: "/Users/a b/Dorothy.app/Contents/MacOS/dorothy-mcp"),
                       "claude mcp add dorothy -- '/Users/a b/Dorothy.app/Contents/MacOS/dorothy-mcp'")
    }

    func testShellQuoteEscapesSingleQuote() {
        XCTAssertEqual(MCPSetup.shellQuote("it's"), "'it'\\''s'")
    }

    func testJSONConfigRoundTrips() throws {
        let json = MCPSetup.jsonConfig(serverPath: "/x/dorothy-mcp")
        XCTAssertFalse(json.contains("\\/"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(obj["mcpServers"] as? [String: Any])
        let dorothy = try XCTUnwrap(servers["dorothy"] as? [String: Any])
        XCTAssertEqual(dorothy["command"] as? String, "/x/dorothy-mcp")
    }
}
