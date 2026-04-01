import AppKit

/// A borderless, floating NSPanel that mimics macOS Spotlight's window behavior.
/// - Appears centered on the active screen
/// - Floats above all windows
/// - Dismisses when focus is lost or Escape is pressed
/// - Grows downward from a fixed top edge when content expands
final class FloatingPanel: NSPanel, NSTextFieldDelegate {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The panel width.
    private let panelWidth: CGFloat = 680

    /// The input bar height.
    private let inputHeight: CGFloat = 54

    /// Max height for the response area.
    private let responseMaxHeight: CGFloat = 400

    /// The stored top edge so the panel grows downward, not upward.
    private var topY: CGFloat = 0

    /// Tracks whether we're currently dismissing to avoid re-entrant calls.
    private var isDismissing = false

    /// Height constraint for the response scroll view.
    private var responseHeightConstraint: NSLayoutConstraint?

    /// Called when the user presses Return in the text field.
    var onSubmit: ((String) -> Void)?

    // MARK: - UI Components

    private lazy var inputField: NSTextField = {
        let field = NSTextField()
        field.delegate = self
        field.placeholderString = "Ask anything…"
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.textColor = .labelColor
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var iconView: NSImageView = {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }()

    private lazy var inputRow: NSStackView = {
        let stack = NSStackView(views: [iconView, inputField])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var divider: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }()

    /// The response text view — read-only, selectable, scrollable.
    private lazy var responseTextView: NSTextView = {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.autoresizingMask = [.width]
        return textView
    }()

    /// The scroll view wrapping the response text.
    private lazy var responseScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.documentView = responseTextView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.scrollerStyle = .overlay
        return scrollView
    }()

    private lazy var mainStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(inputRow)
        return stack
    }()

    private lazy var backgroundView: NSVisualEffectView = {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        return effect
    }()

    // MARK: - Init

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isMovableByWindowBackground = false
        isMovable = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow

        setupContentView()
    }

    private func setupContentView() {
        let container = NSView()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView = container

        container.addSubview(backgroundView)
        backgroundView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            mainStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
        ])

        // Add divider + response to stack once, keep them hidden
        mainStack.addArrangedSubview(divider)
        mainStack.addArrangedSubview(responseScrollView)

        divider.isHidden = true
        responseScrollView.isHidden = true

        let heightConstraint = responseScrollView.heightAnchor.constraint(
            equalToConstant: 0
        )
        heightConstraint.isActive = true
        responseHeightConstraint = heightConstraint
    }

    // MARK: - Dismiss on Escape

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            dismiss()
            return
        }
        super.sendEvent(event)
    }

    // MARK: - Dismiss on focus loss

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    // MARK: - NSTextFieldDelegate — Return key

    func control(
        _: NSControl,
        textView _: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = inputField.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !text.isEmpty else { return true }
            onSubmit?(text)
            return true
        }
        return false
    }

    // MARK: - Response

    /// Shows the response area below the input with the given text.
    func showResponse(_ text: String) {
        responseTextView.string = text
        divider.isHidden = false
        responseScrollView.isHidden = false

        // Calculate the natural text height
        responseTextView.layoutManager?.ensureLayout(
            for: responseTextView.textContainer!
        )
        let textHeight = responseTextView.layoutManager?.usedRect(
            for: responseTextView.textContainer!
        ).height ?? 100

        // Add text container inset
        let totalTextHeight = textHeight
            + responseTextView.textContainerInset.height * 2

        // Clamp to max height
        let targetHeight = min(totalTextHeight, responseMaxHeight)

        // Animate the panel growing downward
        responseHeightConstraint?.constant = targetHeight
        let newPanelHeight = inputHeight + 1 + targetHeight // 1 for divider
        let newOriginY = topY - newPanelHeight
        let newFrame = NSRect(
            x: frame.origin.x,
            y: newOriginY,
            width: panelWidth,
            height: newPanelHeight
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.animator().setFrame(newFrame, display: true)
        }

        // Scroll to top
        responseTextView.scrollToBeginningOfDocument(nil)
        invalidateShadow()
    }

    // MARK: - Presentation

    func present() {
        isDismissing = false

        // Reset state
        inputField.stringValue = ""
        responseTextView.string = ""
        divider.isHidden = true
        responseScrollView.isHidden = true
        responseHeightConstraint?.constant = 0

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        let originX = screenFrame.midX - panelWidth / 2
        topY = screenFrame.midY + screenFrame.height * 0.15

        let panelFrame = NSRect(
            x: originX,
            y: topY - inputHeight,
            width: panelWidth,
            height: inputHeight
        )
        setFrame(panelFrame, display: true)

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(inputField)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.orderOut(nil)
                self.isDismissing = false
            }
        }
    }
}
