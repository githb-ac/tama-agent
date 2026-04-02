import Foundation

final class WriteTool: AgentTool, @unchecked Sendable {
    let name = "write"
    let description = "Write content to a file. Creates parent directories if needed."
    let workingDirectory: String

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "file_path": [
                    "type": "string",
                    "description": "The file path to write to",
                ],
                "content": [
                    "type": "string",
                    "description": "The content to write",
                ],
            ],
            "required": ["file_path", "content"],
        ]
    }

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func execute(args: [String: Any]) async throws -> String {
        guard let filePath = args["file_path"] as? String else {
            throw NSError(
                domain: "WriteTool",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing required parameter: file_path"]
            )
        }
        guard let content = args["content"] as? String else {
            throw NSError(
                domain: "WriteTool",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing required parameter: content"]
            )
        }

        let absolutePath: String = if filePath.hasPrefix("/") {
            filePath
        } else {
            (workingDirectory as NSString).appendingPathComponent(filePath)
        }

        let fileURL = URL(fileURLWithPath: absolutePath)
        let parentDir = fileURL.deletingLastPathComponent()

        let fm = FileManager.default
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        guard let data = content.data(using: .utf8) else {
            throw NSError(
                domain: "WriteTool",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode content as UTF-8"]
            )
        }

        try data.write(to: fileURL)

        return "Wrote \(data.count) bytes to \(absolutePath)"
    }
}
