import AppKit
import ApplicationServices

@MainActor
final class PermissionsChecker: Sendable {
    static let shared = PermissionsChecker()
    private init() {}

    // MARK: - Accessibility

    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission (shows system dialog).
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Full Disk Access

    func isFullDiskAccessGranted() -> Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    /// Reveals the app bundle in Finder so the user can drag it into System Settings.
    func revealAppInFinder() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}
