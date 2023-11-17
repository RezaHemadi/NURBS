//
//  HLSurface.swift
//  NURBSRendering
//
//  Created by Reza on 11/7/23.
//

import Foundation
import Matrix
import Metal

struct HLSurface {
    // MARK: - Properties
    // Control Points fill in u direction (q + 1) * (p + 1)
    var controlPoints: Matf
    // knot vector in u direction
    var uKnotVector: RVecf
    // knot vector in v direction
    var vKnotVector: RVecf
    // two dimensional size of control point net
    var netSize: NetSize
    
    var p: Int {
        (uKnotVector.array() == 0.0).count() - 1
    }
    
    var q: Int {
        (vKnotVector.array() == 0.0).count() - 1
    }
}

extension HLSurface {
    static func Flat(width: Float, height: Float) -> Self {
        let ctrlPts = Matf(4, 4)
        ctrlPts.row(0) <<== [-width / 2.0, height / 2.0, 0.0, 1.0] // top left
        ctrlPts.row(1) <<== [width / 2.0, height / 2.0, 0.0, 1.0] // top right
        ctrlPts.row(2) <<== [-width / 2.0, -height / 2.0, 0.0, 1.0] // lower left
        ctrlPts.row(3) <<== [width / 2.0, -height / 2.0, 0.0, 1.0] // lower right
        
        let uKnots: RVecf = [0.0, 0.0, 1.0, 1.0]
        let vKnots: RVecf = [0.0, 0.0, 1.0, 1.0]
        
        let netSize = NetSize(m: 2, n: 2)
        
        return .init(controlPoints: ctrlPts, uKnotVector: uKnots, vKnotVector: vKnots, netSize: netSize)
    }
    
    static func Grid(width: Float, height: Float,
                     widthSpacing: Float, heightSpacing: Float,
                     widthDegree: Int, heightDegree: Int) -> Self {
        let uCurve = HLCurve(withUniformSpacing: widthSpacing,
                             start: [-width / 2.0, height / 2.0, 0.0],
                             end: [width / 2.0, height / 2.0, 0.0],
                             degree: widthDegree)
        let vCurve = HLCurve(withUniformSpacing: heightSpacing,
                             start: [-width / 2.0, height / 2.0, 0.0],
                             end: [-width / 2.0, -height / 2.0, 0.0],
                             degree: heightDegree)
        return Combine(uCurve: uCurve, vCurve: vCurve)
    }
    
    static func Combine(uCurve: HLCurve, vCurve: HLCurve) -> Self {
        var translations: [RVec4f] = .init(repeating: RVec4f(), count: vCurve.n)
        for i in 0..<vCurve.n {
            translations[i] = vCurve.controlPoints.row(i + 1) - vCurve.controlPoints.row(i)
            if i != 0 {
                translations[i] += translations[i - 1]
            }
        }
        
        let ctrlPtrs = Matf((uCurve.n + 1) * (vCurve.n + 1), 4)
        for i in 0..<uCurve.controlPoints.rows {
            ctrlPtrs.row(i) <<== uCurve.controlPoints.row(i)
        }
        for i in 1..<vCurve.controlPoints.rows {
            let startIdx = i * (uCurve.n + 1) // start index in ctrlPts rows
            for j in 0..<uCurve.controlPoints.rows {
                ctrlPtrs.row(startIdx + j) <<== uCurve.controlPoints.row(j) + translations[i - 1]
            }
        }
        return .init(controlPoints: ctrlPtrs, uKnotVector: uCurve.knotVector, vKnotVector: vCurve.knotVector, netSize: [UInt32(vCurve.n + 1), UInt32(uCurve.n + 1)])
    }
    
    static func SurfaceOfRecolution(S: RVec3f, T: RVec3f, theta: Float, curve: HLCurve) -> Self {
        let weights: RVecf = curve.controlPoints.col(3)
        let Pj: Matf = curve.controlPoints.block(0, 0, curve.controlPoints.rows, 3)
        var n: Int = 0
        var Pij = Matf()
        var wij = Matf()
        var U = RVecf()
        makeRevolvedSurf(S: S, T: T, theta: theta, m: curve.n, Pj: Pj, wj: weights, n: &n, U: &U, Pij: &Pij, wij: &wij)
        
        for i in 0..<Pij.rows {
            Pij.row(i) *= wij[i]
        }
        
        Pij.conservativeResize(Pij.rows, 4)
        for i in 0..<Pij.rows {
            Pij[i, 3] = wij[i]
        }
        
        return .init(controlPoints: Pij, uKnotVector: U, vKnotVector: curve.knotVector, netSize: [UInt32(curve.n + 1), UInt32(n + 1)])
    }
}
