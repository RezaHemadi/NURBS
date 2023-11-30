//
//  HLCurve.swift
//  NURBSRendering
//
//  Created by Reza on 11/6/23.
//

import Foundation
import Matrix
import RenderTools

struct HLCurve {
    // MARK: - Properties
    /// control points in homogenuous form
    var controlPoints: Matf
    var knotVector: RVecf
    var n: Int { controlPoints.rows - 1 }
    var p: Int { (knotVector.array() == 0).count() - 1 }
    var canInsertKnot: Bool {
        for value in knotVector.values {
            if (value != 0.0 && value != 1.0) {
                return true
            }
        }
        return false
    }
    var parameterRange: ClosedRange<Float> {
        assert(knotVector.count != 0)
        let first = knotVector.valuesPtr.pointer[0]
        let last = knotVector.valuesPtr.pointer[knotVector.count - 1]
        
        return first...last
    }
    
    // MARK: - Initialization
    init(controlPoints: Matf, knotVector: RVecf) {
        self.controlPoints = controlPoints
        self.knotVector = knotVector
        
        assert(validateCurve())
    }
    
    init(withUniformSpacing spacing: Float, start: RVec3f, end: RVec3f, degree: Int) {
        let d: RVec3f = (end - start) / spacing
        let legs: Int = Int(ceil(d.norm() / (end - start).norm()))
        let translation: RVec3f = (end - start) / Float(legs)
        
        controlPoints = Matf(legs + 1, 4)
        for i in 0...legs {
            let p: RVec3f = start + (Float(i) * translation)
            controlPoints.row(i) <<== RVec4f(xyz: p, w: 1.0)
        }
        let knotCount: Int = legs + degree + 2
        knotVector = .init(knotCount)
        let m = knotCount - 1
        
        for i in 0...degree {
            knotVector[i] = 0.0
            knotVector[knotCount - 1 - i] = 1.0
        }
        
        let k: Int = (m + 1) - (2 * (degree + 1))
        let knotSpan: Float = 1.0 / Float(k + 1)
        for i in (degree + 1)...(m - degree - 1) {
            knotVector[i] = Float(i - degree) * knotSpan
        }
        
        assert(validateCurve())
    }
    
    init(circleWithCenter O: RVec3f, X: RVec3f, Y: RVec3f, radius: Float, startAngle: Float, endAngle: Float) {
        controlPoints = Matf()
        knotVector = RVecf()
        var n: Int = 0
        
        makeNurbsCircle(O: O, X: X, Y: Y, r: radius, ths: startAngle, the: endAngle, n: &n, U: &knotVector, Pw: &controlPoints)
        
        assert(validateCurve())
    }
    
    init(circleWithCenter O: RVec3f, X: RVec3f, Y: RVec3f, radius: Float) {
        let X = X.normalized() * radius
        let Y = Y.normalized() * radius
        let coef: Float = sqrt(2.0) / 2.0
        controlPoints = Matf(9, 4)
        controlPoints.row(0) <<== RVec4(xyz: O + X, w: 1.0)
        controlPoints.row(1) <<== RVec4(xyz: (O + X + Y) * coef, w: coef)
        controlPoints.row(2) <<== RVec4(xyz: O + Y, w: 1.0)
        controlPoints.row(3) <<== RVec4f(xyz: (O - X + Y) * coef, w: coef)
        controlPoints.row(4) <<== RVec4f(xyz: (O - X), w: 1.0)
        controlPoints.row(5) <<== RVec4f(xyz: (O - X - Y) * coef, w: coef)
        controlPoints.row(6) <<== RVec4f(xyz: (O - Y), w: 1.0)
        controlPoints.row(7) <<== RVec4f(xyz: (O + X - Y) * coef, w: coef)
        controlPoints.row(8) <<== RVec4f(xyz: (O + X), w: 1.0)
        
        knotVector = [0.0, 0.0, 0.0, Float(1.0/4.0), Float(1.0/4.0), Float(1.0/2.0), Float(1.0/2.0), Float(3.0/4.0), Float(3.0/4.0), 1.0, 1.0, 1.0]
        
        assert(validateCurve())
    }
    
    // MARK: - Methods
    func legs(controlPointSpacing s: Int) -> [Ray] {
        var rays: [Ray] = []
        for i in 0..<(controlPoints.rows - s) {
            let firstPointH: RVec4f = controlPoints.row(i)
            let firstPoint: RVec3f = (firstPointH / firstPointH[3]).xyz
            let secondPointH: RVec4f = controlPoints.row(i + s)
            let secondPoint: RVec3f = (secondPointH / secondPointH[3]).xyz
            let dir: RVec3f = secondPoint - firstPoint
            let origin: RVec3f = firstPoint
            
            rays.append(.init(origin: .init(origin), direction: .init(dir)))
        }
        return rays
    }
    
    mutating func insertKnot(at u: Float, multiplicity r: Int = 1) {
        assert(u.isLessThanOrEqualTo(1.0) && !u.isLess(than: 0.0))
        
        var newCtrlPts = Matf()
        var newKnotVec = RVecf()
        var newN: Int = 0
        
        let k = findSpan(n: n, p: p, u: u, knotVector: knotVector)
        let s = (knotVector.array() == u).count()
        curveKnotIns(np: n,
                     p: p, UP: knotVector, Pw: controlPoints, u: u, k: k, s: s, r: r, nq: &newN, UQ: &newKnotVec, Qw: &newCtrlPts)
        controlPoints = newCtrlPts
        knotVector = newKnotVec
        
    }
    
    // MARK: - Helper Methods
    private func validateCurve() -> Bool {
        let p: Int = (knotVector.array() == 0).count() - 1
        if  (knotVector.array() == 1).count() - 1 != p { return false }
        if (knotVector.count - 1 != controlPoints.rows + p) { return false }
        
        return true
    }
}
