import AppKit
import SwiftUI
import SlimPomoCore

/// Colors the waves interpolate. Level is drawn separately so a running timer is not eased.
struct TankPaint: VectorArithmetic, Equatable {
    var bgR = 0.0
    var bgG = 0.0
    var bgB = 0.0
    var frontR = 0.0
    var frontG = 0.0
    var frontB = 0.0
    var frontA = 0.0
    var backR = 0.0
    var backG = 0.0
    var backB = 0.0
    var backA = 0.0

    init() {}

    static var zero: TankPaint { TankPaint() }

    static func + (lhs: TankPaint, rhs: TankPaint) -> TankPaint {
        TankPaint(
            bgR: lhs.bgR + rhs.bgR, bgG: lhs.bgG + rhs.bgG, bgB: lhs.bgB + rhs.bgB,
            frontR: lhs.frontR + rhs.frontR, frontG: lhs.frontG + rhs.frontG,
            frontB: lhs.frontB + rhs.frontB, frontA: lhs.frontA + rhs.frontA,
            backR: lhs.backR + rhs.backR, backG: lhs.backG + rhs.backG,
            backB: lhs.backB + rhs.backB, backA: lhs.backA + rhs.backA
        )
    }

    static func - (lhs: TankPaint, rhs: TankPaint) -> TankPaint {
        TankPaint(
            bgR: lhs.bgR - rhs.bgR, bgG: lhs.bgG - rhs.bgG, bgB: lhs.bgB - rhs.bgB,
            frontR: lhs.frontR - rhs.frontR, frontG: lhs.frontG - rhs.frontG,
            frontB: lhs.frontB - rhs.frontB, frontA: lhs.frontA - rhs.frontA,
            backR: lhs.backR - rhs.backR, backG: lhs.backG - rhs.backG,
            backB: lhs.backB - rhs.backB, backA: lhs.backA - rhs.backA
        )
    }

    mutating func scale(by rhs: Double) {
        bgR *= rhs; bgG *= rhs; bgB *= rhs
        frontR *= rhs; frontG *= rhs; frontB *= rhs; frontA *= rhs
        backR *= rhs; backG *= rhs; backB *= rhs; backA *= rhs
    }

    var magnitudeSquared: Double {
        bgR * bgR + bgG * bgG + bgB * bgB
            + frontR * frontR + frontG * frontG + frontB * frontB + frontA * frontA
            + backR * backR + backG * backG + backB * backB + backA * backA
    }

    static func lerp(_ a: TankPaint, _ b: TankPaint, _ t: Double) -> TankPaint {
        var delta = b - a
        delta.scale(by: min(max(t, 0), 1))
        return a + delta
    }

    var nsBackground: NSColor { NSColor(srgbRed: bgR, green: bgG, blue: bgB, alpha: 1) }
    var nsFront: NSColor { NSColor(srgbRed: frontR, green: frontG, blue: frontB, alpha: frontA) }
    var nsBack: NSColor { NSColor(srgbRed: backR, green: backG, blue: backB, alpha: backA) }

    static func make(phase: Phase, mode: Intensity, paused: Bool = false) -> TankPaint {
        if paused {
            if phase == .breakTime {
                return TankPaint(
                    bg: Theme.pausedBreakAirRGB,
                    front: Theme.pausedBreakWaterRGB,
                    back: Theme.pausedBreakSurfaceRGB,
                    backAlpha: 0.55
                )
            }
            return TankPaint(
                bg: Theme.pausedAirRGB,
                front: Theme.pausedWaterRGB,
                back: Theme.pausedSurfaceRGB,
                backAlpha: 0.55
            )
        }
        if phase == .breakTime {
            return TankPaint(
                bg: Theme.breakCardRGB,
                front: Theme.breakWaterRGB,
                back: Theme.breakSurfaceRGB,
                backAlpha: 0.70
            )
        }
        return TankPaint(
            bg: Theme.tankAirRGB,
            front: Theme.waterRGB(mode),
            back: Theme.surfaceRGB(mode),
            backAlpha: 0.70
        )
    }

    private init(
        bg: ThemeRGB,
        front: ThemeRGB,
        frontAlpha: Double = 1,
        back: ThemeRGB,
        backAlpha: Double = 1
    ) {
        bgR = bg.r; bgG = bg.g; bgB = bg.b
        frontR = front.r; frontG = front.g; frontB = front.b; frontA = frontAlpha
        backR = back.r; backG = back.g; backB = back.b; backA = backAlpha
    }

