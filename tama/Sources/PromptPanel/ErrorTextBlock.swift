import AppKit

/// NSTextBlock subclass that draws a subtle glassmorphic error background.
/// Uses minimal tinting to match the app's aesthetic — errors shouldn't be alarming.
final class ErrorTextBlock: NSTextBlock {
    private let tint: NSColor

    init(tint: NSColor) {
        self.tint = tint
        super.init()
        setContentWidth(100, type: .percentageValueType)
        setWidth(10, type: .absoluteValueType, for: .padding)
        setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        setWidth(12, type: .absoluteValueType, for: .padding, edge: .maxX)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawBackground(
        withFrame frameRect: NSRect,
        in controlView: NSView?,
        characterRange _: NSRange,
        layoutManager _: NSLayoutManager
    ) {
        let rect = frameRect.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        // Subtle glassmorphic fill — much lower opacity for softer appearance
        tint.withAlphaComponent(0.12).setFill()
        path.fill()

        // Soft border
        tint.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
