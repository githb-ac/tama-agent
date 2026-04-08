# Fix All Audit Findings

## Analysis

### Security Fixes (DANGEROUS/BROKEN)

**WebFetchTool.swift** — 5 SSRF issues + 2 resource issues:
- No URL scheme check (`file://` bypass) — line 48
- No redirect validation — line 64 (URLSession follows redirects by default)
- IPv6 private ranges not checked — line 141
- `169.254.0.0/16` not blocked — line 141
- Incomplete loopback blocking (only `127.0.0.1`) — line 128
- Entire response loaded into memory before truncation — line 67
- New URLSession per call, never invalidated — line 62-64

**ClaudeCredentials.swift** — deterministic encryption key (line 32-43):
- Fallback key from hardcoded string; UUID-based key reproducible by any process
- Fix: Use macOS Keychain to store a random encryption key

**ClaudeService.swift** — User-Agent impersonation (line 197-200):
- Sends `claude-cli/2.1.75` — change to honest identifier

**ScheduleStore.swift** — unsupervised routine execution (line 181-228):
- Routines run full AgentLoop with no user confirmation
- Fix: Show confirmation dialog before executing routines

### Performance Fixes (DANGEROUS)

**BashTool.swift**:
- `readDataToEndOfFile()` unbounded memory (line 55-57) — add incremental read with size cap
- Pipe hang after timeout: child processes hold pipe open (line 64) — use process group kill and close pipe on timeout

**GrepTool.swift**:
- No per-file size limit before reading (line 209-210) — add file size check

### Dead Code Cleanup

- `AgentLoop.swift:51,68` — remove `hasDismissTool`
- `StreamParser.swift:24-25` — remove `serverResultToolUseId`, `serverResultContent`
- `MarkdownRenderer.swift:65` — remove `prevWasBlank` and all writes to it
- `FloatingPanel.swift:828` — remove unused `chars` variable
- `ContentView.swift` — delete entire file
- `SpeechService.swift:2` — remove `import KokoroSwift`
- `project.yml:21-23` — remove NotchNotification package

## Steps

1. **WebFetchTool.swift**: Add URL scheme validation (only `http`/`https`), add `SafeRedirectDelegate` class that validates redirect targets against the same SSRF rules, create a shared URLSession with the delegate (reused, not per-call), replace `session.data(from:)` with `session.bytes(for:)` streaming with a 10MB byte limit, expand `isPrivateIP` to cover full `127.0.0.0/8` loopback range + `169.254.0.0/16` link-local range, add IPv6 private range checking (`::1`, `fe80::/10`, `fc00::/7`, `::ffff:` mapped addresses), add decimal/hex/octal IP detection to `blockedHosts`
2. **BashTool.swift**: Replace `readDataToEndOfFile()` with incremental pipe read capped at 10MB, use `setsid` via `posix_spawn` or set `process.qualityOfService` + launch in new process group so `terminate()` kills children, close the pipe's write end and read end explicitly on timeout so `readDataToEndOfFile` returns, add a 5s timeout on `readTask.value` after process termination
3. **GrepTool.swift**: Before `fm.contents(atPath:)` in `searchFiles`, check file size via `FileManager.attributesOfItem` and skip files larger than 10MB with a log warning
4. **ClaudeCredentials.swift**: Store a randomly-generated 256-bit encryption key in the macOS Keychain (service: `com.unstablemind.tamagotchai`, account: `encryption-key`), fall back to creating+storing a new key on first use, remove the hardware UUID / hardcoded string derivation
5. **ClaudeService.swift**: Change User-Agent from `claude-cli/2.1.75` to `tamagotchai/1.0` and `x-app` from `cli` to `tamagotchai`
6. **ScheduleStore.swift**: Before `executeRoutine`, show an `NSAlert` confirmation dialog with the job name and prompt preview, only proceed if the user confirms; add a "trust this routine" option that persists per-job so trusted routines skip the prompt
7. **AgentLoop.swift**: Remove the `hasDismissTool` variable declaration (line 51) and its assignment (line 68)
8. **StreamParser.swift**: Remove unused `serverResultToolUseId` (line 24) and `serverResultContent` (line 25)
9. **MarkdownRenderer.swift**: Remove `prevWasBlank` variable declaration (line 65) and all 9 assignments to it throughout the `render` method
10. **FloatingPanel.swift**: Remove the unused `let chars = characterQueue.prefix(count)` on line 828
11. **ContentView.swift**: Delete the entire file
12. **SpeechService.swift**: Remove the `import KokoroSwift` on line 2
13. **project.yml**: Remove the NotchNotification package declaration (lines 21-23) and regenerate Xcode project with `xcodegen generate`
14. Build the project with `xcodebuild` to verify all changes compile cleanly
