# Fix user message positioning after code blocks

## Root Cause

When `MarkdownRenderer.render()` finishes, it strips ALL trailing `\n` characters. When a code block is the last element in a response, the rendered attributed string ends with characters that carry the `.codeBlockContent` custom attribute.

In `finishTyping()`, this rendered text is appended to `conversationAttributed` (no trailing `\n`). When `makeUserBubble()` is then appended for the next message, the user bubble's attachment character joins the **same paragraph** as the last code line — there's no `\n` paragraph separator between them.

Because they share a paragraph:
- The code block's `.codeBlockContent` attribute extends to cover the user bubble
- `ResponseTextView.collectCodeBlocks()` treats the user bubble as part of the code block
- The code block's paragraph style (left-aligned, tab stops, head indent) overrides the bubble's right-aligned style
- The user bubble appears inline with code, not as a right-aligned chat bubble

This also affects non-code-block responses (no paragraph break between assistant text and user bubble), but it's most visibly broken with code blocks because of the `.codeBlockContent` attribute leaking and the code block background being drawn around the bubble.

## Fix

In `makeUserBubble()` in `FloatingPanel.swift` (line ~620), prepend a `\n` with a plain/reset paragraph style before the bubble attachment. This guarantees the bubble always starts its own paragraph regardless of what preceded it.

## Steps
1. In `FloatingPanel.swift` `makeUserBubble()` method (~line 669 where `let result = NSMutableAttributedString()`), after creating `result`, prepend a newline with a clean paragraph style (paragraphSpacingBefore=0, paragraphSpacing=0) when `conversationAttributed.length > 0` — this ensures a paragraph break separates the previous content from the user bubble, preventing attribute leakage and ensuring the right-aligned paragraph style takes effect
