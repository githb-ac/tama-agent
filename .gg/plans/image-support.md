# Image Support in Chat UI

## Analysis

### Current State
- **MarkdownRenderer** (`tamagotchai/Sources/PromptPanel/MarkdownRenderer.swift`, lines 761-772): When encountering `![alt](url)`, it renders as dim text `"🖼 alt"` — no actual image display.
- **ResponseTextView** (`tamagotchai/Sources/PromptPanel/ResponseTextView.swift`): An NSTextView subclass that draws code block backgrounds and manages copy buttons. Has no image handling.
- **FloatingPanel** (`tamagotchai/Sources/PromptPanel/FloatingPanel.swift`, line 592): `resignKey()` calls `dismiss()` — any child window (like an image preview) that steals focus will dismiss the panel.
- **User bubbles** already use `NSTextAttachment` + `NSTextAttachmentCell(imageCell:)` in `FloatingPanel+Response.swift` (line 386-388) — this proves the text view can render image attachments.
- **Workspace directory**: `~/Documents/Tamagotchai` is created by `PromptPanelController.ensureWorkspace()` (line 30-37). No screenshots subdirectory exists yet.

### What "images in the UI" means
The agent (via tools like bash, browser automation, etc.) will save screenshots to `~/Documents/Tamagotchai/Screenshots/` and include markdown image references `![alt](path)` in its responses. The `url` can be:
1. A **local file path** (e.g., `~/Documents/Tamagotchai/Screenshots/page.png`) — most common from agent/browser tools
2. A **file:// URL**
3. An **http(s):// URL** — from web content

### Architecture
Images need to work in two places:
1. **Streaming responses** — images appear inline as markdown is rendered character-by-character
2. **Restored conversations** — when loading a saved session, images should render again

The approach:
- **Screenshots directory**: Created alongside the workspace at app launch, so browser automation tools always have a known place to save screenshots.
- **MarkdownRenderer**: Instead of dim text, render actual `NSTextAttachment` with the loaded image (scaled to fit the panel width). For URLs that need fetching, show a placeholder first.
- **Image loading**: Synchronous for local files, async for remote URLs. Use a simple cache to avoid re-fetching.
- **Click to enlarge**: Add click handling in `ResponseTextView` to detect clicks on image attachments and open a preview window.
- **Preview window**: A child window of the panel so focus doesn't leave and trigger dismissal. Suppress `resignKey` dismissal while preview is shown.

### Key Constraints
- `resignKey()` dismisses the panel — need to handle this for image preview
- The panel is `level: .floating` — preview must float above it
- Strict concurrency (Swift 6) — image loading must be careful with `@Sendable`
- Images should be reasonably sized (max width ~600px to fit the 680px panel with insets)

## Steps

1. Update `PromptPanelController.ensureWorkspace()` in `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` (line 30-37) to also create a `Screenshots` subdirectory inside the workspace (`~/Documents/Tamagotchai/Screenshots/`). Add a `static var screenshotsDirectory: String` computed property that returns this path, so browser automation tools can reference it.

2. Add a custom `NSAttributedString.Key.imageURL` attribute key in `tamagotchai/Sources/PromptPanel/MarkdownRenderer.swift` (near the existing `.codeBlockContent` key on line 8) to tag image attachments with their source URL for click-to-enlarge handling.

3. Create `tamagotchai/Sources/PromptPanel/ImageCache.swift` — a simple `@MainActor` image cache that loads images from local file paths synchronously and caches `NSImage` by URL string. Keep it minimal: `static func load(from urlString: String) -> NSImage?` that handles `file://`, absolute paths starting with `/` or `~`, and `http(s)://` (for http, return nil — images from agent tools are almost always local files in the Screenshots directory).

4. Update `MarkdownRenderer.swift` `renderInline()` method (line 761-772) to replace the `"🖼 alt"` placeholder with an actual inline image: load the image via `ImageCache`, create a scaled `NSImage` (max width ~600, preserving aspect ratio), create an `NSTextAttachment` with `NSTextAttachmentCell(imageCell:)`, and tag it with `.imageURL` attribute. If the image can't be loaded, fall back to the existing `"🖼 alt"` dim text.

5. Create `tamagotchai/Sources/PromptPanel/ImagePreviewWindow.swift` — an `NSPanel` subclass (borderless, floating, transparent background) that shows a full-size image with a dark semi-transparent backdrop. Key features: (a) level set above the floating panel so it appears on top, (b) click anywhere or press Escape to close, (c) the image scales to fit the screen with padding. Add an `onDismiss` callback so the parent panel can clean up state.

6. Update `FloatingPanel.swift` `resignKey()` (line 592) to check if an image preview is active — if so, skip dismissal. Add `var isShowingImagePreview = false` property. Modify `resignKey()`: `guard !isShowingImagePreview else { return }` before the `dismiss()` call.

7. Add `showImagePreview(for url: String)` and `dismissImagePreview()` methods on `FloatingPanel`. `showImagePreview` creates/reuses an `ImagePreviewWindow`, loads the full-size image, adds it as a child window, and sets `isShowingImagePreview = true`. `dismissImagePreview` removes the child window, resets the flag, and calls `makeKeyAndOrderFront(nil)` to refocus the panel.

8. Update `ResponseTextView.swift` to handle clicks on image attachments: override `mouseDown(with:)` to check if the click location corresponds to a character with the `.imageURL` attribute. If so, call a new `var onImageClicked: ((String) -> Void)?` callback with the URL string. Otherwise, call `super.mouseDown(with:)`.

9. Wire up the image click callback in `FloatingPanel.swift` — in the `responseTextView` lazy initializer (around line 366-390), set `responseTextView.onImageClicked = { [weak self] url in self?.showImagePreview(for: url) }`.

10. Verify the build compiles cleanly with `xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` and test by having the agent output a markdown image reference to a local file.
