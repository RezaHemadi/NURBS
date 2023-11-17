//
//  Renderer.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import Foundation
import MetalKit
import Matrix
import RenderTools
import Transform

let kMaxBuffersInFlight: Int = 3
let kMaxControlPointCount: Int = 32
let kUnitDomainPointCount: Int = 200
let kMaxKnots: Int = 32

let kAlignedSharedUniformsSize: Int = (MemoryLayout<SharedUniforms>.size & 0xFF) + 0x100

class Renderer: NSObject, ObservableObject {
    // MARK: - Properties
    let alignedInstanceUniformsSize: Int = (MemoryLayout<CPInstanceUniforms>.size * kMaxControlPointCount & ~0xFF) + 0x100
    var renderDestination: RenderDestination! {
        didSet { assert(renderDestination != nil); loadMetal() }
    }
    var perspective: matrix_float4x4 = matrix_identity_float4x4
    var inversePerspective: matrix_float4x4 = matrix_identity_float4x4
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    // Tessellation rendering
    var pipelineState: MTLRenderPipelineState!
    var computeState: MTLComputePipelineState!
    var computePointProjectionsState: MTLComputePipelineState!
    var controlPointsBuffer: MTLBuffer!
    var factorsBuffer: MTLBuffer!
    var netBuffer: MTLBuffer!
    var netBufferAddress: UnsafeMutableRawPointer!
    var netBufferOffset: Int = 0
    
    // Curve rendering
    private var curveRenderPipeline: MTLRenderPipelineState!
    private var unitDomainBuffer: MTLBuffer!
    private var evaluateCurveState: MTLComputePipelineState!
    private var curveVertexBuffer: MTLBuffer!
    
    private var _inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    private var inFlightIndex: Int = 0
    private var controlPointBufferAddress: UnsafeMutableRawPointer!
    private var controlPointBufferOffset: Int = 0
    private var controlPointCount: Int { Int(netSize.n * netSize.m) } /*{ controlPointPositions.rows }*/
    private var sharedUniformsBuffer: MTLBuffer!
    private var sharedUniformsBufferAddress: UnsafeMutableRawPointer!
    private var sharedUniformsBufferOffset: Int = 0
    
    // B-Spline buffers
    private var uKnotVectorBuffer: MTLBuffer!
    private var uKnotVectorBufferAddress: UnsafeMutableRawPointer!
    private var uKnotVectorBufferOffset: Int = 0
    private var vKnotVectorBuffer: MTLBuffer!
    private var vKnotVectorBufferOffset: Int = 0
    private var vKnotVectorBufferAddress: UnsafeMutableRawPointer!
    var uKnotVector: RVec<Float>
    var vKnotVector: RVec<Float>
    var uKnotVectorCount: Int { uKnotVector.count }
    var vKnotVectorCount: Int { vKnotVector.count }
    
    private var surfaceTransform: Transform = .init(translationX: 0.0, translationY: 0.0, translationZ: 0.0)
    @Published var camera: Camera = .init(transform: .init(translationX: 0.0, translationY: 0.0, translationZ: -5.0))
    
    @Published var edgeFactor: Float = 64
    @Published var insideFactor: Float = 64
    @Published var wireframe: Bool = false
    
    var controlPointPositions: Matf
    
    var weights: [Float]
    var focalLength: Float = 5.0
    var netSize: NetSize
    
    // Rendering Control Points
    var sphereMesh: MTKMesh!
    var sphereInstanceUniforms: MTLBuffer!
    var sphereInstanceUniformsOffset: Int = 0
    var sphereInstanceUniformsAddress: UnsafeMutableRawPointer!
    var controlPointRenderState: MTLRenderPipelineState!
    var renderDepthState: MTLDepthStencilState!
    
    // Moving control Points
    private var bodies: [SphereBody] = []
    @Published var selectedPoints: [Int] = []
    @Published var showControlPoints: Bool = true
    @Published var controlPointList: [ControlPointViewData] = []
    
