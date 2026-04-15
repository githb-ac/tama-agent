# Auto-Update Feature

## Overview
Add a "Check for Updates…" menu item that opens a modal showing update status. The updater checks the GitHub Releases API for `KenKaiii/tamagotchai`, compares versions, downloads the DMG, mounts/replaces the app, and relaunches.

## Architecture

### New Files
- `Tama/Sources/Update/AppUpdater.swift` — `@MainActor @Observable` service that handles check, download, install, relaunch
- `Tama/Sources/Update/UpdateView.swift` — SwiftUI view for the update modal
- `Tama/Sources/Update/UpdateWindowController.swift` — Window controller (same pattern as `PermissionsWindowController`)

### Modified Files
- `project.yml` — Add `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` build settings
- `Tama/Sources/TamaApp.swift` — Add "Check for Updates…" menu button
- `.github/workflows/release.yml` — Inject version from git tag into build

## Design Decisions

### Version Source
The app currently has no versioning. We need `MARKETING_VERSION` set in `project.yml` so `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` returns something meaningful. The GitHub release workflow already tags with `v*` format (e.g., `v1.2.0`), so we match that.

- Set `MARKETING_VERSION: "1.0.0"` and `CURRENT_PROJECT_VERSION: "1"` in `project.yml` under the Tama target settings
- In the release workflow, override these from the git tag so the built app knows its version

### GitHub API (Private Repo)
The repo `KenKaiii/tamagotchai` is private, so unauthenticated `api.github.com` calls return 404. Two options:
1. **Make releases on a public repo** — not ideal
2. **Ship a GitHub token** — bad security practice
3. **Use a simple JSON endpoint** — a `latest.json` file hosted somewhere (e.g., GitHub Pages on a separate public repo, or a raw gist)

**Best approach**: Use the GitHub API with a hardcoded PAT (fine-grained, read-only on releases). Actually, the simpler approach: since the release workflow already creates public-facing releases, we can **make the repo public** or host a tiny JSON file. 

**Simplest approach for a private repo**: We add a step in the release workflow that uploads a `latest.json` to a GitHub Gist (or another public endpoint). But that adds complexity.

**Pragmatic approach**: Use the GitHub API URL directly. If the repo is private, include a mechanism for a PAT — but more practically, since the app is distributed to users who can't access private repos anyway, **the repo should be public for this to work**, OR we use a custom server endpoint.

For now, we'll code against the standard GitHub Releases API (`https://api.github.com/repos/KenKaiii/tamagotchai/releases/latest`). If the repo is private, the owner can either:
- Make it public
- Add a release workflow step that publishes `latest.json` to a public gist/endpoint

The code will be structured so swapping the endpoint is trivial.

### Update Flow
1. User clicks "Check for Updates…" in menu bar
2. Modal opens showing "Checking for updates…" with spinner
3. Fetch `/releases/latest` from GitHub API
4. Parse `tag_name` for version, find `.dmg` asset in `assets[]`
5. Compare versions (semver: major.minor.patch)
6. **Up to date**: Show "You're up to date" with current version + checkmark
7. **Update available**: Show new version + "Update Now" button
8. User clicks "Update Now"
9. Download DMG with progress bar (reuse existing `downloadFile` helper)
10. Mount DMG with `hdiutil attach`
11. Copy `Tama.app` from mounted DMG to replace current app
12. Unmount DMG
13. Relaunch app

### Install Strategy (DMG-based)
Since the app ships as a notarized DMG:
1. Download DMG to temp directory
2. Mount DMG: `hdiutil attach <dmg> -mountpoint /tmp/TamaUpdate -noverify -nobrowse -noautoopen`
3. Get current app path: `Bundle.main.bundleURL`
4. Get parent dir (e.g., `/Applications/`)
5. Remove old app, copy new app from mount point
6. Unmount: `hdiutil detach /tmp/TamaUpdate`
7. Clean up DMG from temp
8. Relaunch: spawn background shell that waits for process exit then `open <app path>`
9. Terminate current app

