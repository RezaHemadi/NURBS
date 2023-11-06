//
//  Shaders.metal
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

#include <metal_stdlib>
using namespace metal;
#import "ShaderTypes.h"


// Control Point struct
struct ControlPoint {
    float4 position [[attribute(0)]];
};

struct Point {
    float4 position;
};

// Patch struct
struct PatchIn {
    patch_control_point<ControlPoint> control_points;
    uint2 net[[attribute(1)]];
};

// vertex to fragment struct
struct FunctionOutIn {
    float4 position [[position]];
    half4 color [[flat]];
    float3 normal;
};

// MARK: - Helper Methods
unsigned int factorial(unsigned int n)
{
    if (n == 0 || n == 1)
        return 1;
    
    return n * factorial(n - 1);
}

float binomial(unsigned int n, unsigned int k)
{
    assert(n >= k);
    
    unsigned int numerator = factorial(n);
    unsigned int denominator = factorial(k) * factorial(n - k);
    
    return float(numerator) / float(denominator);
}

/// Compute all n-th degree bernstein polynomials.
void allBernstein(int n, float u, thread float* b)
{
    b[0] = 1.0;
    float u1 = 1.0 - u;
    
    for (int j = 1; j <= n; j++)
    {
        float saved = 0.0;
        
        for (int k = 0; k < j; k++)
        {
            float temp = b[k];
            b[k] = saved + u1 * temp;
            saved = u * temp;
        }
        b[j] = saved;
    }
}

/// Compute point on Bezier curve
float4 pointOnBezierCurve(const device Point* p, int n, float u)
{
    assert(n <= 10);
    thread float b[10];
    allBernstein(n, u, b);
    float4 c = float4(0.0, 0.0, 0.0, 0.0);
    
    for (int k = 0; k <= n; k++)
        c = c + b[k] * p[k].position;
    
    return c;
}

/// compute point on a bezier curve using deCasteljau
float4 deCasteljau1(device const Point* p, int n, float u)
{
    assert(n <= 10);
    // use local array so we don't destroy control points
    thread float4 Q[10];
    for (int i = 0; i <= n; i++)
        Q[i] = p[i].position;
    for (int k = 1; k <= n; k++)
        for (int i = 0; i <= (n - k); i++)
            Q[i] = (1.0 - u) * Q[i] + u * Q[i + 1];
    return Q[0];
}

float4 deCasteljau1(thread const float4* p, int n, float u)
{
    assert(n <= 10);
    thread float4 Q[10];
    for (int i = 0; i <= n; i++)
        Q[i] = p[i];
    for (int k = 1; k <= n; k++)
        for (int i = 0; i <= (n - k); i++)
            Q[i] = (1.0 - u) * Q[i] + u * Q[i + 1];
    return Q[0];
}

float4 deCasteljau1(const PatchIn patchIn, int startIdx, int n, float u)
{
    assert(n == end - start - 1);
    assert(n <= 10);
    thread float4 Q[10];
    for (int i = 0; i <= n; i++)
        Q[i] = patchIn.control_points[startIdx + i].position;
    for (int k = 1; k <= n; k++)
        for (int i = 0; i <= (n - k); i++)
            Q[i] = (1.0 - u) * Q[i] + u * Q[i + 1];
    return Q[0];
}

// Compute a point on a bezier surface by deCasteljau
float4 deCasteljau2(device const Point* p, int n, int m, float u0, float v0)
{
    assert(n <= m);
    thread float4 Q[5];
    
    for (int i = 0; i <= n; i++)
    {
        device const Point* jthRow = p + (m + 1) * i;
        Q[i] = deCasteljau1(jthRow, m, v0);
    }
    float4 s = deCasteljau1(Q, m, u0);
    return s;
}

