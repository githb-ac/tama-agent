# Tool Activity Indicator

## Overview

Replace the inline text tool notifications (🔧/✅ emojis injected into the stream) with a dedicated floating indicator bar that shows which tool is currently running, with a spinner animation. The indicator appears during tool execution, dynamically updates as tools change, and disappears when the agent finishes.

## Design

- **Position**: Bottom of the response scroll view, overlaid on top of content (like the skeleton view). Pinned to the bottom-left with padding.
- **Layout**: Horizontal stack — spinning `NSProgressIndicator` (small, indeterminate) + fixed-width label (e.g. "Using bash…")
- **Fixed label width**: All tool labels are padded/truncated to a uniform character count to avoid layout shifts. Use a fixed frame width for the text label.
- **Labels** (uniform length, ~14 chars max):
  - bash → "Running bash…"
  - read → "Reading file…"
  - write → "Writing file…"
  - edit → "Editing file…"
  - ls → "Listing dir…"
  - find → "Finding files…"
  - grep → "Searching…"
  - web_fetch → "Fetching URL…"
  - web_search → "Searching web…"
  - (unknown) → "Working…"
- **Appearance**: Semi-transparent dark pill (matches the panel's HUD aesthetic), white text, small spinner. Fade in on show, crossfade label on tool change, fade out on hide.
- **Lifecycle**: 
  - Show when `AgentEvent.toolStart` fires
  - Update label when a new `toolStart` fires
  - Hide when `AgentEvent.turnComplete` fires (agent done)
  - Also hide on error

## Key files

- `FloatingPanel.swift` — Add `ToolIndicatorView` class (private, at bottom of file alongside `SkeletonView`). Add instance to panel, positioned inside `responseScrollView`. Add `showToolIndicator(name:)` and `hideToolIndicator()` methods.
- `PromptPanelController.swift` — Remove the emoji text injection from `onEvent` callback. Instead call `panel?.showToolIndicator(name:)` and `panel?.hideToolIndicator()`.

## Steps

1. Add a private `ToolIndicatorView` class at the bottom of `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` — an `NSView` subclass containing a horizontal stack of `NSProgressIndicator` (spinning, small) and an `NSTextField` label with fixed width, styled as a semi-transparent dark pill with rounded corners, with a static `displayName(for:)` method mapping tool names to uniform-length labels, and `show(toolName:)` / `hide()` methods that animate opacity
2. Add a `toolIndicatorView` lazy property to `FloatingPanel`, add it as a subview of `responseScrollView` pinned to bottom-leading with padding, initially hidden, and add public `showToolIndicator(name:)` and `hideToolIndicator()` methods that delegate to the indicator view
3. Update `PromptPanelController.swift` to remove the emoji text injection for `.toolStart` and `.toolResult` events, instead calling `panel?.showToolIndicator(name:)` on `.toolStart` and `panel?.hideToolIndicator()` on `.turnComplete` and `.error` events
