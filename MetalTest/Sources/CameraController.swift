import AppKit
import Combine
import CoreGraphics
import RealityKit

class CameraController: MouseInputConsumer, KeyboardInputConsumer {
    var devicePosePublisher: AnyPublisher<Transform, Never> {
        devicePoseSubject.eraseToAnyPublisher()
    }

    private let devicePoseSubject = PassthroughSubject<Transform, Never>()

    private var keys = Set<KeyboardCode>()
    private let arView: ARView
    private var cancellables = Set<AnyCancellable>()
    private let cameraEntity: PerspectiveCamera
    private var mouseMovement = SIMD3<Float>.zero
    private var rightMouseButtonDown = false
    private var cameraSpeedMultiplier: Float = 10

    init(arView: ARView) {
        self.arView = arView

        cameraEntity = PerspectiveCamera()
        cameraEntity.name = "Camera"
        cameraEntity.look(at: [5.0, 0.0, 5.0], from: [5.0, 10.0, 10.0], upVector: [0, 1, 0], relativeTo: nil)

        let anchor = AnchorEntity()
        anchor.name = "Camera Anchor"
        anchor.addChild(cameraEntity)
        arView.scene.addAnchor(anchor)

        arView.scene.subscribe(to: SceneEvents.Update.self, self.update).store(in: &cancellables)
    }

    func getCameraEntity() -> Entity {
        return cameraEntity
    }

    func rightMouseButtonDown(x: Double, y: Double, clickCount: Int) {
        NSCursor.hide()
        rightMouseButtonDown = true
    }

    func rightMouseButtonDragged(x: Double, y: Double, deltaX: Double, deltaY: Double) {
        mouseMovement = [Float(deltaX), Float(deltaY), 0.0]
    }

    func rightMouseButtonUp(x: Double, y: Double, clickCount: Int) {
        NSCursor.unhide()
        rightMouseButtonDown = false
    }

    func mouseMoved(newX: Double, newY: Double, oldX: Double, oldY: Double) {
    }

    func leftMouseButtonDown(x: Double, y: Double, clickCount: Int) {
    }

    func leftMouseButtonDragged(x: Double, y: Double, deltaX: Double, deltaY: Double) {
    }

    func leftMouseButtonUp(x: Double, y: Double, clickCount: Int) {
    }

    func keyPressStarted(key: KeyboardCode) {
        keys.insert(key)
    }

    func keyPressEnded(key: KeyboardCode) {
        keys.remove(key)
    }

    func setCameraSpeedMultiplier(_ newCameraSpeedMultiplier: Float) {
        cameraSpeedMultiplier = newCameraSpeedMultiplier
    }

    private func update(event: SceneEvents.Update) {
        handleRotation(event: event)
        handleMovement(event: event)
    }

    private func handleRotation(event: SceneEvents.Update) {
        guard rightMouseButtonDown else {
            return
        }
        guard let windowFrame = arView.window?.frame else {
            return
        }
        guard let screenFrame = arView.window?.screen?.frame else {
            return
        }

        // Rotation speeds are on input axis, not in world space.
        let rotationSpeedX: Float = 3.0 // So X rotation is rotation based on X axis input, not rotating around the X axis
        let rotationSpeedY: Float = 2.0 // And Y rotation is rotation based on Y axis input, not rotating around the Y axis

        mouseMovement = clamp(mouseMovement, min: -SIMD3.one, max: SIMD3.one) // Clamp to avoid delta-jumps.

        let xRotationQuat = simd_quatf(angle: -mouseMovement.x * Float(event.deltaTime) * rotationSpeedX, axis: [0, 1, 0])
        let yRotationQuat = simd_quatf(angle: -mouseMovement.y * Float(event.deltaTime) * rotationSpeedY, axis: cameraEntity.transform.rotation.act([1, 0, 0]))
        let finalRotation = xRotationQuat * yRotationQuat * cameraEntity.transform.rotation
        cameraEntity.transform.rotation = finalRotation
        mouseMovement = .zero // Avoid having mouse delta stuck at != 0.
        CGWarpMouseCursorPosition(CGPoint(x: windowFrame.midX,
                                          y: screenFrame.height - windowFrame.midY))

        devicePoseSubject.send(getDevicePose())
    }

    private func handleMovement(event: SceneEvents.Update) {
        guard keys.isEmpty == false else {
            return
        }

        let currentPos = cameraEntity.transform.translation
        var viewDirection = SIMD3<Float>.zero

        let cameraSpeed: Float = 0.4 * cameraSpeedMultiplier

        if keys.contains(.w) {
            viewDirection += cameraEntity.transform.rotation.act(SIMD3(0, 0, -1 * Float(event.deltaTime) * cameraSpeed))
        }
        if keys.contains(.a) {
            viewDirection += cameraEntity.transform.rotation.act(SIMD3(-1 * Float(event.deltaTime) * cameraSpeed, 0, 0))
        }
        if keys.contains(.s) {
            viewDirection += cameraEntity.transform.rotation.act(SIMD3(0, 0, 1 * Float(event.deltaTime) * cameraSpeed))
        }
        if keys.contains(.d) {
            viewDirection += cameraEntity.transform.rotation.act(SIMD3(1 * Float(event.deltaTime) * cameraSpeed, 0, 0))
        }
        if keys.contains(.q) {
            viewDirection += cameraEntity.transform.rotation.act(SIMD3(0, -1 * Float(event.deltaTime) * cameraSpeed, 0))
        }
        if keys.contains(.e) {
            viewDirection += cameraEntity.transform.rotation.act(SIMD3(0, 1 * Float(event.deltaTime) * cameraSpeed, 0))
        }

        cameraEntity.transform.translation = currentPos + viewDirection
        devicePoseSubject.send(getDevicePose())
    }

    func getDevicePose() -> Transform {
        Transform(matrix: cameraEntity.transformMatrix(relativeTo: nil))
    }

    func hasValidDevicePose() -> Bool {
        true
    }
}
