import Foundation

private struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class FindTool: AgentTool, @unchecked Sendable {
    let name = "find"
    let description = "Find files matching a glob pattern. Returns sorted file paths, max 100 results."

    let workingDirectory: String

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Glob pattern to match files (e.g. '**/*.swift', 'src/**/*.ts')",
                ],
                "path": [
                    "type": "string",
                    "description": "Directory to search in (defaults to cwd)",
                ],
            ],
            "required": ["pattern"],
        ]
    }

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", "__pycache__", ".DS_Store",
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let pattern = args["pattern"] as? String else {
            throw ToolError(message: "Missing required parameter: pattern")
        }

        let pathArg = args["path"] as? String ?? "."
        let searchPath: String = if pathArg.hasPrefix("/") {
            pathArg
        } else {
            (workingDirectory as NSString).appendingPathComponent(pathArg)
        }

        let standardized = (searchPath as NSString).standardizingPath
        return try findFiles(pattern: pattern, in: standardized)
    }

    private func findFiles(
        pattern: String,
        in directory: String
    ) throws -> String {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir),
              isDir.boolValue
        else {
            throw ToolError(message: "Directory not found: \(directory)")
        }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.producesRelativePathURLs]
        ) else {
            throw ToolError(
                message: "Could not enumerate directory: \(directory)"
            )
        }

        var matches: [String] = []
        var totalMatches = 0

        while let obj = enumerator.nextObject() {
            guard let url = obj as? URL else { continue }
            let relativePath = url.relativePath
            let lastComponent = url.lastPathComponent

            if Self.ignoredDirectories.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            let matched = fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
                || fnmatch(pattern, lastComponent, 0) == 0

            if matched {
                totalMatches += 1
                if matches.count < 100 {
                    matches.append(relativePath)
                }
            }
        }

        matches.sort()

        if matches.isEmpty {
            return "No files found matching pattern: \(pattern)"
        }

        var result = matches.joined(separator: "\n")

        if totalMatches > 100 {
            result += "\n[100 of \(totalMatches) results shown]"
        }

        return result
    }
}
