//
//  Warp.metal
//  warpExample
//
//  Created by Alessandro Dal Grande on 8/11/15.
//  Copyright (c) 2015 Nifty. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexInOut
{
  float4 position [[ position ]];
  float3 warpedTexCoords;
  float3 originalTexCoords;
};

vertex VertexInOut warpVertex(uint vid [[ vertex_id ]],
                              device float4 *positions [[ buffer(0) ]],
                              device float3 *texCoords [[ buffer(1) ]])
{
  VertexInOut v;
  v.position = positions[vid];
  
  // example homography
  simd::float3x3 h = {
    {1.03140473, 0.0778113901, 0.000169219566},
    {0.0342947133, 1.06025684, 0.000459250761},
    {-0.0364957005, -38.3375587, 0.818259298}
  };
  
  v.warpedTexCoords = h * texCoords[vid];
  v.originalTexCoords = texCoords[vid];
  
  return v;
}

fragment half4 warpFragment(VertexInOut inFrag [[ stage_in ]],
                            texture2d<half, access::sample> original [[ texture(0) ]],
                            texture2d<half, access::sample> cpuWarped [[ texture(1) ]])
{
  constexpr sampler s(coord::pixel, filter::linear, address::clamp_to_zero);
  half4 gpuWarpedPixel = half4(original.sample(s, inFrag.warpedTexCoords.xy / inFrag.warpedTexCoords.z).r, 0, 0, 255);
  half4 cpuWarpedPixel = half4(0, cpuWarped.sample(s, inFrag.originalTexCoords.xy).r, 0, 255);
  
  return (gpuWarpedPixel + cpuWarpedPixel) * 0.5;
}