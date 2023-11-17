//
//  HLNurbsSession.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import Foundation
import SwiftUI
import RenderTools

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
    
    func deleteObjectWithid(_ id: UUID) {
        removeGeometry(id)
    }
}
