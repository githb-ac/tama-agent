# Fix Notch Notification: Positioning & Styling

## Problem
1. **Notch hiding content**: The NotchNotification library positions header content (leading/trailing icons) alongside the physical notch, where it gets occluded. The body text sits below but the visual layout is confusing.
2. **Black background**: The library hardcodes a solid black `.foregroundStyle(.black)` rectangle to mimic the notch shape. This doesn't match our app's HUD/glassmorphism aesthetic (`.hudWindow` material, translucent dark backgrounds, white text with opacity).

## Analysis
The NotchNotification library's design is fundamentally a notch-mimicking black shape that expands — this can't be easily styled to match our glass aesthetic. The black background and notch shape are baked into `NotchView.swift` internally.

Our app's aesthetic (from FloatingPanel, GlassButton, LoginView):
- `NSVisualEffectView` with `.hudWindow` material
- Translucent dark backgrounds with blur
- White text at various opacities (0.9, 0.8, 0.45)
- Rounded corners (28pt on panel, 8pt on buttons)
- `.foregroundColor(.white.opacity(...))` pattern

## Approach
**Replace the NotchNotification library** with a custom `NSPanel`-based toast notification that:
- Slides down from the top-center of the screen, positioned just **below** the safe area (below the notch)
- Uses `NSVisualEffectView` with `.hudWindow` material to match FloatingPanel
- Has our glassmorphism styling (rounded corners, white text, subtle border)
- Auto-dismisses after a configurable interval with a slide-up animation

## Steps
1. Remove the NotchNotification SPM package from `project.yml` (both the package declaration and the target dependency), then run `xcodegen generate`
2. Rewrite `tamagotchai/Sources/Notifications/NotchNotificationPresenter.swift` to use a custom `NSPanel` with `NSVisualEffectView` (`.hudWindow` material, `.behindWindow` blending), positioned top-center below the screen's safe area insets, with slide-down/up animation, auto-dismiss timer, and the same `showReminder` / `showRoutineResult` API — no import of NotchNotification
3. Build with `xcodebuild` and verify zero errors
