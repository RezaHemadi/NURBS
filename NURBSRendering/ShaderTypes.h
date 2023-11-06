//
//  ShaderTypes.h
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name: _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, CubeBufferIndex)
{
    CubeBufferIndexMeshPositions    = 0,
    CubeBufferIndexMeshGenerics     = 1,
    CubeBufferIndexSharedUniforms   = 2,
    CubeBufferIndexInstanceUniforms = 3
};

typedef NS_ENUM(NSInteger, PTBufferIndex)
{
    PTBufferIndexControlPoints  = 0,
    PTBufferIndexNetSize        = 1,
    PTBufferIndexSharedUniforms = 2,
    PTBufferIndexUKnotVector    = 3,
    PTBufferIndexVKnotVector    = 4,
    PTBufferIndexUKnotCount     = 5,
    PTBufferIndexVKnotCount     = 6
};

typedef NS_ENUM(NSInteger, CEBufferIndex)
{
    CEBufferIndexParameter = 0,
    CEBufferIndexNumberOfControlPoints = 1,
    CEBufferIndexVertices = 2,
    CEBufferIndexControlPoints = 3,
    CEBufferIndexKnotVector = 4,
    CEBufferIndexKnotVectorCount = 5
};

// cube camera control instance uniforms
typedef struct {
    matrix_float4x4 transform;
} InstanceUniforms;

// control point instance uniforms
typedef struct {
    matrix_float4x4 transform;
    bool            highlight;
} CPInstanceUniforms;

typedef struct {
    matrix_float4x4 projection;
    matrix_float4x4 surfaceTransform;
    matrix_float4x4 viewMatrix;
} SharedUniforms;

typedef struct {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
} CubeSharedUniforms;

#endif /* ShaderTypes_h */