    // MARK: - Initialization
    override init() {
        let curve = HLCurve(withUniformSpacing: 0.2, start: [-1.0, 0.0, 0.0], end: [1.0, 0.0, 0.0], degree: 3)
        uKnotVector = curve.knotVector
        controlPointPositions = curve.controlPoints
        weights = .init(repeating: 1.0, count: curve.n + 1)
        vKnotVector = .init()
        netSize = [UInt32(curve.n + 1), 1]
        
        super.init()
    }
    
    // MARK: - Methods
    func curveInsertKnot(at u: Float, count: Int = 1) {
        defer {
            weights = .init(repeating: 1.0, count: controlPointCount)
            initializeControlPointViewData()
            initializeBodies()
        }
        
        var nq: Int = 0
        var UQ: RVec<Float> = .init()
        var Qw: Mat<Float> = .init()
        let p = (uKnotVector.array() == 0).count() - 1
        let s = (uKnotVector.array() == u).count()
        let k = findSpan(n: controlPointCount - 1, p: p, u: u, knotVector: uKnotVector)
        
        curveKnotIns(np: controlPointCount - 1,
                     p: p,
                     UP: uKnotVector,
                     Pw: controlPointPositions,
                     u: u, k: k, s: s, r: count,
                     nq: &nq, UQ: &UQ, Qw: &Qw)
        
        controlPointPositions = Qw
        uKnotVector = UQ
    }
    
    func surfaceInsertKnot(at uv: Float, direction: QuadPatchDomainDirection, count: Int = 1) {
        defer {
            weights = .init(repeating: 1.0, count: controlPointCount)
            initializeControlPointViewData()
            initializeBodies()
        }
        
        let np = Int(netSize.n) - 1
        let p = (uKnotVector.array() == 0).count() - 1
        let mp = Int(netSize.m) - 1
        let q = (vKnotVector.array() == 0).count() - 1
        let s: Int = {
            if direction == .u {
                (uKnotVector.array() == uv).count()
            } else {
                (vKnotVector.array() == uv).count()
            }
        }()
        let k: Int = {
            if direction == .u {
                return findSpan(n: np, p: p, u: uv, knotVector: uKnotVector)
            } else {
                return findSpan(n: mp, p: q, u: uv, knotVector: vKnotVector)
            }
        }()
        
        var nq: Int = 0
        var UQ = RVec<Float>()
        var mq: Int = 0
        var VQ = RVec<Float>()
        var Qw = Mat<Float>()
        
        surfaceKnotIns(np: np, p: p, UP: uKnotVector, mp: mp, q: q, VP: vKnotVector,
                       Pw: controlPointPositions, dir: direction, uv: uv, k: k, s: s, r: count,
                       nq: &nq, UQ: &UQ, mq: &mq, VQ: &VQ, Qw: &Qw)
        
        //netSize = .init(n: UInt32(mq + 1), m: UInt32(nq + 1))
        netSize = .init(m: UInt32(nq + 1), n: UInt32(mq + 1))
        controlPointPositions = Qw
        uKnotVector = UQ
        vKnotVector = VQ
    }
    
    func topView() {
        let quat: simd_quatf = simd_quaternion(.pi / 2.0, [1.0, 0.0, 0.0])
        let rotTransform = Transform.init(transform: float4x4(quat)).matrix
        let newMatrix = rotTransform * Transform(translation: [0.0, 0.0, -focalLength]).matrix
        
        camera = .init(transform: .init(transform: newMatrix))
    }
    
    func leftView() {
        let quat: simd_quatf = simd_quaternion(.pi / 2, [0.0, 1.0, 0.0])
        let rotTransform = Transform.init(transform: float4x4(quat)).matrix
        let newMatrix = rotTransform * Transform(translation: [0.0, 0.0, -focalLength]).matrix
        
        camera = .init(transform: .init(transform: newMatrix))
    }
    
    func rightView() {
        let quat: simd_quatf = simd_quaternion(-.pi / 2, [0.0, 1.0, 0.0])
        let rotTransform = Transform.init(transform: float4x4(quat)).matrix
        let newMatrix = rotTransform * Transform(translation: [0.0, 0.0, -focalLength]).matrix
        
        camera = .init(transform: .init(transform: newMatrix))
    }
    
