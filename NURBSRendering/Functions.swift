//
//  Functions.swift
//  NURBSRendering
//
//  Created by Reza on 11/2/23.
//

import Foundation
import Matrix
import RenderTools

// Compute new curve from knot insertion
// inputs:
//  np: number of control points
//  p: degree of the curve
//  UP: knot vector before insertion
//  Pw: control points before insertion
//  u: new knot value
//  k: index of the knot span in which the new knot is inserted
//  s: multiplicity of the knot being inserted. (0 if new knot)
//  r: number of times to insert the knot
// outputs:
//  nq: number of new control points
//  UQ: new knot vector
//  Qw: new control points
func curveKnotIns(np: Int, p: Int, UP: RVec<Float>, Pw: Mat<Float>, u: Float, k: Int, s: Int, r: Int, nq: inout Int, UQ: inout RVec<Float>, Qw: inout Mat<Float>) {
    let mp: Int = np + p + 1
    nq = np + r
    UQ.resize(UP.count + r)
    Qw.resize(nq + 1, Pw.cols)
    
    let Rw: Mat<Float> = .init(p + 1, Pw.cols)
    
    // Load new knot vector
    for i in 0...k { UQ[i] = UP[i] }
    for i in 1...r { UQ[k + i] = u }
    for i in (k + 1)...mp { UQ[i + r] = UP[i] }
    
    // Save unaltered control points
    for i in 0...(k - p) { Qw.row(i) <<== Pw.row(i) }
    for i in (k - s)...np { Qw.row(i + r) <<== Pw.row(i) }
    for i in 0...(p - s) { Rw.row(i) <<== Pw.row(k - p + i) }
    
    // Insert the knot r times
    var L: Int = 0
    for j in 1...r {
        L = k - p + j
        for i in 0...(p - j - s) {
            let alpha: Float = (u - UP[L + i]) / (UP[i + k + 1] - UP[L + i])
            let leftTerm: RVec<Float> = alpha * Rw.row(i + 1)
            let rightTerm: RVec<Float> = (1.0 - alpha) * Rw.row(i)
            Rw.row(i) <<== leftTerm + rightTerm
        }
        Qw.row(L) <<== Rw.row(0)
        Qw.row(k + r - j - s) <<== Rw.row(p - j - s)
    }
    
    // Load remaining control points
    if (L + 1 < k - s) {
        for i in (L + 1)..<(k - s) {
            Qw.row(i) <<== Rw.row(i - L)
        }
    }
}

/// return the span index of a certain u in knot vector
/// n = m - p -1
/// m = knot vector count - 1
/// p = degree of segments
/// returns span index
func findSpan(n: Int, p: Int, u: Float, knotVector U: RVec<Float>) -> Int {
    if (u == U[n + 1]) { return n } // special case
    
    // Do binary search
    var low: Int = p
    var high: Int = n + 1
    var mid: Int = (low + high) / 2
    
    while (u < U[mid] || u >= U[mid + 1]) {
        if (u < U[mid]) {
            high = mid
        } else {
            low = mid
        }
        mid = (low + high) / 2
    }
    return mid
}

