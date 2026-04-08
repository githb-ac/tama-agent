# Fix: Tab bar (All/Reminders/Routines) disappears when viewing a session

## Problem

When the user clicks into a session, reminder, or routine from the list, the tab bar (All / Reminders / Routines) disappears. The tab bar should remain visible as persistent navigation.

## Root Cause

In `FloatingPanel.restoreConversation()` (line 1362–1364), when a session is loaded, the method explicitly hides both the session list AND the tab bar:

```swift
sessionListView.isHidden = true
sessionListHeightConstraint?.constant = 0
tabBarContainer.isHidden = true   // ← This is the bug
```

The flow is: click session → `PromptPanelController.loadSession()` → `panel.restoreConversation()` → tab bar hidden.

## Fix

**File: `tamagotchai/Sources/PromptPanel/FloatingPanel.swift`**

Remove the line `tabBarContainer.isHidden = true` from `restoreConversation()` (line 1364). The tab bar should stay visible when viewing a conversation — it's the persistent navigation bar for the panel.

The divider between input and content should also remain visible (it already is — line 1365), which is correct since we have content below the input.

## What stays unchanged

- `hideSessionList()` (line 1279) — correctly hides the tab bar when user starts typing or submits. This is fine because at that point the session list is no longer relevant.
- `showSessionList()` (line 1218) — correctly shows the tab bar when displaying the session list.
- `present()` (line 1513) — tab bar starts hidden, which is correct (no content to navigate yet until sessions load).

## Steps

1. In `FloatingPanel.restoreConversation()`, remove `tabBarContainer.isHidden = true` (line 1364) so the tab bar stays visible when viewing a restored conversation.
