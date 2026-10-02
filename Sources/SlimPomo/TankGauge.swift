import AppKit
import SwiftUI
import SlimPomoCore

/// Variant C of the depth gauge: a ring on top, a dark inside, and a wave of water clipped to the inside.
/// Paths are built in the 24 × 24 reference viewBox (y down) and scaled to the drawn size.
enum TankGaugeArt {
    /// The wave layer is wider than the gauge so it can drift by one wavelength without a gap.
    static let waveStart = -GaugeGeometry.wavelength
    static let waveEnd = GaugeGeometry.viewBox + GaugeGeometry.wavelength
    static let waterBottom = GaugeGeometry.viewBox + 16
    static let levelDuration: CFTimeInterval = 0.25

    static func circle() -> CGPath {
        let c = CGFloat(GaugeGeometry.center)
        let r = CGFloat(GaugeGeometry.radius)
        return CGPath(ellipseIn: CGRect(x: c - r, y: c - r, width: 2 * r, height: 2 * r), transform: nil)
    }

    /// The wave as an open line.
    static func crest(mean: Double) -> CGPath {
        let path = CGMutablePath()
        let points = GaugeGeometry.samples(mean: mean, from: waveStart, to: waveEnd)
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        return path
    }

    /// The wave closed down to the bottom, for the water fill.
    static func body(mean: Double) -> CGPath {
        let path = CGMutablePath()
        path.addPath(crest(mean: mean))
        path.addLine(to: CGPoint(x: waveEnd, y: waterBottom))
        path.addLine(to: CGPoint(x: waveStart, y: waterBottom))
        path.closeSubpath()
        return path
    }

    static func level(of intensity: Intensity) -> Double { intensity.gaugeFill }