// Surface knot insertion
// input:
//  np: n of the existing control point net in u direction
//  p: degree of the existing surface in u direction
//  UP: knot vector in u direction
//  mp: n of the control point net in v direction
//  q: degree of the surface in v direction
//  VP: knot vector in v direction
//  Pw: control point net (p + 1) * (q + 1) size.
//  dir: either u or v direction
//  uv: u value if dir is u or v value if dir is v
//  k: insertion knot span index
//  s: multiplicity of the knot to be inserted in the existing knot vector
//  r: number of times to insert the knot
// output:
//  nq: n of patch in u direction
//  UQ: knot vector in the u direction
//  mq: n of patch in v direction i.e m
//  VQ: knot vector in the v direction
//  Qw: new control point net
func surfaceKnotIns(np: Int,
                    p: Int,
                    UP: RVec<Float>,
                    mp: Int,
                    q: Int,
                    VP: RVec<Float>,
                    Pw: Mat<Float>,
                    dir: QuadPatchDomainDirection,
                    uv: Float,
                    k: Int,
                    s: Int,
                    r: Int,
                    nq: inout Int,
                    UQ: inout RVec<Float>,
                    mq: inout Int,
                    VQ: inout RVec<Float>,
                    Qw: inout Mat<Float>) {
    switch dir {
    case .u:
        UQ.resize(UP.count + r)
        Qw.resize((np + r + 1) * (mp + 1), Pw.cols)
        let mu = np + p + 1
        nq = np + r
        mq = mp
        // load new knot vector
        for i in 0...k { UQ[i] = UP[i] }
        for i in 1...r { UQ[k + i] = uv }
        for i in (k + 1)...mu { UQ[i + r] = UP[i] }
        
        // copy v-vector into VQ
        VQ = .init(VP, VP.rows, VP.cols)
        var L: Int = 0
        var alpha = Mat<Float>(p - s + 1, r + 1)
        // Save the alphas
        for j in 1...r {
            L = k - p + j
            for i in 0...(p - j - s) {
                alpha[i, j] = (uv - UP[L + i]) / (UP[i + k + 1] - UP[L + i])
            }
        }
        for row in 0...mp {
            // save unaltered control points
            for i in 0...(k - p) {
                let qwIdx = (nq + 1) * row + i
                let pwIdx = (np + 1) * row + i
                Qw.row(qwIdx) <<== Pw.row(pwIdx)
            }
            for i in (k-s)...np {
                let qwIdx = (nq + 1) * row + (i + r)
                let pwIdx = (np + 1) * row + (i)
                Qw.row(qwIdx) <<== Pw.row(pwIdx)
            }
            // Load auxiliary control points
            var Rw: [RVec<Float>] = .init(repeating: .init(), count: p - s + 1)
            for i in 0...(p - s) {
                let pwIdx: Int = (np + 1) * row + (k - p + i)
                Rw[i] = Pw.row(pwIdx)
            }
            for j in 1...r {
                // insert knot r times
                L = k - p + j
                for i in 0...(p - j - s) {
                    Rw[i] = alpha[i, j] * Rw[i + 1] + (1.0 - alpha[i, j]) * Rw[i]
                }
                var qwIdx: Int = (nq + 1) * row + L
                Qw.row(qwIdx) <<== Rw[0]
                qwIdx = (nq + 1) * row + (k + r - j - s)
                Qw.row(qwIdx) <<== Rw[p - j - s]
            }
            // load remaining control points
            for i in (L + 1)..<(k - s) {
                let qwIdx: Int = (nq + 1) * row + i
                Qw.row(qwIdx) <<== Rw[i - L]
            }
        }
    case .v:
        VQ.resize(VP.count + r)
        Qw.resize((np + 1) * (mp + 1 + r), Pw.cols)
        let mv = mp + q + 1
        nq = np
        mq = mp + r
        // Load new knot vector
        for i in 0...k { VQ[i] = VP[i] }
        for i in 1...r { VQ[k + i] = uv }
        for i in (k + 1)...mv { VQ[i + r] = VP[i] }
        
        // copy u vector into UQ
        UQ = .init(UP, UP.rows, UP.cols)
        var L: Int = 0
        var alpha = Mat<Float>(q - s + 1, r + 1)
        // Save the alphas
        for j in 1...r {
            L = k - q + j
            for i in 0...(q - j - s) {
                alpha[i, j] = (uv - VP[L + i]) / (VP[i + k + 1] - VP[L + i])
            }
        }
        for col in 0...np {
            // save unaltered control points
            for i in 0...(k - q) {
                let qwIdx = (nq + 1) * i + col
                let pwIdx = (np + 1) * i + col
                Qw.row(qwIdx) <<== Pw.row(pwIdx)
            }
            for i in (k - s)...mp {
                let qwIdx = (nq + 1) * (i + r) + col
                let pwIdx = (np + 1) *  i + col
                Qw.row(qwIdx) <<== Pw.row(pwIdx)
            }
            // load auxiliary control points
            var Rw: [RVec<Float>] = .init(repeating: .init(), count: q - s + 1)
            for i in 0...(q - s) {
                let pwIdx: Int = (np + 1) * (k - q + i) + col
                Rw[i] = Pw.row(pwIdx)
            }
            for j in 1...r {
                // insert knot r times
                L = k - q + j
                for i in 0...(q - j - s) {
                    Rw[i] = alpha[i, j] * Rw[i + 1] + (1.0 - alpha[i, j]) * Rw[i]
                }
                var qwIdx: Int = (nq + 1) * L + col
                Qw.row(qwIdx) <<== Rw[0]
                qwIdx = (nq + 1) * (k + r - j - s) + col
                Qw.row(qwIdx) <<== Rw[q - j - s]
            }
            // Load remaining control points
            for i in (L + 1)..<(k - s) {
                let qwIdx: Int = (nq + 1) * i + col
                Qw.row(qwIdx) <<== Rw[i - L]
            }
        }
    }
}

