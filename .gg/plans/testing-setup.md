# Testing Setup Plan

## Analysis

**Project type**: Swift 6.0 macOS app, built with XcodeGen (`project.yml`), no existing tests.

**Testing framework**: Swift Testing (`import Testing`, `@Test func`, `#expect`) — Apple's modern test framework, shipped with Xcode 16+. Preferred over XCTest for new Swift 6 projects.

**Test target**: XcodeGen `bundle.unit-test` target added to `project.yml`, sources in `tamagotchai/Tests/`.

### What to test

The app has two layers:
1. **Pure logic** (highly testable, no UI/network dependencies): tools, helpers, models, stream parser
2. **Integration** (needs mocks or real files): tool execution against temp directories

**Testable units identified**:

| Component | File | What to test |
|---|---|---|
| `FileSystemToolHelpers` | AgentTool.swift | `resolvePath` (absolute vs relative), `binaryExtensions`, `ignoredDirectories` |
| `ToolRegistry` | AgentTool.swift | `tool(named:)` lookup, `apiToolDefinitions()` schema shape |
| `ClaudeResponse` | ClaudeModels.swift | `textContent` extraction, `toolUseCalls` filtering |
| `StreamParser` | StreamParser.swift | SSE line parsing → content blocks, tool_use accumulation, text flushing, error handling |
| `ReadTool` | ReadTool.swift | Read file, offset/limit, binary detection, truncation, missing file |
| `WriteTool` | WriteTool.swift | Write file, create parent dirs, overwrite |
| `EditTool` | EditTool.swift | Single match replace, not found, multiple matches, CRLF normalization, diff output |
| `LsTool` | LsTool.swift | List directory, hidden files, empty dir, sorting |
| `FindTool` | FindTool.swift | Glob matching, ignored dirs, max 100 cap |
| `GrepTool` | GrepTool.swift | Regex search, case insensitive, include glob, max results, binary skip |
| `BashTool` | BashTool.swift | Execute command, exit code, timeout, output truncation |
| `WebFetchTool` | WebFetchTool.swift | SSRF validation (private IPs, localhost), blocked hosts |
| `OAuthCredentials` | ClaudeCredentials.swift | `isExpired` logic |

### What NOT to test (yet)
- `FloatingPanel`, `PromptPanelController` — heavy AppKit UI, needs UI testing framework
- `ClaudeService` — network-dependent, needs mock URLSession
- `MarkdownRenderer` — `@MainActor` + AppKit, complex rendering
- `MascotView` — Rive animation, visual only

## Architecture

```
tamagotchai/Tests/
├── Helpers/
│   └── FileSystemToolHelpersTests.swift     # resolvePath, binaryExtensions, ignoredDirs
├── Models/
│   ├── ClaudeModelsTests.swift              # ClaudeResponse, ContentBlock
│   └── OAuthCredentialsTests.swift          # isExpired
├── StreamParser/
│   └── StreamParserTests.swift              # SSE parsing: text, tool_use, server_tool, errors
├── Tools/
│   ├── ReadToolTests.swift                  # File reading, offset/limit, binary, truncation
│   ├── WriteToolTests.swift                 # File writing, parent dir creation
│   ├── EditToolTests.swift                  # Replace, not found, multiple matches, CRLF, diff
│   ├── LsToolTests.swift                    # Directory listing, hidden files, sorting
│   ├── FindToolTests.swift                  # Glob search, ignored dirs, result cap
│   ├── GrepToolTests.swift                  # Regex search, case insensitive, include glob
│   ├── BashToolTests.swift                  # Command execution, exit code, timeout, truncation
│   └── WebFetchToolTests.swift              # SSRF validation (private IPs, localhost blocks)
└── Registry/
    └── ToolRegistryTests.swift              # Tool lookup, API schema generation
```

All tool tests use a temp directory created in setUp/torn down after — no fixtures needed.

## Steps

1. Add `TamagotchaiTests` target to `project.yml` as `bundle.unit-test` with `sources: tamagotchai/Tests`, `dependencies: [target: Tamagotchai]`, link it to the main scheme's `testTargets`, then create the `tamagotchai/Tests/` directory
2. Create `tamagotchai/Tests/Helpers/FileSystemToolHelpersTests.swift` with Swift Testing: test `resolvePath` with absolute path, relative path, and trailing slash; test `binaryExtensions` contains key types (jpg, zip, exe, sqlite); test `ignoredDirectories` contains .git and node_modules
3. Create `tamagotchai/Tests/Models/ClaudeModelsTests.swift`: test `ClaudeResponse.textContent` with mixed content blocks returns only text; test `ClaudeResponse.toolUseCalls` filters only `.toolUse` blocks; test empty response returns empty string and empty array
4. Create `tamagotchai/Tests/Models/OAuthCredentialsTests.swift`: test `isExpired` returns true for past date, false for future date, true for exact now
5. Create `tamagotchai/Tests/StreamParser/StreamParserTests.swift`: test parsing text-only SSE lines produces `.text` block; test parsing tool_use SSE lines produces `.toolUse` block with parsed JSON input; test parsing server_tool_use and web_search_tool_result; test error event throws `streamError`; test `buildResponse` returns correct stop_reason — use `processLine` via feeding lines manually (StreamParser.processLine is private, so feed lines through a mock AsyncBytes or test `buildResponse` after constructing events)
6. Create `tamagotchai/Tests/Tools/ReadToolTests.swift`: create temp dir in init, write test files; test reading a normal file returns numbered lines; test offset/limit parameters; test binary file detection by extension; test missing file throws error; test file with trailing newline handling; clean up temp dir
7. Create `tamagotchai/Tests/Tools/WriteToolTests.swift`: test writing new file creates it with correct content; test writing creates parent directories; test overwriting existing file; test missing content parameter throws
8. Create `tamagotchai/Tests/Tools/EditToolTests.swift`: test single occurrence replacement produces diff output; test old_text not found throws; test multiple matches throws with count; test CRLF normalization; test missing parameters throw
9. Create `tamagotchai/Tests/Tools/LsToolTests.swift`: test listing directory returns dirs first then files sorted; test hidden files excluded by default; test `all: true` includes hidden files; test empty directory; test non-existent directory throws
10. Create `tamagotchai/Tests/Tools/FindToolTests.swift`: test glob pattern matches expected files; test ignored directories (.git) are skipped; test max 100 results cap; test no matches returns message
11. Create `tamagotchai/Tests/Tools/GrepToolTests.swift`: test regex pattern finds matches with line numbers; test case_insensitive flag; test include glob filters files; test max_results cap; test no matches returns message; test invalid regex throws
12. Create `tamagotchai/Tests/Tools/BashToolTests.swift`: test `echo hello` returns exit code 0 and output; test failing command returns non-zero exit code; test short timeout causes timeout message; test output truncation with large output
13. Create `tamagotchai/Tests/Tools/WebFetchToolTests.swift`: test SSRF validation — localhost, 127.0.0.1, 10.x.x.x, 172.16-31.x.x, 192.168.x.x are all blocked; test missing URL parameter throws; test invalid URL throws
14. Create `tamagotchai/Tests/Registry/ToolRegistryTests.swift`: test `defaultRegistry` creates all 8 tools; test `tool(named:)` returns correct tool; test `tool(named:)` returns nil for unknown name; test `apiToolDefinitions()` returns correct schema shape with name, description, input_schema keys
15. Run `xcodegen generate` to regenerate the Xcode project with the test target, then run `xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug test` to execute all tests and fix any compilation or test failures
16. Create `.gg/commands/test.md` with the /test command that runs all tests, collects failures, and spawns parallel sub-agents to fix them
