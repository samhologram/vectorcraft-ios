import UIKit
import Observation
@preconcurrency import VectorCraftKit

/// The UIKit canvas. Draws the engine's rendered image (placed by the view transform it was rendered for, so
/// pinch and pan feel instant), the overlays above it, and turns touches, Pencil, pointer hover and keys into
/// model events.
@MainActor
final class CanvasUIView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    var model: DocumentModel {
        didSet { if model !== oldValue { restart() } }
    }

    // MARK: Subviews
    private let imageLayer = CALayer()
    private let overlayView = CanvasOverlayView()
    private let textInput = CanvasTextInput()

    // MARK: Rendering
    private struct RenderKey: Equatable {
        var tick: Int
        var centerX: Double, centerY: Double, zoom: Double
        var size: CGSize
        var scale: Double
        var outline: Bool
        var draft: Bool
    }
    private var requestedKey: RenderKey?
    private var frame_: RenderedFrame?
    private var renderDirty = true
    private var renderInFlight = false
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    // MARK: Input state
    private struct PendingDown {
        var location: CGPoint
        var pressure: Float
        var modifiers: Modifiers
    }
    private var activeTouch: UITouch?
    private var pendingDown: PendingDown?
    private var pendingWork: DispatchWorkItem?
    private var strokeStarted = false
    private var strokeStart = CGPoint.zero
    private var suppressTouches = false
    private var spaceDown = false
    private var gestureTokens = Set<ObjectIdentifier>()
    private var observing = false

    private let pinch = UIPinchGestureRecognizer()
    private let twoFingerPan = UIPanGestureRecognizer()
    private let fingerPan = UIPanGestureRecognizer()
    private let twoFingerTap = UITapGestureRecognizer()
    private let threeFingerTap = UITapGestureRecognizer()
    private let hover = UIHoverGestureRecognizer()

    /// A finger waits this long before its "down" reaches the tool, so a second finger (pinch, pan, tap) can
    /// still take over without the tool having drawn anything.
    private static let fingerDownDelay = 0.07
    private static let fingerSlop: CGFloat = 6

    init(model: DocumentModel) {
        self.model = model
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        clipsToBounds = true
        backgroundColor = .secondarySystemBackground
        isAccessibilityElement = true
        accessibilityIdentifier = "canvas"
        accessibilityLabel = String(localized: "Canvas")
        accessibilityTraits = [.allowsDirectInteraction]

        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        imageLayer.isOpaque = false
        layer.addSublayer(imageLayer)
        addSubview(overlayView)

        textInput.onInsert = { [weak self] text in self?.model.toolText(text) }
        textInput.onDelete = { [weak self] in self?.model.toolKey("backspace") }
        addSubview(textInput)

        configureGestures()
        addInteraction(UIPencilInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Lifecycle

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startObserving()
            startDisplayLink()
            apply()
            if !textInput.isFirstResponder { DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() } }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayView.frame = bounds
        model.setViewSize(bounds.size, pixelScale: Double(traitCollection.displayScale))
        apply()
    }

    private func restart() {
        requestedKey = nil
        renderDirty = true
        frame_ = nil
        imageLayer.contents = nil
        observing = false
        startObserving()  // re-arm on the new model
        apply()
    }

    // MARK: Observation + display link

    private func startObserving() {
        guard !observing else { return }
        observing = true
        track()
    }

    private func track() {
        let model = self.model
        withObservationTracking {
            _ = model.renderTick
            _ = model.overlayTick
            _ = model.view
            _ = model.pencilOnly
            _ = model.state.toolWantsText
            _ = model.isInteractingStorage
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.window != nil else { self?.observing = false; return }
                self.apply()
                self.track()
            }
        }
    }

    /// Weakly targeted so the run loop never keeps the view alive.
    /// Main-actor isolated: the display link is added to the main run loop, so `tick` runs on the main thread.
    @MainActor private final class LinkProxy: NSObject {
        weak var view: CanvasUIView?
        @objc func tick(_ link: CADisplayLink) {
            view?.displayTick(link)
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = LinkProxy()
        proxy.view = self
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = false
        displayLink = link
        lastTick = CACurrentMediaTime()
    }

    private func displayTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = max(0, now - lastTick)
        lastTick = now
        if activeTouch != nil, strokeStarted, model.toolWantsTicks { model.toolTick(dt) }
        if renderDirty && !renderInFlight { startRender() }
        if !renderDirty && !renderInFlight && activeTouch == nil { link.isPaused = true }
    }

    private func wakeDisplayLink() { displayLink?.isPaused = false }

    // MARK: Apply model state

    /// Brings the view in line with the model: render request, image placement, overlays, keyboard, gestures.
    func apply() {
        guard bounds.width > 1 else { return }
        let key = currentKey()
        if key != requestedKey {
            renderDirty = true
            wakeDisplayLink()
        }
        placeImage()
        overlayView.update(items: model.overlays(), transform: model.view)
        updateTextInput()
        fingerPan.isEnabled = model.pencilOnly
    }

    private func currentKey() -> RenderKey {
        let v = model.view
        return RenderKey(tick: model.renderTick, centerX: v.centerX, centerY: v.centerY, zoom: v.zoom,
                         size: v.viewSize, scale: v.pixelScale, outline: v.outline, draft: model.isInteracting)
    }

    private func startRender() {
        let key = currentKey()
        requestedKey = key
        renderDirty = false
        renderInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let frame = await self.model.renderFrame(draft: key.draft)
            self.renderInFlight = false
            if let frame {
                self.frame_ = frame
                self.imageLayer.contents = frame.image
                self.placeImage()
                self.model.canvasDidPresent()
            }
            // Something changed while rendering (or the draft needs its sharp pass): go again.
            if self.currentKey() != self.requestedKey { self.renderDirty = true }
            self.wakeDisplayLink()
        }
    }

    /// Positions the last rendered image for the current view: the render covered the view as it was then.
    private func placeImage() {
        guard let f = frame_, f.zoom > 0 else { return }
        let v = model.view
        let s = v.zoom / f.zoom
        let x = -s * Double(f.size.width) / 2 + (f.centerX - v.centerX) * v.zoom + Double(v.viewSize.width) / 2
        let y = -s * Double(f.size.height) / 2 + (f.centerY - v.centerY) * v.zoom + Double(v.viewSize.height) / 2
        let rect = CGRect(x: x, y: y, width: s * Double(f.size.width), height: s * Double(f.size.height))
        guard rect.width.isFinite, rect.height.isFinite, rect.origin.x.isFinite, rect.origin.y.isFinite else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = rect
        CATransaction.commit()
    }

    private func updateTextInput() {
        if model.state.toolWantsText {
            if !textInput.isFirstResponder { textInput.becomeFirstResponder() }
        } else if textInput.isFirstResponder {
            textInput.resignFirstResponder()
            becomeFirstResponder()
        }
    }

    // MARK: Gestures

    private func configureGestures() {
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        twoFingerPan.addTarget(self, action: #selector(handlePan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.allowedScrollTypesMask = .all  // trackpad / mouse-wheel scrolling pans too
        twoFingerPan.delegate = self
        addGestureRecognizer(twoFingerPan)

        // "Only Draw with Apple Pencil": one finger pans.
        fingerPan.addTarget(self, action: #selector(handlePan(_:)))
        fingerPan.minimumNumberOfTouches = 1
        fingerPan.maximumNumberOfTouches = 1
        fingerPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerPan.isEnabled = model.pencilOnly
        fingerPan.delegate = self
        addGestureRecognizer(fingerPan)

        twoFingerTap.addTarget(self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.delegate = self
        addGestureRecognizer(twoFingerTap)

        threeFingerTap.addTarget(self, action: #selector(handleThreeFingerTap))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.delegate = self
        addGestureRecognizer(threeFingerTap)

        hover.addTarget(self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)

        for g in [pinch, twoFingerPan, fingerPan, twoFingerTap, threeFingerTap] as [UIGestureRecognizer] {
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let nav: [UIGestureRecognizer] = [pinch, twoFingerPan]
        return nav.contains(gestureRecognizer) && nav.contains(other)
    }

    private func gestureActive(_ g: UIGestureRecognizer, _ on: Bool) {
        if on { gestureTokens.insert(ObjectIdentifier(g)) } else { gestureTokens.remove(ObjectIdentifier(g)) }
        model.setInteracting(!gestureTokens.isEmpty || strokeStarted)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            gestureActive(g, true)
        case .changed:
            model.zoom(by: Double(g.scale), around: g.location(in: self))
            g.scale = 1
        case .ended, .cancelled, .failed:
            gestureActive(g, false)
        default:
            break
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            gestureActive(g, true)
        case .changed:
            let t = g.translation(in: self)
            model.pan(by: CGSize(width: t.x, height: t.y))
            g.setTranslation(.zero, in: self)
        case .ended, .cancelled, .failed:
            gestureActive(g, false)
        default:
            break
        }
    }

    @objc private func handleTwoFingerTap() { model.undo() }
    @objc private func handleThreeFingerTap() { model.redo() }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        guard activeTouch == nil, g.state == .began || g.state == .changed else { return }
        let p = model.view.toDocument(g.location(in: self))
        model.pointer("move", atDocument: p, pressure: 0, modifiers: modifiers(from: g.modifierFlags))
    }

    // MARK: Pencil

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        model.selectPreviousTool()
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { model.selectPreviousTool() }
    }

    // MARK: Touches

    private func shouldDraw(_ touch: UITouch) -> Bool {
        switch touch.type {
        case .pencil: true
        case .direct: !model.pencilOnly
        case .indirectPointer: true
        default: false
        }
    }

    private func pressure(of touch: UITouch) -> Float {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return 1 }
        let p = touch.force / touch.maximumPossibleForce
        return Float(min(max(p, 0.02), 1))
    }

    private func modifiers(from flags: UIKeyModifierFlags) -> Modifiers {
        Modifiers(shift: flags.contains(.shift), alt: flags.contains(.alternate), cmd: flags.contains(.command),
                  ctrl: flags.contains(.control), space: spaceDown)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !textInput.isFirstResponder { becomeFirstResponder() }
        let all = event?.allTouches ?? touches
        // Several touches at once (pinch, pan, tap): never a stroke.
        if touches.count > 1 || all.filter({ $0.phase != .ended && $0.phase != .cancelled }).count > 1 {
            if activeTouch != nil, !(activeTouch?.type == .pencil && touches.allSatisfy({ $0.type != .pencil })) {
                cancelStroke()
            }
            suppressTouches = activeTouch == nil
            return
        }
        guard !suppressTouches, activeTouch == nil, let touch = touches.first, shouldDraw(touch) else { return }
        activeTouch = touch
        let location = touch.location(in: self)
        let mods = modifiers(from: event?.modifierFlags ?? [])
        let down = PendingDown(location: location, pressure: pressure(of: touch), modifiers: mods)
        strokeStart = location
        if touch.type == .direct {
            pendingDown = down
            let work = DispatchWorkItem { [weak self] in self?.commitPendingDown() }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fingerDownDelay, execute: work)
        } else {
            send(down: down)
        }
        wakeDisplayLink()
    }

    private func commitPendingDown() {
        pendingWork?.cancel()
        pendingWork = nil
        guard let down = pendingDown else { return }
        pendingDown = nil
        send(down: down)
    }

    private func send(down: PendingDown) {
        strokeStarted = true
        model.pointer("down", atDocument: model.view.toDocument(down.location), pressure: down.pressure,
                      modifiers: down.modifiers)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if pendingDown != nil {
            let l = touch.location(in: self)
            guard hypot(l.x - strokeStart.x, l.y - strokeStart.y) > Self.fingerSlop else { return }
            commitPendingDown()
        }
        guard strokeStarted else { return }
        let mods = modifiers(from: event?.modifierFlags ?? [])
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples.isEmpty ? [touch] : samples {
            model.pointer("drag", atDocument: model.view.toDocument(sample.location(in: self)),
                          pressure: pressure(of: sample), modifiers: mods)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { resetSuppressionIfIdle(event) }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if pendingDown != nil { commitPendingDown() }  // a tap: down now, up below
        let mods = modifiers(from: event?.modifierFlags ?? [])
        let p = model.view.toDocument(touch.location(in: self))
        if strokeStarted {
            model.pointer("up", atDocument: p, pressure: pressure(of: touch), modifiers: mods)
            if touch.tapCount == 2 {
                model.pointer("doubleClick", atDocument: p, pressure: pressure(of: touch), modifiers: mods)
            }
        }
        endStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { resetSuppressionIfIdle(event) }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        cancelStroke()
    }

    /// A second touch took over, or the system cancelled: abandon the stroke (Escape cancels the tool's action).
    private func cancelStroke() {
        if strokeStarted { model.toolKey("escape") }
        endStroke()
        suppressTouches = true
    }

    private func endStroke() {
        pendingWork?.cancel()
        pendingWork = nil
        pendingDown = nil
        activeTouch = nil
        strokeStarted = false
        model.setInteracting(!gestureTokens.isEmpty)
    }

    private func resetSuppressionIfIdle(_ event: UIEvent?) {
        let live = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
        if live.isEmpty { suppressTouches = false }
    }

    // MARK: Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if press.key?.keyCode == .keyboardSpacebar { spaceDown = true }
            if let key = press.key, handle(key: key) { continue }
            unhandled.insert(press)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardSpacebar }) { spaceDown = false }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        spaceDown = false
        super.pressesCancelled(presses, with: event)
    }

    /// Arrows, Return, Escape, Delete, Tab (and brush-size brackets) go to the active tool. Command and Control
    /// combinations stay with the menu bar. While typing, text keys belong to the text input.
    private func handle(key: UIKey) -> Bool {
        let flags = key.modifierFlags
        guard flags.isDisjoint(with: [.command, .control]) else { return false }
        let typing = model.state.toolWantsText
        let name: String
        switch key.keyCode {
        case .keyboardUpArrow: name = "up"
        case .keyboardDownArrow: name = "down"
        case .keyboardLeftArrow: name = "left"
        case .keyboardRightArrow: name = "right"
        case .keyboardEscape: name = "escape"
        case .keyboardDeleteForward: name = "delete"
        case .keyboardHome: name = "home"
        case .keyboardEnd: name = "end"
        case .keyboardReturnOrEnter, .keypadEnter:
            guard !typing else { return false }
            name = "enter"
        case .keyboardDeleteOrBackspace:
            guard !typing else { return false }
            name = "backspace"
        case .keyboardTab:
            guard !typing else { return false }
            name = "tab"
        case .keyboardOpenBracket:
            guard !typing else { return false }
            name = "["
        case .keyboardCloseBracket:
            guard !typing else { return false }
            name = "]"
        default:
            return false
        }
        model.toolKey(name, modifiers: modifiers(from: flags))
        return true
    }

    // MARK: Edit actions (Cmd-C / X / V / A and the edit menu reach the engine through the responder chain)

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(UIResponderStandardEditActions.copy(_:)): model.isEnabled("edit.copy")
        case #selector(UIResponderStandardEditActions.cut(_:)): model.isEnabled("edit.cut")
        case #selector(UIResponderStandardEditActions.paste(_:)): model.isEnabled("edit.paste")
        case #selector(UIResponderStandardEditActions.selectAll(_:)): model.isEnabled("select.all")
        default: super.canPerformAction(action, withSender: sender)
        }
    }

    override func copy(_ sender: Any?) { model.run("edit.copy") }
    override func cut(_ sender: Any?) { model.run("edit.cut") }
    override func paste(_ sender: Any?) { model.run("edit.paste") }
    override func selectAll(_ sender: Any?) { model.run("select.all") }
}