// Create arbitrary NURBS circular arc
// input:
//  O: origin of the arc in 3D
//  X: x coordinate of the arc in 3D
//  Y: y coordinate of the arc in 3D
//  r: radius
//  ths: start angle (degrees)
//  the: end angle (degrees)
// output:
//  n: number of control points - 1
//  U: knot vector
//  Pw: control points net
func makeNurbsCircle(O: RVec3f,
                     X: RVec3f,
                     Y: RVec3f,
                     r: Float,
                     ths: Float,
                     the: Float,
                     n: inout Int,
                     U: inout RVecf,
                     Pw: inout Matf) {
    let angleConverter: Float = .pi / 180.0
    var the = the
    if (the < ths) { the += 360.0 }
    let theta = the - ths
    
    // get number of arcs
    var narcs: Int = 0
    if (theta <= 90.0) {
        narcs = 1
    } else {
        if (theta <= 180.0) {
            narcs = 2
        } else {
            if (theta <= 270.0) {
                narcs = 3
            } else {
                narcs = 4
            }
        }
    }
    
    let dtheta = theta / Float(narcs)
    n = 2 * narcs // n + 1 control points
    Pw.resize(n + 1, 4)
    let w1: Float = cosf((dtheta / 2.0) * angleConverter) // dtheta / 2.0 is base angle
    var P0: RVec3f = O + r * cosf(ths * angleConverter) * X + r * sinf(ths * angleConverter) * Y
    var T0: RVec3f = -sinf(ths * angleConverter) * X + cosf(ths * angleConverter) * Y // initialize start values
    Pw.row(0) <<== RVec4f(xyz: P0, w: 1.0)
    var index: Int = 0
    var angle: Float = ths
    // create narcs segments
    for i in 1...narcs {
        angle += dtheta
        let P2: RVec3f = O + r * cosf(angle * angleConverter) * X + r * sinf(angle * angleConverter) * Y
        //Pw.row(index + 2) <<== P2
        Pw.row(index + 2) <<== RVec4f(xyz: P2, w: 1.0)
        let T2: RVec3f = -sinf(angle * angleConverter) * X + cosf(angle * angleConverter) * Y
        let r1: Ray = .init(origin: .init(P0), direction: .init(T0))
        let r2: Ray = .init(origin: .init(P2), direction: .init(T2))
        var dummy1: Float?
        var dummy2: Float?
        var tempPoint: SIMD3<Float>?
        RayCast(rayOne: r1, rayTwo: r2, t1: &dummy1, t2: &dummy2, intersection: &tempPoint)
        assert(tempPoint != nil)
        let P1: RVec3f = .init([tempPoint!.x, tempPoint!.y, tempPoint!.z])
        //Pw.row(index + 1) <<== w1 * P1
        Pw.row(index + 1) <<== RVec4f(xyz: w1 * P1, w: w1)
        index += 2
        if i < narcs {
            P0 = P2
            T0 = T2
        }
    }
    // Load the knot vector
    let j: Int = 2 * narcs + 1
    U.resize(j + 3)
    
    for i in 0..<3 {
        U[i] = 0.0
        U[i + j] = 1.0
    }
    
    switch narcs {
    case 1:
        break
    case 2:
        U[3] = 0.5
        U[4] = 0.5
        break
    case 3:
        U[3] = Float(1.0/3.0)
        U[4] = Float(1.0/3.0)
        U[5] = Float(2.0/3.0)
        U[6] = Float(2.0/3.0)
        break
    case 4:
        U[3] = 0.25
        U[4] = 0.25
        U[5] = 0.5
        U[6] = 0.5
        U[7] = 0.75
        U[8] = 0.75
        break
    default:
        fatalError("undefined narcs value")
    }
}

// Create one Bezier conic arc
// input:
//  P0: first point on the arc
//  T0: tangent to the arc at P0
//  P2: second point on the arc
//  T2: tangent to the arc at P2
//  P:  a point on the arc
// output:
//  P1: new control point based on input
//  w1: weight of the new control point
func makeOneArc(P0: RVec3f,
                T0: RVec3f,
                P2: RVec3f,
                T2: RVec3f,
                P: RVec3f,
                P1: inout RVec3f!,
                w1: inout Float) {
    let V02: RVec3f = P2 - P0
    var dummy1: Float?
    var dummy2: Float?
    let i: Int = RayCast(rayOne: .init(origin: .init(P0), direction: .init(T0)),
                         rayTwo: .init(origin: .init(P2), direction: .init(T2)),
                         t1: &dummy1, t2: &dummy2,
                         intersection: &P1)
    if (i == 0) {
        // finite control point
        let V1P: RVec3f = P - P1
        var alf0: Float!
        var alf2: Float!
        var dummy: SIMD3<Float>?
        RayCast(rayOne: .init(origin: .init(P1), direction: .init(V1P)),
                rayTwo: .init(origin: .init(P0), direction: .init(V02)), t1: &alf0, t2: &alf2, intersection: &dummy)
        alf0 = abs(alf0)
        alf2 = abs(alf2)
        let a: Float = sqrtf(alf2/(1.0 - alf2))
        let u: Float = a / (1.0 + a)
        let num: Float = (1.0 - u) * (1.0 - u) * (P - P0).dot(P1 - P) + u * u * (P - P2).dot(P1 - P)
        let den: Float = 2.0 * u * (1.0 - u) * (P1 - P).dot(P1 - P)
        w1 = num / den
        return
    } else {
        // infinite control point, 180 degree arc
        w1 = 0.0
        var alf0: Float!
        var alf2: Float!
        var dummy: SIMD3<Float>?
        RayCast(rayOne: .init(origin: .init(P), direction: .init(T0)),
                rayTwo: .init(origin: .init(P0), direction: .init(V02)),
                t1: &alf0, t2: &alf2, intersection: &dummy)
        let a: Float = sqrt(alf2 / (1.0 - alf2))
        let u: Float = a / (1.0 + a)
        var b: Float = 2.0 * u * (1.0 - u)
        b = -alf0 * (1.0 - b) / b
        P1 = .init([T0.x * b, T0.y * b, T0.z * b])
        return
    }
}

