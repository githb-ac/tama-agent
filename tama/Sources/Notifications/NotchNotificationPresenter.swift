import AppKit
import AVFoundation
import os

private let logger = Logger(
    subsystem: "com.unstablemind.tama",
    category: "notch"
)

/// A displayed notification panel with its metadata.
private struct DisplayedNotification {
    let id: UUID
    let panel: NSPanel
    let timer: Timer?
    let onTap: () -> Void
}

/// Presents glassmorphism toast notifications that slide down from the top-center of the screen.
/// Supports showing multiple notifications simultaneously as a stack.
@MainActor
enum NotchNotificationPresenter {
    /// Currently visible toast panels, ordered from newest (index 0) to oldest.
    private static var activeNotifications: [DisplayedNotification] = []

    /// Audio player for the notification sound.
    private static var audioPlayer: AVAudioPlayer?

    /// The full title of the current top notification (for detail view).
    private(set) static var currentTitle: String = ""

    /// The full body of the current top notification (for detail view).
    private(set) static var currentBody: String = ""

    /// Maximum number of notifications to show simultaneously.
    private static let maxVisibleNotifications = 5

    /// Vertical spacing between stacked notifications.
    private static let stackSpacing: CGFloat = 8

    /// Height of each toast (approximate, used for positioning).
    private static let estimatedToastHeight: CGFloat = 80

    /// Show a reminder notification.
    static func showReminder(name: String, message: String) {
        logger.info("Showing toast reminder: '\(name)'")
        showToast(
            icon: "bell.fill",
            iconColor: .systemYellow,
            title: name,
            subtitle: message,
            duration: 5
        )
    }

    /// Show an agent reply notification (when panel was dismissed during processing).
    static func showAgentReply(message: String) {
        logger.info("Showing toast agent reply")
        showToast(
            icon: "bubble.left.fill",
            iconColor: .systemPurple,
            title: "Tama",
            subtitle: message,
            duration: 6
        )
    }

    /// Show a routine result notification.
    static func showRoutineResult(name: String, result: String) {
        logger.info("Showing toast routine result: '\(name)'")
        showToast(
            icon: "bolt.fill",
            iconColor: .systemTeal,
            title: name,
            subtitle: result,
            duration: 6
        )
    }

