import SwiftUI

@main
struct TamagotchaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var isLoggedIn = ClaudeService.shared.isLoggedIn

    var body: some Scene {
        // Menu bar presence — the app lives in the menu bar
        MenuBarExtra("Tamagotchai", systemImage: "sparkles") {
            Button("Show Prompt ⌥Space") {
                PromptPanelController.shared.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command])

            Divider()

            if isLoggedIn {
                Button("Logout from Claude") {
                    ClaudeService.shared.logout()
                    isLoggedIn = false
                }
            } else {
                Button("Login to Claude") {
                    ClaudeOAuth.startLogin()
                }
                Button("Paste Login Code…") {
                    promptForLoginCode()
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func promptForLoginCode() {
        let alert = NSAlert()
        alert.messageText = "Paste Login Code"
        alert.informativeText = "Paste the code from your browser (format: code#state):"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Login")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "code#state"
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let rawCode = input.stringValue
        guard !rawCode.isEmpty else { return }

        Task {
            do {
                let credentials = try await ClaudeOAuth.completeLogin(rawCode: rawCode)
                ClaudeService.shared.setCredentials(credentials)
                isLoggedIn = true
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Login Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }
}

/// App delegate handles hotkey registration at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Register global hotkey: ⌥ + Space
        PromptPanelController.shared.register()
    }

    func applicationWillTerminate(_: Notification) {
        PromptPanelController.shared.unregister()
    }
}