    func bottomView() {
        let quat: simd_quatf = simd_quaternion(-.pi / 2, [1.0, 0.0, 0.0])
        let rotTransform = Transform.init(transform: float4x4(quat)).matrix
        let newMatrix = rotTransform * Transform(translation: [0.0, 0.0, -focalLength]).matrix
        
        camera = .init(transform: .init(transform: newMatrix))
    }
    
    func alignCamera() {
        focalLength = 5.0
        
        let rot = simd_quatf(camera.transform.matrix)
        let angle = rot.angle
        let axis = rot.axis
        
        var newAxis: SIMD3<Float>?
        var newAngle: Float?
        
        if axis.y.isLess(than: 0.0) {
            switch angle {
            case 0..<(.pi / 4):
                // Align to front
                newAxis = SIMD3<Float>.init(x: 0.0, y: -1.0, z: 0.0)
                newAngle = 0.0
            case (.pi / 4)..<(3 * .pi / 2):
                // Align to right
                newAxis = SIMD3<Float>.init(x: 0.0, y: -1.0, z: 0.0)
                newAngle = .pi / 2
            case (3 * .pi / 4)...(.pi):
                // Align to back
                newAxis = SIMD3<Float>.init(x: 0.0, y: -1.0, z: 0.0)
                newAngle = .pi
            default:
                break
            }
        } else {
            switch angle {
            case 0..<(.pi / 4):
                // Align to front
                newAxis = SIMD3<Float>.init(x: 0.0, y: 1.0, z: 0.0)
                newAngle = 0.0
            case (.pi / 4)..<(3 * .pi / 4):
                // Align to left
                newAxis = SIMD3<Float>.init(x: 0.0, y: 1.0, z: 0.0)
                newAngle = .pi / 2
            case (3 * .pi / 4)..<(5 * .pi / 4):
                // Align to back
                newAxis = [0.0, 1.0, 0.0]
                newAngle = .pi
            case (5 * .pi / 4)..<(7 * .pi / 4):
                // Align to right:
                newAxis = SIMD3<Float>.init(x: 0.0, y: -1.0, z: 0.0)
                newAngle = .pi / 2
            case (7 * .pi / 4)...(2 * .pi):
                // Align to front
                newAxis = SIMD3<Float>.init(x: 0.0, y: 1.0, z: 0.0)
                newAngle = 0.0
            default:
                break
            }
        }
        
        if let newAxis = newAxis, let newAngle = newAngle {
            let quat = simd_quaternion(newAngle, newAxis)
            let rotTransform = Transform.init(transform: float4x4(quat)).matrix
            let newMatrix = rotTransform * Transform.init(translationX: 0.0,
                                                          translationY: 0.0,
                                                           translationZ: -focalLength).matrix
            
            camera = .init(transform: .init(transform: newMatrix))
        }
    }
    
    func pickControlPoint(screenRelPos: CGPoint) {
        // raycast against bodies
        let ray = Ray(normalizedScreenCoords: [Float(screenRelPos.x), Float(screenRelPos.y)],
                      inverseProjection: inversePerspective,
                      cameraTranslation: camera.transform.translation,
                      cameraTransform: camera.transform.matrix)
        var ts: [Float?] = .init(repeating: nil, count: bodies.count)
        
        for i in 0..<bodies.count {
            let t = RayCast(sphere: bodies[i], ray: ray)
            ts[i] = t
        }
        
        var minTIdx: Int? = nil
        for i in 0..<ts.count {
            if ts[i] != nil {
                guard ts[i]! >= 0.0 else { continue }
                
                if minTIdx == nil {
                    minTIdx = i
                } else {
                    if ts[i]! < ts[minTIdx!]! {
                        minTIdx = i
                    }
                }
            }
        }
        
        if minTIdx == nil {
            deSelectAllControlPoints()
            return
        }
        
        selectControlPoint(index: minTIdx!)
    }
    