float4 deCasteljau2(thread const float4* p, int n, int m, float u0, float v0)
{
    assert(n <= m);
    thread float4 Q[5];
    
    for (int i = 0; i <= n; i++)
    {
        thread const float4* jthRow = p + (m + 1) * i;
        Q[i] = deCasteljau1(jthRow, m, v0);
    }
    float4 s = deCasteljau1(Q, m, u0);
    return s;
}

float4 deCasteljau2(const PatchIn patchIn, int n, int m, float u0, float v0)
{
    thread float4 Q[3];
    for (int j = 0; j <= n; j++)
    {
        int startIdx = (m + 1) * j;
        Q[j] = deCasteljau1(patchIn, startIdx, m, u0);
    }
    return deCasteljau1(Q, n, v0);
}

/// return the span index of a certain u in knot vector
/// n = m - p -1
/// m = knot vector count - 1
/// p = degree of segments
/// returns span index
int FindSpan(int n, int p, float u, device const float* U)
{
    if (u == U[n + 1])
        return (n); // Special case
    // Do binary search
    int low = p;
    int high = n + 1;
    int mid = (low + high) / 2;
    
    while (u < U[mid] || u >= U[mid + 1])
    {
        if ( u < U[mid] )
            high = mid;
        else
            low = mid;
        mid = (low + high) / 2;
    }
    
    return mid;
}

/// compute the non-vanishing basis functions (B-spline) and stores them in the array N[0], ...., N[p]
/// input: i, u, p, U
/// output: N
void basisFuns_bSpline(int i, float u, int p, device const float* U, thread float* N)
{
    thread float left[10];
    thread float right[10];
    N[0] = 1.0;
    for (int j = 1; j <= p; j++)
    {
        left[j] = u - U[i + 1 - j];
        right[j] = U[i + j] - u;
        float saved = 0.0;
        
        for (int r = 0; r < j; r++)
        {
            float temp = N[r] / (right[r + 1] + left[j - r]);
            N[r] = saved + right[r + 1] * temp;
            saved = left[j - r] * temp;
        }
        N[j] = saved;
    }
}

/// Compute non-zero basis functions and their derivatives
///  input: i, u, p, n, U
// output: ders
void dersBasisFuns_bSpline(uint8_t i, float u, uint8_t p, uint8_t n, const device float* U, thread float ders[5][5])
{
    assert(p <= 5);
    thread float ndu[5][5];
    
    ndu[0][0] = 1.0;
    
    uint8_t j;
    
    
    thread float left[5];
    thread float right[5];
    
    for (uint8_t j = 1; j <= p; j++)
    {
        left[j] = u - U[i + 1 - j];
        right[j] = U[i + j] - u;
        float saved = 0.0;
        
        for (uint8_t r = 0; r < j; r++)
        {
            // Lower triangle
            ndu[j][r] = right[r + 1] + left[j - r];
            float temp = ndu[r][j - 1] / ndu[j][r];
            // Upper triangle
            ndu[r][j] = saved + right[r + 1] * temp;
            saved = left[j - r] * temp;
        }
        ndu[j][j] = saved;
    }
    
    for (uint8_t j = 0; j <= p; j++)
        // Load the basis functions
        ders[0][j] = ndu[j][p];
    // this section computes the derivatives
    for (uint8_t r = 0; r <= p; r++)
    {
        // alternate rows in array a
        uint8_t s1 = 0;
        uint8_t s2 = 1;
        thread float a[2][2];
        a[0][0] = 1.0;
        // loop to compute k-th derivative
        for (uint8_t k = 1; k <= n; k++)
        {
            float d = 0.0;
            int8_t rk = r - k;
            int8_t pk = p - k;
            if (r >= k)
            {
                a[s2][0] = a[s1][0] / ndu[pk + 1][rk];
                d = a[s2][0] * ndu[rk][pk];
            }
            
            int8_t j1;
            int8_t j2;
            if (rk >= -1)
                j1 = 1;
            else
                j1 = -1;
            if (r - 1 <= pk)
                j2 = k - 1;
            else
                j2 = p - r;
            for (int8_t j = j1; j <= j2; j++)
            {
                a[s2][j] = (a[s1][j] - a[s1][j-1]) / ndu[pk+1][rk+j];
                d += a[s2][j] * ndu[rk+j][pk];
            }
            if (r <= pk)
            {
                a[s2][k] = -a[s1][k-1] / ndu[pk+1][r];
                d += a[s2][k] * ndu[r][pk];
            }
            ders[k][r] = d;
            // switch rows
            j = s1;
            s1 = s2;
            s2 = j;
        }
    }
    // Multiply through by the correct factors
    uint8_t r;
    r = p;
    for (uint8_t k = 1; k <= n; k++)
    {
        for (uint8_t j = 0; j <= p; j++)
            ders[k][j] *= r;
        r *= (p - k);
    }
}
// compute curve derivatives
// n: number of control points is n + 1
// p: the degree of the curve
// U: the knot vector
// P: the control points
// output: array CK where CK[k] is the kth derivative, 0 <= k <= d
void curveDerivesAlg1_Bspline(uint8_t n, uint8_t p, const device float* U, device Point* P, float u, uint8_t d, thread float3 CK[2])
{
    uint8_t du = min(d, p);
    for (uint8_t k = p + 1; k <= d; k++)
        CK[k] = 0.0;
    uint8_t span = FindSpan(n, p, u, U);
    thread float nders[5][5];
    dersBasisFuns_bSpline(span, u, p, du, U, nders);
    for (uint8_t k = 0; k <= du; k++)
    {
        CK[k] = 0.0;
        for (uint8_t j = 0; j <= p; j++)
            CK[k] = CK[k] + nders[k][j] * P[span - p + j].position.xyz;
    }
}