func splitArc(P0: RVec3f,
              P1: RVec3f,
              w1: Float,
              P2: RVec3f,
              Q1: inout RVec3f,
              S: inout RVec3f,
              R1: inout RVec3f,
              wqr: inout Float) {
    if (w1 == 0.0) {
        // infinite control point
        Q1 = P0 + P1
        R1 = P2 + P1
        S = 0.5 * (Q1 + R1)
        wqr = sqrt(2) / 2.0
    } else {
        // general case
        Q1 = (P0 + w1 * P1) / (1 + w1)
        R1 = (w1 * P1 + P2) / (1 + w1)
        S = 0.5 * (Q1 + R1)
        wqr = sqrt((1.0 + w1) / 2)
    }
}

// Construct open conic arc in 3D
// input:
//  P0, T0, P2, T2, P
// output:
//  n, U, Pw
func makeOpenConic(P0: RVec3f, T0: RVec3f, P2: RVec3f, T2: RVec3f, P: RVec3f, n: inout Int, U: inout RVecf, Pw: inout Matf) {
    var w1: Float = 0.0
    var P1: RVec3f!
    makeOneArc(P0: P0, T0: T0, P2: P2, T2: T2, P: P, P1: &P1, w1: &w1)
    
    if (w1 <= -1.0) {
        // parabola or hyperbola
        fatalError("outside convex hull")
    }
    var nsegs: Int = 0
    if (w1 >= 1.0) {
        // classify type and number of segments
        nsegs = 1 // hyperbola or parabola, one segment
    } else {
        // ellispe, determine number of segments
        if (w1 > 0.0 && angle(P0, P1, P2).degress > 60.0) {
            nsegs = 1
        } else {
            if (w1 < 0.0 && angle(P0, P1, P2).degress > 90) {
                nsegs = 4
            } else {
                nsegs = 2
            }
        }
    }
    
    n = 2 * nsegs
    Pw.resize(n + 1, 4)
    let j = 2 * nsegs + 1
    U.resize(j + 3)
    for i in 0..<3 {
        // load end knots
        U[i] = 0.0
        U[i + j] = 1.0
    }
    // load end ctrl pts
    Pw.row(0) <<== RVec4f(xyz: P0, w: 1.0)
    Pw.row(n) <<== RVec4f(xyz: P2, w: 1.0)
    
    if (nsegs == 1) {
        Pw.row(1) <<== RVec4f(xyz: w1 * P1, w: w1)
        return
    }
    var Q1 = RVec3f()
    var S = RVec3f()
    var R1 = RVec3f()
    var wqr: Float = .zero
    splitArc(P0: P0, P1: P1, w1: w1, P2: P2, Q1: &Q1, S: &S, R1: &R1, wqr: &wqr)
    
    if (nsegs == 2) {
        Pw.row(2) <<== RVec4f(xyz: S, w: 1.0)
        Pw.row(1) <<== RVec4f(xyz: wqr * Q1, w: wqr)
        Pw.row(3) <<== RVec4f(xyz: wqr * R1, w: wqr)
        U[3] = 0.5
        U[4] = 0.5
        return
    }
    
    // nsegs == 4
    Pw.row(4) <<== RVec4f(xyz: S, w: 1.0)
    w1 = wqr
    var HQ1 = RVec3f()
    var HS = RVec3f()
    var HR1 = RVec3f()
    splitArc(P0: P0, P1: Q1, w1: w1, P2: S, Q1: &HQ1, S: &HS, R1: &HR1, wqr: &wqr)
    Pw.row(2) <<== RVec4f(xyz: HS, w: 1.0)
    Pw.row(1) <<== RVec4f(xyz: wqr * HQ1, w: wqr)
    Pw.row(3) <<== RVec4f(xyz: wqr * HR1, w: wqr)
    splitArc(P0: S, P1: R1, w1: w1, P2: P2, Q1: &HQ1, S: &HS, R1: &HR1, wqr: &wqr)
    Pw.row(6) <<== RVec4f(xyz: HS, w: 1.0)
    Pw.row(5) <<== RVec4f(xyz: wqr * HQ1, w: wqr)
    Pw.row(7) <<== RVec4f(xyz: wqr * HR1, w: wqr)
    
    // load remaining knots
    for i in 0..<2 {
        U[i + 3] = 0.25
        U[i + 5] = 0.5
        U[i + 7] = 0.75
    }
    return
}

