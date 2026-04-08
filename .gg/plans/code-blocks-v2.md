# Code Blocks V2 — Fix Aesthetic, Width, Header Bar, Spacing

## Problems
1. **Width overflow**: Code blocks extend beyond the chat message width. The `draw()` uses `inset: 6` from view edges but the text container has 20px horizontal inset + 4px line fragment padding. Code block rects must align to the actual text area.
2. **Dark opaque background clashes**: `NSColor(white: 0.10, alpha: 0.85)` is too dark/opaque for the glassmorphism HUD. Should use a subtler translucent fill matching the app's `NSColor(white: 0.15, alpha: 0.6)` pattern.
3. **Highlightr theme background leaks**: `atom-one-dark` applies its own `.backgroundColor` attribute to the text. Must strip `.backgroundColor` from highlighted output.
4. **No header bar**: Need a visual header bar at the top of each code block with the language label on the left and copy button on the right — like GitHub/VS Code code blocks.
5. **Insufficient spacing**: `paragraphSpacingBefore: 6` and `paragraphSpacing: 6` on code blocks is too tight. User bubble uses `paragraphSpacing: 8` which is also tight. Need more breathing room around code blocks and between conversation turns.

## Design

### Header bar
- Drawn as part of the code block background rect in `draw()`, at the top
- Height: ~28px
- Background: slightly lighter than code body — `NSColor(white: 0.18, alpha: 0.5)`
- Separated from code body by a thin 0.5px line (`white @ 0.1`)
- Language label on the left (inset 10px), small dim text
- Copy button positioned in the header bar on the right side

### Code block body
- Background: `NSColor(white: 0.12, alpha: 0.55)` — translucent, fits HUD
- Corner radius: 8px (top corners on header, bottom corners on body — single rounded rect with header drawn inside)
- Border: 0.5px `white @ 0.1`
- No `.backgroundColor` attribute on the text itself (strip from Highlightr output)

### Width alignment
- The text container origin is at `textContainerInset.width` (20px) from the text view edge
- Line fragment padding is 4px
- So text content starts at x=24 from the left edge
- The code block rect should span from `textContainerInset.width` to `bounds.width - textContainerInset.width` (i.e. 20px inset on each side), matching the text flow area

### Spacing
- Code block `paragraphSpacingBefore`: 14 (up from 6)
- Code block `paragraphSpacing`: 14 (up from 6) 
- Add top padding to code text: first line needs extra head indent to clear the header bar — but actually the header bar is drawn ABOVE the text bounding rect, so we need to account for header height in the block rect calculation
- User bubble `paragraphSpacingBefore`: 14 (up from 8) and `paragraphSpacing`: 14 (up from 8)

### Architecture change
- The header bar height (28px) needs to be accounted for. The simplest approach: add a blank line at the start of the code block text with a small font to create space for the header, OR offset the drawn background rect upward by the header height. The second approach is cleaner — extend the blockRect upward by `headerHeight` beyond the text bounding rect.

## Files to modify
- `tamagotchai/Sources/PromptPanel/ResponseTextView.swift` — fix width calc, add header bar drawing, reposition copy buttons into header
- `tamagotchai/Sources/PromptPanel/MarkdownRenderer.swift` — strip `.backgroundColor` from Highlightr output, increase spacing, add top padding for header clearance
- `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` — increase user bubble spacing

## Steps
1. In `MarkdownRenderer.swift` (`appendCodeBlock`, ~line 351): (a) after getting highlighted output from Highlightr, enumerate and remove `.backgroundColor` attribute from the entire range, (b) change `paragraphSpacingBefore` from 6 to 14, (c) change `paragraphSpacing` from 6 to 14, (d) prepend a blank line with a small 28pt-height paragraph (using a 22pt font with 6pt lineSpacing) to the code block to reserve space for the header bar — this blank line should also carry the `.codeBlockContent` and `.codeBlockLanguage` attributes
2. In `ResponseTextView.swift` (`draw` method): (a) fix the block rect x-position to use `textContainerInset.width` instead of hardcoded `inset: 6`, making width `bounds.width - textContainerInset.width * 2`, (b) replace the single rounded rect with a two-part design: draw the full rounded rect background with `NSColor(white: 0.12, alpha: 0.55)` and 8px corner radius, then draw a header bar rect at the top (height 28px, clipped to the top corners) filled with `NSColor(white: 0.18, alpha: 0.5)`, then a 0.5px separator line between header and body, (c) draw the language label in the header bar (left-aligned, inset 10px from left edge of block, vertically centered in header), (d) draw the 0.5px border on the full block, (e) remove the separate language label drawing that was positioned at top-right
3. In `ResponseTextView.swift` (`updateCodeBlockOverlays`): (a) fix block rect calculation to match the updated `draw()` method, (b) position copy buttons in the header bar — right-aligned, vertically centered within the 28px header height
4. In `FloatingPanel.swift` (`makeUserBubble`, ~line 674): change `paragraphSpacingBefore` from 8 to 14 and `paragraphSpacing` from 8 to 14 for more breathing room between conversation turns
5. Build with `xcodebuild -scheme Tamagotchai -configuration Debug build`, kill the running app, and relaunch
