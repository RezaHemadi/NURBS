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
    for i in (L + 1)..<(k - s) {
        Qw.row(i) <<== Rw.row(i - L)
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
