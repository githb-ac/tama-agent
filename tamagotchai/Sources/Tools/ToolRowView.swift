import AppKit

/// A single row in the tool list showing icon, name, description, and optional shortcut hint.
final class ToolRowView: NSView {
    var onSelect: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    private lazy var highlightLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer.cornerRadius = 6
        layer.isHidden = true
        return layer
    }()

    init(tool: PanelTool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(highlightLayer)
        setupViews(tool: tool)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(tool: PanelTool) {
        let iconSize: CGFloat = 28
        let iconView = NSImageView(image: MenuBarIcon.symbolIcon(name: tool.icon, size: iconSize))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nameLabel = NSTextField(labelWithString: tool.name)
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = NSTextField(labelWithString: tool.toolDescription)
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [nameLabel, descLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])

        if let hint = tool.shortcutHint {
            let hintLabel = NSTextField(labelWithString: hint)
            hintLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            hintLabel.textColor = .tertiaryLabelColor
            hintLabel.translatesAutoresizingMaskIntoConstraints = false
            hintLabel.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(hintLabel)

            NSLayoutConstraint.activate([
                hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: hintLabel.leadingAnchor, constant: -12
            ).isActive = true
        }
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds.insetBy(dx: 8, dy: 1)
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
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        highlightLayer.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        ButtonSound.shared.play()
        super.mouseDown(with: event)
        onSelect?()
    }
}
