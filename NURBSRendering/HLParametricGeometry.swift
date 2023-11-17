//
//  HLParametricGeometry.swift
//  NURBSRendering
//
//  Created by Reza on 11/7/23.
//

import Foundation
import Metal
import Matrix
import Transform
import RenderTools

// Base class for renderable parametric geometries
class HLParametricGeometry: HLNObject {
    // MARK: - Properties
    var controlPointCount: Int { return 0 }
    var controlPoints: Matf { return .init() }
    @Published var transform: Transform = .init(transform: matrix_identity_float4x4)
    
    // MARK: - Methods
    func updateState() {}
    func updateDynamicBuffers(inFlightIndex: Int) {}
    func evaluateCurve(encoder: MTLComputeCommandEncoder) {}
    func draw(encoder: MTLRenderCommandEncoder) {}
    func projectControlPoints(encoder: MTLComputeCommandEncoder) {}
    func drawPostTessellation(encoder: MTLRenderCommandEncoder) {}
    
    func generateCollisionBodies() -> [SphereBody] {
        var output: [SphereBody] = []
        output.reserveCapacity(controlPointCount)
        for i in 0..<controlPoints.rows {
            let row: MatrixRow<Float> = controlPoints.row(i)
            let pos: SIMD3<Float> = [row[0], row[1], row[2]]
            let body = SphereBody(position: pos, radius: 0.03)
            output.append(body)
        }
        return output
    }
}
