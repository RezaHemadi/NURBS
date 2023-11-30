//
//  HLNurbsSession.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import Foundation
import SwiftUI
import RenderTools
import Matrix

enum UXConfig {
    case pickKnot
}

// Data Model
class HLNurbsSession: ObservableObject {
    // MARK: - Properties
    @Published var geometries: [HLParametricGeometry] = []
    @Published var wireframe: Bool = false
    @Published var showControlPoints: Bool = false
    @Published var showNewCurveView: Bool = false
    @Published var showNewSurfaceView: Bool = false
    @Published var showAxes: Bool = true
    @Published var snapToGrid: Bool = true
    @Published var bodies: [[SphereBody]] = []
    @Published var selectedControlPoints: [[Int]] = []
    @Published var selectedObject: Int?
    @Published var objectForAttributes: HLParametricGeometry
    
    @Published var sessionConfig: Set<UXConfig> = []
    
    // MARK: - Initialization
    init() {
        objectForAttributes = .init(name: nil, type: .curve)
    }
    
    // MARK: - Methods
    func addGeometry(_ geometry: HLParametricGeometry) {
        // deselect last object
        if selectedObject != nil {
            geometries[selectedObject!].selected = false
        }
        geometries.append(geometry)
        bodies.append(geometry.generateCollisionBodies())
        selectedControlPoints.append([])
        selectedObject = geometries.count - 1
        geometry.selected = true
        objectForAttributes = geometry
    }
    
    @discardableResult
    func removeGeometry(_ id: UUID) -> Bool {
        if let index = geometries.firstIndex(where: {$0.id == id}) {
            geometries.remove(at: index)
            bodies.remove(at: index)
            selectedControlPoints.remove(at: index)
            if geometries.count == 0 {
                selectedObject = nil
                objectForAttributes = .init(name: nil, type: .curve)
            } else {
                selectedObject = geometries.count - 1
                geometries[geometries.count - 1].selected = true
                objectForAttributes = geometries[geometries.count - 1]
            }
            return true
        }
        return false
    }
    
    func selectObject(_ object: HLParametricGeometry) {
        if let index = geometries.firstIndex(of: object) {
            if selectedObject != nil, selectedObject! == index {
                return
            } else {
                if let selectedIndex = selectedObject {
                    geometries[selectedIndex].selected = false
                }
                selectedObject = index
                geometries[index].selected = true
                objectForAttributes = geometries[index]
            }
        }
    }
    
    func insertKnot() {
        // show UI for picking knot
        if let targetIdx = selectedObject, geometries[targetIdx] is HLRCurve {
            if (geometries[targetIdx] as! HLRCurve).canInsertKnot {
                sessionConfig.insert(.pickKnot)
                (geometries[targetIdx] as! HLRCurve).showKnotIndicator = true
            }
        }
    }
    
    func newCurve() {
        withAnimation {
            showNewCurveView = true
        }
    }
    
    func newSurface() {
        withAnimation {
            showNewSurfaceView = true
        }
    }
    
    func dismissNewCurveView() {
        withAnimation {
            showNewCurveView = false
        }
    }
    
    func dismissNewSurfaceView() {
        withAnimation {
            showNewSurfaceView = false
        }
    }
    
    func createCurve(spacing: Float, degree: Int, name: String? = nil) {
        let curve = HLCurve(withUniformSpacing: spacing, start: [-1.0, 0.0, 0.0], end: [1.0, 0.0, 0.0], degree: degree)
        DispatchQueue.main.async { [weak self] in
            //self?.geometries.append(HLRCurve(curve: curve, device: GPUDevice.shared, name: name))
            self?.addGeometry(HLRCurve(curve: curve, device: GPUDevice.shared, name: name))
        }
    }
    
    func createCircularArc(radius: Float, startAngle: Float, endAngle: Float, name: String? = nil) {
        let circularArc = HLCurve(circleWithCenter: [0.0, 0.0, 0.0], X: [1.0, 0.0, 0.0], Y: [0.0, 1.0, 0.0], radius: radius, startAngle: startAngle, endAngle: endAngle)
        addGeometry(HLRCurve(curve: circularArc, device: GPUDevice.shared, name: name))
    }
    
    func createFullCircle(radius: Float, name: String? = nil) {
        let circle = HLCurve(circleWithCenter: [0.0, 0.0, 0.0], X: [1.0, 0.0, 0.0], Y: [0.0, 1.0, 0.0], radius: radius)
        addGeometry(HLRCurve(curve: circle, device: GPUDevice.shared, name: name))
    }
    
    func createGridSurface(width: Float, height: Float, widthSpacing: Float, heightSpacing: Float, widthDegree: Int, heightDegree: Int, name: String? = nil) {
        let surface = HLSurface.Grid(width: width, height: height, widthSpacing: widthSpacing, heightSpacing: heightSpacing, widthDegree: widthDegree, heightDegree: heightDegree)
        addGeometry(HLRSurface(surface: surface, device: GPUDevice.shared, name: name))
    }
    