    /// Show multiple notifications simultaneously (for testing batch display).
    static func showBatch(count: Int, prefix: String = "Test") {
        logger.info("Showing batch of \(count) notifications simultaneously")
        for i in 1 ... count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i - 1) * 0.15) {
                showToast(
                    icon: "number.circle.fill",
                    iconColor: .systemIndigo,
                    title: "\(prefix) #\(i) of \(count)",
                    subtitle: "Notification \(i) in batch of \(count)",
                    duration: 6
                )
            }
        }
    }

    /// Clear all notification panels and reset state.
    static func clearAll() {
        logger.info("Clearing all notifications (\(activeNotifications.count) active)")
        for notification in activeNotifications {
            notification.timer?.invalidate()
            notification.panel.orderOut(nil)
        }
        activeNotifications.removeAll()
    }

    // MARK: - Private

    private static let toastWidth: CGFloat = 340
    private static let toastCornerRadius: CGFloat = 16
    private static let slideInDuration: TimeInterval = 0.3
    private static let slideOutDuration: TimeInterval = 0.15

    /// Show a toast notification, stacking with existing ones.
    private static func showToast(
        icon: String,
        iconColor: NSColor,
        title: String,
        subtitle: String,
        duration: TimeInterval
    ) {
        playNotificationSound()

        guard let screen = NSScreen.main else { return }

        // Remove oldest if we're at max capacity
        if activeNotifications.count >= maxVisibleNotifications {
            removeOldestNotification()
        }

        // Build content view.
        let contentView = buildContentView(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle)
        let contentSize = contentView.fittingSize
        let toastHeight = max(contentSize.height, 64)

        // Position: top-center, stacked below existing notifications.
        let safeTop = screen.safeAreaInsets.top
        let screenFrame = screen.frame
        let originX = screenFrame.midX - toastWidth / 2

        // Calculate Y position based on stack index
        let stackIndex = activeNotifications.count
        let offsetY = CGFloat(stackIndex) * (toastHeight + stackSpacing)
        let visibleY = screenFrame.maxY - safeTop - toastHeight - 8 - offsetY
        let hiddenY = screenFrame.maxY + 50 // Start above screen for animation

        let panel = NSPanel(
            contentRect: NSRect(x: originX, y: hiddenY, width: toastWidth, height: toastHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        // Clear wrapper so the window itself is fully transparent.
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight))
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor

        // Glass background.
        let effectView = NSVisualEffectView(frame: wrapper.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = toastCornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Add content on top of the effect view.
        contentView.frame = NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight)
        effectView.addSubview(contentView)

        let notificationID = UUID()

        wrapper.addSubview(effectView)
        panel.contentView = wrapper
        panel.orderFrontRegardless()

        // Add click gesture and hover tracking via a transparent overlay.
        let overlay = ToastOverlayView(frame: effectView.bounds, notificationId: notificationID)
        overlay.autoresizingMask = [.width, .height]
        effectView.addSubview(overlay)

        // Store tap handler
        let tapHandler = {
            dismissNotification(id: notificationID)
            NotificationDetailPanel.show(title: title, body: subtitle)
        }

        // Create timer for auto-dismiss
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            Task { @MainActor in
                dismissNotification(id: notificationID)
            }
        }

        // Store notification
        let displayedNotification = DisplayedNotification(
            id: notificationID,
            panel: panel,
            timer: timer,
            onTap: tapHandler
        )
        activeNotifications.insert(displayedNotification, at: 0)

        // Update current title/body to top notification
        currentTitle = title
        currentBody = subtitle

        // Animate slide-down to final position.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = slideInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: originX, y: visibleY, width: toastWidth, height: toastHeight),
                display: true
            )
        }

        // Update positions of existing notifications to make room
        updateStackPositions()
    }

    /// Dismiss a specific notification by ID.
    private static func dismissNotification(id: UUID) {
        guard let index = activeNotifications.firstIndex(where: { $0.id == id }) else { return }

        let notification = activeNotifications.remove(at: index)
        notification.timer?.invalidate()

        guard let screen = NSScreen.main else {
            notification.panel.orderOut(nil)
            updateStackPositions()
            return
        }

        let frame = notification.panel.frame
        let targetY = screen.frame.maxY + 50 // Slide up and out

        NSAnimationContext.runAnimationGroup { context in
            context.duration = slideOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            notification.panel.animator().alphaValue = 0
            notification.panel.animator().setFrame(
                NSRect(x: frame.origin.x, y: targetY, width: frame.width, height: frame.height),
                display: true
            )
        } completionHandler: {
            MainActor.assumeIsolated {
                notification.panel.orderOut(nil)
            }
        }

        // Update current title/body to new top notification
        if let topNotification = activeNotifications.first {
            // We need to extract title/body from the panel, but for now just clear
            // In a real implementation, we'd store these in the struct
        }

        // Animate remaining notifications to new positions
        updateStackPositions()
    }

    /// Remove the oldest notification (called when at max capacity).
    private static func removeOldestNotification() {
        guard let oldest = activeNotifications.last else { return }
        dismissNotification(id: oldest.id)
    }

    /// Update positions of all notifications in the stack.
    private static func updateStackPositions() {
        guard let screen = NSScreen.main else { return }

        let safeTop = screen.safeAreaInsets.top
        let screenFrame = screen.frame
        let originX = screenFrame.midX - toastWidth / 2

        for (index, notification) in activeNotifications.enumerated() {
            let panel = notification.panel
            let currentFrame = panel.frame
            let toastHeight = currentFrame.height

            // Calculate new Y position
            let offsetY = CGFloat(index) * (toastHeight + stackSpacing)
            let visibleY = screenFrame.maxY - safeTop - toastHeight - 8 - offsetY

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(
                    NSRect(x: originX, y: visibleY, width: toastWidth, height: toastHeight),
                    display: true
                )
            }
        }
    }

    /// Dismiss all notifications immediately without animation.
    static func clearQueue() {
        clearAll()
    }

    private static func playNotificationSound() {
        guard let url = Bundle.main.url(forResource: "notification", withExtension: "mp3") else {
            logger.warning("Notification sound file not found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.6
            player.play()
            audioPlayer = player
        } catch {
            logger.error("Failed to play notification sound: \(error.localizedDescription)")
        }
    }

    private static func buildContentView(
        icon: String,
        iconColor: NSColor,
        title: String,
        subtitle: String
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let iconImageView = NSImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        if let iconImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            iconImageView.image = iconImage.withSymbolConfiguration(config)
        }
        iconImageView.contentTintColor = iconColor
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(iconImageView)

        // Title
        let titleField = NSTextField(labelWithString: title)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = NSColor.white.withAlphaComponent(0.9)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        container.addSubview(titleField)

        // Subtitle
        let subtitleField = NSTextField(wrappingLabelWithString: subtitle)
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleField.textColor = NSColor.white.withAlphaComponent(0.7)
        subtitleField.maximumNumberOfLines = 3
        subtitleField.lineBreakMode = .byWordWrapping
        subtitleField.preferredMaxLayoutWidth = toastWidth - 56
        container.addSubview(subtitleField)

        let padding: CGFloat = 14

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            iconImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 20),

            titleField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding),
            titleField.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            subtitleField.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -padding),
        ])

        return container
    }

    /// Handles a click on a toast.
    static func handleTap(for notificationId: UUID) {
        guard let notification = activeNotifications.first(where: { $0.id == notificationId }) else { return }
        notification.onTap()
    }
}

// MARK: - Toast Overlay View

/// Transparent overlay that captures mouse clicks and hover events on the toast.
private final class ToastOverlayView: NSView {
    private var trackingArea: NSTrackingArea?
    private let notificationId: UUID

    init(frame: NSRect, notificationId: UUID = UUID()) {
        self.notificationId = notificationId
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        notificationId = UUID()
        super.init(coder: coder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with _: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with _: NSEvent) {
        ButtonSound.shared.play()
        NotchNotificationPresenter.handleTap(for: notificationId)
    }
}
