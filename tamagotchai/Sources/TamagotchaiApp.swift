import SwiftUI

@main
struct TamagotchaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar presence — the app lives in the menu bar
        MenuBarExtra("Tamagotchai", systemImage: "sparkles") {
            Button("Show Prompt ⌥Space") {
                PromptPanelController.shared.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command])

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
