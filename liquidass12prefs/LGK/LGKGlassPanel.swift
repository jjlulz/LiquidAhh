// SpringBoard-facing wrapper around LiquidGlassView, loaded from Objective-C by name (LGKGlassPanel).
import UIKit

@objc(LGKGlassPanel)
public final class GlassPanel: UIView {

    private let glass = LiquidGlassView(.regular)

    /// Corner radius of the glass shape (0 = flat bar, e.g. the home-button dock).
    @objc public var glassCornerRadius: CGFloat = 0 {
        didSet {
            glass.layer.cornerRadius = glassCornerRadius
            setNeedsLayout()
        }
    }

    /// Redraw rate. Lower = cheaper; 30 is plenty for a mostly static background.
    @objc public var framesPerSecond: Int = 30 {
        didSet { glass.preferredFramesPerSecond = max(1, framesPerSecond) }
    }

    private var visibilityTimer: Timer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        glass.isUserInteractionEnabled = false
        glass.preferredFramesPerSecond = framesPerSecond
        glass.isPaused = true          // stays paused until the panel is really on screen
        addSubview(glass)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        updatePaused()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        if window != nil {
            // re-check visibility twice a second so hidden windows / faded views stop drawing
            visibilityTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                                                   selector: #selector(visibilityTick),
                                                   userInfo: nil, repeats: true)
        }
        updatePaused()
    }

    @objc private func visibilityTick() {
        updatePaused()
    }

    private func updatePaused() {
        var visible = window != nil && !bounds.isEmpty
        if visible, let window, window.isHidden || window.alpha < 0.01 { visible = false }
        var view: UIView? = self
        while visible, let current = view {
            if current.isHidden || current.alpha < 0.01 { visible = false }
            view = current.superview
        }
        if glass.isPaused == visible { glass.isPaused = !visible }
    }
}
