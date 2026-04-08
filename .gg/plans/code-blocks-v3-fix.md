# Code Blocks V3 — Fix line numbers, whitespace, deformed subsequent chats

## Root Causes

### 1. Excessive whitespace between code lines
`paragraphSpacingBefore = 38` and `paragraphSpacing = 14` are set on the ENTIRE code block paragraph style. Since each `\n` in the code content creates a new paragraph, EVERY line of code gets 38px top spacing and 14px bottom spacing. This should only apply to the first/last line.

### 2. Line numbers mispositioned
Drawing line numbers via `lineFragmentRect(forGlyphAt:)` in `draw()` is unreliable — the Y coordinates don't align with where the text system renders the code glyphs. The cleanest fix: **embed line numbers directly into the attributed string** using tab stops. This guarantees perfect alignment because the text system renders both numbers and code together.

### 3. Deformed subsequent chats
The `paragraphSpacing = 14` and `paragraphSpacingBefore = 38` on the code block's paragraph style leaks into subsequent text elements. Also the trailing `plain("\n", font: bodyFont)` after the code block doesn't carry the right paragraph style to reset spacing.

## Solution

### MarkdownRenderer.swift — `appendCodeBlock`
- **Remove the separate gutter/indent approach entirely**
- **Embed line numbers into the attributed string**: After highlighting, split the code by `\n`, prepend each line with a dim line number + tab character
- **Use tab stops** to align code text: first tab at ~30px (right-aligned for numbers), second tab at ~40px (left-aligned for code)
- **Use TWO paragraph styles**: 
  - `firstLineStyle`: `paragraphSpacingBefore = 38` (room for the header drawn in `draw()`), `paragraphSpacing = 0`
  - `innerStyle`: `paragraphSpacingBefore = 0`, `paragraphSpacing = 0`
  - Last line gets `paragraphSpacing = 14` for spacing after the block
- **Remove `headIndent`/`firstLineHeadIndent`** — the tab stops handle indentation now
- Keep stripping `.backgroundColor` from Highlightr

### ResponseTextView.swift — `drawCodeBlock`
- **Remove all line number drawing code** (the layout manager iteration)
- Keep everything else: block background, header bar, language label, border, copy button

### Approach for embedding line numbers
```
// After highlighting the full content:
let lines = content.components(separatedBy: "\n") 
let result = NSMutableAttributedString()
for (i, line) in lines.enumerated() {
    let lineNumStr = NSAttributedString(string: "\t\(i+1)\t", attributes: [
        .font: lineNumFont,
        .foregroundColor: dimColor,  
        .paragraphStyle: (i == 0 ? firstLineStyle : innerStyle)
    ])
    result.append(lineNumStr)
    // Extract the highlighted substring for this line from the highlighted output
    result.append(highlightedLine)
    if i < lines.count - 1 { result.append("\n") }
}
```

The tricky part: Highlightr highlights the whole block. To split it line-by-line, I need to find `\n` boundaries in the highlighted attributed string and extract substrings. This preserves syntax colors across line boundaries.

## Steps
1. In `MarkdownRenderer.swift` `appendCodeBlock`: rewrite to embed line numbers into the attributed string using tab stops and per-line paragraph styles — first line gets `paragraphSpacingBefore = 38`, inner lines get 0, last line gets `paragraphSpacing = 14`; remove `headIndent`/`firstLineHeadIndent`/`gutterWidth`; split highlighted output by `\n` character positions and prepend dim line numbers with tab alignment
2. In `ResponseTextView.swift` `drawCodeBlock`: remove the entire line number drawing section (the `while gi < giEnd` loop and `lineNumAttrs` static property); keep block background, header, language label, border drawing unchanged
3. Build with `xcodebuild -scheme Tamagotchai -configuration Debug build`, kill running app, relaunch
