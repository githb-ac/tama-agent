# High Priority Refactor Plan

## Overview

Four high-priority refactors targeting the biggest code quality issues: the FloatingPanel god class, ClaudeService mixed concerns, duplicated tool code, and duplicated window controller boilerplate.

## Analysis

### 1. FloatingPanel God Class (1325 lines)
The `FloatingPanel` class in `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` handles window management, text streaming animation (CVDisplayLink + character queue), cursor blinking, panel resizing, user bubble rendering, scroll management, and contains 5 inner classes.

**Extraction plan:**
- **`StreamingTextEngine`** — Character queue, display link, cursor blink, `displayLinkFired()`, `finishTyping()`, `renderDisplayedMarkdown()`. ~180 lines. This is the most self-contained piece — it reads from `characterQueue` and writes to `displayedMarkdown`, calling back to the panel for rendering.
- **`SkeletonView`** → own file (lines 1137–1206, ~70 lines). Completely self-contained, no references to FloatingPanel internals.
- **`ToolIndicatorView`** → own file (lines 1211–1325, ~115 lines). Also fully self-contained.
- **`ConditionalScrollView`**, **`FlippedStackView`**, **`WhiteCursorTextField`** → own file `PanelHelperViews.swift` (~40 lines combined). Trivial helpers.
- **`makeUserBubble()`** → stays in FloatingPanel (it reads `panelWidth` and `conversationAttributed.length`). Not worth extracting — it's a single method.
- **Panel resize logic** (`updateHeight`, `computeTextHeight`, `measureTextHeight`, scroll methods) — these are tightly coupled to panel state (`topY`, `responseMaxHeight`, `reachedMaxHeight`, constraints). Keep in FloatingPanel.

After extraction, FloatingPanel drops from ~1325 to ~950 lines — still large but within reason for a complex panel class, and the `swiftlint:disable` can be removed.

### 2. ClaudeService Mixed Concerns (604 lines)
`tamagotchai/Sources/AI/ClaudeService.swift` has 4 things:
- `TimeZone.offsetString()` extension (lines 4–14)
- API model types: `ContentBlock`, `ClaudeResponse`, `StreamEvent` (lines 17–55)
- `ClaudeService` class (lines 59–401)
- `StreamParser` class (lines 407–604)

Also: dead `send()` method (lines 109–128) and dead `streamRequestLegacy()` (lines 170–232).

