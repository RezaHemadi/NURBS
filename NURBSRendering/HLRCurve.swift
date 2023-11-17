//
//  HLRCurve.swift
//  NURBSRendering
//
//  Created by Reza on 11/7/23.
//

import Foundation
import Metal
import Transform
import Matrix
import RenderTools

let kAlignedGeometryInstanceUniformsSize: Int = (MemoryLayout<GeometryInstanceUniforms>.size & ~0xFF) + 0x100

class HLRCurve: HLParametricGeometry {
    // MARK: - Properties
    private var curve: HLCurve
    override var controlPointCount: Int { curve.controlPoints.rows }
    override var controlPoints: Matf { curve.controlPoints }
    var canInsertKnot: Bool { curve.canInsertKnot }
    
    private var renderConfig: Int8 = 0x00000000
    var knotIndicator: Float = 0.5
    var p: Int { curve.p }
    var knotVector: RVecf { curve.knotVector }
    var showKnotIndicator: Bool = false {
        didSet {
            guard oldValue != showKnotIndicator else { return }
            
            if showKnotIndicator {
                renderConfig = renderConfig | (1<<0)
            } else {
                renderConfig = renderConfig & ~(1<<0)
            }
        }
    }
    
    // single buffers
    private var unitDomainBuffer: MTLBuffer!
    private var curveVertexBuffer: MTLBuffer!
    private var curveColorsBuffer: MTLBuffer!
    
    // dynamic ring buffers
    private var controlPointsBuffer: MTLBuffer
    private var controlPointsBufferAddress: UnsafeMutableRawPointer
    private var controlPointsBufferOffset: Int = 0
    private var knotVectorBuffer: MTLBuffer!
    private var knotVectorBufferAddress: UnsafeMutableRawPointer
    private var knotVectorBufferOffset: Int = 0
    private var instanceUniformsBuffer: MTLBuffer
    private var instanceUniformsAddress: UnsafeMutableRawPointer
    private var instanceUniformsOffset: Int = 0
    
