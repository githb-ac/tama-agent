import SwiftUI

@main
struct TamagotchaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var isLoggedIn = ClaudeService.shared.isLoggedIn

    var body: some Scene {
        // Menu bar presence — the app lives in the menu bar
        MenuBarExtra("Tamagotchai", systemImage: "pawprint.fill") {
            Button("Open Tamagotchai ⌥Space") {
                PromptPanelController.shared.toggle()
            }
            .keyboardShortcut(.space, modifiers: [.option])

            Button("Permissions…") {
                PermissionsWindowController.show()
            }

            Divider()

            if isLoggedIn {
                Button("Claude Account…") {
                    LoginWindowController.show(isLoggedIn: true) { isLoggedIn = $0 }
                }
            } else {
                Button("Login to Claude…") {
                    LoginWindowController.show(isLoggedIn: false) { isLoggedIn = $0 }
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
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
