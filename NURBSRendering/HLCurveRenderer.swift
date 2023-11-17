//
//  HLCurveRenderer.swift
//  NURBSRendering
//
//  Created by Reza on 11/7/23.
//

import Foundation
import SwiftUI
import MetalKit
import RenderTools
import Matrix
import Transform

let kAlignedAxisUniformsSize: Int = (MemoryLayout<AxisInstanceUniforms>.size & ~0xFF) + 0x100

let AxisVertices = Matf([-10.0, 0.0, 0.0, // white
                          0.0, 0.0, 0.0, // white
                          0.0, 0.0, 0.0, // red
                          10.0, 0.0, 0.0, // red
                          0.0, -10.0, 0.0, // white
                          0.0, 0.0, 0.0, // white
                          0.0, 0.0, 0.0, // green
                          0.0, 10.0, 0.0, // green
                          0.0, 0.0, -10.0, // white
                          0.0, 0.0, 0.0, // white
                          0.0, 0.0, 0.0, // blue
                          0.0, 0.0, 10.0], // blue
                        [12, 3])
let AxisColors = Matf([1.0, 1.0, 1.0,
                       1.0, 1.0, 1.0,
                       1.0, 0.0, 0.0,
                       1.0, 0.0, 0.0,
                       1.0, 1.0, 1.0,
                       1.0, 1.0, 1.0,
                       0.0, 1.0, 0.0,
                       0.0, 1.0, 0.0,
                       1.0, 1.0, 1.0,
                       1.0, 1.0, 1.0,
                       0.0, 0.0, 1.0,
                       0.0, 0.0, 1.0],
                      [12, 3])

struct HLCurveRenderer: NSViewRepresentable {
    @Binding var camera: Camera
    @Binding var geometries: [HLParametricGeometry]
    @Binding var bodies: [[SphereBody]]
    @Binding var wireframe: Bool
    @Binding var renderControlPoints: Bool
    @Binding var selectedControlPoints: [[Int]]
    @Binding var showAxes: Bool
    @Binding var snapToGrid: Bool
    @Binding var sessionConfig: Set<UXConfig>
    
    
    func makeNSView(context: Context) -> some NSView {
        let view = HMTKView()
        view.device = GPUDevice.shared
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.clearColor = MTLClearColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        context.coordinator.renderDestination = view
        context.coordinator.device = view.device
        context.coordinator.loadMetal()
        view.delegate = context.coordinator
        context.coordinator.view = view
        
        let panGestureRecognizer = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didPan(_:)))
        view.addGestureRecognizer(panGestureRecognizer)
        let tapGestureRecognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)
        
        return view
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        
    }
}

extension HLCurveRenderer {
    class Coordinator: NSObject {
        // MARK: - Properties
        var view: HMTKView!
        private let parent: HLCurveRenderer
        var renderDestination: RenderDestination!
        var device: MTLDevice!
        private let alignedInstanceUniformSize: Int = (MemoryLayout<CPInstanceUniforms>.size * kMaxControlPointCount & ~0xFF) + 0x100
        private var perspective: matrix_float4x4 = matrix_identity_float4x4
        private var inversePerspective: matrix_float4x4 = matrix_identity_float4x4
        private var commandQueue: MTLCommandQueue!
        private var depthState: MTLDepthStencilState!
        
        // Tessellation and post-tessellation
        private var tessellationState: MTLRenderPipelineState!
        private var computeFactors: MTLComputePipelineState!
        private var computePointProjectionState: MTLComputePipelineState!
        private var factorsBuffer: MTLBuffer!
        private var edgeFactor: Float = 64.0
        private var insideFactor: Float = 64.0
        
        // Curve Render MetalObjects
        private var curveRenderPipelineState: MTLRenderPipelineState!
        private var evaluateCurveState: MTLComputePipelineState!
        
