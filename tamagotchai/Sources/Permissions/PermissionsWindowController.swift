import AppKit
import SwiftUI

@MainActor
enum PermissionsWindowController {
    private static var panel: NSPanel?
    private static let cornerRadius: CGFloat = 20

    static func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: PermissionsView())
        hosting.view.setFrameSize(hosting.view.fittingSize)

        let windowSize = hosting.view.fittingSize

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Vibrancy background matching the chat input style
        let container = NSView(frame: NSRect(origin: .zero, size: windowSize))
        container.wantsLayer = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        effect.addSubview(hosting.view)

        window.contentView = container
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isFloatingPanel = false
        window.level = .normal

        // Position directly below the menu bar icon using the mouse location
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
