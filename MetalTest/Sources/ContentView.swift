import RealityKit
import SwiftUI

struct ContentView: View {
    @State var arView = ARViewContainer()
    @State var particleState = ParticleState()
    @State var entities: [Entity] = []
    var body: some View {
        RealityView(arView: $arView)
            .tick { _ in
            }
            .task {
                guard let path = Bundle.main.path(forResource: "Scene", ofType: "usdz") else {
                    fatalError("path is not available")
                }
                let url = URL(fileURLWithPath: path)
                guard let entity = try? Entity.load(contentsOf: url, withName: "Root/Cube") else {
                    fatalError("entity not found at \(url.absoluteString)")
                }

                // let boxMesh = MeshResource.generateBox(size: 0.1)
                // let material = SimpleMaterial(color: .red, isMetallic: false)
                // let model =  ModelEntity(mesh: boxMesh, materials: [material])

                // guard let child = entity.children[0] as? ModelEntity else {
                //    fatalError("no model entity")
                // }

                self.entities = particleState.particles.map { particle in
                    let newModel = entity.clone(recursive: true)

                    // newModel.model?.materials = [material]

                    newModel.position = SIMD3(particle.position.x, 0, particle.position.y)
                    // let random = Float.random(in: 10.0 ... 1.0)
                    newModel.scale = SIMD3(repeating: 10.0)

                    arView.rootAnchor.addChild(newModel)
                    return newModel
                }
            }
            .task {
                let cameraController = CameraController(arView: arView)
                arView.attachMouseInputConsumer(cameraController)
                arView.attachKeyboardInputConsumer(cameraController)
            }
            .task {
                Task.detached {
                    while true {
                        particleState.loop(deltaTime: min(0.1, 1.0 / 60.0))
                        zip(particleState.particles, entities).forEach { particle, entity in
                            entity.position = SIMD3(particle.position.x, 0, particle.position.y)
                        }
                    }
                }
            }
    }
}
