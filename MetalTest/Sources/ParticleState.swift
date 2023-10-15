import Foundation
import simd

class ParticleState {
    var particles: [Particle]
    private let smoothingRadius: Float = 340.0
    private let targetDensity: Float = 3.15
    private let pressureMultiplier: Float = 10000.0

    init() {
        let width: Float = 10.0
        let height: Float = 10.0

        self.particles = stride(from: 0.0, to: height, by: 2.0).flatMap { (x: Float) -> [Particle] in
            return stride(from: 0.0, to: width, by: 2.0).map { (y: Float) -> Particle in

                let index = Int(y * width + x)
                return Particle(index: index,
                                position: simd_packed_float2(100 + x * 200, 100 + y * 100), // set starting
                                predictedPosition: simd_packed_float2(0, 0),
                                velocity: simd_packed_float2(Float.random(in: -1 ..< 1), Float.random(in: -1 ..< 1)) * 50.0,
                                density: 0,
                                mass: 10)
            }
        }

        if particles.count > 100 {
            fatalError("the particle array length can be max 100 due to the shader")
        }
    }

    func loop(deltaTime: Float, viewport: Viewport) {
        for i in particles.indices {
            particles[i].predictedPosition = particles[i].position + particles[i].velocity * deltaTime
        }

        for i in particles.indices {
            //  let gravityForce = simd_packed_float2(0, 1000.2)
            // particles[i].velocity += gravityForce * deltaTime
            particles[i].density = calculateDensity(at: particles[i].predictedPosition)
        }

        for i in particles.indices {
            let pressureForce = calculatePressureForce(for: particles[i])
            let pressureAcceleration = pressureForce / particles[i].density
            particles[i].velocity += pressureAcceleration * deltaTime
        }

        for i in particles.indices {
            particles[i].position += particles[i].velocity * deltaTime
            particles[i].velocity *= 0.99

            if particles[i].position.x < 0 || particles[i].position.x > viewport.width {
                particles[i].position.x = min(viewport.width, max(0, particles[i].position.x))
                particles[i].velocity.x *= -1
            }

            if particles[i].position.y < 0 || particles[i].position.y > viewport.height {
                particles[i].position.y = min(viewport.height, max(0, particles[i].position.y))
                particles[i].velocity.y *= -1
            }
        }
    }

    func smoothingKernel(distance: Float, radius: Float) -> Float {
        if distance >= radius {
            return 0.0
        }

        let volume: Float = (.pi * pow(radius, 4)) / 6
        return ((radius - distance) * (radius - distance)) / volume
    }

    func smoothingKernelDerivative(distance: Float, radius: Float) -> Float {
        if distance >= radius {
            return 0
        }

        let scale = 12 / (.pi * pow(radius, 4))
        return (distance - radius) * scale
    }

    func calculateDensity(at samplePoint: simd_packed_float2) -> Float {
        var density: Float = 0

        for particle in particles {
            let distance = (particle.position - samplePoint).magnitude
            let influence = smoothingKernel(distance: distance, radius: smoothingRadius)
            density += particle.mass * influence
        }

        return density
    }

    func calculatePressue(from particle: Particle) -> Float {
        let targetDensity: Float = particle.position.x < 1000 ? 0.02 : 0.05
        let densityError = particle.density - targetDensity
        let pressure = densityError * pressureMultiplier
        return pressure
    }

    func calculateSharedPressureForce(_ particle1: Particle, _ particle2: Particle) -> Float {
        let pressure1 = calculatePressue(from: particle1)
        let pressure2 = calculatePressue(from: particle2)
        return (pressure1 + pressure2) / 2.0
    }

    func calculatePressureForce(for particle: Particle) -> simd_packed_float2 {
        var pressureForce = simd_float2(0, 0)
        for otherParticle in particles {
            if particle.index == otherParticle.index {
                continue
            }
            let offset = otherParticle.predictedPosition - particle.predictedPosition
            let distance = offset.magnitude
            let randomDir = simd_packed_float2(0, -1)
            let direction = distance == 0 ? randomDir : offset / distance
            let slope = smoothingKernelDerivative(distance: distance, radius: smoothingRadius)
            // let pressure = calculatePressue(from: density)
            let sharedPressure = calculateSharedPressureForce(otherParticle, particle)
            pressureForce += -sharedPressure * direction * slope * otherParticle.mass / otherParticle.density
        }
        return pressureForce
    }
}

struct Particle {
    let index: Int // FIXME: A smaller number type?
    var position: simd_packed_float2
    var predictedPosition: simd_packed_float2
    var velocity: simd_packed_float2
    var density: Float
    let mass: Float
}

extension simd_packed_float2 {
    var magnitude: Float {
        simd_distance(simd_packed_float2(0, 0), self)
    }
}
