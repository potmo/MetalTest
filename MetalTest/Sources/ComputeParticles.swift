import Foundation
import MetalKit
import os.log

class ComputeParticles {
    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("not possible to load metal device")
        }
        self.device = device

        guard let library = device.makeDefaultLibrary() else { // .makeLibrary(filepath: "compute.metallib")
            fatalError("not able to create default library")
        }

        guard let addFunction = library.makeFunction(name: "updateParticles") else {
            fatalError("not able to create the add function")
        }

        do {
            pipelineState = try device.makeComputePipelineState(function: addFunction)
        } catch {
            fatalError("failed create pipeline state: \(error.localizedDescription)")
        }
    }

    func compute(inPositions: [simd_packed_float2],
                 inVelocities: [simd_packed_float2],
                 inDensities: [Float]) -> (positions: [simd_packed_float2],
                                           velocities: [simd_packed_float2]) {
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("not able to create command queue")
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("not atble to create command buffer")
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("not able to create command buffer")
        }

        encoder.setComputePipelineState(pipelineState)

        let inputPositionsBuffer = device.makeBuffer(bytes: inPositions, length: MemoryLayout<simd_packed_float2>.stride * inPositions.count, options: [])
        encoder.setBuffer(inputPositionsBuffer, offset: 0, index: 0)
        // encoder.setBytes(inPositions, length: MemoryLayout<simd_packed_float2>.stride * inPositions.count, index: 0)

        let inputVelocitiesBuffer = device.makeBuffer(bytes: inVelocities, length: MemoryLayout<simd_packed_float2>.stride * inVelocities.count, options: [])
        encoder.setBuffer(inputVelocitiesBuffer, offset: 0, index: 1)

        let inputDensitiesBuffer = device.makeBuffer(bytes: inDensities, length: MemoryLayout<Float>.stride * inVelocities.count, options: [])
        encoder.setBuffer(inputDensitiesBuffer, offset: 0, index: 2)

        let outputPositionsBuffer = device.makeBuffer(length: MemoryLayout<simd_packed_float2>.stride * inPositions.count, options: [])!
        encoder.setBuffer(outputPositionsBuffer, offset: 0, index: 3)

        let outputVelocitiesBuffer = device.makeBuffer(length: MemoryLayout<simd_packed_float2>.stride * inPositions.count, options: [])!
        encoder.setBuffer(outputVelocitiesBuffer, offset: 0, index: 4)

        var particleCount = UInt32(inPositions.count)
        let inputParticleCountBuffer = device.makeBuffer(bytes: &particleCount, length: MemoryLayout<UInt32>.stride, options: [])!
        encoder.setBuffer(inputParticleCountBuffer, offset: 0, index: 5)

        // run kernel

        let maxThreadgroups = min(pipelineState.maxTotalThreadsPerThreadgroup, inPositions.count)
        let numThreadgroups = MTLSize(width: maxThreadgroups, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: 1024, height: 1, depth: 1)
        encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        // ----------------------------------------------------------------------
        // Results
        let packedFloatSize = MemoryLayout<simd_packed_float2>.stride
        let outputPositions = stride(from: 0, to: inPositions.count, by: 1).map { index in
            outputPositionsBuffer.contents().load(fromByteOffset: index * packedFloatSize, as: simd_packed_float2.self)
        }

        let outputVelocities = stride(from: 0, to: inVelocities.count, by: 1).map { index in
            outputVelocitiesBuffer.contents().load(fromByteOffset: index * packedFloatSize, as: simd_packed_float2.self)
        }

        // outputPositionsBuffer.contents().copyMemory(from: &outputPositions, byteCount: MemoryLayout<simd_packed_float2>.stride * inPositions.count)

        return (outputPositions, outputVelocities)
    }
}
