import Foundation
import simd

class ParticleState {
    var particles: [Particle]
    private let smoothingRadius: Float = 100.0
    private let targetDensity: Float = 3.15
    private let pressureMultiplier: Float = 100.0

    private let compute: ComputeParticles

    init() {
        let width: Float = 10.0
        let height: Float = 20.0

        self.particles = stride(from: 0.0, to: height, by: 1.0).flatMap { (x: Float) -> [Particle] in
            return stride(from: 0.0, to: width, by: 1.0).map { (y: Float) -> Particle in

                let index = Int(y * width + x)
                let position = simd_packed_float2(400 + x * 50, 400 + y * 50)
                return Particle(index: index,
                                position: position, // set starting
                                predictedPosition: position,
                                velocity: simd_packed_float2(Float.random(in: -1 ..< 1), Float.random(in: -1 ..< 1)) * 50.0,
                                density: 0,
                                mass: 20)
            }
        }

        if particles.count > 200 {
            fatalError("the particle array length can be max 100 due to the shader")
        }

        self.compute = ComputeParticles()
    }

    func cellCoordinate(for point: simd_packed_float2, radius: Float) -> (UInt, UInt) {
        let coordinate = (UInt(point.x / radius), UInt(point.x / radius))
        return coordinate
    }

    func cellHashFor(cellCoordinate: (cellX: UInt, cellY: UInt)) -> UInt {
        return cellCoordinate.cellX * 15823 + cellCoordinate.cellY * 9_737_333
    }

    func keyFrom(hash: UInt) -> Int {
        return Int(hash) % particles.count
    }

    func computeSpatialLookup(from particles: [Particle]) -> [(index: Int, key: Int)] {
        let spatialLookup = particles.enumerated().map { index, particle in
            let coordinate = cellCoordinate(for: particle.predictedPosition, radius: smoothingRadius)
            let cellHash = cellHashFor(cellCoordinate: coordinate)
            let key = keyFrom(hash: cellHash)
            return (index: index, key: key)
        }.sorted { a, b in
            return a.key < b.key
        }
        return spatialLookup
    }

    func computeStartIndices(from spatialLookup: [(index: Int, key: Int)]) -> [Int] {
        var startIndices = Array(repeating: Int.max, count: spatialLookup.count)

        (0 ..< spatialLookup.count).forEach { index in
            let key = spatialLookup[index].key
            let lastIndex = index - 1
            guard spatialLookup.indices.contains(lastIndex) else {
                startIndices[key] = index
                return
            }
            let lastKey = spatialLookup[lastIndex].key

            if lastKey != key {
                startIndices[key] = index
            }
        }

        return startIndices
    }

    func cellKeysAtPosition(of point: simd_packed_float2, radius: Float) -> [Int] {
        let lookupKeys = stride(from: max(0, point.x - radius), through: point.x + radius, by: radius).flatMap { x in
            return stride(from: max(0, point.y - radius), through: point.y + radius, by: radius).map { y in
                let cellCoordinate = cellCoordinate(for: simd_packed_float2(x, y), radius: radius)
                let cellHash = cellHashFor(cellCoordinate: cellCoordinate)
                return keyFrom(hash: cellHash)
            }
        }

        return Array(Set(lookupKeys))
    }

    func particlesInAreaOf(position: simd_packed_float2,
                           radius: Float,
                           particles: [Particle],
                           spatialLookup: [(index: Int, key: Int)],
                           startIndices: [Int]) -> [Particle] {
        let keys = cellKeysAtPosition(of: position, radius: radius)

        let radiusSquared = radius * radius

        var result: [Particle] = []

        for key in keys {
            let startIndex = startIndices[key]

            if startIndex == Int.max {
                continue
            }

            for i in startIndex ..< spatialLookup.count {
                guard spatialLookup[i].key == key else {
                    break
                }
                let particleIndex = spatialLookup[i].index
                let particle = particles[particleIndex]

                let squaredDistance = simd_distance_squared(position, particle.predictedPosition)

                if squaredDistance <= radiusSquared {
                    result.append(particle)
                }
            }
        }

        return result
    }

