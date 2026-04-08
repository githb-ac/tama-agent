# Browser Chromium Download + Permissions Integration

## Analysis

### Current State
- `BrowserManager` searches for 7 known browsers at fixed `/Applications/` paths (Chrome, Brave, Edge, Arc, Vivaldi, Opera, Chromium)
- If none found, `BrowserManagerError.noBrowserFound` is thrown
- No auto-download capability exists
- Permissions modal (`PermissionsView.swift`) shows 4 permissions: Accessibility, Full Disk Access, Microphone, Speech Recognition
- Onboarding (`OnboardingView.swift`) has a permissions step with those same 4 permissions
- There is no browser/Chromium row in either place
- The download pattern in `KokoroManager.swift` provides a good model: `ObservableObject` with `@Published` state for download progress, a `downloadFile()` helper using delegate-based URLSession

### Chrome for Testing API
- Endpoint: `https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json`
- Returns JSON with `channels.Stable.downloads.chrome[]` where each has `platform` and `url`
- Platforms: `mac-arm64`, `mac-x64` (we detect at runtime via `ProcessInfo.processInfo.processorArchitecture` or `#if arch(arm64)`)
- Zip contains: `chrome-mac-arm64/Google Chrome for Testing.app` (or `chrome-mac-x64/...`)
- After download: unzip, move .app to `~/Library/Application Support/Tamagotchai/Chromium/`, clear quarantine with `xattr -cr`
- The executable path inside the .app: `Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`

### Design Decisions
- **ChromiumManager** — new `@MainActor ObservableObject` singleton, follows the KokoroManager pattern
  - Published state: `isDownloaded`, `isDownloading`, `downloadProgress`
  - `downloadChromium()` — fetches version JSON, downloads zip, extracts, clears quarantine
  - `chromiumPath` — returns path to the executable if downloaded
  - `deleteChromium()` — removes the downloaded browser
  - Stored at: `~/Library/Application Support/Tamagotchai/Chromium/Google Chrome for Testing.app`
- **BrowserManager integration** — add the downloaded Chromium path to the `knownBrowsers` list (checked first before system browsers)
- **downloadFile helper** — extract from KokoroManager to a shared utility in `tamagotchai/Sources/Utilities/`
- **PermissionsView** — add "Browser" row that shows download button or "Ready" badge
- **OnboardingView** — add "Browser" row in the permissions step (same pattern) plus show it in the ready step summary
- The browser row is **not a system permission** — it's an optional capability. Label it "Browser (Optional)" so users know they can skip it.

### Files to Create
- `tamagotchai/Sources/AI/Tools/Browser/ChromiumManager.swift` — download manager
- `tamagotchai/Sources/Utilities/DownloadHelper.swift` — extracted shared download helper

### Files to Modify
- `tamagotchai/Sources/AI/Tools/Browser/BrowserManager.swift` — add downloaded Chromium to search paths (line 25-33, line 140)
- `tamagotchai/Sources/Permissions/PermissionsView.swift` — add browser row
- `tamagotchai/Sources/Onboarding/OnboardingView.swift` — add browser row in permissions step + ready summary
- `tamagotchai/Sources/Voice/KokoroManager.swift` — change `downloadFile` from private free function to use shared utility

## Steps
1. Create `tamagotchai/Sources/Utilities/DownloadHelper.swift` — extract `downloadFile(from:to:onProgress:)` and `DownloadSessionDelegate` from `KokoroManager.swift` (lines 362-435) into a new shared file; make them `internal` (not `private`)
2. Update `tamagotchai/Sources/Voice/KokoroManager.swift` — remove the `private func downloadFile` and `private final class DownloadSessionDelegate` at the bottom of the file (lines 362-435); the file now uses the shared `downloadFile` from DownloadHelper.swift
3. Create `tamagotchai/Sources/AI/Tools/Browser/ChromiumManager.swift` — `@MainActor final class ChromiumManager: ObservableObject` with `@Published isDownloaded/isDownloading/downloadProgress`, `downloadChromium()` that fetches `last-known-good-versions-with-downloads.json`, picks the right platform zip URL (`mac-arm64` or `mac-x64` via `#if arch(arm64)`), downloads to a temp file, unzips with `Process("/usr/bin/ditto" -xk)`, moves the .app into `~/Library/Application Support/Tamagotchai/Chromium/`, runs `xattr -cr` to clear quarantine, and sets `isDownloaded = true`; a `chromiumExecutablePath` computed property that returns the path to the binary inside the .app; a `deleteChromium()` method; `checkExisting()` on init
4. Update `tamagotchai/Sources/AI/Tools/Browser/BrowserManager.swift` — in `launchBrowser(headless:)` (line 140), before checking `knownBrowsers`, first check `ChromiumManager.shared.chromiumExecutablePath` — if it exists on disk, use that as the browser binary; this makes the downloaded Chromium the first-priority browser
5. Update `tamagotchai/Sources/Permissions/PermissionsView.swift` — add a "Browser (Optional)" row between Speech Recognition and the bottom Divider; use `@ObservedObject private var chromium = ChromiumManager.shared`; when not downloaded, show a "Download" button that calls `chromium.downloadChromium()`; when downloading, show a ProgressView with `chromium.downloadProgress`; when downloaded, show "Ready" badge; also add a note like "~400 MB download" in the description
6. Update `tamagotchai/Sources/Onboarding/OnboardingView.swift` — add `@ObservedObject private var chromium = ChromiumManager.shared`; in `permissionsStep`, add a "Browser (Optional)" row after Speech Recognition with the same download/progress/ready pattern; in `readyStep`, add a summary row for "Browser" using `chromium.isDownloaded`
7. Build, lint, format, and run unit tests to verify everything compiles and existing tests still pass
