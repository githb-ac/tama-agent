import AppKit
import SwiftUI

@MainActor
enum LoginWindowController {
    private static var panel: NSPanel?

    static func show(isLoggedIn: Bool, onLoginStateChanged: @escaping (Bool) -> Void) {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LoginView(isLoggedIn: isLoggedIn, onLoginStateChanged: onLoginStateChanged)
        let hosting = NSHostingController(rootView: view)
        hosting.view.setFrameSize(hosting.view.fittingSize)

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.view.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isFloatingPanel = false
        window.level = .normal

        // Position directly below the menu bar icon using the mouse location
        let windowSize = hosting.view.fittingSize
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main {
            let menuBarBottom = screen.visibleFrame.maxY
            let x = min(
                max(mouseLocation.x - windowSize.width / 2, screen.visibleFrame.minX),
                screen.visibleFrame.maxX - windowSize.width
            )
            let y = menuBarBottom - windowSize.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        panel = window
    }

    static func dismiss() {
        panel?.close()
        panel = nil
    }
}