float4 surfacePoint_Bspline(int n, int p, const device float* U, int m, int q, const device float* V, PatchIn P, float u, float v)
{
    thread float Nu[10];
    thread float Nv[10];
    uint8_t uspan = FindSpan(n, p, u, U);
    basisFuns_bSpline(uspan, u, p, U, Nu);
    uint8_t vspan = FindSpan(m, q, v, V);
    basisFuns_bSpline(vspan, v, q, V, Nv);
    int uind = uspan - p;
    float4 S = float4(0.0, 0.0, 0.0, 0.0);
    for (int l = 0; l <= q; l++)
    {
        float4 temp = float4(0.0, 0.0, 0.0, 0.0);
        int vind = vspan - q + l;
        for (int k = 0; k <= p; k++)
        {
            int index = (n + 1) * vind + (uind + k);
            temp = temp + Nu[k] * P.control_points[index].position;
        }
        S = S + Nv[l] * temp;
    }
    return S;
}

// Compute surface derivatives
// input: n, p, U, m, q, V, P, u, v, d
// output: SKL
void surfaceDerivsAlg1_Bspline(int n, int p, device const float* U, int m, int q, device const float* V, PatchIn P, float u, float v, int d, thread float3 SKL[3][3])
{
    assert(d <= 2);
    int du = min(d, p);
    for (int k = p + 1; k <= d; k++)
        for (int l = 0; l <= d - k; l++)
            SKL[k][l] = float3(0.0, 0.0, 0.0);
    int dv = min(d, q);
    for (int l = q + 1; l <= d; l++)
        for (int k = 0; k <= d - l; k++)
            SKL[k][l] = float3(0.0, 0.0, 0.0);
    
    int uspan = FindSpan(n, p, u, U);
    thread float Nu[5][5];
    dersBasisFuns_bSpline(uspan, u, p, du, U, Nu);
    int vspan = FindSpan(m, q, v, V);
    thread float Nv[5][5];
    dersBasisFuns_bSpline(vspan, v, q, dv, V, Nv);
    
    thread float3 temp[5];
    for (int k = 0; k <= du; k++)
    {
        for (int s = 0; s <= q; s++)
        {
            temp[s] = float3(0.0, 0.0, 0.0);
            for (int r = 0; r <= p; r++)
            {
                int index = (n + 1) * (vspan - q + s) + (uspan - p + r);
                temp[s] = temp[s] + Nu[k][r] * P.control_points[index].position.xyz;
            }
        }
        int dd = min(d - k, dv);
        for (int l = 0; l <= dd; l++)
        {
            SKL[k][l] = float3(0.0, 0.0, 0.0);
            for (int s = 0; s <= q; s++)
                SKL[k][l] = SKL[k][l] + Nv[l][s] * temp[s];
        }
    }
}