    // MARK: - Initialization
    init(curve: HLCurve, device: MTLDevice, transform: Transform? = nil, name: String? = nil) {
        self.curve = curve
        controlPointsBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 4 * kMaxBuffersInFlight * kMaxControlPointCount,
                                                options: .storageModeShared)!
        controlPointsBufferAddress = controlPointsBuffer.contents()
        unitDomainBuffer = device.makeBuffer(bytes: Self.unitDomainPoints,
                                             length: MemoryLayout<Float>.size * Self.unitDomainPoints.count,
                                             options: .storageModeShared)
        let curveVertexBufferSize: Int = MemoryLayout<Float>.size * 4 * kUnitDomainPointCount
        curveVertexBuffer = device.makeBuffer(length: curveVertexBufferSize, options: .storageModePrivate)
        curveColorsBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 3 * kUnitDomainPointCount, options: .storageModePrivate)
        knotVectorBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * kMaxKnots * kMaxBuffersInFlight,
                                             options: .storageModeShared)
        knotVectorBufferAddress = knotVectorBuffer.contents()
        
        instanceUniformsBuffer = device.makeBuffer(length: kAlignedGeometryInstanceUniformsSize * kMaxBuffersInFlight, options: .storageModeShared)!
        instanceUniformsAddress = instanceUniformsBuffer.contents()
        
        super.init(name: name, type: .curve)
    }
    
    /// transform control points and return curve geometry
    func getCurve() -> HLCurve {
        let ctrlPts: Matf = .init(curve.controlPoints, curve.controlPoints.rows, curve.controlPoints.cols)
        let knotV: RVecf = .init(curve.knotVector, curve.knotVector.rows, curve.knotVector.cols)
        
        var points: [SIMD4<Float>] = []
        points.reserveCapacity(ctrlPts.rows)
        for i in 0..<ctrlPts.rows {
            let row: MatrixRow = ctrlPts.row(i)
            points.append(.init([row[0], row[1], row[2]], 1.0))
        }
        for i in 0..<points.count {
            points[i] = transform.matrix * points[i]
        }
        for i in 0..<ctrlPts.rows {
            ctrlPts.row(i) <<== RVec4f(xyz: [points[i].x, points[i].y, points[i].z], w: ctrlPts.row(i)[3])
        }
        
        return .init(controlPoints: ctrlPts, knotVector: knotV)
    }
    
    // MARK: Methods
    func legs(controlPointSpacing: Int) -> [Ray] {
        return curve.legs(controlPointSpacing: controlPointSpacing)
    }
    
    func insertKnotAtCurrentIndicator() {
        let u = knotIndicator
        curve.insertKnot(at: u)
    }
    /// called before rendering each frame
    override func updateState() {
        controlPointsBufferAddress.assumingMemoryBound(to: Float.self).update(from: curve.controlPoints.valuesPtr.pointer,
                                                                              count: curve.controlPoints.size.count)
        knotVectorBufferAddress.assumingMemoryBound(to: Float.self).update(from: curve.knotVector.valuesPtr.pointer,
                                                                           count: curve.knotVector.count)
        instanceUniformsAddress.assumingMemoryBound(to: GeometryInstanceUniforms.self).pointee.transform = transform.matrix
        instanceUniformsAddress.assumingMemoryBound(to: GeometryInstanceUniforms.self).pointee.uIndicator = knotIndicator
        instanceUniformsAddress.assumingMemoryBound(to: GeometryInstanceUniforms.self).pointee.config = renderConfig
    }
    
    /// called before updateState() beginning of each frame
    override func updateDynamicBuffers(inFlightIndex: Int) {
        controlPointsBufferOffset = MemoryLayout<Float>.size * 4 * kMaxControlPointCount * inFlightIndex
        controlPointsBufferAddress = controlPointsBuffer.contents().advanced(by: controlPointsBufferOffset)
        knotVectorBufferOffset = MemoryLayout<Float>.size * kMaxKnots * inFlightIndex
        knotVectorBufferAddress = knotVectorBuffer.contents().advanced(by: knotVectorBufferOffset)
        instanceUniformsOffset = kAlignedGeometryInstanceUniformsSize * inFlightIndex
        instanceUniformsAddress = instanceUniformsBuffer.contents().advanced(by: instanceUniformsOffset)
    }
    
    override func projectControlPoints(encoder: MTLComputeCommandEncoder) {
        encoder.setBuffer(controlPointsBuffer, offset: controlPointsBufferOffset, index: 0)
        encoder.setBuffer(instanceUniformsBuffer, offset: instanceUniformsOffset, index: 1)
        encoder.dispatchThreadgroups(.init(width: controlPointCount, height: 1, depth: 1), threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
    }
    
    override func evaluateCurve(encoder: MTLComputeCommandEncoder) {
        var cpCount: Int = curve.controlPoints.rows
        var knotCount: Int = curve.knotVector.count
        
        encoder.setBuffer(unitDomainBuffer, offset: 0, index: CEBufferIndex.parameter.rawValue)
        encoder.setBytes(&cpCount, length: MemoryLayout<Int>.size, index: CEBufferIndex.numberOfControlPoints.rawValue)
        encoder.setBuffer(curveVertexBuffer, offset: 0, index: CEBufferIndex.vertices.rawValue)
        encoder.setBuffer(curveColorsBuffer, offset: 0, index: CEBufferIndex.colors.rawValue)
        encoder.setBuffer(controlPointsBuffer, offset: controlPointsBufferOffset, index: CEBufferIndex.controlPoints.rawValue)
        encoder.setBuffer(knotVectorBuffer, offset: knotVectorBufferOffset, index: CEBufferIndex.knotVector.rawValue)
        encoder.setBuffer(instanceUniformsBuffer, offset: instanceUniformsOffset, index: CEBufferIndex.instanceUniforms.rawValue)
        encoder.setBytes(&knotCount, length: MemoryLayout<Int>.size, index: CEBufferIndex.knotVectorCount.rawValue)
        
        encoder.dispatchThreadgroups(.init(width: 10, height: 1, depth: 1), threadsPerThreadgroup: .init(width: 20, height: 1, depth: 1))
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(curveVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(curveColorsBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: kUnitDomainPointCount)
    }
}

extension HLRCurve {
    static let unitDomainPoints: [Float] = (0...kUnitDomainPointCount).map({ Float($0) * (Float(1.0) / Float(kUnitDomainPointCount))})
}
