#include <metal_stdlib>
using namespace metal;

constant float pi = 3.14159265359;

constant float particleMass = 20.0;
constant float smoothingRadius = 100.0;
constant float pressureMultiplier = 100;
constant float targetDensity = 3.75;

kernel void add(const device float2 *in [[ buffer(0) ]],
                device float  *out [[ buffer(1) ]],
                uint id [[ thread_position_in_grid ]]) {
    out[id] = in[id].x + in[id].y;
}

struct Particle {
    simd_packed_float2 position;
    float density;
    int index;
};






float smoothingKernel(float distance, float radius) {
    if (distance >= radius) {
        return 0.0;
    }


    float volume = (pi * pow(radius, 4.0)) / 6.0;
    return ((radius - distance) * (radius - distance)) / volume;
}

float smoothingKernelDerivative(float distance, float radius)  {
    if (distance >= radius) {
        return 0;
    }

    float scale = 12.0 / (pi * pow(radius, 4));
    return (distance - radius) * scale;
}

//NOTE: 200 particles max
float calculateDensity(simd_packed_float2 samplePoint, Particle particles[200], int particleCount) {
    float density = 0.0;

    for (int i = 0; i < particleCount; i++) {
        float distance = length(particles[i].position - samplePoint);
        float influence = smoothingKernel( distance, smoothingRadius);
        density += particleMass * influence;
    }

    return density;
}


float calculatePressue(float density){
    float densityError = density - targetDensity;
    float pressure = densityError * pressureMultiplier;
    return pressure;
}

float calculateSharedPressureForce(float density1, float density2)  {
    float pressure1 = calculatePressue(density1);
    float pressure2 = calculatePressue(density2);
    return (pressure1 + pressure2) / 2.0;
}

// NOTE: max 200 particles
simd_packed_float2 calculatePressureForce(uint particleIndex,
                                          const device simd_packed_float2 positions[200],
                                          const device float densities[200],
                                          const device uint *particleCount) {
    simd_packed_float2 pressureForce = simd_packed_float2(0, 0);
    for (uint i = 0; i < *particleCount; i ++) {

        if (particleIndex == i) {
            continue;
        }

        if (densities[i] == 0.0) {
            continue;
        }

        if (densities[particleIndex] == 0.0) {
            continue;
        }

        simd_packed_float2 offset = positions[i] - positions[particleIndex];
        float distance = length(offset);

        if (distance == 0.0) {
            continue;
        }
        
        simd_packed_float2 randomDir = simd_packed_float2(0, -1);
        simd_packed_float2 direction = distance == 0 ? randomDir : offset / distance;
        float slope = smoothingKernelDerivative(distance, smoothingRadius);

        float sharedPressure = calculateSharedPressureForce(densities[i], densities[particleIndex]);
        pressureForce += -sharedPressure * direction * slope * particleMass / densities[i];
    }
    return pressureForce;
}

//NOTE: Max 200 particles
kernel void updateParticles(const device simd_packed_float2 inPositions [[ buffer(0) ]][200],
                            const device simd_packed_float2 inVelocities [[ buffer(1) ]][200],
                            const device float inDensities [[ buffer(2) ]][200],
                            device simd_packed_float2 outPositions [[ buffer(3) ]][200],
                            device simd_packed_float2 outVelocities [[ buffer(4) ]][200],
                            const device uint *particleCount [[ buffer(5)]],
                            uint id [[ thread_position_in_grid ]]) {

    // exit if out of bounds
    if (id < 0 || id >= *particleCount) {
        return;
    }

    float deltaTime = 1.0 / 60;
    simd_packed_float2 pressureForce = calculatePressureForce(id, inPositions, inDensities, particleCount);
    if (inDensities[id] != 0.0) {
        simd_packed_float2 pressureAcceleration = pressureForce / inDensities[id];
        outVelocities[id] =  inVelocities[id] + pressureAcceleration * deltaTime;
    }

    outVelocities[id] *= 0.99;

    outPositions[id] =  inPositions[id] + outVelocities[id] * deltaTime;

    float width = 1200.0;
    float height = 1200.0;
    if (outPositions[id].x < 0 || outPositions[id].x > width) {
        outPositions[id].x = min(width, max(0.0, outPositions[id].x));
        outVelocities[id].x *= -1.0;
    }

    if (outPositions[id].y < 0 || outPositions[id].y > height) {
        outPositions[id].y = min(height, max(0.0, outPositions[id].y));
        outVelocities[id].y *= -1.0;
    }

}
