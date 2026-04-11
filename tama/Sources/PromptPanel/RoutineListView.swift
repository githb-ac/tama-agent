import AppKit

/// Displays scheduled routines in a scrollable list with Run and Delete actions.
/// Uses the same styling as SessionListView for consistency.
final class RoutineListView: NSView {
    /// Called when a routine is clicked (to view details).
    var onSelectRoutine: ((ScheduledJob) -> Void)?

    /// Called when a routine's delete button is clicked.
    var onDeleteRoutine: ((ScheduledJob) -> Void)?

    /// Called when a routine's run button is clicked.
    var onRunRoutine: ((ScheduledJob) -> Void)?

    private lazy var scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.scrollerStyle = .overlay
        sv.verticalScrollElasticity = .none
        sv.contentView.postsBoundsChangedNotifications = true
        return sv
    }()

    /// Scroll notification observer for updating hover states during scrolling.
    private var scrollObserver: NSObjectProtocol?

    private lazy var contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        return stack
    }()

    /// Currently active (running) routine IDs for shimmer effect
    private var activeRoutineIDs: Set<UUID> = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates hover states on all row views after scrolling.
    private func updateHoverStatesAfterScroll() {
        let mouseLocation = window?.mouseLocationOutsideOfEventStream ?? .zero
        for case let row as RoutineRowView in contentStack.arrangedSubviews {
            let rowLocation = row.convert(mouseLocation, from: nil)
            let isActuallyHovered = row.bounds.contains(rowLocation)
            row.updateHoverState(isHovered: isActuallyHovered)
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Listen for scroll to update hover states (mouse stays still while content moves)
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateHoverStatesAfterScroll()
        }

        let docView = FlippedDocumentView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView
        docView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: docView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    /// Reloads the routine list, or shows an empty state message.
    func reload(routines: [ScheduledJob], emptyMessage: String? = nil, activeRoutineIDs: Set<UUID> = []) {
        self.activeRoutineIDs = activeRoutineIDs
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if routines.isEmpty, let emptyMessage {
            contentStack.addArrangedSubview(makeEmptyState(emptyMessage))
        } else {
            for routine in routines {
                let row = makeRoutineRow(routine)
                contentStack.addArrangedSubview(row)
            }
        }
    }

    /// Resets scroll position to show the very first item.
    func scrollToTop() {
        contentStack.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
        scrollView.contentView.setBoundsOrigin(.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Row Construction

    private func makeEmptyState(_ message: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 80),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])

        return container
    }

    private func makeRoutineRow(_ routine: ScheduledJob) -> NSView {
        let isActive = activeRoutineIDs.contains(routine.id)
        let row = RoutineRowView(routine: routine, isActive: isActive)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        row.onSelect = { [weak self] in
            self?.onSelectRoutine?(routine)
        }
        row.onDelete = { [weak self] in
            self?.onDeleteRoutine?(routine)
        }
        row.onRun = { [weak self] in
            self?.onRunRoutine?(routine)
        }
        return row
    }
}

// MARK: - Routine Row View

/// A single routine row matching SessionRowView styling, with added Run button and shimmer effect.
private final class RoutineRowView: NSView {
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?
    var onRun: (() -> Void)?