    func moveControlPoints(xTranslation: Float, yTranslation: Float) {
        guard !selectedPoints.isEmpty else { return }
        
        let cameraSpaceMoveDirection: SIMD4<Float> = [xTranslation, -yTranslation, 0.0, 0.0]
        var worldMoveDirection = camera.transform.matrix * cameraSpaceMoveDirection
        worldMoveDirection *= 1.0
        
        let translation: RVec<Float> = .init([worldMoveDirection.x, worldMoveDirection.y, worldMoveDirection.z, 0.0])
        
        for cpIdx in selectedPoints {
            controlPointPositions.row(cpIdx) += translation
            controlPointList[cpIdx].refresh()
        }
    }
    
    private func deSelectAllControlPoints() {
        selectedPoints.removeAll()
    }
    
    private func selectControlPoint(index: Int) {
        if selectedPoints.contains(index) { return }
        
        selectedPoints.append(index)
    }
    
    func rotateSceneCamera(xNormalizedTranslation: Float, yNormalizedTranslation: Float) {
        DispatchQueue.main.async { [weak self] in
            let localFocalPointV: SIMD4<Float> = [0.0, 0.0, self!.focalLength, 1.0]
            let focalPointWorldV = self!.camera.transform.matrix * localFocalPointV
            
            
            // get vector from focal point pointing to camera
            let vector = self!.camera.transform.translation - focalPointWorldV.xyz
            
            let camUpV: SIMD4<Float> = [0.0, 1.0, 0.0, 0.0]
            let camUpWorldV = self!.camera.transform.matrix * camUpV
            let camRightV: SIMD4<Float> = [1.0, 0.0, 0.0, 0.0]
            let camRightWorldV = self!.camera.transform.matrix * camRightV
            let yRot = simd_quaternion((yNormalizedTranslation / 8.0) / 2.0 * .pi, normalize(camRightWorldV.xyz))
            let xRot = simd_quaternion((xNormalizedTranslation / 8.0) / 2.0 * .pi, normalize(camUpWorldV.xyz))
            let totalRot = xRot * yRot
            let rotMatrix = float4x4(totalRot)
            
            let rotatedV = rotMatrix * SIMD4<Float>.init(vector, 0.0)
            let sceneUpV: SIMD3<Float> = [0.0, 1.0, 0.0]
            let dot = dot(normalize(rotatedV.xyz), sceneUpV)
            guard abs(dot).isLess(than: 0.99) else { return }
            
            let camPos = focalPointWorldV.xyz + rotatedV.xyz
            
            self!.camera.transform = .init(translation: camPos)
            self!.camera.lookAt(.init(translation: focalPointWorldV.xyz))
        }
    }
    
    func panSceneCamera(xNormalizedTranslation: Float, yNormalizedTranslation: Float) {
        DispatchQueue.main.async { [weak self] in
            let localPanDirection: SIMD4<Float> = [xNormalizedTranslation, -yNormalizedTranslation, 0.0, 0.0]
            let worldPanDirection = self!.camera.transform.matrix * localPanDirection
            
            let worldPanDirectionScaled = worldPanDirection * 0.2
            let translationMatrix = Transform(translation: worldPanDirectionScaled.xyz)
            self!.camera.transform = translationMatrix * self!.camera.transform
        }
    }
    
    func zoomCamera(length: Float = 0.2) {
        focalLength -= length
        DispatchQueue.main.async { [weak self] in
            let front: SIMD4<Float> = [0.0, 0.0, length, 0.0]
            let worldFront = self!.camera.transform.matrix * front
            
            let translationMatrix = Transform(translation: worldFront.xyz)
            self!.camera.transform = translationMatrix * self!.camera.transform
        }
    }
    
    func zoomOutCamera(length: Float = 0.2) {
        focalLength += length
        DispatchQueue.main.async { [weak self] in
            let front: SIMD4<Float> = [0.0, 0.0, -length, 0.0]
            let worldFront = self!.camera.transform.matrix * front
            
            let translationMatrix = Transform(translation: worldFront.xyz)
            self!.camera.transform = translationMatrix * self!.camera.transform
        }
    }
    