**Extraction plan:**
- Move `ContentBlock`, `ClaudeResponse`, `StreamEvent` → new `AI/ClaudeModels.swift`
- Move `StreamParser` → new `AI/StreamParser.swift`
- Move `TimeZone.offsetString()` into `dynamicContext()` inline (it's only used there) or a small extensions file
- Delete dead `send()` and `streamRequestLegacy()` methods (~120 lines)
- Fix stale "Keychain" comment on line 87

After: ClaudeService drops from 604 to ~250 lines.

### 3. Duplicated Tool Code
**Path resolution** — 6 tools have identical logic:
- `ReadTool.swift:92–96` (`resolvePath()`)
- `GrepTool.swift:90–92` (inline in `parseArgs`)
- `FindTool.swift:45–48` (inline in `execute`)
- `WriteTool.swift:45–48` (inline in `execute`)
- `LsTool.swift:39–42` (inline in `execute`)
- `EditTool.swift:64–68` (inline in `execute`)

**`binaryExtensions`** — identical sets in `ReadTool.swift:41–49` and `GrepTool.swift:52–60`

**`ignoredDirectories`** — nearly identical in `FindTool.swift:35–37` and `GrepTool.swift:48–50`. FindTool includes `.DS_Store` which is a file (bug).

**Plan:** Add a `FileSystemToolHelpers` enum (namespace) in `AgentTool.swift` with:
- `static func resolvePath(_ path: String, workingDirectory: String) -> String`
- `static let binaryExtensions: Set<String>`
- `static let ignoredDirectories: Set<String>` (without `.DS_Store`)

Then update all 6 tools to use these shared helpers. Using an `AgentTool` protocol extension won't work cleanly because `WebFetchTool` and `BashTool` don't have `workingDirectory`, so a standalone namespace enum is cleaner.

### 4. Duplicated Window Controllers
`LoginWindowController.swift` and `PermissionsWindowController.swift` are ~95% identical. Both:
- Hold a static `panel: NSPanel?`
- Create NSPanel with borderless style
- Set up NSVisualEffectView with hudWindow material
- Host a SwiftUI view inside
- Position below menu bar using mouse location
- Have identical `dismiss()`

**Callers:**
- `LoginWindowController.show(isLoggedIn:onLoginStateChanged:)` — called from `TamagotchaiApp.swift:25,29` and dismissed from `LoginView.swift:36,61,133`
- `PermissionsWindowController.show()` — called from `TamagotchaiApp.swift:18` and dismissed from `PermissionsView.swift:55`

**Plan:** Create `DropdownPanelController` as a generic shared implementation in `tamagotchai/Sources/UI/DropdownPanelController.swift`. Then rewrite both window controllers to delegate to it. Keep the existing `LoginWindowController` and `PermissionsWindowController` enums as thin wrappers so callers don't need to change.

## Risks

- **FloatingPanel streaming**: The `StreamingTextEngine` extraction touches timing-sensitive display link code. Must verify the typing animation still works correctly after the refactor.
- **Build breakage**: XcodeGen (`project.yml`) auto-discovers sources from `tamagotchai/Sources/`, so new files in existing directories should be picked up automatically. No `project.yml` changes needed.
- **Concurrency**: Moving `StreamParser` to its own file doesn't change its access level (it stays `private` to the module — actually it's `private class` so we need to change it to `internal` or keep it in the same file... wait, it's `private class StreamParser` which means file-private). We'll need to change it to `final class StreamParser` (internal) when moving to its own file.

## Steps

1. Create `tamagotchai/Sources/PromptPanel/SkeletonView.swift` — move the `SkeletonView` class from `FloatingPanel.swift` lines 1137–1206, change from `private` to `internal`
2. Create `tamagotchai/Sources/PromptPanel/ToolIndicatorView.swift` — move the `ToolIndicatorView` class from `FloatingPanel.swift` lines 1211–1325, change from `private` to `internal`
3. Create `tamagotchai/Sources/PromptPanel/PanelHelperViews.swift` — move `ConditionalScrollView` (lines 1092–1111), `FlippedStackView` (lines 1117–1119), and `WhiteCursorTextField` (lines 1124–1132) from `FloatingPanel.swift`, change from `private` to `internal`
4. Remove the extracted inner classes from `FloatingPanel.swift` (lines 1088–1325) and remove the `swiftlint:disable` on line 15
5. Remove dead methods `isScrolledNearBottom()` (lines 958–965) and `scrollToBottomIfNeeded()` (lines 967–972) from `FloatingPanel.swift`
6. Create `tamagotchai/Sources/AI/ClaudeModels.swift` — move `ContentBlock`, `ClaudeResponse`, and `StreamEvent` from `ClaudeService.swift` lines 17–55
7. Create `tamagotchai/Sources/AI/StreamParser.swift` — move the `StreamParser` class from `ClaudeService.swift` lines 407–604, change access from `private` to `final class` (internal), update the `ClaudeService.ClaudeServiceError` reference to use the full path since it's now in a different file
8. Delete dead code from `ClaudeService.swift`: the `send()` method (lines 108–128), the `streamRequestLegacy()` method (lines 170–232), and the `TimeZone.offsetString()` extension (lines 4–14) — inline the timezone formatting into `dynamicContext()`
9. Fix the stale comment on `ClaudeService.swift` line 87: change "loaded from Keychain" to "loaded from encrypted file"
10. Create shared tool helpers: add a `FileSystemToolHelpers` enum in `tamagotchai/Sources/AI/Tools/AgentTool.swift` with `resolvePath(_:workingDirectory:)`, `binaryExtensions`, and `ignoredDirectories` (without `.DS_Store`)
11. Update `ReadTool.swift` to use `FileSystemToolHelpers.resolvePath()` and `FileSystemToolHelpers.binaryExtensions`, removing its private copies
12. Update `GrepTool.swift` to use `FileSystemToolHelpers.resolvePath()`, `FileSystemToolHelpers.binaryExtensions`, and `FileSystemToolHelpers.ignoredDirectories`, removing its private copies
13. Update `FindTool.swift` to use `FileSystemToolHelpers.resolvePath()` and `FileSystemToolHelpers.ignoredDirectories`, removing its private copies (this also fixes the `.DS_Store` bug)
14. Update `WriteTool.swift` to use `FileSystemToolHelpers.resolvePath()` and replace raw `NSError` throws with the shared `ToolError` pattern
15. Update `LsTool.swift` to use `FileSystemToolHelpers.resolvePath()`
16. Update `EditTool.swift` to use `FileSystemToolHelpers.resolvePath()`
17. Create `tamagotchai/Sources/UI/DropdownPanelController.swift` — a generic `@MainActor enum DropdownPanelController` with a static `show<Content: View>(content: Content)` method and `dismiss()` that contains the shared NSPanel + NSVisualEffectView + mouse positioning logic
18. Rewrite `LoginWindowController.swift` to use `DropdownPanelController` internally, keeping the same public API (`show(isLoggedIn:onLoginStateChanged:)` and `dismiss()`)
19. Rewrite `PermissionsWindowController.swift` to use `DropdownPanelController` internally, keeping the same public API (`show()` and `dismiss()`)
20. Build the project with `xcodebuild` to verify everything compiles cleanly