    /// Draws one gauge into a context that is already scaled to the viewBox with y down.
    static func draw(intensity: Intensity, opacity: CGFloat, in ctx: CGContext) {
        let surface = Theme.surfaceRGB(intensity).nsColor.cgColor
        let water = Theme.waterRGB(intensity).nsColor.cgColor
        let mean = GaugeGeometry.meanY(level: level(of: intensity))
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(circle())
        ctx.setFillColor(Theme.gaugeInnerRGB.nsColor.cgColor)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(circle())
        ctx.clip()
        ctx.addPath(body(mean: mean))
        ctx.setFillColor(water)
        ctx.fillPath()
        ctx.addPath(crest(mean: mean))
        ctx.setStrokeColor(surface)
        ctx.setLineWidth(CGFloat(GaugeGeometry.crestWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(circle())
        ctx.setStrokeColor(surface)
        ctx.setLineWidth(CGFloat(GaugeGeometry.ringWidth))
        ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

/// The gauge as Core Animation layers. The wave drifts with one transform animation, so nothing redraws per frame.
struct TankGauge: NSViewRepresentable {
    var intensity: Intensity
    /// The running task's wave drifts one wavelength every 3 s.
    var drifting = false
    /// Grey ring, crest, and water, for the NOW row while work is paused.
    var paused = false
    var reduceMotion = false

    func makeNSView(context: Context) -> TankGaugeView {
        let view = TankGaugeView()
        view.setAccessibilityElement(false)
        view.configure(intensity: intensity, drifting: drifting, paused: paused, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(_ view: TankGaugeView, context: Context) {
        view.configure(intensity: intensity, drifting: drifting, paused: paused, reduceMotion: reduceMotion)
    }
}

final class TankGaugeView: NSView {
    private let inner = CAShapeLayer()
    private let clip = CALayer()
    private let clipMask = CAShapeLayer()
    private let levelLayer = CALayer()
    private let drift = CALayer()
    private let body = CAShapeLayer()
    private let crest = CAShapeLayer()
    private let ring = CAShapeLayer()

    private var intensity = Intensity.regular
    private var wantsDrift = false
    private var paused = false
    private var reduceMotion = false
    private var builtSide: CGFloat = 0
    private var laidOut = false
    private var observers: [NSObjectProtocol] = []

    override var isOpaque: Bool { false }

    /// The control around the gauge takes the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        body.strokeColor = nil
        crest.fillColor = nil
        crest.lineCap = .round
        crest.lineJoin = .round
        ring.fillColor = nil
        for shape in [body, crest] {
            shape.anchorPoint = .zero
            shape.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            shape.position = .zero
        }
        for plain in [levelLayer, drift] {
            plain.anchorPoint = .zero
            plain.bounds = .zero
            plain.position = .zero
        }
        drift.addSublayer(body)
        drift.addSublayer(crest)
        levelLayer.addSublayer(drift)
        clip.addSublayer(levelLayer)
        clip.mask = clipMask
        layer?.addSublayer(inner)
        layer?.addSublayer(clip)
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    func configure(intensity: Intensity, drifting: Bool, paused: Bool, reduceMotion: Bool) {
        let modeChanged = intensity != self.intensity
        let pauseChanged = paused != self.paused
        self.intensity = intensity
        self.paused = paused
        wantsDrift = drifting
        self.reduceMotion = reduceMotion
        applyLook(animated: (modeChanged || pauseChanged) && laidOut && !reduceMotion, duration: pauseChanged ? 0.4 : TankGaugeArt.levelDuration)
        applyDrift()
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        guard side > 1 else { return }
        if abs(side - builtSide) > 0.01 {
            rebuild(side: side)
            builtSide = side
        }
        if !laidOut {
            laidOut = true
            applyLook(animated: false, duration: 0)
        }
        applyDrift()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let window {
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyDrift() }
                })
            }
        }
        applyDrift()
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Reference units to points, with y flipped for a bottom-up layer space.
    private func transform(side: CGFloat, translated: Bool) -> CGAffineTransform {
        let scale = side / CGFloat(GaugeGeometry.viewBox)
        var t = CGAffineTransform(scaleX: scale, y: -scale)
        if translated {
            t.ty = side
        }
        return t
    }

    private func rebuild(side: CGFloat) {
        let scale = side / CGFloat(GaugeGeometry.viewBox)
        var placed = transform(side: side, translated: true)
        var local = transform(side: side, translated: false)
        let circle = TankGaugeArt.circle()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inner.frame = bounds
        inner.path = circle.copy(using: &placed)
        clip.frame = bounds
        clipMask.frame = bounds
        clipMask.path = circle.copy(using: &placed)
        ring.frame = bounds
        ring.path = circle.copy(using: &placed)
        ring.lineWidth = CGFloat(GaugeGeometry.ringWidth) * scale
        body.path = TankGaugeArt.body(mean: 0).copy(using: &local)
        crest.path = TankGaugeArt.crest(mean: 0).copy(using: &local)
        crest.lineWidth = CGFloat(GaugeGeometry.crestWidth) * scale
        CATransaction.commit()
    }

    private func applyLook(animated: Bool, duration: CFTimeInterval) {
        let side = max(builtSide, min(bounds.width, bounds.height))
        let scale = side / CGFloat(GaugeGeometry.viewBox)
        let mean = GaugeGeometry.meanY(level: TankGaugeArt.level(of: intensity))
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        inner.fillColor = Theme.gaugeInnerRGB.nsColor.cgColor
        let water = paused ? Theme.pausedWaterRGB : Theme.waterRGB(intensity)
        let surface = paused ? Theme.pausedSurfaceRGB : Theme.surfaceRGB(intensity)
        body.fillColor = water.nsColor.cgColor
        crest.strokeColor = surface.nsColor.cgColor
        ring.strokeColor = surface.nsColor.cgColor
        levelLayer.position = CGPoint(x: 0, y: side - CGFloat(mean) * scale)
        CATransaction.commit()
    }

    private var windowVisible: Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible)
    }

    private func applyDrift() {
        let shouldDrift = wantsDrift && !reduceMotion && windowVisible && builtSide > 1
        let running = drift.animation(forKey: "drift") != nil
        if !shouldDrift {
            if running {
                drift.removeAnimation(forKey: "drift")
            }
            return
        }
        guard !running else { return }
        let scale = builtSide / CGFloat(GaugeGeometry.viewBox)
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = CGFloat(GaugeGeometry.wavelength) * scale
        animation.duration = GaugeGeometry.driftSeconds
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        drift.add(animation, forKey: "drift")
    }
}