void surfacePointNormal_Bspline(int n, int p, const device float* U, int m, int q, const device float* V, PatchIn P, float u, float v, thread float4& point, thread float3& normal)
{
    thread float Nu[5][5];
    thread float Nv[5][5];
    int uspan = FindSpan(n, p, u, U);
    dersBasisFuns_bSpline(uspan, u, p, n, U, Nu);
    int vspan = FindSpan(m, q, v, V);
    dersBasisFuns_bSpline(vspan, v, q, m, V, Nv);
    int uind = uspan - p;
    point = float4(0.0, 0.0, 0.0, 0.0);
    float3 du = float3(0.0, 0.0, 0.0);
    float3 dv = float3(0.0, 0.0, 0.0);
    for (int l = 0; l <= q; l++)
    {
        float4 temp = float4(0.0, 0.0, 0.0, 0.0);
        int vind = vspan - q + l;
        for (int k = 0; k <= p; k++)
        {
            int index = (n + 1) * vind + (uind + k);
            temp = temp + Nu[0][k] * P.control_points[index].position;
            du = du + Nu[1][k] * P.control_points[index].position.xyz;
        }
        point = point + Nv[0][l] * temp;
        dv = dv + Nv[1][l] * (temp / temp.w).xyz;
        normal += cross(dv, du);
    }
    
    //normal = cross(dv, du);
    normal.y *= -1;
}

// MARK: - Compute Kernels
// compute kernel
kernel void computeFactors(constant float&                          edge_factor   [[ buffer(0) ]],
                           constant float&                          inside_factor [[ buffer(1) ]],
                           device   MTLQuadTessellationFactorsHalf* factors       [[ buffer(2) ]],
                                    uint                            pid           [[ thread_position_in_grid ]])
{
    // simple passthrough operation
    // More sophisticated compute kernels might determine the tessellation factors based on the state of the scene (e.g. camera distance)

    factors[pid].edgeTessellationFactor[0] = edge_factor;
    factors[pid].edgeTessellationFactor[1] = edge_factor;
    factors[pid].edgeTessellationFactor[2] = edge_factor;
    factors[pid].edgeTessellationFactor[3] = edge_factor;
    factors[pid].insideTessellationFactor[0] = inside_factor;
    factors[pid].insideTessellationFactor[1] = inside_factor;
}
// kernel to transform control points to world space
kernel void projectPoints(constant SharedUniforms& uniforms [[buffer(0)]],
                          device   Point*          points   [[buffer(1)]],
                                   uint            pid      [[thread_position_in_grid]]) {
    points[pid].position = uniforms.surfaceTransform * points[pid].position;
}

// MARK: - Rendering

