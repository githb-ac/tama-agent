# Code Blocks Redesign

## Problem
Code blocks currently render as plain monospaced white text with a flat `.backgroundColor` fill. No rounded corners, no visual header bar, no copy button, no syntax highlighting. Doesn't match the app's glassmorphism / HUD aesthetic.

## Aesthetic Reference (must match)
The app uses a consistent dark glassmorphism style throughout:
- **Colors**: `NSColor(white: 0.15, alpha: 0.6)` for backgrounds, white text at 0.85–0.95 opacity, `NSColor.secondaryLabelColor` for dim text
- **Borders**: 0.5px `white.withAlphaComponent(0.15)`
- **Corner radius**: 8–12px on UI elements
- **Buttons**: Translucent fills (`white @ 0.08` normal, `0.14` hover), 0.5px white border, rounded corners 8px — see `GlassButton.swift`
- **Indicators**: `.hudWindow` vibrancy, pill-shaped, spinner+label — see `ToolIndicatorView` in `FloatingPanel.swift`
- **Panel**: 680px wide, `.hudWindow` material, 28px corner radius

The copy button and code block header must match this aesthetic exactly.

## Syntax Highlighting
Use **Highlightr** (`https://github.com/raspu/Highlightr`) — SPM package that wraps highlight.js:
- 185 languages, 89 themes, returns `NSAttributedString`  
- Usage: `let highlightr = Highlightr(); highlightr.setTheme(to: "atom-one-dark"); let highlighted = highlightr.highlight(code, as: "swift")`
- Use `atom-one-dark` theme (dark, fits our HUD aesthetic)
- Falls back to plain mono text if highlighting fails or language is unknown
- Add to `project.yml` under `packages:` and `dependencies:`

## Architecture

### Custom Attributes
- `NSAttributedString.Key("codeBlockContent")` — stores raw code string for copy button
- `NSAttributedString.Key("codeBlockLanguage")` — stores language string for header label

### ResponseTextView (NSTextView subclass)
Replaces the plain `NSTextView()` in `FloatingPanel.swift` line 178. Responsibilities:
- `draw(_:)` override: enumerate `.codeBlockContent` ranges, compute bounding rects, draw rounded-rect backgrounds (corner radius 10, fill `NSColor(white: 0.10, alpha: 0.85)`, 0.5px border `white @ 0.1`) BEFORE `super.draw()`
- Draw language label in top-right of each block's background rect (small, dim text)
- Manage array of `CodeBlockCopyButton` overlays, positioned top-right of each code block
- `updateCodeBlockOverlays()` method to create/reposition/remove buttons after text changes

### CodeBlockCopyButton (NSButton subclass)
Styled to match glassmorphism:
- 24×24pt, SF Symbol `doc.on.doc` at 11pt, `white @ 0.7`
- Background: `white @ 0.06` normal, `0.14` hover
- Corner radius 6, 0.5px border `white @ 0.12`
- On click: copy associated code to `NSPasteboard.general`, swap icon to `checkmark` for 1.5s
- Tracking area for hover state

### MarkdownRenderer Changes
- Remove `.backgroundColor` from code block text (custom draw handles it)
- Apply `.codeBlockContent` and `.codeBlockLanguage` custom attributes
- Use Highlightr to syntax-highlight the code content, preserving the custom attributes
- Language label no longer rendered as separate attributed text — drawn by ResponseTextView

## Files to modify
- `project.yml` — add Highlightr package dependency
- `tamagotchai/Sources/PromptPanel/MarkdownRenderer.swift` — update `appendCodeBlock` (~lines 336-373)
- `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` — new `ResponseTextView` subclass, `CodeBlockCopyButton`, replace text view instantiation

## Steps
1. In `project.yml`, add Highlightr as an SPM dependency: under `packages:` add `Highlightr: { url: "https://github.com/raspu/Highlightr", from: "2.2.1" }`, and under the Tamagotchai target's `dependencies:` add `- package: Highlightr` — then regenerate the Xcode project with `xcodegen generate`
2. In `MarkdownRenderer.swift`, add two custom attribute keys (`static let codeBlockContent = NSAttributedString.Key("codeBlockContent")` and `static let codeBlockLanguage = NSAttributedString.Key("codeBlockLanguage")`), then rewrite `appendCodeBlock` to: (a) use Highlightr to syntax-highlight the code content with `atom-one-dark` theme, falling back to plain mono text, (b) remove `.backgroundColor` from the code attributes, (c) apply `.codeBlockContent` (raw code string) and `.codeBlockLanguage` (language string) across the entire code block range, (d) remove the separate language label append (it will be drawn by ResponseTextView), (e) keep the paragraph style with headIndent/tailIndent/firstLineHeadIndent for proper text inset
3. In `FloatingPanel.swift`, create `CodeBlockCopyButton: NSView` (not NSButton, for full control) at the bottom of the file: 24×24pt view with a CALayer background (`white @ 0.06`, corner radius 6, 0.5px border `white @ 0.12`), an NSImageView centered showing SF Symbol `doc.on.doc` at 11pt in `white @ 0.7`, NSTrackingArea for hover (changes bg to `white @ 0.14`), a `codeString` property, mouseDown handler that copies `codeString` to `NSPasteboard.general` and swaps the image to `checkmark` for 1.5s with a DispatchQueue delayed reset
4. In `FloatingPanel.swift`, create `ResponseTextView: NSTextView` subclass that: (a) has a `private var copyButtons: [CodeBlockCopyButton] = []` array, (b) overrides `draw(_:)` to enumerate `.codeBlockContent` ranges in `textStorage`, compute bounding rects via `layoutManager?.boundingRect(forGlyphRange:in:)` (or textLayoutManager equivalent), draw filled rounded rects (`NSColor(white: 0.10, alpha: 0.85)`, corner radius 10, 0.5px `white @ 0.1` border) behind each code block, and draw the language label (from `.codeBlockLanguage` attribute) in the top-right of each block rect using small dim text (`NSFont.systemFont(ofSize: 11, weight: .medium)`, `white @ 0.4`), then calls `super.draw(_:)`, (c) exposes `updateCodeBlockOverlays()` which scans textStorage for `.codeBlockContent` ranges, computes bounding rects, creates/reuses/removes `CodeBlockCopyButton` instances positioned at the top-right corner of each block (inset 8pt from top and right edges), setting each button's `codeString` to the attribute value
5. In `FloatingPanel.swift`, replace `let textView = NSTextView()` (line 178) with `let textView = ResponseTextView()`, keeping all existing configuration, and call `responseTextView.updateCodeBlockOverlays()` at the end of `renderDisplayedMarkdown()` and at the end of `finishTyping()` to keep copy buttons positioned correctly as content streams in
6. Build with `xcodebuild -scheme Tamagotchai -configuration Debug build`, fix any SwiftFormat/SwiftLint errors, kill the running app process, and relaunch from the build products directory
