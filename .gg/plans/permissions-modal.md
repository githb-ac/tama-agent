# Permissions Modal

## Overview

Add a "Permissions…" menu item to the menu bar that opens a modal window showing the status of all macOS permissions the app needs. Each permission row shows its current status (granted/not granted) and a button to open the relevant System Settings pane.

## Permissions to check

Based on the tools the app provides:

| Permission | Why needed | Detection | System Settings deep link |
|---|---|---|---|
| **Accessibility** | Global hotkey (⌥Space), potential AppleScript | `AXIsProcessTrusted()` | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` |
| **Full Disk Access** | Read/write/edit files anywhere (ReadTool, WriteTool, EditTool, BashTool) | `FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")` | `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` |

Note: Automation permission is only needed if controlling other apps via AppleScript — not currently a tool. Network/outgoing connections (for ClaudeService, WebFetchTool) don't require a permission grant on macOS for non-sandboxed apps.

## Key files

- **New: `tamagotchai/Sources/Permissions/PermissionsChecker.swift`** — Singleton that checks each permission status
- **New: `tamagotchai/Sources/Permissions/PermissionsWindow.swift`** — NSWindow subclass with permission rows (SwiftUI hosted in NSHostingController, presented as a modal sheet or standalone window)
- **Modified: `tamagotchai/Sources/TamagotchaiApp.swift`** — Add "Permissions…" menu item

## UI Design

A small, centered NSPanel (similar style to the login code alert but richer):
- Title: "Permissions"  
- Each permission is a row with:
  - SF Symbol icon (lock.shield / checkmark.shield.fill)
  - Permission name + short description
  - Status badge: green checkmark "Granted" or orange warning "Not Granted"
  - "Open Settings" button (only when not granted)
- A "Refresh" button at the bottom to re-check statuses
- "Done" button to dismiss

Use SwiftUI for the view content, presented via `NSHostingController` in an `NSPanel`/`NSWindow`.

## Steps

1. Create `tamagotchai/Sources/Permissions/PermissionsChecker.swift` with a `PermissionsChecker` class containing methods `isAccessibilityGranted() -> Bool` (using `AXIsProcessTrusted()`) and `isFullDiskAccessGranted() -> Bool` (probing `/Library/Application Support/com.apple.TCC/TCC.db`), plus a `requestAccessibility()` method that calls `AXIsProcessTrustedWithOptions` with prompt, and `openFullDiskAccessSettings()` / `openAccessibilitySettings()` methods that open the corresponding `x-apple.systempreferences:` deep links via `NSWorkspace.shared.open`
2. Create `tamagotchai/Sources/Permissions/PermissionsView.swift` with a SwiftUI view showing permission rows for Accessibility and Full Disk Access — each row has an SF Symbol, title, description, green/orange status badge, and an "Open Settings" button when not granted — plus a "Refresh" button that re-checks all statuses and a "Done" button that dismisses the window, using `PermissionsChecker` for status checks and actions
3. Create `tamagotchai/Sources/Permissions/PermissionsWindowController.swift` with a static `show()` method that creates an `NSPanel` containing an `NSHostingController` with the `PermissionsView`, centered on screen, floating, and key — reusing an existing instance if already shown
4. Add a "Permissions…" `Button` to the `MenuBarExtra` in `tamagotchai/Sources/TamagotchaiApp.swift`, placed between the "Show Prompt" button and the login section divider, that calls `PermissionsWindowController.show()`
