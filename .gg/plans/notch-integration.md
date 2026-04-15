# Notch Integration Plan

## What boring.notch Does

boring.notch creates a **black-filled, notch-shaped window** that sits directly on top of the Mac's physical notch. The key techniques:

### 1. Notch Detection & Sizing (`sizing/matters.swift`)
- Uses `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` to calculate the **exact width** of the hardware notch: `screen.frame.width - leftPadding - rightPadding + 4`
- Uses `screen.safeAreaInsets.top` for the **exact height** of the notch
- Falls back to menu bar height on non-notch displays

### 2. Custom Notch Shape (`NotchShape.swift`)
- A custom `Shape` that draws the iconic notch silhouette — **flat top edge** with **quad-curve rounded corners** that curve inward at the top and outward at the bottom
- The shape has two corner radii: `topCornerRadius` (small, ~6pt — the tight inner curve at the top) and `bottomCornerRadius` (larger, ~14pt — the wider round at the bottom)
- Both radii are `animatableData` so the shape smoothly morphs between closed (tight) and open (wide) states
- The path draws: top-left → quad curve down-right → straight down → quad curve out to bottom → across bottom → mirror on right side

### 3. Window Setup (`BoringNotchWindow.swift` / `BoringNotchSkyLightWindow.swift`)
- Uses `NSPanel` with `.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow` style
- `level = .mainMenu + 3` — sits **above the menu bar**
- `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`
- `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`
- `canBecomeKey = false`, `canBecomeMain = false` — never steals focus
- Positioned at **top-center of screen**: `screenFrame.midX - width/2, screenFrame.maxY - height`

### 4. Content & Animation (`ContentView.swift`, `BoringViewModel.swift`)
- **Closed state**: window is notch-sized, filled black, blends seamlessly with the hardware notch
- **Open state**: window expands to `640×190` (+ shadow padding), with spring animation
- Content is `.background(.black)` then `.clipShape(currentNotchShape)` — the notch shape clips the black background, making it look like the physical notch is expanding
- The `.shadow()` only appears when open/hovering
- Scale gesture support for pull-down-to-open

## What We Currently Have

### Notification Toasts (`NotchNotificationPresenter.swift`)
- **Rectangular** toasts, 340pt wide, 16pt corner radius — just a rounded rectangle
- Positioned top-center below the safe area: `screenFrame.maxY - safeTop - height - 8`
- Uses `NSVisualEffectView` with `.hudWindow` material (glass blur)
- Slides down from above the screen, stacks vertically
- **No notch-aware shaping at all** — it's a plain rounded rect that sits below the notch area

### Floating Panel (`FloatingPanel.swift`)
- Spotlight-style panel centered on screen, 680pt wide
- 28pt corner radius rounded rectangle
- Completely separate from the notch — positioned at vertical center of screen

## What Needs to Change

The goal is to make our **notification toasts** appear to extend from the physical notch, rather than being disconnected rectangles below it. There are two approaches:

### Approach: Notch-Hugging Notifications

Transform `NotchNotificationPresenter` so the toast visually extends from the notch:

**Key changes:**

1. **Add `NSScreen` extensions** for notch detection (`hasNotch`, `notchSize`, `notchFrame`) using `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` and `safeAreaInsets.top`

2. **Create `NotchShape`** — a custom `Shape` / `CAShapeLayer` path that mimics the notch silhouette. The shape has:
   - Flat top edge (flush against screen top)
   - Small quad-curve corners at the top (matching hardware notch curvature, ~6pt)
   - Larger quad-curve corners at the bottom (~14-24pt)
   - Animatable corner radii for open/close transitions

