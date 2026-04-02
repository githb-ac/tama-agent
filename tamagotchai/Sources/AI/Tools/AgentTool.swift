import Foundation

/// Protocol that all agent tools must conform to.
protocol AgentTool: Sendable {
    /// The tool name as sent to the Anthropic API (e.g. "bash", "read").
    var name: String { get }

    /// Human-readable description of what the tool does.
    var description: String { get }

    /// JSON Schema describing the tool's input parameters,
    /// matching Anthropic's `input_schema` format.
    var inputSchema: [String: Any] { get }

    /// Execute the tool with the given arguments and return the result string.
    func execute(args: [String: Any]) async throws -> String
}

/// Holds the set of available tools and serializes their schemas for the API.
final class ToolRegistry: Sendable {
    let tools: [AgentTool]

    init(tools: [AgentTool]) {
        self.tools = tools
    }

    /// Creates the default registry with all built-in tools.
    static func defaultRegistry(workingDirectory: String? = nil) -> ToolRegistry {
        let cwd = workingDirectory ?? FileManager.default.currentDirectoryPath
        return ToolRegistry(tools: [
            BashTool(workingDirectory: cwd),
            ReadTool(workingDirectory: cwd),
            WriteTool(workingDirectory: cwd),
            EditTool(workingDirectory: cwd),
            LsTool(workingDirectory: cwd),
            FindTool(workingDirectory: cwd),
            GrepTool(workingDirectory: cwd),
            WebFetchTool(),
        ])
    }

    /// Look up a tool by name.
    func tool(named name: String) -> AgentTool? {
        tools.first { $0.name == name }
    }

    /// Serializes all tool definitions into the format expected by the Anthropic API.
    func apiToolDefinitions() -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
            ]
        }
    }
}
