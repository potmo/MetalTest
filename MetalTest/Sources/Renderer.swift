import Foundation
import MetalKit
import SwiftUI

class Renderer: NSObject, MTKViewDelegate, ObservableObject {
    private let metalDevice: MTLDevice
    private let metalCommandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var vertexBuffer: MTLBuffer
    private var viewportBuffer: MTLBuffer
    private var viewPort: Viewport

    private let particleState: ParticleState

    init(viewport: Viewport) {
        self.viewPort = viewport

        self.particleState = ParticleState()

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("failed creating metal device")
        }
        self.metalDevice = metalDevice

        guard let metalCommandQueue = metalDevice.makeCommandQueue() else {
            fatalError("failed creating metal command queue")
        }

        self.metalCommandQueue = metalCommandQueue

        guard let defaultLibrary = metalDevice.makeDefaultLibrary() else {
            fatalError("failed to get default library")
        }

        guard let vertexProgram = defaultLibrary.makeFunction(name: "basic_vertex") else {
            fatalError("not able to make vertex program")
        }

        guard let fragmentProgram = defaultLibrary.makeFunction(name: "fluid_fragment") else { // basic_fragment
            fatalError("not able to create fragment program")
        }

        let vertexDescriptor = MTLVertexDescriptor()

        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0 // Position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].bufferIndex = 0 // Color
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride

        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // this should be the same as view.colorPixelFormat
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch {
            fatalError("Failed to create pipeline state")
        }

        let vertices = [
            Vertex(x: 0.0, y: 0.0, z: 0.0, r: 1.0, g: 0.0, b: 0.0, a: 1.0),
            Vertex(x: 1, y: 0, z: 0.0, r: 0.0, g: 1.0, b: 0.0, a: 1.0),
            Vertex(x: 1, y: 1, z: 0.0, r: 0.0, g: 0.0, b: 1.0, a: 1.0),
        ]

        guard let vertexBuffer = metalDevice.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: []) else {
            fatalError("could not create vertex buffer")
        }

        self.vertexBuffer = vertexBuffer

        guard let viewportBuffer = metalDevice.makeBuffer(bytes: &self.viewPort, length: MemoryLayout<Viewport>.stride, options: []) else {
            fatalError("could not create viewport buffer")
        }
        self.viewportBuffer = viewportBuffer

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.viewPort = Viewport(width: Float(size.width), height: Float(size.height))
        guard let viewportBuffer = metalDevice.makeBuffer(bytes: &viewPort, length: MemoryLayout<Viewport>.stride, options: []) else {
            fatalError("could not create viewport buffer")
        }
        self.viewportBuffer = viewportBuffer

        let vertices = [
            Vertex(x: 0.0, y: 0.0, z: 0.0, r: 1.0, g: 0.0, b: 0.0, a: 1.0),
            Vertex(x: viewPort.width, y: 0, z: 0.0, r: 0.0, g: 1.0, b: 0.0, a: 1.0),
            Vertex(x: viewPort.width, y: viewPort.height, z: 0.0, r: 0.0, g: 0.0, b: 1.0, a: 1.0),

            Vertex(x: viewPort.width, y: viewPort.height, z: 0.0, r: 0.0, g: 0.0, b: 1.0, a: 1.0),
            Vertex(x: 0, y: viewPort.height, z: 0.0, r: 0.0, g: 0.0, b: 1.0, a: 1.0),
            Vertex(x: 0.0, y: 0.0, z: 0.0, r: 1.0, g: 0.0, b: 0.0, a: 1.0),
        ]

        guard let vertexBuffer = metalDevice.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: []) else {
            fatalError("could not create vertex buffer")
        }

        self.vertexBuffer = vertexBuffer
    }

    func draw(in view: MTKView) {
        // FIXME: This should be  actual delta tine
        let deltaTime: Float = 1.0 / Float(view.preferredFramesPerSecond)

        let maxParticles = 100

        if particleState.particles.count < maxParticles, Int.random(in: 0 ..< 50) == 1 {
            let newParticle = Particle(index: (particleState.particles.last?.index ?? 0) + 1,
                                       position: simd_float2(viewPort.width, viewPort.height) * Float.random(in: 0.0 ..< 1.0),
                                       predictedPosition: simd_packed_float2(0, 0),
                                       velocity: simd_packed_float2(Float.random(in: -1 ... 1), Float.random(in: -1 ... 1)) * 500,
                                       density: 0,
                                       mass: 10)
            particleState.particles.append(newParticle)
        }

        particleState.loop(deltaTime: deltaTime, viewport: viewPort)

        let fragments = particleState.particles.map(\.position).map { position in
            return FragmentData(position: position)
        }

        guard let fragmentBuffer = metalDevice.makeBuffer(bytes: fragments, length: MemoryLayout<FragmentData>.stride * maxParticles, options: []) else {
            fatalError("could not create fragments buffer")
        }

        var count = UInt32(fragments.count)
        guard let fragmentsLengthBuffer = metalDevice.makeBuffer(bytes: &count, length: MemoryLayout<Int>.stride, options: []) else {
            fatalError("could not create fragments buffer")
        }

        guard let drawable = view.currentDrawable else {
            return
        }

        guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
            fatalError("failed getting current render pass descriptor")
        }
        // let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else {
            fatalError("failed creating command buffer")
        }

        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("failed creating render command encoder")
        }

        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder.setVertexBuffer(viewportBuffer, offset: 0, index: 1)

        renderCommandEncoder.setFragmentBuffer(fragmentBuffer, offset: 0, index: 0)
        renderCommandEncoder.setFragmentBuffer(fragmentsLengthBuffer, offset: 0, index: 1)

        renderCommandEncoder.drawPrimitives(type: .triangle,
                                            vertexStart: 0,
                                            vertexCount: vertexBuffer.length / MemoryLayout<Vertex>.stride)

        renderCommandEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct Vertex {
    let x: Float
    let y: Float
    let z: Float
    let r: Float
    let g: Float
    let b: Float
    let a: Float
}

struct Viewport {
    let width: Float
    let height: Float
}

struct FragmentData {
    let position: simd_packed_float2

    init(x: Float, y: Float) {
        self.position = simd_packed_float2(x: x, y: y)
    }

    init(position: simd_packed_float2) {
        self.position = position
    }
}