3. **Redesign `NotchNotificationPresenter`**:
   - Position the window so its **top edge is flush with `screen.frame.maxY`** (above menu bar, not below safe area)
   - Set `level = .mainMenu + 3` (above menu bar) or `.statusBar + 3`
   - Make the window width at least as wide as the notch, but expandable
   - Use **solid black background** clipped to `NotchShape` (not glass blur) — this is critical for blending with the hardware notch
   - The notification content sits inside the black notch-shaped area
   - On non-notch displays, fall back to a centered rounded rectangle at menu bar height

4. **Animate expand/collapse**: When a notification appears, animate the shape from notch-sized (closed) to expanded (open) with a spring animation. When dismissing, animate back to notch size then fade.

5. **Window configuration changes**:
   - Remove `hasShadow = true` in closed state, only show shadow when expanded
   - Add `.stationary` and `.ignoresCycle` to `collectionBehavior`
   - Consider `canBecomeKey = false` since these are non-interactive toasts (except for tap-to-dismiss)
   - Use `.darkAqua` appearance forced

### Files to Change

| File | Change |
|------|--------|
| `tama/Sources/Notifications/NotchNotificationPresenter.swift` | Major rewrite: notch-aware positioning, black background, notch shape clipping, expand/collapse animation |
| **NEW** `tama/Sources/Notifications/NotchShape.swift` | Custom `CAShapeLayer` or SwiftUI `Shape` that draws the notch silhouette with animatable corner radii |
| **NEW** `tama/Sources/Extensions/NSScreen+Notch.swift` | `hasNotch`, `notchSize`, `notchFrame` extensions using `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` |

### Files NOT to Change (for now)
- `FloatingPanel.swift` — the main chat panel stays as-is (centered Spotlight-style). Notch integration is only for notifications.
- `PromptPanelController.swift` — no changes needed

### Risks & Considerations
- **Non-notch Macs**: Need graceful fallback (use menu bar height as notch height, arbitrary ~300pt width, still use the notch shape but smaller)
- **External displays**: May not have a notch — `auxiliaryTopLeftArea` will be nil, so we fall back
- **Multiple notifications**: Stacking needs rethinking — can't have multiple notch-shaped toasts. Options: queue (one at a time with the notch shape), or first one is notch-shaped and subsequent ones stack below as regular rounded rects
- **Window level**: `level = .mainMenu + 3` may conflict with full-screen apps or other overlay apps. boring.notch adds `.fullScreenAuxiliary` to handle this
- **`safeAreaInsets.top`**: This API is macOS 12+; we target 15+ so we're fine
- **Dark mode only**: The solid black notch trick only works because the hardware notch is black. Our notifications should force dark appearance

## Steps

1. Create `tama/Sources/Extensions/NSScreen+Notch.swift` with computed properties: `hasNotch` (checks `auxiliaryTopLeftArea != nil`), `notchSize` (width from `frame.width - leftArea.width - rightArea.width`, height from `safeAreaInsets.top`), and `notchFrame` (positioned at top-center of screen frame)
2. Create `tama/Sources/Notifications/NotchShape.swift` with a CAShapeLayer-based path generator that draws the notch silhouette — flat top, small quad-curve top corners (~6pt), vertical sides, larger quad-curve bottom corners (~14pt) — with configurable top/bottom corner radii for animation between closed and expanded states
3. Rewrite `tama/Sources/Notifications/NotchNotificationPresenter.swift` to position the notification window flush with the screen top (`screen.frame.maxY`), use solid black background clipped to the NotchShape, set window level to `.mainMenu + 3`, force `.darkAqua` appearance, use `.stationary` + `.ignoresCycle` collection behavior, and animate from notch-sized (closed) to expanded size with spring animation on show and reverse on dismiss; fall back to centered rounded rectangle on non-notch displays
4. Add the new `NSScreen+Notch.swift` file to the Xcode project sources in `project.yml` if needed (verify XcodeGen picks it up automatically from the Sources directory)
5. Build the project with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compile errors
6. Test on a notch-equipped Mac by triggering a test notification (or the existing batch test) and verify the toast visually extends from the notch with proper shape, animation, and fallback on external displays