// Create NURBS surface of revolution
// input:
//  S: origin of axis to make rovolution surface around
//  T: direction of axis to make revolution surface around
//  theta: angle of revolution around the axis ( in degrees )
//  m: number of control points - 1 of the generatrix curve
//  Pj: control points of the generatrix curve (must have 3 columns)
//  wj: weights of control points of generatrix curve
// output:
//  n: control points - 1 of the surface in u direction
//  U: knot vector of the surface in u direction
//  Pij: surface control points
//  wij: surface control points weights
func makeRevolvedSurf(S: RVec3f,
                      T: RVec3f,
                      theta: Float,
                      m: Int,
                      Pj: Matf,
                      wj: RVecf,
                      n: inout Int,
                      U: inout RVecf,
                      Pij: inout Matf,
                      wij: inout Matf) {
    let radianConverter: Float = .pi / 180.0
    var narcs: Int = 0
    if (theta <= 90.0) { narcs = 1; U.resize(6 + 2 * (narcs - 1)) }
    else {
        if (theta <= 180.0) {
            narcs = 2
            U.resize(6 + 2 * (narcs - 1))
            U[3] = 0.5
            U[4] = 0.5
        } else {
            if (theta <= 270) {
                narcs = 3
                U.resize(6 + 2 * (narcs - 1))
                U[3] = Float(1.0/3.0)
                U[4] = Float(1.0/3.0)
                U[5] = Float(2.0/3.0)
                U[6] = Float(2.0/3.0)
            } else {
                narcs = 4
                U.resize(6 + 2 * (narcs - 1))
                U[3] = 0.25
                U[4] = 0.25
                U[5] = 0.5
                U[6] = 0.5
                U[7] = 0.75
                U[8] = 0.75
            }
        }
    }
    
    let dtheta: Float = theta / Float(narcs)
    // load end knots
    var j: Int = 3 + 2 * (narcs - 1)
    for i in 0..<3 {
        U[i] = 0.0
        U[j] = 1.0
        j += 1
    }
    n = 2 * narcs
    Pij.resize((n + 1) * (m + 1), 3)
    wij.resize(m + 1, n + 1)
    let wm: Float = cosf(dtheta * radianConverter / 2.0) // dtheta / 2 is base angle
    var angle: Float = 0.0 // compute sines and cosines only once
    var cosines: [Float] = .init(repeating: 0.0, count: narcs + 1)
    var sines: [Float] = .init(repeating: 0.0, count: narcs + 1)
    for i in 1...narcs {
        angle = angle + dtheta
        cosines[i] = cosf(angle * radianConverter)
        sines[i] = sinf(angle * radianConverter)
    }
    for j in 0...m {
        // loop and compute each u row of ctrl pts and weights
        var O = RVec3f()
        projectPointOnLine(pointOnLine: S, lineTangent: T, pointToProject: Pj.row(j), projectedPoint: &O)
        var X: RVec3f = Pj.row(j) - O
        let r: Float = X.norm()
        X.normalize()
        let Y: RVec3f = T.cross(X)
        // Initialize first ctrl point and weight
        let pIdx: Int = (n + 1) * j + 0
        var P0: RVec3f = Pj.row(j)
        Pij.row(pIdx) <<== P0
        wij[j, 0] = wj[j]
        var T0: RVec3f = Y
        var index: Int = 0
        angle = 0.0
        
        for i in 1...narcs {
            // compute u row
            let P2: RVec3f = O + r * cosines[i] * X + r * sines[i] * Y
            var pIdx: Int = (n + 1) * j + (index + 2)
            Pij.row(pIdx) <<== P2
            wij[j, index + 2] = wj[j]
            let T2: RVec3f = -sines[i] * X + cosines[i] * Y
            var dummy1: Float?
            var dummy2: Float?
            var intersection: RVec3f?
            RayCast(rayOne: .init(origin: .init(P0), direction: .init(T0)),
                    rayTwo: .init(origin: .init(P2), direction: .init(T2)),
                    t1: &dummy1, t2: &dummy2,
                    intersection: &intersection)
            assert(intersection != nil)
            pIdx = (n + 1) * j + (index + 1)
            Pij.row(pIdx) <<== intersection!
            wij[j, index+1] = wm * wj[j]
            index += 2
            if (i < narcs) {
                P0 = P2
                T0 = T2
            }
        }
    }
}