    private init(
        bgR: Double, bgG: Double, bgB: Double,
        frontR: Double, frontG: Double, frontB: Double, frontA: Double,
        backR: Double, backG: Double, backB: Double, backA: Double
    ) {
        self.bgR = bgR; self.bgG = bgG; self.bgB = bgB
        self.frontR = frontR; self.frontG = frontG; self.frontB = frontB; self.frontA = frontA
        self.backR = backR; self.backG = backG; self.backB = backB; self.backA = backA
    }
}

/// The line at the bottom of the timer card. A task name gets its muted project label; everything else is plain.
struct TankTaskLine: Equatable {
    /// Words before the task, such as "Next:".
    var lead: String? = nil
    var text: String
    var isTask = false

    /// What a screen reader says: the raw text, without the label styling.
    var spoken: String {
        [lead, text].compactMap { $0 }.joined(separator: " ")
    }
}

struct WaterTank: View {
    var session: Session
    /// Model tick. Digits and the water level read this, never the wave clock.
    var now: Date
    var reduceMotion: Bool
    var taskLine: TankTaskLine

    var body: some View {
        ZStack {
            TankWaveHost(
                level: level,
                running: frozenLevel == nil && session.isRunning,
                phase: phase,
                mode: Self.mode(of: session),
                paused: paused,
                reduceMotion: reduceMotion || frozenLevel != nil,
                fades: !reduceMotion
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            content
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    static let height: CGFloat = 150

    /// Dev builds can pin the tank to one level and phase to check the scale against the water.
    private var frozenLevel: CGFloat? {
        #if SLIMPOMO_DEV
        return DevTank.current.map { CGFloat($0.level) }
        #else
        return nil
        #endif
    }

    private var phase: Phase {
        #if SLIMPOMO_DEV
        if let frozen = DevTank.current { return frozen.phase }
        #endif
        return session.phase
    }

    private var level: CGFloat {
        frozenLevel ?? Self.fraction(of: session, at: now)
    }

    private var content: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(clockText)
                        .font(.system(size: 40, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(timeColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(clockText)
                    if showsPause {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(pauseColor)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 14)
                taskLabel
                    .padding(.leading, 16)
                    .padding(.trailing, 64)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            scale
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: paused)
    }

    private var taskLabel: some View {
        let parts = taskLine.isTask
            ? TaskName.split(taskLine.text)
            : TaskName.Parts(prefix: nil, rest: taskLine.text, restOffset: 0)
        return HStack(spacing: 0) {
            if let lead = taskLine.lead {
                Text(lead)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(taskColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 5)
            }
            if let tag = parts.tag {
                TagLabel(tag: tag, model: AppRuntime.model)
                    .padding(.trailing, LabelStyle.gap)
            }
            Text(parts.rest)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(taskColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .shadow(color: onBreak ? .clear : .black.opacity(0.35), radius: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taskLine.spoken)
    }

    /// Three ticks on the same axis as the water: full, half, and empty. Only the top and bottom ticks carry a label.
    private var scale: some View {
        ZStack(alignment: .topTrailing) {
            tick(level: 1, label: Self.mark(scaleMinutes))
            tick(level: 0.5, label: nil)
            tick(level: 0, label: "0")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(scaleColor)
        .accessibilityHidden(true)
    }

    /// A 6 × 1 pt tick centered on the level's height, with its label to the left, centered on the tick.
    private func tick(level: Double, label: String?) -> some View {
        let row: CGFloat = 14
        let y = CGFloat(TankAxis.y(level: level, height: Double(Self.height)))
        return HStack(spacing: 4) {
            if let label {
                Text(label)
                    .lineLimit(1)
                    .fixedSize()
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
            Rectangle()
                .fill(scaleColor.opacity(0.6))
                .frame(width: 6, height: 1)
        }
        .padding(.trailing, 16)
        .frame(height: row, alignment: .trailing)
        .offset(y: y - row / 2)
    }

    private var clockText: String {
        let seconds: TimeInterval
        if session.phase == .idle {
            seconds = session.queue.first { $0.count > 0 }?.intensity.workDuration
                ?? Intensity.regular.workDuration
        } else {
            seconds = session.displayedRemaining(at: now)
        }
        let total = max(0, Int(seconds.rounded(.down)))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private var showsPause: Bool { paused }

    /// Work or a break is stopped. The tank turns grey and the waves stand still.
    private var paused: Bool {
        session.phase != .idle && !session.isRunning && frozenLevel == nil
    }

    private var onBreak: Bool { phase == .breakTime }

    private var timeColor: Color {
        if paused { return onBreak ? Theme.pausedBreakText : Theme.pausedTime }
        return onBreak ? Theme.breakText : (session.phase == .idle ? Theme.textOnWater : Theme.textStrong)
    }

    private var taskColor: Color {
        if paused { return onBreak ? Theme.pausedBreakText : Theme.pausedText }
        return onBreak ? Theme.breakText : Theme.textStrong
    }

    private var pauseColor: Color {
        if paused { return onBreak ? Theme.pausedBreakText : Theme.pausedTime }
        return onBreak ? Theme.breakText : Theme.link
    }

    private var scaleColor: Color {
        if paused { return onBreak ? Theme.pausedBreakSurface : Theme.pausedSurface }
        return onBreak ? Theme.breakScale : Theme.link
    }

    private var scaleMinutes: Double {
        if frozenLevel != nil {
            let mode = Self.mode(of: session).mode
            return Double(phase == .breakTime ? mode.breakMinutes : mode.workMinutes)
        }
        switch session.phase {
        case .work, .breakTime:
            return max(0, session.phaseDuration / 60)
        case .idle:
            return Double(session.queue.first { $0.count > 0 }?.intensity.mode.workMinutes ?? 25)
        }
    }

    /// Work fills with elapsed time. A break drains with the time still left. Idle sits at 5%.
    static func fraction(of session: Session, at date: Date) -> CGFloat {
        switch session.phase {
        case .idle:
            return 0.05
        case .work:
            guard session.phaseDuration > 0 else { return 0 }
            let elapsed = 1 - session.displayedRemaining(at: date) / session.phaseDuration
            return CGFloat(min(1, max(0, elapsed)))
        case .breakTime:
            guard session.phaseDuration > 0 else { return 0 }
            let remaining = session.displayedRemaining(at: date) / session.phaseDuration
            return CGFloat(min(1, max(0, remaining)))
        }
    }

    private static func mode(of session: Session) -> Intensity {
        switch session.phase {
        case .work, .breakTime:
            return session.activeItem?.intensity ?? .regular
        case .idle:
            return session.queue.first { $0.count > 0 }?.intensity ?? .regular
        }
    }

    private static func mark(_ minutes: Double) -> String {
        "\(Int(minutes.rounded()))′"
    }
}

/// Two wave layers, shifted by Core Animation. The model tick only moves the water line.
private struct TankWaveHost: NSViewRepresentable {
    var level: CGFloat
    var running: Bool
    var phase: Phase
    var mode: Intensity
    var paused: Bool
    var reduceMotion: Bool
    /// Pause and resume crossfade the colors over 400 ms. Off with Reduce Motion.
    var fades: Bool

    func makeNSView(context: Context) -> TankWaveView {
        let view = TankWaveView()
        view.update(level: level, running: running, phase: phase, mode: mode, paused: paused, reduceMotion: reduceMotion, fades: fades)
        return view
    }

    func updateNSView(_ view: TankWaveView, context: Context) {
        view.update(level: level, running: running, phase: phase, mode: mode, paused: paused, reduceMotion: reduceMotion, fades: fades)
    }
}

/// Clipped to the tank. Each wave is twice as wide as the tank so a one-width shift loops.
final class TankWaveView: NSView {
    private let waves = CALayer()
    private let back = CAShapeLayer()
    private let front = CAShapeLayer()
    private let crest = CAShapeLayer()

    private var levelTarget: CGFloat = 0.05
    private var running = false
    private var phase: Phase = .idle
    private var paused = false
    private var reduceMotion = false
    private var paint = TankPaint()
    private var builtWidth: CGFloat = 0
    private var placed = false
    private var playing = false
    /// The waves stand still on a static offset. Their slide animation is removed, never slowed to speed 0:
    /// a layer at speed 0 also freezes every other animation on it, and the color fade would stay at its first frame.
    private var frozen = false
    private var shownY: CGFloat = -.greatestFiniteMagnitude
    private var observers: [NSObjectProtocol] = []

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true
        layer?.cornerRadius = 14
        crest.fillColor = nil
        crest.lineWidth = 1.5
        crest.lineCap = .round
        crest.lineJoin = .round
        front.addSublayer(crest)
        waves.addSublayer(back)
        waves.addSublayer(front)
        layer?.addSublayer(waves)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(level: CGFloat, running: Bool, phase: Phase, mode: Intensity, paused: Bool, reduceMotion: Bool, fades: Bool) {
        let crossfade = fades && placed && paused != self.paused
        self.paused = paused
        paint = TankPaint.make(phase: phase, mode: mode, paused: paused)
        applyColors(fade: crossfade)
        levelTarget = level
        self.running = running
        self.phase = phase
        self.reduceMotion = reduceMotion
        applyMotion()
        placeWater(animated: placed && !reduceMotion)
    }

    override func layout() {
        super.layout()
        layer?.masksToBounds = true
        layer?.cornerRadius = 14
        let width = bounds.width
        if width > 1, abs(width - builtWidth) > 0.5 {
            rebuildPaths(width: width)
            builtWidth = width
        }
        if !placed, bounds.height > 1 {
            placeWater(animated: false)
            placed = true
        }
        applyMotion()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.applyMotion()
                    }
                }
            )
        }
        applyMotion()
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private static let fadeDuration: CFTimeInterval = 0.4

    /// Sets the colors at once. With `fade`, each layer eases from the color on screen to the new one.
    private func applyColors(fade: Bool) {
        let background = paint.nsBackground.cgColor
        let frontFill = paint.nsFront.cgColor
        let backFill = paint.nsBack.cgColor
        let crestStroke = NSColor(srgbRed: paint.backR, green: paint.backG, blue: paint.backB, alpha: paused ? 1 : 0.55).cgColor
        let fromBackground = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        let fromFront = front.presentation()?.fillColor ?? front.fillColor
        let fromBack = back.presentation()?.fillColor ?? back.fillColor
        let fromCrest = crest.presentation()?.strokeColor ?? crest.strokeColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = background
        front.fillColor = frontFill
        back.fillColor = backFill
        crest.strokeColor = crestStroke
        crest.fillColor = nil
        CATransaction.commit()
        guard fade else { return }
        if let layer { Self.ease(layer, key: "backgroundColor", from: fromBackground, to: background) }
        Self.ease(front, key: "fillColor", from: fromFront, to: frontFill)
        Self.ease(back, key: "fillColor", from: fromBack, to: backFill)
        Self.ease(crest, key: "strokeColor", from: fromCrest, to: crestStroke)
    }

    private static func ease(_ layer: CALayer, key: String, from: CGColor?, to: CGColor) {
        guard let from else { return }
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = fadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "fade.\(key)")
    }

    /// Wavelength is half the tank, so two full waves sit across it. The layer is two tanks wide.
    private func rebuildPaths(width: CGFloat) {
        let frontPhase = slidePhase(of: front, from: 0, to: -width, duration: 6)
        let backPhase = slidePhase(of: back, from: -width, to: 0, duration: 9)
        let wasFrozen = frozen
        let wasPlaying = playing
        let depth: CGFloat = 400
        let amplitude: CGFloat = 3
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fill = Self.wavePath(tankWidth: width, amplitude: amplitude, depth: depth, closed: true)
        let line = Self.wavePath(tankWidth: width, amplitude: amplitude, depth: depth, closed: false)
        front.path = fill
        crest.path = line
        back.path = fill
        pin(front, width: width * 2)
        pin(crest, width: width * 2)
        pin(back, width: width * 2)
        front.position = .zero
        crest.position = .zero
        back.position = CGPoint(x: 0, y: 3)
        CATransaction.commit()
        if wasPlaying {
            if wasFrozen {
                hold(front, from: 0, to: -width, phase: frontPhase)
                hold(back, from: -width, to: 0, phase: backPhase)
            } else {
                installSlide(on: front, from: 0, to: -width, duration: 6, phase: frontPhase)
                installSlide(on: back, from: -width, to: 0, duration: 9, phase: backPhase)
            }
        }
    }

    private func pin(_ layer: CAShapeLayer, width: CGFloat) {
        layer.anchorPoint = .zero
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: 1)
        layer.masksToBounds = false
    }

    /// Quadratic arches, amplitude 3 pt, one full wave every half tank.
    private static func wavePath(tankWidth: CGFloat, amplitude: CGFloat, depth: CGFloat, closed: Bool) -> CGPath {
        let path = CGMutablePath()
        let layerWidth = tankWidth * 2
        let half = tankWidth / 4
        guard half > 0 else { return path }
        path.move(to: .zero)
        var x: CGFloat = 0
        var crestUp = true
        while x < layerWidth - 0.01 {
            let end = min(x + half, layerWidth)
            let control = CGPoint(x: (x + end) / 2, y: crestUp ? amplitude : -amplitude)
            path.addQuadCurve(to: CGPoint(x: end, y: 0), control: control)
            x = end
            crestUp.toggle()
        }
        if closed {
            path.addLine(to: CGPoint(x: layerWidth, y: -depth))
            path.addLine(to: CGPoint(x: 0, y: -depth))
            path.closeSubpath()
        }
        return path
    }

    private func placeWater(animated: Bool) {
        let height = bounds.height
        guard height > 1 else { return }
        // The layer's y runs up from the bottom; the axis measures down from the top.
        let y = height - CGFloat(TankAxis.y(level: Double(levelTarget), height: Double(height)))
        waves.anchorPoint = .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waves.bounds = bounds
        CATransaction.commit()
        if y == shownY, animated { return }
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            waves.removeAnimation(forKey: "level")
            waves.position = CGPoint(x: 0, y: y)
            CATransaction.commit()
            shownY = y
            return
        }
        let from = waves.presentation()?.position.y ?? waves.position.y
        let anim = CABasicAnimation(keyPath: "position.y")
        anim.fromValue = from
        anim.toValue = y
        anim.duration = 1
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        waves.position = CGPoint(x: 0, y: y)
        waves.add(anim, forKey: "level")
        shownY = y
    }

    private func applyMotion() {
        guard bounds.width > 1 else { return }
        let wantsMotion = !reduceMotion && phase != .idle
        if !wantsMotion {
            resetSlides()
            playing = false
            return
        }
        if !playing {
            let width = bounds.width
            installSlide(on: front, from: 0, to: -width, duration: 6, phase: 0)
            installSlide(on: back, from: -width, to: 0, duration: 9, phase: 0)
            playing = true
            frozen = false
        }
        let moving = running && windowVisible
        if moving {
            if frozen { thaw() }
        } else if !frozen {
            freeze()
        }
    }

    private func slidePhase(of layer: CALayer, from: CGFloat, to: CGFloat, duration: CFTimeInterval) -> Double {
        guard playing, let tx = layer.presentation()?.transform.m41 else { return 0 }
        let span = to - from
        guard span != 0 else { return 0 }
        let raw = (tx - from) / span
        return raw - floor(raw)
    }

    private func installSlide(
        on layer: CALayer,
        from: CGFloat,
        to: CGFloat,
        duration: CFTimeInterval,
        phase: Double
    ) {
        layer.removeAnimation(forKey: "wave")
        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        let elapsed = max(0, min(0.999, phase)) * duration
        anim.beginTime = CACurrentMediaTime() - elapsed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        layer.add(anim, forKey: "wave")
    }

    /// Stops a wave where it is: the slide animation goes and the offset it reached stays as the layer's transform.
    private func hold(_ layer: CALayer, from: CGFloat, to: CGFloat, phase: Double) {
        layer.removeAnimation(forKey: "wave")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(from + CGFloat(phase) * (to - from), 0, 0)
        CATransaction.commit()
    }

    private func freeze() {
        let width = bounds.width
        guard width > 1 else { return }
        let frontPhase = slidePhase(of: front, from: 0, to: -width, duration: 6)
        let backPhase = slidePhase(of: back, from: -width, to: 0, duration: 9)
        hold(front, from: 0, to: -width, phase: frontPhase)
        hold(back, from: -width, to: 0, phase: backPhase)
        frozen = true
    }

    private func thaw() {
        let width = bounds.width
        guard width > 1 else { return }
        let frontPhase = slidePhase(of: front, from: 0, to: -width, duration: 6)
        let backPhase = slidePhase(of: back, from: -width, to: 0, duration: 9)
        installSlide(on: front, from: 0, to: -width, duration: 6, phase: frontPhase)
        installSlide(on: back, from: -width, to: 0, duration: 9, phase: backPhase)
        frozen = false
    }

    private func resetSlides() {
        for wave in [front, back] {
            wave.removeAnimation(forKey: "wave")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            wave.transform = CATransform3DIdentity
            CATransaction.commit()
        }
        frozen = false
    }

    private var windowVisible: Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible)
    }
}


