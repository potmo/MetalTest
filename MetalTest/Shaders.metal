#include <metal_stdlib>
using namespace metal;

struct VertexIn{
    packed_float3 position;
    packed_float4 color;
};

struct ViewportIn {
    packed_float2 size;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct FragmentData {
    simd_packed_float2 position;
};

float dot2( simd_packed_float2 v ) { return dot(v,v); }
float dot2( simd_packed_float3 v ) { return dot(v,v); }
float ndot( simd_packed_float2 a, simd_packed_float2 b ) { return a.x*b.x - a.y*b.y; }


float circleDistance( simd_packed_float2 point, float radii )
{
    return length(point) - radii;
}

// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

vertex VertexOut basic_vertex(const device VertexIn* vertices [[ buffer(0) ]],
                              const device ViewportIn* viewportPointer [[buffer(1)]],
                              unsigned int vertexID [[ vertex_id ]]) {

    float2 pixelSpacePosition = vertices[vertexID].position.xy;
    ViewportIn viewportSize = ViewportIn(*viewportPointer);

    VertexIn vertexIn = vertices[vertexID];
    VertexOut vertexOut;
    vertexOut.position = float4(vertexIn.position, 1);
    vertexOut.position.xy = (pixelSpacePosition - viewportSize.size / 2) / (viewportSize.size / 2.0); // notmalize to 0...1

    vertexOut.color = vertexIn.color;

    return vertexOut;
}

fragment half4 basic_fragment(VertexOut interpolated [[stage_in]],
                              const device FragmentData* data [[buffer(0)]]) {


    simd_packed_float2 pos = interpolated.position.xy;
    float dist1 = circleDistance(pos - float2(800, 600), 200.0);
    float dist2 = circleDistance(pos - float2(700, 600), 200.0);
    float distance = min(dist1, dist2) / 200;

    // distance
    float3 color = float3(1.0) - sign(distance) * float3(0.1,0.4,0.7); // inside/outside color
    float blackFeatherAmount = 4.0; // less is more
    color *= 1.0 - exp(-blackFeatherAmount * abs(distance)); // black feather
    float frequency = 120.0;
    color *= 0.8 + 0.2 * cos(frequency * distance); // lines
    float outlineStrength = 0.8;
    float outlineWidth = 0.02;
    color = mix( color, float3(outlineStrength), 1.0 - smoothstep(0.0, outlineWidth, abs(distance))); // outline


    return half4(color.r,
                 color.g,
                 color.b,
                 1); // interpolated.color[3]
}

struct FluidFragmentArguments {
    simd_float2 positions[2000];
};

fragment half4 fluid_fragment(VertexOut interpolated [[stage_in]],
                              constant FluidFragmentArguments& fragmentShaderArgs [[ buffer(0) ]],
                              const device uint& dataLength [[buffer(1)]]) {



    simd_packed_float2 pos = floor(interpolated.position.xy);

    float distance = 1.0;

    for (uint32_t i = 0; i < dataLength; i++) { // note: 100 here must be the same as the array definition
        float2 circlePosition = fragmentShaderArgs.positions[i];
        float distanceToCircle = circleDistance(pos - circlePosition, 10.0);
        distance = min(distanceToCircle, distance);
    }

    /*
    for (uint32_t i = 0; i < dataLength; i++) {
        simd_packed_float2 circlePosition = floor(fragmentShaderArgs.positions[i]);

       // dist = dist * ((circlePosition.x == pos.x && circlePosition.y == pos.y) ? 1.0 : 0.0);
        //hit |= floor(circlePosition.x) == floor(pos.x) && floor(circlePosition.y) == floor(pos.y);
    }
     */


    half4 color = mix(half4(1,1,1,1), half4(0,0,0,0), 1.0 - distance);
    return color;


    // distance
    //float3 color = float3(1.0) - sign(distance) * float3(0.1,0.4,0.7); // inside/outside color

    //float3 color = float3(1.0) - sign(distance) * float3(0.1,0.4,0.7); // inside/outside color
    //float blackFeatherAmount = 20.0; // less is more
    //color *= 1.0 - exp(-blackFeatherAmount * abs(distance)); // black feather
    //float frequency = 120.0;
    //color *= 0.8 + 0.2 * cos(frequency * distance); // lines
    //float outlineStrength = 0.8;
    //float outlineWidth = 0.02;
    //color = mix( color, float3(outlineStrength), 1.0 - smoothstep(0.0, outlineWidth, abs(distance))); // outline


    //return half4(color.r,
    //             color.g,
    //             color.b,
    //             1); // interpolated.color[3]

}