    private let routine: ScheduledJob
    private let isActive: Bool
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    private lazy var highlightLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer.cornerRadius = 6
        layer.isHidden = true
        return layer
    }()

    private lazy var runButton: NSButton = {
        let btn = NSButton()
        btn.title = "Run"
        btn.font = .systemFont(ofSize: 11, weight: .medium)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
        btn.layer?.borderWidth = 0.5
        btn.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.25).cgColor
        btn.contentTintColor = .systemGreen
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        btn.target = self
        btn.action = #selector(runClicked)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        return btn
    }()

    private lazy var deleteButton: NSButton = {
        let btn = NSButton()
        btn.title = "Delete"
        btn.font = .systemFont(ofSize: 11, weight: .medium)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.14).cgColor
        btn.layer?.borderWidth = 0.5
        btn.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor
        btn.contentTintColor = .systemRed
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        btn.target = self
        btn.action = #selector(deleteClicked)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        return btn
    }()

    private let timeLabel = NSTextField(labelWithString: "")
    private var titleLabel: NSTextField?

    /// Gradient layer used for the text shimmer effect when a routine is active.
    private lazy var shimmerGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.systemGreen.cgColor,
            NSColor.white.cgColor,
            NSColor.systemGreen.cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.5, 1].map { NSNumber(value: $0) }
        return gradient
    }()

    /// Text mask so the shimmer gradient is only visible through the letter shapes.
    private let shimmerTextMask = CATextLayer()

    init(routine: ScheduledJob, isActive: Bool = false) {
        self.routine = routine
        self.isActive = isActive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(highlightLayer)
        setupViews()
        if isActive {
            setupShimmer()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Use the same icon styling as SessionRowView - use a bolt icon with a mood
        let mood = MenuBarMood.Mood.afternoon
        let iconSize: CGFloat = 28
        let iconImage = MenuBarIcon.sessionIcon(mood: mood, size: iconSize)
        let iconView = NSImageView(image: iconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: routine.name)
        titleLabel.font = .systemFont(ofSize: 18, weight: .regular)
        titleLabel.textColor = isActive ? .systemGreen : .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel = titleLabel

        // Show run count and next run time
        let runInfo = "Runs: \(routine.runCount)"
        timeLabel.stringValue = runInfo
        timeLabel.font = .systemFont(ofSize: 22, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(timeLabel)
        addSubview(runButton)
        addSubview(deleteButton)

        // Size the buttons
        NSLayoutConstraint.activate([
            runButton.widthAnchor.constraint(equalToConstant: 48),
            runButton.heightAnchor.constraint(equalToConstant: 26),
            deleteButton.widthAnchor.constraint(equalToConstant: 56),
            deleteButton.heightAnchor.constraint(equalToConstant: 26),
        ])

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: runButton.leadingAnchor, constant: -12),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            runButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            runButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func setupShimmer() {
        guard let titleLabel else { return }
        titleLabel.wantsLayer = true
        titleLabel.layer?.masksToBounds = true

        // Make the NSTextField text invisible — the gradient provides the visible text.
        titleLabel.textColor = .clear

        // Configure the text mask layer to match the title label.
        shimmerTextMask.string = titleLabel.stringValue
        shimmerTextMask.font = titleLabel.font
        shimmerTextMask.fontSize = titleLabel.font?.pointSize ?? 18
        shimmerTextMask.foregroundColor = NSColor.white.cgColor
        shimmerTextMask.alignmentMode = .left
        shimmerTextMask.truncationMode = .end
        shimmerTextMask.isWrapped = false
        shimmerTextMask.contentsScale = window?.backingScaleFactor ?? 2.0

        // The gradient is masked by the text — only letter shapes are visible.
        shimmerGradient.mask = shimmerTextMask
        titleLabel.layer?.addSublayer(shimmerGradient)

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0].map { NSNumber(value: $0) }
        animation.toValue = [1.0, 1.5, 2.0].map { NSNumber(value: $0) }
        animation.duration = 1.5
        animation.repeatCount = .infinity
        shimmerGradient.add(animation, forKey: "shimmer")
    }

    @objc private func runClicked() {
        ButtonSound.shared.play()
        onRun?()
    }

    @objc private func deleteClicked() {
        ButtonSound.shared.play()
        onDelete?()
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds.insetBy(dx: 8, dy: 1)
        if isActive, let titleLabel {
            shimmerGradient.frame = titleLabel.bounds
            shimmerTextMask.frame = titleLabel.bounds
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
        highlightLayer.isHidden = false
        timeLabel.isHidden = true
        runButton.isHidden = false
        deleteButton.isHidden = false
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        highlightLayer.isHidden = true
        runButton.isHidden = true
        deleteButton.isHidden = true
        timeLabel.isHidden = false
    }

    /// Updates the hover state programmatically (used during scrolling).
    func updateHoverState(isHovered: Bool) {
        guard self.isHovered != isHovered else { return }
        self.isHovered = isHovered
        highlightLayer.isHidden = !isHovered
        timeLabel.isHidden = isHovered
        runButton.isHidden = !isHovered
        deleteButton.isHidden = !isHovered
    }

    override func mouseDown(with event: NSEvent) {
        // Don't trigger select if clicking either button
        let loc = convert(event.locationInWindow, from: nil)
        if runButton.frame.contains(loc) || deleteButton.frame.contains(loc) { return }
        ButtonSound.shared.play()
        super.mouseDown(with: event)
        onSelect?()
    }
}

// MARK: - Flipped Document View

/// An NSView with a flipped coordinate system (origin at top-left)
/// so that scroll views display content from the top down.
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
