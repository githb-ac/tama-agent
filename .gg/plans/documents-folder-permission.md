# Documents Folder Permission — Move TCC Prompt to Onboarding

## Problem

On first use, when the user sends their first prompt, macOS shows a TCC dialog: "Tama would like to access files in your Documents folder". This dismisses the floating panel and disrupts the experience.

The root cause is that `PromptPanelController.ensureWorkspace()` (line 30-41 of `PromptPanelController.swift`) accesses `~/Documents/Tama` lazily — it's called by the `lazy var agentLoop` on line 23-25, which is only initialized when the first prompt is submitted.

## Approach

1. **Trigger the Documents folder access during onboarding** by calling `ensureWorkspace()` when the user clicks "Grant" on a new "Documents Folder" permission row. This causes the macOS TCC dialog to appear while the user is already in the permissions UI, not mid-conversation.

2. **Add a check for Documents folder access** to `PermissionsChecker` so both the onboarding and menu bar permissions views can show whether access has been granted.

3. **Add a "Documents Folder" permission row** to both the onboarding permissions step and the menu bar Permissions view, positioned right after "Full Disk Access" since they're related.

4. **Note**: There is no API to programmatically request Documents folder access — the only way to trigger the TCC prompt is to actually access the folder. The "Grant" button will call `ensureWorkspace()` directly, which creates `~/Documents/Tama` and triggers the system dialog. If the user has Full Disk Access, this will already be granted automatically.

## Key Files

- `tama/Sources/PromptPanel/PromptPanelController.swift` — Contains `ensureWorkspace()` (line 30-41), the method that triggers the TCC prompt
- `tama/Sources/Permissions/PermissionsChecker.swift` — Permission check/request methods
- `tama/Sources/Onboarding/OnboardingView.swift` — Onboarding permissions step (line 156-282)
- `tama/Sources/Permissions/PermissionsView.swift` — Menu bar permissions panel

## Steps

1. In `tama/Sources/Permissions/PermissionsChecker.swift`, add a `isDocumentsFolderGranted() -> Bool` method that checks if the app can read `~/Documents` (using `FileManager.default.isReadableFile(atPath:)` on a test file inside `~/Documents`), add a cached state `lastDocumentsFolderState`, add a `requestDocumentsFolderAccess()` method that calls `PromptPanelController.ensureWorkspace()` to trigger the TCC prompt, and add `openFilesAndFoldersSettings()` that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders`.
2. In `tama/Sources/PromptPanel/PromptPanelController.swift`, change `ensureWorkspace()` from `private static` to `static` (remove `private`) so it can be called from `PermissionsChecker`.
3. In `tama/Sources/Onboarding/OnboardingView.swift`, add a `@State private var documentsFolderGranted = false` property, add a "Documents Folder" permission row in the `permissionsStep` after the "Full Disk Access" row (around line 196) with title "Documents Folder", description "Tama stores files in ~/Documents/Tama", granted state `documentsFolderGranted`, and action that calls `OnboardingController.yieldToSystemUI()` then `PermissionsChecker.shared.requestDocumentsFolderAccess()`, then update `refreshPermissions()` to also set `documentsFolderGranted = checker.isDocumentsFolderGranted()`.
4. In `tama/Sources/Permissions/PermissionsView.swift`, add a `@State private var documentsFolderGranted = false` property, add a "Documents Folder" permission row after the "Full Disk Access" row (around line 53) with the same pattern as existing rows — if not determined, call `requestDocumentsFolderAccess()`, else open Files and Folders settings — and update `refreshStatuses()` to also set `documentsFolderGranted = checker.isDocumentsFolderGranted()`.
5. Build the project with `xcodegen generate && xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compilation errors.