// TODO: Test this function
// Refine curve knot vector
// input:
//  n: number of control points - 1
//  p: degree of curve
//  U: knot vector of the curve
//  Pw: control points
//  X: vector of knots to insert
// output:
//  Ubar: new knot vector
//  Qw: new control points
func refineKnotVectCurve(n: Int,
                         p: Int,
                         U: RVecf,
                         Pw: Matf,
                         X: RVecf,
                         Ubar: inout RVecf,
                         Qw: inout Matf) {
    let m = n + p + 1
    let a = findSpan(n: n, p: p, u: X[0], knotVector: U)
    let r = X.count - 1
    var b = findSpan(n: n, p: p, u: X[r], knotVector: U)
    b = b + 1
    for j in 0...(a - p) { Qw.row(j) <<== Pw.row(j) }
    for j in (b - 1)...n { Qw.row(j + r + 1) <<== Pw.row(j) }
    for j in 0...a { Ubar[j] = U[j] }
    for j in (b + p)...m { Ubar[j + r + 1] = U[j] }
    var i = b + p - 1
    var k = b + p + r
    for j in 0...r {
        let j = r - j
        while (X[j] <= U[i] && i > a) {
            Qw.row(k - p - 1) <<== Pw.row(i - p - 1)
            Ubar[k] = U[i]
            k = k - 1
            i = i - 1
        }
        Qw.row(k - p - 1) <<== Qw.row(k - p)
        for l in 1...p {
            let ind = k - p + 1
            var alpha = Ubar[k + l] - X[j]
            if (abs(alpha) == 0.0) {
                Qw.row(ind - 1) <<== Qw.row(ind)
            } else {
                alpha = alpha / (Ubar[k + l] - U[i - p + l])
                let temp1: RVecf = Qw.row(ind - l)
                let temp2: RVecf = Qw.row(ind)
                Qw.row(ind - l) <<== alpha * temp1 + (1.0 - alpha) * temp2
            }
        }
        Ubar[k] = X[j]
        k = k - 1
    }
}

// TODO: Test this function
// Remove knot u (index r) num times
// input:
//  n: number of control points - 1
//  p: degree of the curve
//  U: knot vector
//  Pw: control points
//  u: knot to be removed
//  r: index of the knot to be removed
//  s: multiplicity of the knot to be removed
//  num: number of times to remove knot u
// output:
//  t: the actual number of times knot u is removed
//  U: new knot vector
//  Pw: new control points
func removeCurveKnot(n: Int, p: Int, U: inout RVecf, Pw: inout Matf, u: Float, r: Int, s: Int, num: Int, t: inout Int) {
    // compute TOL
    let wmin: Float = Pw.col(3).minCoeff()
    var Pmax: Float = .zero
    for i in 0..<Pw.rows {
        var P: RVec4f = Pw.row(i)
        P = P / P[3]
        let norm = P.xyz.norm()
        if norm > Pmax {
            Pmax = norm
        }
    }
    let d: Float = 1.0e-1
    
    let TOL = (d * wmin) / (1.0 + Pmax)
    
    let m: Int = n + p + 1
    let ord: Int = p + 1
    let fout: Int = (2 * r - s - p) / 2 // first control point out
    var last: Int = r - s
    var first: Int = r - p
    
    var  off: Int = .zero
    var  temp = Matf(2 * p + 1, Pw.cols)
    var i: Int = 0
    var j: Int = 0
    var ii: Int = 0
    var jj: Int = 0
    var remflag: Int = 0
    for t in 0..<num {
        off = first - 1 // diff in index between temp and P
        temp.row(0) <<== Pw.row(off)
        temp.row(last + 1 - off) <<== Pw.row(last + 1)
        i = first
        j = last
        ii = 1
        jj = last - off
        remflag = 0
        var alfi: Float = .zero
        while (j - i > t) {
            // compute new control points for one removal step
            alfi = (u - U[i]) / (U[i + ord + t] - U[i])
            let alfj: Float = (u - U[j - t]) / (U[j + ord] - U[j - t])
            var numerator: RVec4 = (Pw.row(i) - (1.0 - alfi) * temp.row(ii - 1))
            temp.row(ii) <<== (numerator / alfi)
            numerator = (Pw.row(j) - alfj * temp.row(jj + 1))
            temp.row(jj) <<== numerator / (1.0 - alfj)
            i += 1
            ii += 1
            j -= 1
            jj -= 1
        }
        // check if knot is removable
        if (j - i < t) {
            let distance = (temp.row(ii - 1) - temp.row(jj + 1)).norm()
            if (distance <= TOL) {
                remflag = 1
            }
        } else {
            alfi = (u - U[i]) / (U[i + ord + t] - U[i])
            let leftTerm: RVec = Pw.row(i)
            let rightTerm: RVec = (alfi * temp.row(ii + t + 1) + (1.0 - alfi) * temp.row(ii - 1))
            let distance = (leftTerm - rightTerm).norm()
            if distance <= TOL {
                remflag = 1
            }
        }
        
        if (remflag == 0) {
            // cannot remove any more knots
            // get out of for-loop
            break
        } else {
            // successful removal. save new control points
            i = first
            j = last
            while (j - i > t) {
                Pw.row(i) <<== temp.row(i - off)
                Pw.row(j) <<== temp.row(j - off)
                i += 1
                j -= 1
            }
        }
        first -= 1
        last += 1
    } // end of for-loop
    
    if (t == 0) { return }
    
    for k in (r+1)...m {
        // shift knots
        U[k - t] = U[k]
    }
    // Pj through Pi will be overwritten
    j = fout
    i = j
    for k in 1..<t {
        if (k % 2 == 1) {
            i += 1
        } else {
            j -= 1
        }
    }
    for k in (i + 1)...n {
        // shift
        Pw.row(j) <<== Pw.row(k)
        j += 1
    }
    return
}

