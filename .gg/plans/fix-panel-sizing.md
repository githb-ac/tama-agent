# Fix Panel Sizing on Session/Tab Navigation

## Problem
When opening a session (chat, reminder, or routine), the panel expands to max height via `restoreConversation` which sets `reachedMaxHeight = true`. After that, navigating to a different tab or back to the session list never shrinks the panel because:

1. `showSessionList` doesn't hide the response area or reset `reachedMaxHeight` — so the response scroll view stays visible at max height behind/alongside the session list
2. `restoreConversation` unconditionally sets `reachedMaxHeight = true` and uses `responseMaxHeight` even for short conversations
3. Tab switching calls `showSessionList` but the old response area content and constraints persist

## Root Causes
- **`showSessionList` (line ~1218)**: Never hides `responseScrollView`, never resets `responseHeightConstraint`, never resets `reachedMaxHeight`. The response area stays at 400px while the session list stacks on top.
- **`restoreConversation` (line ~1302)**: Always forces max height. Also doesn't hide `tabBarContainer`, so tab bar height isn't included in panel calculations, yet the tab bar may still be visible from a prior `showSessionList` call.

## Steps
1. In `FloatingPanel.showSessionList`, add cleanup at the top: hide `responseScrollView`, reset `responseHeightConstraint` to 0, reset `reachedMaxHeight` to false, reset `lastTargetHeight` to 0, and clear response text storage/conversation state so the response area doesn't ghost behind the list.
2. In `FloatingPanel.restoreConversation`, hide `tabBarContainer` before calculating panel height so its height isn't double-counted, and use dynamic height (min of content height and `responseMaxHeight`) instead of always forcing max height — only set `reachedMaxHeight = true` if the content actually exceeds `responseMaxHeight`.
