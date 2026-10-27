import Foundation

/// Copy-pasteable setup for connecting MCP clients to the bundled `dorothy-mcp` server.
public enum MCPSetup {
    public static let serverName = "dorothy"
    public static let executableName = "dorothy-mcp"

    /// `dorothy-mcp` ships next to the app binary (Contents/MacOS, or .build/debug in development).
    public static func serverURL(appExecutable: URL) -> URL {
        appExecutable.deletingLastPathComponent().appendingPathComponent(executableName)
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func claudeCodeCommand(serverPath: String) -> String {
        "claude mcp add \(serverName) -- " + shellQuote(serverPath)
    }

    public static func jsonConfig(serverPath: String) -> String {
        let config = ["mcpServers": [serverName: ["command": serverPath]]]
        let data = try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