The app is **not sandboxed**, so all shell operations work. The app uses `Process()` in many tools already (BashTool, ChromiumManager).

### UI States (matching existing HUD style)
```
enum UpdateState {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(currentVersion: String, newVersion: String)
    case downloading(progress: Double)
    case installing
    case failed(String)
}
```

The modal follows the exact same pattern as `PermissionsView`/`LoginView`:
- 340px wide
- Title at top
- Content in middle
- Divider + button row at bottom (with "Done" / "Update Now")
- Uses `GlassButton`, same font sizes, same opacity values

### Version Comparison
Simple semver: strip leading "v", split by ".", compare major → minor → patch numerically.

## Steps
1. Add `MARKETING_VERSION: "1.0.0"` and `CURRENT_PROJECT_VERSION: "1"` to the `Tama` target settings in `project.yml`, then regenerate the Xcode project with `xcodegen generate`
2. Update `.github/workflows/release.yml` to inject the git tag as `MARKETING_VERSION` in the `xcodebuild` step (e.g., extract version from `GITHUB_REF_NAME`, strip the leading "v", pass as `MARKETING_VERSION=$(echo ${GITHUB_REF_NAME} | sed 's/^v//')`)
3. Create `Tama/Sources/Update/AppUpdater.swift` — an `@MainActor` observable class with: `UpdateState` enum, `currentVersion` (from `Bundle.main`), `checkForUpdate()` async method that hits GitHub Releases API (`https://api.github.com/repos/KenKaiii/tamagotchai/releases/latest`), parses `tag_name` and `assets[].browser_download_url` for the `.dmg` file, compares versions with semver logic, and `performUpdate()` that downloads the DMG (reusing the existing `downloadFile()` from `Tama/Sources/Utilities/DownloadHelper.swift`), mounts it with `hdiutil`, replaces `Bundle.main.bundleURL` with the new `.app`, unmounts, cleans up, and relaunches via a background shell script that waits for process exit then runs `open <app path>`. Include `UpdateError` as a `LocalizedError` enum. Use `os.Logger` with category `"updater"`.
4. Create `Tama/Sources/Update/UpdateView.swift` — a SwiftUI view matching the existing HUD panel style (340px width, same fonts/colors/spacing as `PermissionsView`). Show: spinner + "Checking for updates…" during `.checking`; green checkmark + "You're up to date" + version for `.upToDate`; new version info + "Update Now" button for `.available`; progress bar + percentage + "Downloading…" for `.downloading`; spinner + "Installing update…" for `.installing`; orange error banner + "Retry" button for `.failed`. Bottom bar has "Done" button (calls `UpdateWindowController.dismiss()`). Observe the `AppUpdater` instance and auto-trigger check on appear.
5. Create `Tama/Sources/Update/UpdateWindowController.swift` — an `@MainActor` enum with `private static var panel: NSPanel?`, `show()` that creates an `UpdateView` and passes it to `DropdownPanelController.show(content:)`, and `dismiss()` that calls `DropdownPanelController.dismiss(&panel)`. Same pattern as `VoiceSettingsController` in `Tama/Sources/Voice/VoiceSettingsController.swift`.
6. Add the "Check for Updates…" menu item in `Tama/Sources/TamaApp.swift` — insert a `Button("Check for Updates…")` in the `MenuBarExtra` content, placed between "Voice Settings…" and the first `Divider()` (before "AI Settings…"), that calls `ButtonSound.shared.play()` then `UpdateWindowController.show()`
7. Build the project with `xcodebuild -project Tama.xcodeproj -scheme Tama -configuration Debug build` and fix any compilation errors, then run `swiftlint lint --config .swiftlint.yml` and `swiftformat --lint --config .swiftformat Tama/Sources` to verify code quality