// quad post-tessellation vertex function
[[patch(quad, 32)]]
vertex FunctionOutIn vertexShader(             PatchIn         patchIn     [[stage_in]],
                                  constant     SharedUniforms& uniforms    [[buffer(PTBufferIndexSharedUniforms)]],
                                  const device float*          U           [[buffer(PTBufferIndexUKnotVector)]],
                                  const device float*          V           [[buffer(PTBufferIndexVKnotVector)]],
                                  constant     int&            uKnots      [[buffer(PTBufferIndexUKnotCount)]],
                                  constant     int&            vKnots      [[buffer(PTBufferIndexVKnotCount)]],
                                               float2          patch_coord [[ position_in_patch ]])
{
    // Parameter coordinates
    float u = patch_coord.x;
    float v = patch_coord.y;
    
    thread float4 s = float4(0.0, 0.0, 0.0, 0.0);
    uint8_t n = patchIn.net.y - 1; // n + 1 is number of control points across u parameter space.
    uint8_t m = patchIn.net.x - 1; // m + 1 is number of control points across v parameter space.
    uint8_t p = uKnots - 1 - n - 1; // p is the curve degree across u parameter space.
    uint8_t q = vKnots - 1 - m - 1;
    
    //s = surfacePoint_Bspline(n, p, U, m, q, V, patchIn, u, v);
    thread float3 normal;
    s = surfacePoint_Bspline(n, p, U, m, q, V, patchIn, u, v);
    
    thread float3 SKU[3][3];
    surfaceDerivsAlg1_Bspline(n, p, U, m, q, V, patchIn, u, v, 2, SKU);
    normal = cross(SKU[1][0], SKU[0][1]);
    normal = float3(abs(normal.x), abs(normal.y), abs(normal.z));
    
    //float4 s = deCasteljau2(patchIn, patchIn.net.x, patchIn.net.y, u, v);
    
    if (s.w != 0) {
        s = s / s.w;
    }
    
    FunctionOutIn vertexOut;
    vertexOut.position = uniforms.projection * uniforms.viewMatrix * s;
    vertexOut.color = half4(u, v, 1.0-v, 1.0);
    vertexOut.normal = normalize(normal);
    return vertexOut;
    
    /*
    // Linear interpolation
    float4 um = bezier(u, patchIn.control_points[0].position, patchIn.control_points[2].position, patchIn.control_points[3].position);
    float4 lm = bezier(u, patchIn.control_points[8].position, patchIn.control_points[10].position, patchIn.control_points[11].position);
    //float4 upper_middle = mix(patchIn.control_points[0].position, patchIn.control_points[1].position, u);
    //float4 lower_middle = mix(patchIn.control_points[2].position, patchIn.control_points[3].position, u);
    
    // Output
    FunctionOutIn vertexOut;
    vertexOut.position = uniforms.projection * uniforms.viewMatrix * mix(um, lm, v);
    vertexOut.color = half4(u, v, 1.0-v, 1.0);
    return vertexOut;*/
}

fragment float4 fragmentShader(FunctionOutIn fragmentIn [[stage_in]])
{
    return float4(fragmentIn.normal, 1.0);
    //return fragmentIn.color;
}

// MARK: - Curve rendering
struct CurveVertex {
    float4 position [[attribute(0)]];
};

struct CurveVertexInOut {
    float4 position [[position]];
};

void kernel evaluateCurve(device   float*       u                     [[ buffer(CEBufferIndexParameter) ]],
                          constant int&         numberOfControlPoints [[ buffer(CEBufferIndexNumberOfControlPoints) ]],
                          device   CurveVertex* vertices              [[ buffer(CEBufferIndexVertices) ]],
                          device   Point*       controlPoints         [[ buffer(CEBufferIndexControlPoints) ]],
                          const device   float*       knotVector      [[ buffer(CEBufferIndexKnotVector) ]],
                          constant uint8_t&     knotVectorCount       [[ buffer(CEBufferIndexKnotVectorCount) ]],
                                   uint         id                    [[thread_position_in_grid]])
{
    //vertices[id].position = pointOnBezierCurve(controlPoints, numberOfControlPoints - 1, u[id]);
    //float4 pw = deCasteljau1(controlPoints, numberOfControlPoints - 1, u[id]);
    
    thread float N[10];
    int p = static_cast<uint8_t>(knotVectorCount - 1 - numberOfControlPoints);
    int span = FindSpan(numberOfControlPoints - 1, p, u[id], knotVector);
    basisFuns_bSpline(span, u[id], p, knotVector, N);
    float4 pw = float4(0.0, 0.0, 0.0, 0.0);
    
    for (uint8_t i = 0; i <= p; i++)
    {
        pw += N[i] * controlPoints[span - p + i].position;
    }
    
    if (pw.w != 0) {
        pw = pw / pw.w;
    }
    vertices[id].position = pw;
}