    func loadMetal() {
        assert(controlPointCount <= kMaxControlPointCount)
        
        let library = device.makeDefaultLibrary()!
        let postTessellationVertexFunction = library.makeFunction(name: "vertexShader")!
        let fragmentFunction = library.makeFunction(name: "fragmentShader")!
        let factorKernel = library.makeFunction(name: "computeFactors")!
        let projectPointsFunction = library.makeFunction(name: "projectPoints")!
        let evaluateCurveFunction = library.makeFunction(name: "evaluateCurve")!
        let curveVertexFunction = library.makeFunction(name: "curveVertexShader")!
        let curveFragmentFunction = library.makeFunction(name: "curveFragmentShader")!
        let controlPointRenderVertexFunction = library.makeFunction(name: "controlPointVertexShader")!
        let controlPointRenderFragmentFunction = library.makeFunction(name: "controlPointFragmentShader")!
        
        // Initialize compute state
        do {
            try computeState = device.makeComputePipelineState(function: factorKernel)
        } catch {
            print(error.localizedDescription)
        }
        
        do {
            try computePointProjectionsState = device.makeComputePipelineState(function: projectPointsFunction)
        } catch {
            print(error.localizedDescription)
        }
        
        // configure vertex descriptor for control points
        let vertexDescriptor = MTLVertexDescriptor()
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
        
        // configure render pipeline state descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.maxTessellationFactor = 64
        pipelineDescriptor.isTessellationFactorScaleEnabled = false
        pipelineDescriptor.tessellationFactorFormat = .half
        pipelineDescriptor.vertexFunction = postTessellationVertexFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.tessellationControlPointIndexType = .none
        pipelineDescriptor.tessellationFactorStepFunction = .constant
        pipelineDescriptor.tessellationOutputWindingOrder = .counterClockwise
        pipelineDescriptor.tessellationPartitionMode = .fractionalEven
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print(error.localizedDescription)
        }
        
        // configure buffers
        // Allocate memory for the tessellation factors buffer
        // This is a private buffer whose contents are later populated by the GPU (compute kernel)
        factorsBuffer = device.makeBuffer(length: 256, options: .storageModePrivate)
        factorsBuffer.label = "Tessellation Factors"
        
        controlPointsBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 4 * kMaxBuffersInFlight * kMaxControlPointCount,
                                                options: .storageModeShared)
        
        sharedUniformsBuffer = device.makeBuffer(length: kAlignedSharedUniformsSize * kMaxBuffersInFlight, options: .storageModeShared)
        
        commandQueue = device.makeCommandQueue()
        
        let unitDomainPoints: [Float] = (0...kUnitDomainPointCount).map({ Float($0) * (Float(1.0) / Float(kUnitDomainPointCount))})
        unitDomainBuffer = device.makeBuffer(bytes: unitDomainPoints,
                                             length: MemoryLayout<Float>.size * unitDomainPoints.count,
                                             options: .storageModeShared)
        do {
            try evaluateCurveState = device.makeComputePipelineState(function: evaluateCurveFunction)
        } catch {
            print(error.localizedDescription)
        }
        
        let curveVertexBufferSize: Int = MemoryLayout<Float>.size * 4 * kUnitDomainPointCount
        curveVertexBuffer = device.makeBuffer(length: curveVertexBufferSize, options: .storageModePrivate)
        
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
            try curveRenderPipeline = device.makeRenderPipelineState(descriptor: curveRenderDesc)
        } catch {
            print(error.localizedDescription)
        }
        
        netBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size * 2 * kMaxBuffersInFlight, options: .storageModeShared)
        
        uKnotVectorBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * kMaxKnots * kMaxBuffersInFlight,
                                             options: .storageModeShared)
        vKnotVectorBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * kMaxKnots * kMaxBuffersInFlight,
                                              options: .storageModeShared)
        
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
        
        sphereInstanceUniforms = device.makeBuffer(length: alignedInstanceUniformsSize * kMaxBuffersInFlight, options: .storageModeShared)
        
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
        
        let controlPointRenderDepthStateDesc = MTLDepthStencilDescriptor()
        controlPointRenderDepthStateDesc.depthCompareFunction = .less
        controlPointRenderDepthStateDesc.isDepthWriteEnabled = true
        renderDepthState = device.makeDepthStencilState(descriptor: controlPointRenderDepthStateDesc)
        
        initializeBodies()
        initializeControlPointViewData()
    }
    
    private func initializeBodies() {
        bodies.removeAll()
        bodies.reserveCapacity(controlPointCount)
        
        for i in 0..<controlPointCount {
            let row: MatrixRow<Float> = controlPointPositions.row(i)
            let pos: SIMD3<Float> = [row[0], row[1], row[2]]
            let body = SphereBody(position: pos, radius: 0.03)
            bodies.append(body)
        }
    }
    
    private func initializeControlPointViewData() {
        DispatchQueue.main.async { [weak self] in
            self!.controlPointList.removeAll()
            for i in 0..<self!.controlPointPositions.rows {
                self!.controlPointList.append(.init(id: i, row: self!.controlPointPositions.row(i), weight: &self!.weights[i]))
            }
        }
    }
    
    private func updateBodies() {
        assert(bodies.count == controlPointPositions.rows)
        
        for i in 0..<controlPointCount {
            let row: MatrixRow<Float> = controlPointPositions.row(i)
            let pos: SIMD3<Float> = [row[0], row[1], row[2]]
            bodies[i].update(position: pos)
        }
    }
    
    private func updateAppState() {
        /*
        let weightedControlPoints: Mat<Float> = .init(controlPointPositions, controlPointPositions.rows, controlPointPositions.cols)
        for i in 0..<weightedControlPoints.rows {
            weightedControlPoints.row(i) *= weights[i]
        }*/
        
        controlPointBufferAddress.assumingMemoryBound(to: Float.self).update(from: controlPointPositions.valuesPtr.pointer,
                                                                             count: controlPointPositions.size.count)
        sharedUniformsBufferAddress.assumingMemoryBound(to: SharedUniforms.self).pointee.projection = perspective
        sharedUniformsBufferAddress.assumingMemoryBound(to: SharedUniforms.self).pointee.surfaceTransform = surfaceTransform.matrix
        sharedUniformsBufferAddress.assumingMemoryBound(to: SharedUniforms.self).pointee.viewMatrix = camera.viewMatrix
        
        // assign net n degree
        netBufferAddress.assumingMemoryBound(to: UInt32.self).pointee = netSize.n
        // assign net m degree
        netBufferAddress.assumingMemoryBound(to: UInt32.self).advanced(by: 1).pointee = netSize.m
        
        // assign knot vector to dynamic buffer
        uKnotVectorBufferAddress.assumingMemoryBound(to: Float.self).update(from: uKnotVector.valuesPtr.pointer,
                                                                           count: uKnotVector.count)
        vKnotVectorBufferAddress.assumingMemoryBound(to: Float.self).update(from: vKnotVector.valuesPtr.pointer,
                                                                            count: vKnotVector.count)
        
        // Flip z to convert geometry from right hand to left hand
        var coordinateSpaceTransform = matrix_identity_float4x4
        coordinateSpaceTransform.columns.2.z = -1.0
        
        for i in 0..<controlPointCount {
            let position: Vec<Float> = controlPointPositions.row(i)
            let translation = Transform(translation: [position[0], position[1], position[2]])
            var modelMatrix = simd_mul(translation.matrix, coordinateSpaceTransform)
            modelMatrix = simd_mul(surfaceTransform.matrix, modelMatrix)
            
            // update control point rendering buffers
            let ptr = sphereInstanceUniformsAddress.assumingMemoryBound(to: CPInstanceUniforms.self).advanced(by: i)
            ptr.pointee.transform = modelMatrix
            
            // highlight selected points
            if selectedPoints.contains(i) {
                ptr.pointee.highlight = true
            } else {
                ptr.pointee.highlight = false
            }
        }
        
        updateBodies()
    }
    
    private func updateDynamicBuffers() {
        inFlightIndex = (inFlightIndex + 1) % kMaxBuffersInFlight
        
        controlPointBufferOffset = MemoryLayout<Float>.size * 4 * kMaxControlPointCount * inFlightIndex
        controlPointBufferAddress = controlPointsBuffer.contents().advanced(by: controlPointBufferOffset)
        netBufferOffset = MemoryLayout<UInt32>.size * 2 * inFlightIndex
        uKnotVectorBufferOffset = MemoryLayout<Float>.size * kMaxKnots * inFlightIndex
        vKnotVectorBufferOffset = MemoryLayout<Float>.size * kMaxKnots * inFlightIndex
        sphereInstanceUniformsOffset = alignedInstanceUniformsSize * inFlightIndex
        
        sharedUniformsBufferOffset = kAlignedSharedUniformsSize * inFlightIndex
        sharedUniformsBufferAddress = sharedUniformsBuffer.contents().advanced(by: sharedUniformsBufferOffset)
        netBufferAddress = netBuffer.contents().advanced(by: netBufferOffset)
        uKnotVectorBufferAddress = uKnotVectorBuffer.contents().advanced(by: uKnotVectorBufferOffset)
        vKnotVectorBufferAddress = vKnotVectorBuffer.contents().advanced(by: vKnotVectorBufferOffset)
        sphereInstanceUniformsAddress = sphereInstanceUniforms.contents().advanced(by: sphereInstanceUniformsOffset)
    }
    
    func drawCurve(view: MTKView, commandBuffer: MTLCommandBuffer) {
        //assert(validateCurve(), "curve parameters invalid.")
        
        var cpCount: Int = controlPointPositions.rows
        var knotCount: Int = uKnotVectorCount
        
        // evaluate curve using kernel
        let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeCommandEncoder.label = "Compute command encoder"
        computeCommandEncoder.pushDebugGroup("Evaluate curve")
        computeCommandEncoder.setComputePipelineState(evaluateCurveState)
        
        computeCommandEncoder.setBuffer(unitDomainBuffer, offset: 0, index: CEBufferIndex.parameter.rawValue)
        computeCommandEncoder.setBytes(&cpCount, length: MemoryLayout<Int>.size, index: CEBufferIndex.numberOfControlPoints.rawValue)
        computeCommandEncoder.setBuffer(curveVertexBuffer, offset: 0, index: CEBufferIndex.vertices.rawValue)
        computeCommandEncoder.setBuffer(controlPointsBuffer, offset: controlPointBufferOffset, index: CEBufferIndex.controlPoints.rawValue)
        computeCommandEncoder.setBuffer(uKnotVectorBuffer, offset: uKnotVectorBufferOffset, index: CEBufferIndex.knotVector.rawValue)
        computeCommandEncoder.setBytes(&knotCount, length: MemoryLayout<Int>.size, index: CEBufferIndex.knotVectorCount.rawValue)
        
        
        computeCommandEncoder.dispatchThreadgroups(.init(width: 10, height: 1, depth: 1), threadsPerThreadgroup: .init(width: 20, height: 1, depth: 1))
        computeCommandEncoder.popDebugGroup()
        computeCommandEncoder.endEncoding()
        
        if let renderPassDesc = view.currentRenderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
            renderEncoder.pushDebugGroup("render curve")
            renderEncoder.setRenderPipelineState(curveRenderPipeline)
            renderEncoder.setVertexBuffer(curveVertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: 1)
            renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: kUnitDomainPointCount)
            
            if showControlPoints {
                drawControlPoints(renderEncoder: renderEncoder)
            }
            
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
        }
    }
    
    func drawSurface(view: MTKView, commandBuffer: MTLCommandBuffer) {
        let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeCommandEncoder.label = "Compute Command Encoder"
        computeCommandEncoder.pushDebugGroup("Compute Tessellation Factors")
        computeCommandEncoder.setComputePipelineState(computeState)
        
        // Bind user selected edge and inside factor values to the compute kernel
        computeCommandEncoder.setBytes(&edgeFactor, length: MemoryLayout<Float>.size, index: 0)
        computeCommandEncoder.setBytes(&insideFactor, length: MemoryLayout<Float>.size, index: 1)
        
        // Bind the tessellation factors buffer to the compute kernel
        computeCommandEncoder.setBuffer(factorsBuffer, offset: 0, index: 2)
        
        // Dispatch threadgroups
        computeCommandEncoder.dispatchThreadgroups(.init(width: 1, height: 1, depth: 1), threadsPerThreadgroup: .init(width: 1, height: 1, depth: 1))
        
        computeCommandEncoder.pushDebugGroup("Project Points")
        computeCommandEncoder.setComputePipelineState(computePointProjectionsState)
        computeCommandEncoder.setBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: 0)
        computeCommandEncoder.setBuffer(controlPointsBuffer, offset: controlPointBufferOffset, index: 1)
        computeCommandEncoder.dispatchThreadgroups(.init(width: 1, height: 1, depth: 1), threadsPerThreadgroup: .init(width: controlPointCount, height: 1, depth: 1))
        
        // All compute commands have been encoded
        computeCommandEncoder.popDebugGroup()
        computeCommandEncoder.endEncoding()
        
        // obtain render pass descriptor generated from the view's drawable
        if let renderPassDescriptor = view.currentRenderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.label = "Render Command Encoder"
            renderEncoder.pushDebugGroup("Tessellate and Render")
            
            var uKnots: Int = uKnotVectorCount
            var vKnots: Int = vKnotVectorCount
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(renderDepthState)
            renderEncoder.setFrontFacing(.clockwise)
            renderEncoder.setVertexBuffer(controlPointsBuffer, offset: controlPointBufferOffset, index: PTBufferIndex.controlPoints.rawValue)
            renderEncoder.setVertexBuffer(netBuffer, offset: netBufferOffset, index: PTBufferIndex.netSize.rawValue)
            renderEncoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: PTBufferIndex.sharedUniforms.rawValue)
            renderEncoder.setVertexBuffer(uKnotVectorBuffer, offset: uKnotVectorBufferOffset, index: PTBufferIndex.uKnotVector.rawValue)
            renderEncoder.setVertexBuffer(vKnotVectorBuffer, offset: vKnotVectorBufferOffset, index: PTBufferIndex.vKnotVector.rawValue)
            renderEncoder.setVertexBytes(&uKnots, length: MemoryLayout<Int>.size, index: PTBufferIndex.uKnotCount.rawValue)
            renderEncoder.setVertexBytes(&vKnots, length: MemoryLayout<Int>.size, index: PTBufferIndex.vKnotCount.rawValue)
            
            if wireframe {
                renderEncoder.setTriangleFillMode(.lines)
            }
            
            // encode tessellation specific commands
            renderEncoder.setTessellationFactorBuffer(factorsBuffer, offset: 0, instanceStride: 0)
            renderEncoder.drawPatches(numberOfPatchControlPoints: 32,
                                      patchStart: 0,
                                      patchCount: 1,
                                      patchIndexBuffer: nil,
                                      patchIndexBufferOffset: 0,
                                      instanceCount: 1,
                                      baseInstance: 0)
            
            if showControlPoints {
                drawControlPoints(renderEncoder: renderEncoder)
            }
            
            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
        }
    }
    
    func drawControlPoints(renderEncoder: MTLRenderCommandEncoder) {
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
                                                instanceCount: controlPointCount)
        }
        
        renderEncoder.popDebugGroup()
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspectRatio = Float(size.width) / Float(size.height)
        perspective = matrix_perspective_left_hand(fovyRadians: .pi / 4.0, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100.0)
        inversePerspective = perspective.inverse
    }
    
    func draw(in view: MTKView) {
        let _ = _inFlightSemaphore.wait(timeout: .distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.addCompletedHandler { [weak self] commandBuffer in
                self?._inFlightSemaphore.signal()
            }
            
            updateDynamicBuffers()
            updateAppState()
            
            //drawSurface(view: view, commandBuffer: commandBuffer)
            drawCurve(view: view, commandBuffer: commandBuffer)
            
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            
            commandBuffer.commit()
        }
    }
}