// TODO: test this function
// Degree elevate a curve t times.
// input:
//  n: number of control points - 1
//  p: degree of the curve
//  U: knot vector
//  Pw: control points
//  t: number of times to elevate the degree
// output:
//  nh: number of control points of the new curve
//  Uh: knot vector of new curve
//  Qw: new control points
func degreeElevateCurve(n: Int, p: Int, U: RVecf, Pw: Matf, t: Int, nh: inout Int, Uh: inout RVecf, Qw: inout Matf) {
    let m: Int = n + p + 1
    let ph: Int = p + t
    let ph2: Int = ph / 2
    // compute bezier degree elevation coefficients
    // coefficients for degree elevating the Bezier segments
    var bezalfs: [[Float]] = .init(repeating: .init(repeating: .zero, count: p + 1), count: p + t + 1)
    // pth-degree Bezier control points of the current segment
    let bpts = Matf(p + 1, Pw.cols)
    // (p + t)th-degree Bezier control points of the current segment
    let ebpts = Matf(p + t + 1, Pw.cols)
    // leftmost control points of the next Bezier segment
    let nextBpts = Matf(p - 1, Pw.cols)
    // knot insertion alphas
    var alphas: [Float] = .init(repeating: .zero, count: p - 1)
    bezalfs[ph][p] = 1.0
    bezalfs[0][0] = 1.0
    
    for i in 1...ph2 {
        let inv: Float = 1.0 / binomial(UInt(ph), UInt(i))
        let mpi: Int = min(p, i)
        
        let tmp: Int = max(0, i - t)
        for j in tmp...mpi {
            bezalfs[i][j] = inv * binomial(p, j) * binomial(t, i - j)
        }
    }
    if (ph2 + 1) <= (ph - 1) {
        for i in (ph2 + 1)...(ph - 1) {
            let mpi: Int = min(p, i)
            for j in max(0, i-t)...mpi {
                bezalfs[i][j] = bezalfs[ph - i][p - j]
            }
        }
    }
    
    var mh: Int = ph
    var kind: Int = ph + 1
    var r: Int = -1
    var a: Int = p
    var b: Int = p + 1
    var cind: Int = 1
    var ua: Float = U[0]
    Qw.resize(1, Pw.cols)
    Qw.row(0) <<== Pw.row(0)
    
    Uh.resize(ph + 1)
    for i in 0...ph { Uh[i] = ua }
    // Initialize first Bezier seg
    for i in 0...p { bpts.row(i) <<== Pw.row(i) }
    
    // Big loop through knot vector
    while (b < m) {
        let i: Int = b
        while (b < m && U[b] == U[b + 1]) { b += 1 }
        let mul: Int = b - i + 1
        mh = mh + mul + t
        let ub: Float = U[b]
        let oldr: Int = r
        r = p - mul
        // Insert knot u(b) r times
        var lbz: Int = .zero
        var rbz: Int = .zero
        if (oldr > 0) {
            lbz = (oldr + 2) / 2
        } else {
            lbz = 1
        }
        
        if (r > 0) {
            rbz = ph - (r + 1) / 2
        } else {
            rbz = ph
        }
        
        if (r > 0) {
            // Insert knot to get Bezier segment
            let numer: Float = ub - ua
            for k in stride(from: p, to: mul, by: -1) { alphas[k - mul - 1] = numer / (U[a + k] - ua) }
            for j in 1...r {
                let save: Int = r - j
                let s: Int = mul + j
                for k in stride(from: p, through: s, by: -1) {
                    bpts.row(k) <<== alphas[k - s] * bpts.row(k) + (1.0 - alphas[k - s]) * bpts.row(k - 1)
                }
                nextBpts.row(save) <<== bpts.row(p)
            }
        } // end of 'insert knot'
        
        for i in lbz...ph {
            // degree elevate Bezier
            // Only points lbz,...,ph are used below
            ebpts.row(i) <<== RVecf.Zero(Pw.cols)
            let mpi: Int = min(p, i)
            for j in max(0, i - t)...mpi {
                ebpts.row(i) <<== ebpts.row(i) + bezalfs[i][j] * bpts.row(j)
            }
        } // End of degree elevating Bezier
        if (oldr > 1) {
            // Must remove knot u = U[a] oldr times
            var first: Int = kind - 2
            var last: Int = kind
            let den: Float = ub - ua
            let bet: Float = (ub - Uh[kind - 1]) / den
            
            for tr in 1..<oldr {
                // Knot removal loop
                var i: Int = first
                var j: Int = last
                var kj: Int = j - kind + 1
                
                while(j - i > tr) { // loop and compute new control points for one removal step
                    if (i < cind) {
                        let alf: Float = (ub - Uh[i]) / (ua - Uh[i])
                        let leftTerm: RVecf = alf * Qw.row(i)
                        let rightTerm: RVecf = (1.0 - alf) * Qw.row(i - 1)
                        if (i >= Qw.rows) { Qw.conservativeResize(i + 1, Qw.cols) }
                        Qw.row(i) <<== leftTerm + rightTerm
                    }
                    if (j >= lbz) {
                        if (j - tr <= kind - ph + oldr) {
                            let gam: Float = (ub - Uh[j - tr]) / den
                            let leftTerm: RVecf = gam * ebpts.row(kj)
                            let rightTerm: RVecf = (1.0 - gam) * ebpts.row(kj + 1)
                            ebpts.row(kj) <<== leftTerm + rightTerm
                        } else {
                            let leftTerm: RVecf = bet * ebpts.row(kj)
                            let rightTerm: RVecf = (1.0 - bet) * ebpts.row(kj + 1)
                            ebpts.row(kj) <<== leftTerm + rightTerm
                        }
                    }
                    i += 1
                    j -= 1
                    kj -= 1
                }
                first -= 1
                last += 1
            }
        } // end of removing knot, u = U[a]
        
        if (a != p) { // load the knot ua
            for _ in 0..<(ph - oldr) {
                if kind >= Uh.count {
                    Uh.conservativeResize(kind + 1)
                }
                Uh[kind] = ua
                kind += 1
            }
        }
        
        for j in lbz...rbz {
            // Load control points into Qw
            if (cind >= Qw.rows) { Qw.conservativeResize(cind + 1, Qw.cols) }
            Qw.row(cind) <<== ebpts.row(j)
            cind += 1
        }
        if (b < m) {
            // set up for next pass thru loop
            for j in 0..<r { bpts.row(j) <<== nextBpts.row(j) }
            for j in r...p { bpts.row(j) <<== Pw.row(b - p + j) }
            a = b
            b += 1
            ua = ub
        } else {
            // end knot
            for i in 0...ph {
                if (kind + i >= Uh.count) {
                    Uh.conservativeResize(kind + i + 1)
                }
                Uh[kind + i] = ub
            }
        }
    } // end of while loop (b < m)
    nh = mh - ph - 1
}

// MARK: - Helper methods
private func binomial(_ n: UInt, _ k: UInt) -> Float {
    assert(n >= k)
    
    let numerator = factorial(n)
    let denominator = factorial(k) * factorial(n - k)
    
    return Float(numerator) / Float(denominator)
}

private func binomial(_ n: Int, _ k: Int) -> Float {
    assert(n >= k)
    
    let numerator = factorial(UInt(n))
    let denominator = factorial(UInt(k)) * factorial(UInt(n - k))
    
    return Float(numerator) / Float(denominator)
}

private func factorial(_ n: UInt) -> UInt {
    if (n == 0 || n == 1) { return 1 }
    
    return n * factorial(n - 1)
}