vertex CurveVertexInOut curveVertexShader(CurveVertex in [[stage_in]],
                                          constant SharedUniforms& uniforms [[buffer(1)]])
{
    CurveVertexInOut out;
    out.position = uniforms.projection * uniforms.viewMatrix * in.position;
    
    return out;
}

fragment half4 curveFragmentShader(CurveVertexInOut in [[stage_in]])
{
    return half4(1.0, 0.0, 0.0, 1.0);
}

// Mark: - Cube Rendering
typedef struct {
    float3 position [[ attribute(0) ]];
    float2 texcoord [[ attribute(1) ]];
    half3  normal   [[ attribute(2) ]];
} CubeVertex;

typedef struct {
    float4 position [[position]];
    float2 texcoord;
    float4 normal;
    float4 color;
} CubeColorInOut;

CubeColorInOut vertex cubeVertexShader(CubeVertex in [[ stage_in ]],
                                       constant CubeSharedUniforms &uniforms [[ buffer(CubeBufferIndexSharedUniforms) ]],
                                       constant InstanceUniforms   &instanceUniforms [[ buffer(CubeBufferIndexInstanceUniforms) ]],
                                                ushort              vid              [[vertex_id]])
{
    CubeColorInOut out;
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * instanceUniforms.transform * position;
    out.texcoord = float2(in.texcoord.x, 1 - in.texcoord.y);
    out.normal = instanceUniforms.transform * float4(in.normal.x, in.normal.y, in.normal.z, 0.0);
    
    // Color each face a different color
    ushort colorID = vid / 4 % 6;
    out.color = colorID == 0 ? float4(0.0, 1.0, 0.0, 1.0) // Right face
              : colorID == 1 ? float4(1.0, 0.0, 0.0, 1.0) // Left face
              : colorID == 2 ? float4(0.0, 0.0, 1.0, 1.0) // Top face
              : colorID == 3 ? float4(1.0, 0.5, 0.0, 1.0) // Bottom face
              : colorID == 4 ? float4(1.0, 1.0, 0.0, 1.0) // Back face
              : float4(1.0, 1.0, 1.0, 1.0); // Front face
    
    return out;
}

float4 fragment cubeFragmentShader(CubeColorInOut in [[ stage_in ]],
                                   texture2d<float> color [[texture(0)]])
{
    return in.color;
    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
    float4 diffuse = color.sample(colorSampler, in.texcoord);
    return diffuse;
    //return float4(in.texcoord.x, in.texcoord.y, 0.0, 1.0);
}

// MARK: - Control Point Rendering
struct CPVertexInOut
{
    float4 position [[position]];
    float3 normal;
    half4 color;
};

struct CPVertex
{
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

vertex CPVertexInOut controlPointVertexShader(CPVertex in [[stage_in]],
                                              constant CPInstanceUniforms* instanceUniforms [[buffer(1)]],
                                              constant SharedUniforms& sharedUniforms [[buffer(2)]],
                                              uint id [[instance_id]])
{
    CPVertexInOut out;
    
    out.position = sharedUniforms.projection * sharedUniforms.viewMatrix * instanceUniforms[id].transform * float4(in.position, 1.0);
    out.normal = in.normal;
    
    if (instanceUniforms[id].highlight) {
        out.color = half4(235.0/255.0, 64.0/255.0, 52.0/255.0, 1.0);
    } else {
        out.color = half4(62.0/255.0, 156.0/255.0, 156.0/255.0, 1.0);
    }
    
    return out;
}

fragment half4 controlPointFragmentShader(CPVertexInOut in [[stage_in]])
{
    return in.color;
}