    func loop(deltaTime: Float, viewport: Viewport) {
        for i in particles.indices {
            particles[i].predictedPosition = particles[i].position + particles[i].velocity * deltaTime
        }

        let spatialLookup = computeSpatialLookup(from: particles)
        let startIndices = computeStartIndices(from: spatialLookup)

        let particlesWithinArea = particles.indices.map { i in
            let closeParticles = particlesInAreaOf(position: particles[i].predictedPosition,
                                                   radius: smoothingRadius,
                                                   particles: particles,
                                                   spatialLookup: spatialLookup,
                                                   startIndices: startIndices)

            return closeParticles
        }

        for i in particles.indices {
            particles[i].density = calculateDensity(at: particles[i].predictedPosition, particlesInArea: particlesWithinArea[i])
        }

        let (positions, velocities) = compute.compute(inPositions: particles.map(\.position),
                                                      inVelocities: particles.map(\.velocity),
                                                      inDensities: particles.map(\.density))

        for index in particles.indices {
            particles[index].position = positions[index]
            particles[index].velocity = velocities[index]
        }

        /*

         for i in particles.indices {
             let pressureForce = calculatePressureForce(for: particles[i], particlesInArea: particlesWithinArea[i])
             let pressureAcceleration = pressureForce / particles[i].density
             particles[i].velocity += pressureAcceleration * deltaTime
             // particles[i].velocity = particles[i].velocity.normalized * min(50.0, particles[i].velocity.magnitude)
         }

         for i in particles.indices {
             particles[i].velocity *= 0.99
             // let maxSpeeed: Float = 100
             // particles[i].velocity = particles[i].velocity.clamped(lowerBound: [-maxSpeeed, -maxSpeeed], upperBound: [maxSpeeed, maxSpeeed])
             particles[i].position += particles[i].velocity * deltaTime

             if particles[i].position.x < 0 || particles[i].position.x > viewport.width {
                 particles[i].position.x = min(viewport.width, max(0, particles[i].position.x))
                 particles[i].velocity.x *= -1
             }

             if particles[i].position.y < 0 || particles[i].position.y > viewport.height {
                 particles[i].position.y = min(viewport.height, max(0, particles[i].position.y))
                 particles[i].velocity.y *= -1
             }
         }
          */
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

    func calculateDensity(at samplePoint: simd_packed_float2, particlesInArea: [Particle]) -> Float {
        var density: Float = 0

        for particle in particlesInArea {
            let distance = (particle.position - samplePoint).magnitude
            let influence = smoothingKernel(distance: distance, radius: smoothingRadius)
            density += particle.mass * influence
        }

        return density
    }

    func calculatePressue(from particle: Particle) -> Float {
        let densityError = particle.density - targetDensity
        let pressure = densityError * pressureMultiplier
        return pressure
    }

    func calculateSharedPressureForce(_ particle1: Particle, _ particle2: Particle) -> Float {
        let pressure1 = calculatePressue(from: particle1)
        let pressure2 = calculatePressue(from: particle2)
        return (pressure1 + pressure2) / 2.0
    }

    func calculatePressureForce(for particle: Particle, particlesInArea: [Particle]) -> simd_packed_float2 {
        var pressureForce = simd_float2(0, 0)
        for otherParticle in particlesInArea {
            if particle.index == otherParticle.index {
                continue
            }
            guard otherParticle.density != 0 else {
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
    private var _position: simd_packed_float2
    var position: simd_packed_float2 {
        get {
            return _position
        }
        set {
            guard !newValue.x.isNaN, !newValue.y.isNaN else {
                fatalError("boom")
            }

            self._position = newValue
        }
    }

    var predictedPosition: simd_packed_float2
    var _velocity: simd_packed_float2

    var velocity: simd_packed_float2 {
        get {
            return _velocity
        }
        set {
            guard !newValue.x.isNaN, !newValue.y.isNaN else {
                fatalError("boom")
            }

            self._velocity = newValue
        }
    }

    var density: Float
    let mass: Float
    let radius: Float = 40

    init(index: Int, position: simd_packed_float2, predictedPosition: simd_packed_float2, velocity: simd_packed_float2, density: Float, mass: Float) {
        self.index = index
        self._position = position
        self.predictedPosition = predictedPosition
        self._velocity = velocity
        self.density = density
        self.mass = mass
    }
}

extension simd_packed_float2 {
    var magnitude: Float {
        simd_distance(simd_packed_float2(0, 0), self)
    }

    var normalized: simd_packed_float2 {
        guard self.magnitude > 0 else {
            return self
        }
        return simd_normalize(self)
    }
}
