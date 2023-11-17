//
//  HLRSurface.swift
//  NURBSRendering
//
//  Created by Reza on 11/7/23.
//

import Foundation
import Metal
import Matrix
import Transform

class HLRSurface: HLParametricGeometry {
    // MARK: - Properties
    override var controlPointCount: Int { surface.controlPoints.rows }
    override var controlPoints: Matf { surface.controlPoints }
    private var surface: HLSurface
    private var controlPointsBuffer: MTLBuffer
    private var controlPointsBufferAddress: UnsafeMutableRawPointer
    private var controlPointsBufferOffset: Int = 0
    private var netBuffer: MTLBuffer
    private var netBufferOffset: Int = 0
    private var netBufferAddress: UnsafeMutableRawPointer
    private var uKnotVectorBuffer: MTLBuffer
    private var uKnotVectorBufferAddress: UnsafeMutableRawPointer
    private var uKnotVectorBufferOffset: Int = 0
    private var vKnotVectorBuffer: MTLBuffer
    private var vKnotVectorBufferOffset: Int = 0
    private var vKnotVectorBufferAddress: UnsafeMutableRawPointer
    private var instanceUniformsBuffer: MTLBuffer
    private var instanceUniformsAddress: UnsafeMutableRawPointer
    private var instanceUniformsOffset: Int = 0
    private var netSize: NetSize { surface.netSize }
    private var uKnotVector: RVecf { surface.uKnotVector }
    private var vKnotVector: RVecf { surface.vKnotVector }
    
    // MARK: Initialization
    init(surface: HLSurface, device: MTLDevice, name: String? = nil) {
        self.surface = surface
        
        controlPointsBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 4 * kMaxBuffersInFlight * kMaxControlPointCount,
                                                options: .storageModeShared)!
        controlPointsBufferAddress = controlPointsBuffer.contents()
        
        netBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size * 2 * kMaxBuffersInFlight,
                                      options: .storageModeShared)!
        netBufferAddress = netBuffer.contents()
        uKnotVectorBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * kMaxKnots * kMaxBuffersInFlight,
                                              options: .storageModeShared)!
        uKnotVectorBufferAddress = uKnotVectorBuffer.contents()
        vKnotVectorBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * kMaxKnots * kMaxBuffersInFlight,
                                              options: .storageModeShared)!
        vKnotVectorBufferAddress = vKnotVectorBuffer.contents()
        
        instanceUniformsBuffer = device.makeBuffer(length: 256 * kMaxBuffersInFlight, options: .storageModeShared)!
        instanceUniformsAddress = instanceUniformsBuffer.contents()
        
        super.init(name: name, type: .surface)
    }
    
    // MARK: - Methods
    override func updateState() {
        controlPointsBufferAddress.assumingMemoryBound(to: Float.self).update(from: controlPoints.valuesPtr.pointer,
                                                                              count: controlPoints.size.count)
        netBufferAddress.assumingMemoryBound(to: UInt32.self).pointee = netSize.n
        netBufferAddress.assumingMemoryBound(to: UInt32.self).advanced(by: 1).pointee = netSize.m
        
        uKnotVectorBufferAddress.assumingMemoryBound(to: Float.self).update(from: uKnotVector.valuesPtr.pointer,
                                                                            count: uKnotVector.count)
        vKnotVectorBufferAddress.assumingMemoryBound(to: Float.self).update(from: vKnotVector.valuesPtr.pointer,
                                                                            count: vKnotVector.count)
        instanceUniformsAddress.assumingMemoryBound(to: GeometryInstanceUniforms.self).pointee.transform = transform.matrix
    }
    
    override func updateDynamicBuffers(inFlightIndex: Int) {
        controlPointsBufferOffset = MemoryLayout<Float>.size * 4 * kMaxControlPointCount * inFlightIndex
        controlPointsBufferAddress = controlPointsBuffer.contents().advanced(by: controlPointsBufferOffset)
        netBufferOffset = MemoryLayout<UInt32>.size * 2 * inFlightIndex
        netBufferAddress = netBuffer.contents().advanced(by: netBufferOffset)
        uKnotVectorBufferOffset = MemoryLayout<Float>.size * kMaxKnots * inFlightIndex
        uKnotVectorBufferAddress = uKnotVectorBuffer.contents().advanced(by: uKnotVectorBufferOffset)
        vKnotVectorBufferOffset = MemoryLayout<Float>.size * kMaxKnots * inFlightIndex
        vKnotVectorBufferAddress = vKnotVectorBuffer.contents().advanced(by: vKnotVectorBufferOffset)
        instanceUniformsOffset = 256 * inFlightIndex
        instanceUniformsAddress = instanceUniformsBuffer.contents().advanced(by: instanceUniformsOffset)
    }
    
    override func projectControlPoints(encoder: MTLComputeCommandEncoder) {
        // bind control points buffer
        encoder.setBuffer(controlPointsBuffer, offset: controlPointsBufferOffset, index: 0)
        encoder.setBuffer(instanceUniformsBuffer, offset: instanceUniformsOffset, index: 1)
        encoder.dispatchThreadgroups(.init(width: 1, height: 1, depth: 1), threadsPerThreadgroup: .init(width: controlPointCount, height: 1, depth: 1))
    }
    
    override func drawPostTessellation(encoder: MTLRenderCommandEncoder) {
        var uKnots: Int = uKnotVector.count
        var vKnots: Int = vKnotVector.count
        
        encoder.setVertexBuffer(controlPointsBuffer, offset: controlPointsBufferOffset, index: PTBufferIndex.controlPoints.rawValue)
        encoder.setVertexBuffer(netBuffer, offset: netBufferOffset, index: PTBufferIndex.netSize.rawValue)
        encoder.setVertexBuffer(uKnotVectorBuffer, offset: uKnotVectorBufferOffset, index: PTBufferIndex.uKnotVector.rawValue)
        encoder.setVertexBuffer(vKnotVectorBuffer, offset: vKnotVectorBufferOffset, index: PTBufferIndex.vKnotVector.rawValue)
        encoder.setVertexBytes(&uKnots, length: MemoryLayout<Int>.size, index: PTBufferIndex.uKnotCount.rawValue)
        encoder.setVertexBytes(&vKnots, length: MemoryLayout<Int>.size, index: PTBufferIndex.vKnotCount.rawValue)
        
        encoder.drawPatches(numberOfPatchControlPoints: 32,
                            patchStart: 0,
                            patchCount: 1,
                            patchIndexBuffer: nil,
                            patchIndexBufferOffset: 0,
                            instanceCount: 1,
                            baseInstance: 0)
    }
}