    func createSurfaceByCombination(curveOne: HLRCurve, curveTwo: HLRCurve, name: String? = nil) {
        let c1 = curveOne.getCurve()
        let c2 = curveTwo.getCurve()
        let surface = HLSurface.Combine(uCurve: c1, vCurve: c2)
        addGeometry(HLRSurface(surface: surface, device: GPUDevice.shared, name: name))
    }
    
    func createSurfaceOfRevolution(curve: HLRCurve, axis: AxisOfRevolution, sweepAngle: Float, name: String? = nil) {
        let curve = curve.getCurve()
        let surface = HLSurface.SurfaceOfRecolution(S: [0.0, 0.0, 0.0], T: axis.vector, theta: sweepAngle, curve: curve)
        addGeometry(HLRSurface(surface: surface, device: GPUDevice.shared, name: name))
    }
    
    func createRuledSurface(firstCurve: HLRCurve, secondCurve: HLRCurve, name: String? = nil) {
        var c1 = firstCurve.getCurve()
        var c2 = secondCurve.getCurve()
        
        // make sure c1 and c2 are defined on the same parameter range
        assert(c1.parameterRange == c2.parameterRange)
        
        // set the degree to maximum of the degree of the two curves
        let p: Int = max(c1.p, c2.p)
        
        // elevate the degree of the first curve if it's not equal to p
        if (c1.p != p) {
            let t = p - c1.p
            var n: Int = .zero
            var U = RVecf()
            var Pw = Matf()
            degreeElevateCurve(n: c1.n, p: c1.p, U: c1.knotVector, Pw: c1.controlPoints, t: t, nh: &n, Uh: &U, Qw: &Pw)
            c1 = .init(controlPoints: Pw, knotVector: U)
        }
        
        // elevate the degree of the second curve if it's not equal to p
        if (c2.p != p) {
            let t = p - c2.p
            var n: Int = .zero
            var U = RVecf()
            var Pw = Matf()
            degreeElevateCurve(n: c2.n, p: c2.p, U: c2.knotVector, Pw: c2.controlPoints, t: t, nh: &n, Uh: &U, Qw: &Pw)
            c2 = .init(controlPoints: Pw, knotVector: U)
        }
        
        // Merge knot vectors of the two curves
        struct KnotInsertionDescriptor {
            /// value to place
            let u: Float
            /// number of times to insert
            let t: Int
        }
        
        var c2Insertions: [KnotInsertionDescriptor] = []
        // loop over knot vector of c1 to determine knots to be inserted in c2
        for i in 0..<c1.knotVector.count {
            let u = c1.knotVector[i]
            let t = (c1.knotVector.array() == u).count()
            
            guard !c2Insertions.contains(where: {$0.u == u}) else { continue }
            
            // determine if knot vector of c2 has this value
            var c2Count: Int = 0
            c2Count = (c2.knotVector.array() == u).count()
            
            let count: Int = t - c2Count
            if (count > 0) {
                c2Insertions.append(.init(u: u, t: count))
            }
        }
        
        var c1Insertions: [KnotInsertionDescriptor] = []
        // loop over knot vector of c2 to determine  knots to be inserted in c1
        for i in 0..<c2.knotVector.count {
            let u = c2.knotVector[i]
            let t = (c2.knotVector.array() == u).count()
            
            guard !c1Insertions.contains(where: {$0.u == u}) else { continue }
            
            // determine if knot vector of c1 has thisvalue
            var c1Count: Int = 0
            c1Count = (c1.knotVector.array() == u).count()
            
            let count: Int = t - c1Count
            if (count > 0) {
                c1Insertions.append(.init(u: u, t: t))
            }
        }
        
        // Insert knots in curve two
        for insertion in c2Insertions {
            c2.insertKnot(at: insertion.u,
                          multiplicity: insertion.t)
        }
        
        // Insert knots in curve one
        for insertion in c1Insertions {
            c1.insertKnot(at: insertion.u,
                          multiplicity: insertion.t)
        }
        
        // Construct ruled surface using c1 and c2
        let vKnotVector = RVecf([0.0, 0.0, 1.0, 1.0])
        let uKnotVector = c1.knotVector
        let netSize: NetSize = [2, UInt32(c1.controlPoints.rows)]
        let Pw = Matf(2 * c1.controlPoints.rows, 4)
        
        for i in 0..<c1.controlPoints.rows {
            Pw.row(i) <<== c1.controlPoints.row(i)
        }
        
        let offset: Int = c1.controlPoints.rows
        for i in 0..<c2.controlPoints.rows {
            Pw.row(i + offset) <<== c2.controlPoints.row(i)
        }
        
        let surface = HLSurface(controlPoints: Pw, uKnotVector: uKnotVector, vKnotVector: vKnotVector, netSize: netSize)
        print(netSize)
        addGeometry(HLRSurface(surface: surface, device: GPUDevice.shared, name: name))
    }
    
    func deleteObjectWithid(_ id: UUID) {
        removeGeometry(id)
    }
}