        private var _inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
        private var inFlightIndex: Int = 0
        private var sharedUniformsBuffer: MTLBuffer!
        private var sharedUniformsBufferAddress: UnsafeMutableRawPointer!
        private var sharedUniformsBufferOffset: Int = 0
        
        // control point rendering objects
        private var controlPointRenderState: MTLRenderPipelineState!
        private var sphereMesh: MTKMesh!
        private var sphereInstanceUniforms: MTLBuffer!
        private var sphereInstanceUniformsOffset: Int = 0
        private var sphereInstanceUniformsAddress: UnsafeMutableRawPointer!
        
        // PanGesture
        private var initialPanLocation: CGPoint?
        
        // Rendering Axis
        private var axisRenderState: MTLRenderPipelineState!
        private var axisDepthState: MTLDepthStencilState!
        private var axisVertexBuffer: MTLBuffer!
        private var axisVertexColorBuffer: MTLBuffer!
        private var axisInstanceUniformsBuffer: MTLBuffer!
        private var axisInstanceUniformsBufferAddress: UnsafeMutableRawPointer!
        private var axisInstanceUniformsBufferOffset: Int = 0
        
        // MARK: - Initialization
        init(_ container: HLCurveRenderer) {
            parent = container
            super.init()
        }
        
        // MARK: - Methods
        func loadMetal() {
            let library = device.makeDefaultLibrary()!
            // post tessellation shaders
            let postTessellationVertexFunction = library.makeFunction(name: "vertexShader")!
            let postTessellationFragmentFunction = library.makeFunction(name: "fragmentShader")!
            let factorKernel = library.makeFunction(name: "computeFactors")!
            let projectPointsFunction = library.makeFunction(name: "projectPoints")!
            // curve shaders
            let evaluateCurveFunction = library.makeFunction(name: "evaluateCurve")!
            let curveVertexFunction = library.makeFunction(name: "curveVertexShader")!
            let curveFragmentFunction = library.makeFunction(name: "curveFragmentShader")!
            // control point render shaders
            let controlPointRenderVertexFunction = library.makeFunction(name: "controlPointVertexShader")!
            let controlPointRenderFragmentFunction = library.makeFunction(name: "controlPointFragmentShader")!
            // Axis shaders
            let axisVertexFunction = library.makeFunction(name: "axisVertexShader")!
            let axisFragmentFunction = library.makeFunction(name: "axisFragmentShader")!
            
            sharedUniformsBuffer = device.makeBuffer(length: kAlignedSharedUniformsSize * kMaxBuffersInFlight, options: .storageModeShared)
            commandQueue = device.makeCommandQueue()
            
            do {
                try evaluateCurveState = device.makeComputePipelineState(function: evaluateCurveFunction)
            } catch {
                print(error.localizedDescription)
            }
            
            let curveVertexDesc = MTLVertexDescriptor()
            curveVertexDesc.attributes[0].format = .float4
            curveVertexDesc.attributes[0].offset = 0
            curveVertexDesc.attributes[0].bufferIndex = 0
            curveVertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 4
            
            let curveRenderDesc = MTLRenderPipelineDescriptor()
            curveRenderDesc.vertexDescriptor = curveVertexDesc
            curveRenderDesc.vertexFunction = curveVertexFunction
            curveRenderDesc.fragmentFunction = curveFragmentFunction
            curveRenderDesc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            curveRenderDesc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            curveRenderDesc.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            
            do {
                try curveRenderPipelineState = device.makeRenderPipelineState(descriptor: curveRenderDesc)
            } catch {
                print(error.localizedDescription)
            }
            
            let allocator = MTKMeshBufferAllocator(device: device)
            let mesh = MDLMesh(sphereWithExtent: SIMD3<Float>(0.015, 0.015, 0.015),
                               segments: SIMD2<UInt32>(10, 10),
                               inwardNormals: false,
                               geometryType: .triangles, allocator: allocator)
            let controlRenderVertexDesc = MTLVertexDescriptor()
            controlRenderVertexDesc.attributes[0].format = .float3
            controlRenderVertexDesc.attributes[0].offset = 0
            controlRenderVertexDesc.attributes[0].bufferIndex = 0
            controlRenderVertexDesc.attributes[1].format = .float3
            controlRenderVertexDesc.attributes[1].offset = MemoryLayout<Float>.size * 3
            controlRenderVertexDesc.attributes[1].bufferIndex = 0
            controlRenderVertexDesc.layouts[0].stride = MemoryLayout<Float>.size * 6
            
            let modelVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(controlRenderVertexDesc)
            (modelVertexDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
            (modelVertexDescriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
            mesh.vertexDescriptor = modelVertexDescriptor
            
            do {
                try sphereMesh = MTKMesh(mesh: mesh, device: device)
            } catch {
                print(error.localizedDescription)
            }
            
            sphereInstanceUniforms = device.makeBuffer(length: alignedInstanceUniformSize * kMaxBuffersInFlight, options: .storageModeShared)
            
            let controlPointRenderStateDesc = MTLRenderPipelineDescriptor()
            controlPointRenderStateDesc.vertexFunction = controlPointRenderVertexFunction
            controlPointRenderStateDesc.fragmentFunction = controlPointRenderFragmentFunction
            controlPointRenderStateDesc.vertexDescriptor = controlRenderVertexDesc
            controlPointRenderStateDesc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            controlPointRenderStateDesc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            controlPointRenderStateDesc.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            
            do {
                controlPointRenderState = try device.makeRenderPipelineState(descriptor: controlPointRenderStateDesc)
            } catch {
                print(error.localizedDescription)
            }
            
            let depthStateDesc = MTLDepthStencilDescriptor()
            depthStateDesc.depthCompareFunction = .less
            depthStateDesc.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depthStateDesc)
            
            // Initialize tessellation objects
            var vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float4
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = PTBufferIndex.controlPoints.rawValue
            vertexDescriptor.attributes[1].format = .uint2
            vertexDescriptor.attributes[1].offset = 0
            vertexDescriptor.attributes[1].bufferIndex = PTBufferIndex.netSize.rawValue
            vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
            vertexDescriptor.layouts[1].stepFunction = .perPatch
            vertexDescriptor.layouts[1].stepRate = 1
            vertexDescriptor.layouts[1].stride = MemoryLayout<UInt32>.size * 2
            
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.maxTessellationFactor = 64
            pipelineDesc.isTessellationFactorScaleEnabled = false
            pipelineDesc.tessellationFactorFormat = .half
            pipelineDesc.vertexFunction = postTessellationVertexFunction
            pipelineDesc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            pipelineDesc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            pipelineDesc.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            pipelineDesc.fragmentFunction = postTessellationFragmentFunction
            pipelineDesc.tessellationControlPointIndexType = .none
            pipelineDesc.tessellationFactorStepFunction = .constant
            pipelineDesc.tessellationOutputWindingOrder = .counterClockwise
            pipelineDesc.tessellationPartitionMode = .fractionalEven
            pipelineDesc.vertexDescriptor = vertexDescriptor
            
            do {
                try computeFactors = device.makeComputePipelineState(function: factorKernel)
                try computePointProjectionState = device.makeComputePipelineState(function: projectPointsFunction)
                try tessellationState = device.makeRenderPipelineState(descriptor: pipelineDesc)
            } catch {
                print(error.localizedDescription)
            }
            
            factorsBuffer = device.makeBuffer(length: 256, options: .storageModePrivate)
            factorsBuffer.label = "Tessellation Factors"
            
            // Axis rendering
            vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float3
            vertexDescriptor.attributes[1].offset = 0
            vertexDescriptor.attributes[1].bufferIndex = 1
            vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 3
            vertexDescriptor.layouts[1].stride = MemoryLayout<Float>.size * 3
            
            let stateDesc = MTLRenderPipelineDescriptor()
            stateDesc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            stateDesc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            stateDesc.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            stateDesc.vertexDescriptor = vertexDescriptor
            stateDesc.vertexFunction = axisVertexFunction
            stateDesc.fragmentFunction = axisFragmentFunction
            
            do {
                try axisRenderState = device.makeRenderPipelineState(descriptor: stateDesc)
            } catch {
                print(error.localizedDescription)
            }
            
            let axisDepthDesc = MTLDepthStencilDescriptor()
            axisDepthDesc.depthCompareFunction = .always
            axisDepthDesc.isDepthWriteEnabled = false
            axisDepthState = device.makeDepthStencilState(descriptor: axisDepthDesc)
            
            axisVertexBuffer = device.makeBuffer(bytes: AxisVertices.valuesPtr.pointer,
                                                 length: MemoryLayout<Float>.size * AxisVertices.size.count,
                                                 options: .storageModeShared)
            axisVertexColorBuffer = device.makeBuffer(bytes: AxisColors.valuesPtr.pointer,
                                                      length: MemoryLayout<Float>.size * AxisColors.size.count,
                                                      options: .storageModeShared)
            axisInstanceUniformsBuffer = device.makeBuffer(length: kAlignedAxisUniformsSize * kMaxBuffersInFlight, options: .storageModeShared)
            
        }
        
        @objc
        func didPan(_ recognizer: NSPanGestureRecognizer) {
            let location: CGPoint = recognizer.location(in: recognizer.view)
            let relLocation: CGPoint = .init(x: location.x / recognizer.view!.bounds.width,
                                             y: 1.0 - location.y / recognizer.view!.bounds.height)
            switch recognizer.state {
            case .possible:
                initialPanLocation = nil
            case .began:
                // try to pick
                pickControlPoint(relPos: relLocation)
                initialPanLocation = location
            case .changed:
                // try moving contorl point
                var xTranslation = location.x - initialPanLocation!.x
                var yTranslation = location.y - initialPanLocation!.y
                xTranslation /= recognizer.view!.bounds.width
                yTranslation /= recognizer.view!.bounds.height
                moveControlPoints(xTranslation: Float(xTranslation),
                                  yTranslation: Float(-yTranslation))
                initialPanLocation = location
            case .ended:
                initialPanLocation = nil
            case .cancelled:
                initialPanLocation = nil
            case .failed:
                initialPanLocation = nil
            case .recognized:
                break
            }
        }
        
        private func refreshBodies(atObjectIndex index: Int) {
            parent.bodies[index] = parent.geometries[index].generateCollisionBodies()
        }
        
        @objc func didTap(_ recognizer: NSPanGestureRecognizer) {
            if parent.sessionConfig.contains(.pickKnot) {
                // pick knot
                if let activeObject = parent.geometries.firstIndex(where: {$0.selected == true}), let curve = parent.geometries[activeObject] as? HLRCurve {
                    curve.insertKnotAtCurrentIndicator()
                    curve.showKnotIndicator = false
                    refreshBodies(atObjectIndex: activeObject)
                }
                parent.sessionConfig.remove(.pickKnot)
            } else {
                let location: CGPoint = recognizer.location(in: recognizer.view)
                let relLocation: CGPoint = .init(x: location.x / recognizer.view!.bounds.width,
                                                 y: 1.0 - location.y / recognizer.view!.bounds.height)
                // try to pick
                pickControlPoint(relPos: relLocation)
            }
        }
        
        private func queryKnotInsertion(target: HLParametricGeometry) {
            switch target {
            case is HLRCurve:
                queryKnotInsertion(curve: target as! HLRCurve)
            case is HLRSurface:
                fatalError("To be implemented")
            default:
                break
            }
        }
        
        private func queryKnotInsertion(curve: HLRCurve) {
            // hit test against line segments
            if let pointerLocation = view.pointerLocation {
                let screenCoords: Point = [Float(pointerLocation.x), Float(pointerLocation.y)]
                var ray = Ray(normalizedScreenCoords: screenCoords,
                              inverseProjection: inversePerspective,
                              cameraTranslation: parent.camera.transform.translation,
                              cameraTransform: parent.camera.transform.matrix)
                // move ray to curve space
                ray = curve.transform.inverseTransformMatrix * ray
                
                // hit test against each leg of the curve
                let targetRays = curve.legs(controlPointSpacing: curve.p)
                for i in 0..<targetRays.count {
                    var t1: Float?
                    var t2: Float?
                    var intersection: RVec3f?
                    RayCast(rayOne: ray, rayTwo: targetRays[i], t1: &t1, t2: &t2, intersection: &intersection)
                    if let t2 = t2, t2.isLess(than: 1.0), !t2.isLess(than: 0.0) {
                        let p = curve.p
                        let ui = curve.knotVector[i + 1]
                        let uip = curve.knotVector[i + 1 + p]
                        curve.knotIndicator = ui + t2 * (uip - ui)
                    }
                }
            }
        }
        
        private func deselectAllControlPoints() {
            parent.selectedControlPoints = .init(repeating: [], count: parent.geometries.count)
        }
        
        private func pickControlPoint(relPos: CGPoint) {
            // raycast against bodies
            let ray = Ray(normalizedScreenCoords: [Float(relPos.x), Float(relPos.y)],
                          inverseProjection: inversePerspective,
                          cameraTranslation: parent.camera.transform.translation,
                          cameraTransform: parent.camera.transform.matrix)
            
            var minT: Float = .greatestFiniteMagnitude
            var minTIInndex: Int?
            var minTJIndex: Int?
            for i in 0..<parent.geometries.count {
                for j in 0..<parent.bodies[i].count {
                    if let t = RayCast(sphere: parent.bodies[i][j], ray: ray) {
                        if t < minT {
                            minTIInndex = i
                            minTJIndex = j
                            minT = t
                        }
                    }
                }
            }
            
            if let i = minTIInndex, let j = minTJIndex {
                if !parent.selectedControlPoints[i].contains(j) {
                    parent.selectedControlPoints[i].append(j)
                }
            } else {
                deselectAllControlPoints()
            }
        }
        
        private func moveControlPoints(xTranslation: Float, yTranslation: Float) {
            let cameraSpaceMoveDirection: SIMD4<Float> = [xTranslation, -yTranslation, 0.0, 0.0]
            let worldMoveDirection = parent.camera.transform.matrix * cameraSpaceMoveDirection
            
            for i in 0..<parent.selectedControlPoints.count {
                for j in parent.selectedControlPoints[i] {
                    // convert translation to local space
                    var localMoveDirection = parent.geometries[i].transform.inverseTransformMatrix * worldMoveDirection
                    localMoveDirection *= 3.0
                    var translation: RVec<Float> = .init([localMoveDirection.x, localMoveDirection.y, localMoveDirection.z, 0.0])
                    let domIdx: Int = translation.projectToLargestComponent()
                    
                    let row: MatrixRow = parent.geometries[i].controlPoints.row(j)
                    row += translation
                    if parent.snapToGrid {
                        let value: Float = row[domIdx]
                        row.values[row.indexFinder(domIdx)] = round(value * 80.0) / 80.0
                    }
                }
            }
        }
        
        private func updateBodies() {
            for i in 0..<parent.geometries.count {
                for j in 0..<(parent.geometries[i].controlPointCount) {
                    let row: MatrixRow<Float> = parent.geometries[i].controlPoints.row(j)
                    let pos: SIMD4<Float> = [row[0], row[1], row[2], 1.0]
                    let worldPos = parent.geometries[i].transform.matrix * pos
                    parent.bodies[i][j].update(position: worldPos.xyz)
                }
            }
        }
        
        private func updateDynamicBuffers() {
            inFlightIndex = (inFlightIndex + 1) % kMaxBuffersInFlight
            
            sphereInstanceUniformsOffset = alignedInstanceUniformSize * inFlightIndex
            sphereInstanceUniformsAddress = sphereInstanceUniforms.contents().advanced(by: sphereInstanceUniformsOffset)
            sharedUniformsBufferOffset = kAlignedSharedUniformsSize * inFlightIndex
            sharedUniformsBufferAddress = sharedUniformsBuffer.contents().advanced(by: sharedUniformsBufferOffset)
            axisInstanceUniformsBufferOffset = kAlignedAxisUniformsSize * inFlightIndex
            axisInstanceUniformsBufferAddress = axisInstanceUniformsBuffer.contents().advanced(by: axisInstanceUniformsBufferOffset)
            
            parent.geometries.forEach({$0.updateDynamicBuffers(inFlightIndex: inFlightIndex)})
        }
        
        private func updateAppState() {
            if parent.sessionConfig.contains(.pickKnot), let target = parent.geometries.first(where: {$0.selected}) {
                // hit test against selected geometry
                queryKnotInsertion(target: target)
            }
            
            sharedUniformsBufferAddress.assumingMemoryBound(to: SharedUniforms.self).pointee.projection = perspective
            sharedUniformsBufferAddress.assumingMemoryBound(to: SharedUniforms.self).pointee.surfaceTransform = matrix_identity_float4x4
            sharedUniformsBufferAddress.assumingMemoryBound(to: SharedUniforms.self).pointee.viewMatrix = parent.camera.viewMatrix
            axisInstanceUniformsBufferAddress.assumingMemoryBound(to: AxisInstanceUniforms.self).pointee.transform = matrix_identity_float4x4
            
            // Flip z to convert geometry from right hand to left hand
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            var t: Int = 0
            for i in 0..<parent.geometries.count {
                guard !parent.geometries[i].hidden else { continue }
                for j in 0..<parent.geometries[i].controlPoints.rows {
                    let position: Vec<Float> = parent.geometries[i].controlPoints.row(j)
                    let translation = Transform(translation: [position[0], position[1], position[2]])
                    var modelMatrix = simd_mul(translation.matrix, coordinateSpaceTransform)
                    modelMatrix = simd_mul(parent.geometries[i].transform.matrix, modelMatrix)
                    
                    // update control point rendering buffers
                    let ptr = sphereInstanceUniformsAddress.assumingMemoryBound(to: CPInstanceUniforms.self).advanced(by: t)
                    ptr.pointee.transform = modelMatrix
                    if parent.selectedControlPoints[i].contains(j) {
                        ptr.pointee.highlight = true
                    } else {
                        ptr.pointee.highlight = false
                    }
                    t += 1
                }
            }
            updateBodies()
            parent.geometries.forEach({ $0.updateState() })
        }
    }
}

extension HLCurveRenderer.Coordinator: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspectRatio = Float(size.width) / Float(size.height)
        perspective = matrix_perspective_left_hand(fovyRadians: .pi / 4.0, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100.0)
        inversePerspective = perspective.inverse
    }
    
    func draw(in view: MTKView) {
        let _ = _inFlightSemaphore.wait(timeout: .distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?._inFlightSemaphore.signal()
            }
            
            updateDynamicBuffers()
            updateAppState()
            
            let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            // project control points
            computeCommandEncoder.pushDebugGroup("Project Points")
            computeCommandEncoder.setComputePipelineState(computePointProjectionState)
            parent.geometries.forEach({$0.projectControlPoints(encoder: computeCommandEncoder)})
            
            // compute tessellation factors
            computeCommandEncoder.pushDebugGroup("Compute tessellation factors")
            computeCommandEncoder.setComputePipelineState(computeFactors)
            computeCommandEncoder.setBytes(&edgeFactor, length: MemoryLayout<Float>.size, index: 0)
            computeCommandEncoder.setBytes(&insideFactor, length: MemoryLayout<Float>.size, index: 1)
            computeCommandEncoder.setBuffer(factorsBuffer, offset: 0, index: 2)
            computeCommandEncoder.dispatchThreadgroups(.init(width: 1, height: 1, depth: 1), threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
            
            // evaluate curves
            computeCommandEncoder.label = "Compute command encoder"
            computeCommandEncoder.pushDebugGroup("Evaluate curve")
            computeCommandEncoder.setComputePipelineState(evaluateCurveState)
            for geometry in parent.geometries {
                guard !geometry.hidden else { continue }
                geometry.evaluateCurve(encoder: computeCommandEncoder)
            }
            computeCommandEncoder.popDebugGroup()
            computeCommandEncoder.endEncoding()
            
            if let renderPassDesc = view.currentRenderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                if parent.showAxes {
                    // render axis
                    renderEncoder.pushDebugGroup("Render Axis")
                    renderEncoder.setRenderPipelineState(axisRenderState)
                    renderEncoder.setDepthStencilState(axisDepthState)
                    renderEncoder.setVertexBuffer(axisVertexBuffer, offset: 0, index: 0)
                    renderEncoder.setVertexBuffer(axisVertexColorBuffer, offset: 0, index: 1)
                    renderEncoder.setVertexBuffer(axisInstanceUniformsBuffer, offset: axisInstanceUniformsBufferOffset, index: 2)
                    renderEncoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: 3)
                    renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 12)
                    renderEncoder.popDebugGroup()
                }
                
                renderEncoder.setDepthStencilState(depthState)
                
                if parent.renderControlPoints {
                    // render control points
                    let count: Int = parent.geometries.filter({!$0.hidden}).map({$0.controlPointCount}).reduce(0, +)
                    if count != 0 {
                        renderEncoder.pushDebugGroup("Control Point Rendering")
                        renderEncoder.setRenderPipelineState(controlPointRenderState)
                        renderEncoder.setVertexBuffer(sphereInstanceUniforms, offset: sphereInstanceUniformsOffset, index: 1)
                        renderEncoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: 2)
                        
                        for bufferIndex in 0..<sphereMesh.vertexBuffers.count {
                            let vertexBuffer = sphereMesh.vertexBuffers[bufferIndex]
                            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: bufferIndex)
                        }
                        
                        for submesh in sphereMesh.submeshes {
                            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                                indexCount: submesh.indexCount,
                                                                indexType: submesh.indexType,
                                                                indexBuffer: submesh.indexBuffer.buffer,
                                                                indexBufferOffset: submesh.indexBuffer.offset,
                                                                instanceCount: count)
                        }
                        
                        renderEncoder.popDebugGroup()
                    }
                }
                
                // Draw curves
                renderEncoder.pushDebugGroup("render curve")
                renderEncoder.setRenderPipelineState(curveRenderPipelineState)
                renderEncoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: 1)
                for geometry in parent.geometries {
                    guard !geometry.hidden else { continue }
                    geometry.draw(encoder: renderEncoder)
                }
                renderEncoder.popDebugGroup()
                
                // Draw surfaces
                renderEncoder.pushDebugGroup("Tessellate and Render")
                renderEncoder.setRenderPipelineState(tessellationState)
                renderEncoder.setFrontFacing(.clockwise)
                renderEncoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: PTBufferIndex.sharedUniforms.rawValue)
                if parent.wireframe {
                    renderEncoder.setTriangleFillMode(.lines)
                }
                renderEncoder.setTessellationFactorBuffer(factorsBuffer, offset: 0, instanceStride: 0)
                for geometry in parent.geometries {
                    guard !geometry.hidden else { continue }
                    geometry.drawPostTessellation(encoder: renderEncoder)
                }
                renderEncoder.popDebugGroup()
                
                renderEncoder.endEncoding()
            }
            
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            
            commandBuffer.commit()
        }
    }
}
