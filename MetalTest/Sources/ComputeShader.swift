import Foundation
import MetalKit
import os.log

actor ComputeShader {
    private let device: MTLDevice
    private let commandBuffer: MTLCommandBuffer
    private let encoder: MTLComputeCommandEncoder

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("not possible to load metal device")
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("not able to create command queue")
        }
        guard let library = device.makeDefaultLibrary() else { // .makeLibrary(filepath: "compute.metallib")
            fatalError("not able to create default library")
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("not atble to create command buffer")
        }
        self.commandBuffer = commandBuffer

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("not able to create command buffer")
        }

        self.encoder = encoder

        guard let addFunction = library.makeFunction(name: "add") else {
            fatalError("not able to create the add function")
        }
        let pipelineState: MTLComputePipelineState
        do {
            pipelineState = try device.makeComputePipelineState(function: addFunction)
        } catch {
            fatalError("failed create pipeline state: \(error.localizedDescription)")
        }

        encoder.setComputePipelineState(pipelineState)
    }

    func compute(a: Float, b: Float) async -> Float {
        let input: [Float] = [a, b]

        let buffer = device.makeBuffer(bytes: input, length: MemoryLayout<Float>.stride * input.count, options: [])
        encoder.setBuffer(buffer, offset: 0, index: 0)

        let outputBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride, options: [])!
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)

        // run kernel

        let numThreadgroups = MTLSize(width: 1, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        // ----------------------------------------------------------------------
        // Results
        let result = outputBuffer.contents().load(as: Float.self)

        Logger().debug("\(input[0]) + \(input[1]) = \(result)")
        return result
    }

  
}

