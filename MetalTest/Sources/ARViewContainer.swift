import Cocoa
import Combine
import RealityKit
import SwiftUI

class ARViewContainer: ARView {
    private var mouseInputConsumers: [MouseInputConsumer] = []
    private var keyboardInputConsumers: [KeyboardInputConsumer] = []
    private let directionalLight: DirectionalLight

    private var trackingArea: NSTrackingArea?

    let rootAnchor: AnchorEntity

    required init() {
        self.rootAnchor = AnchorEntity()
        let anchor = AnchorEntity()
        anchor.addChild(rootAnchor)
        self.directionalLight = Self.setupLighting(anchor: anchor)

        super.init(frame: .zero)
        self.layer?.isOpaque = true

        scene.addAnchor(anchor)
    }

    func addTicker(_ ticker: @escaping (_ deltaTime: Float) -> Void) {
        self.scene
            .subscribe(to: SceneEvents.Update.self) { event in ticker(Float(event.deltaTime)) }
            .storeWhileEntityActive(rootAnchor)
    }

    @available(*, unavailable)
    dynamic required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    dynamic required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func attachMouseInputConsumer(_ consumer: MouseInputConsumer) {
        mouseInputConsumers.append(consumer)
    }

    func detachMouseInputConsumer(_ consumer: MouseInputConsumer) {
        mouseInputConsumers = mouseInputConsumers.filter { !($0 === consumer) }
    }

    func attachKeyboardInputConsumer(_ consumer: KeyboardInputConsumer) {
        keyboardInputConsumers.append(consumer)
    }

    func detachKeyboardInputConsumer(_ consumer: KeyboardInputConsumer) {
        keyboardInputConsumers = keyboardInputConsumers.filter { !($0 === consumer) }
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)

        let position = getLocalPosition(for: event)

        let newX = position.x
        let newY = position.y

        let oldPointInWindow = NSPoint(x: event.locationInWindow.x - event.deltaX, y: event.locationInWindow.y + event.deltaY)
        let oldPosition = convert(oldPointInWindow, from: nil)
        let oldX = Double(oldPosition.x)
        let oldY = Double(oldPosition.y)

        mouseInputConsumers.forEach { consumer in
            consumer.mouseMoved(newX: newX, newY: newY, oldX: oldX, oldY: oldY)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        let position = getLocalPosition(for: event)

        mouseInputConsumers.forEach { consumer in
            consumer.leftMouseButtonDown(x: position.x, y: position.y, clickCount: event.clickCount)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        let position = getLocalPosition(for: event)

        mouseInputConsumers.forEach { consumer in
            consumer.leftMouseButtonDragged(x: position.x,
                                            y: position.y,
                                            deltaX: Double(event.deltaX),
                                            deltaY: Double(event.deltaY))
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        let position = getLocalPosition(for: event)

        mouseInputConsumers.forEach { consumer in
            consumer.leftMouseButtonUp(x: position.x, y: position.y, clickCount: event.clickCount)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let position = getLocalPosition(for: event)

        mouseInputConsumers.forEach { consumer in
            consumer.rightMouseButtonDown(x: position.x, y: position.y, clickCount: event.clickCount)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let position = getLocalPosition(for: event)

        mouseInputConsumers.forEach { consumer in
            consumer.rightMouseButtonUp(x: position.x, y: position.y, clickCount: event.clickCount)
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        let position = getLocalPosition(for: event)

        mouseInputConsumers.forEach { consumer in
            consumer.rightMouseButtonDragged(x: position.x,
                                             y: position.y,
                                             deltaX: Double(event.deltaX),
                                             deltaY: Double(event.deltaY))
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let key = KeyboardCode(rawValue: event.keyCode) else {
            super.keyDown(with: event)
            return
        }

        keyboardInputConsumers.forEach { consumer in
            consumer.keyPressStarted(key: key)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let key = KeyboardCode(rawValue: event.keyCode) else {
            super.keyUp(with: event)
            return
        }

        keyboardInputConsumers.forEach { consumer in
            consumer.keyPressEnded(key: key)
        }
    }

    func getLocalPosition(for event: NSEvent) -> (x: Double, y: Double) {
        let position = convert(event.locationInWindow, from: nil)
        return (x: Double(position.x), y: Double(position.y))
    }

    private static func setupLighting(anchor: HasAnchoring) -> DirectionalLight {
        let directionalLight = DirectionalLight()
        directionalLight.name = "light"
        directionalLight.light.color = .white
        directionalLight.light.intensity = 2000
        directionalLight.light.isRealWorldProxy = true
        directionalLight.shadow = DirectionalLightComponent.Shadow(maximumDistance: 10,
                                                                   depthBias: 5.0)
        directionalLight.look(at: [-0.7, -3, -1], from: [0, 0, 0], relativeTo: nil)
        anchor.addChild(directionalLight)
        return directionalLight
    }
}

protocol MouseInputConsumer: AnyObject {
    func mouseMoved(newX: Double, newY: Double, oldX: Double, oldY: Double)
    func leftMouseButtonDown(x: Double, y: Double, clickCount: Int)
    func leftMouseButtonDragged(x: Double, y: Double, deltaX: Double, deltaY: Double)
    func leftMouseButtonUp(x: Double, y: Double, clickCount: Int)
    func rightMouseButtonDown(x: Double, y: Double, clickCount: Int)
    func rightMouseButtonDragged(x: Double, y: Double, deltaX: Double, deltaY: Double)
    func rightMouseButtonUp(x: Double, y: Double, clickCount: Int)
}

protocol KeyboardInputConsumer: AnyObject {
    func keyPressStarted(key: KeyboardCode)
    func keyPressEnded(key: KeyboardCode)
}

// From: https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066
enum KeyboardCode: UInt16 {
    case q = 0x0C // 12
    case w = 0x0D // 13
    case e = 0x0E // 14
    case a = 0x00 // 0
    case s = 0x01 // 1
    case d = 0x02 // 2
}

struct RealityView: NSViewRepresentable {
    @State private var cancellables: Set<AnyCancellable> = []

    @Binding var arView: ARViewContainer

    func makeNSView(context: Context) -> ARViewContainer {
        arView.debugOptions = .showStatistics
        return arView
    }

    func updateNSView(_ nsView: ARViewContainer, context: Context) {
    }

    func tick(ticker: @escaping (_ deltaTime: Float) -> Void) -> Self {
        arView.addTicker(ticker)
        return self
    }
}
