//
//  Shaders.metal
//  FireworksTest
//
//  Created by Andy Qua on 23/12/2018.
//  Copyright © 2018 Andy Qua. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;



struct VertexInOut
{
    float4  position [[position]];
    float4  color;
};

vertex VertexInOut passThroughVertex(uint vid [[ vertex_id ]],
                                     constant packed_float4* position  [[ buffer(0) ]],
                                     constant packed_float4* color    [[ buffer(1) ]],
                                     constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    VertexInOut outVertex;
    
    //outVertex.position = position[vid];
    float4 pos = position[vid];
    outVertex.position = uniforms.viewProjectionMatrix * pos;
    outVertex.color    = color[vid];
    
    return outVertex;
};


fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]])
{
    return half4(inFrag.color);
};


kernel void computeShader(
                          texture2d<float, access::read> source [[ texture(0) ]],
                          texture2d<float, access::write> dest [[ texture(1) ]],
                          uint2 gid [[ thread_position_in_grid ]])
{
    float4 source_color = source.read(gid);
    float4 result_color = source_color;
    
    dest.write(result_color, gid);
}
