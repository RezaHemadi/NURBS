//
//  CubeView.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import Foundation
import SwiftUI
import MetalKit
import RenderTools
import Transform

let kAlignedCubeSharedUniformsSize: Int = (MemoryLayout<CubeSharedUniforms>.size & ~0xFF) + 0x100
let kAlignedInstanceUniformsSize: Int = (MemoryLayout<InstanceUniforms>.size & ~0xFF) + 0x100

struct CubeView: NSViewRepresentable {
    var renderer: Renderer
    
    func makeNSView(context: Context) -> some NSView {
        let view = MTKView()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.clearColor = .init(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        view.sampleCount = 1
        context.coordinator.view = view
        view.device = GPUDevice.shared
        context.coordinator.device = GPUDevice.shared
        context.coordinator.loadMetal()
        context.coordinator.loadAssets()
        view.delegate = context.coordinator
        
        return view
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        
    }
}

extension CubeView {
    class Coordinator: NSObject, MTKViewDelegate {
        var parent: CubeView
        var view: MTKView!
        var inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
        
        // Metal Objects
        var device: MTLDevice!
        var renderState: MTLRenderPipelineState!
        var depthState: MTLDepthStencilState!
        var commandQueue: MTLCommandQueue!
        var sharedUniformsBuffer: MTLBuffer!
        var geometryVertexDescriptor: MTLVertexDescriptor!
        var cubeMesh: MTKMesh!
        var uniformBufferIndex: Int = 0
        var sharedUniformsBufferOffset: Int = 0
        var sharedUniformsBufferAddress: UnsafeMutableRawPointer!
        var viewportSize: CGSize = .init()
        var viewportSizeDidChange: Bool = false
        var cubeInstanceUniformBuffer: MTLBuffer!
        var cubeInstanceUniformBufferOffset: Int = 0
        var cubeInstanceUniformAddress: UnsafeMutableRawPointer!
        
        var camera: Camera
        let projection: matrix_float4x4
        
        // MARK: Initialization
        init(_ container: CubeView) {
            parent = container
            
            camera = .init(transform: .init(translationX: -0.5, translationY: 0.0, translationZ: 1.5))
            projection = matrix_perspective_left_hand(fovyRadians: .pi / 18, aspectRatio: 1.0, nearZ: 0.1, farZ: 1000.0)
        }
        
        // MARK: - Methods
        func loadMetal() {
            let sharedUniformsBufferSize = kAlignedCubeSharedUniformsSize * kMaxBuffersInFlight
            sharedUniformsBuffer = device.makeBuffer(length: sharedUniformsBufferSize, options: .storageModeShared)
            sharedUniformsBuffer.label = "Cube Shared Uniforms"
            
            let library = device.makeDefaultLibrary()!
            let vertexFunction = library.makeFunction(name: "cubeVertexShader")!
            let fragmentFunction = library.makeFunction(name: "cubeFragmentShader")!
            
            geometryVertexDescriptor = MTLVertexDescriptor()
            
            // Positions
            geometryVertexDescriptor.attributes[0].format = .float3
            geometryVertexDescriptor.attributes[0].offset = 0
            geometryVertexDescriptor.attributes[0].bufferIndex = CubeBufferIndex.meshPositions.rawValue
            
            // Texture Coordinates
            geometryVertexDescriptor.attributes[1].format = .float2
            geometryVertexDescriptor.attributes[1].offset = 0
            geometryVertexDescriptor.attributes[1].bufferIndex = CubeBufferIndex.meshGenerics.rawValue
            
            // Normals
            geometryVertexDescriptor.attributes[2].format = .half3
            geometryVertexDescriptor.attributes[2].offset = 8
            geometryVertexDescriptor.attributes[2].bufferIndex = CubeBufferIndex.meshGenerics.rawValue
            
            // Position buffer layout
            geometryVertexDescriptor.layouts[0].stride = 12
            geometryVertexDescriptor.layouts[0].stepRate = 1
            geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
            
            // Generic buffer layout
            geometryVertexDescriptor.layouts[1].stride = 16
            geometryVertexDescriptor.layouts[1].stepRate = 1
            geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
            
            // create reusable render state to render the cube
            let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
            renderPipelineDescriptor.label = "Cube render pipeline"
            renderPipelineDescriptor.vertexDescriptor = geometryVertexDescriptor
            renderPipelineDescriptor.vertexFunction = vertexFunction
            renderPipelineDescriptor.fragmentFunction = fragmentFunction
            renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            renderPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            renderPipelineDescriptor.isAlphaToOneEnabled = false
            renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
            
            do {
                try renderState = device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
            } catch {
                print(error.localizedDescription)
            }
            
            let depthStateDescriptor = MTLDepthStencilDescriptor()
            depthStateDescriptor.depthCompareFunction = .less
            depthStateDescriptor.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)
            
            // create command queue
            commandQueue = device.makeCommandQueue()
        }
        
        func loadAssets() {
            let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
            
            // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
            (vertexDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
            (vertexDescriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
            (vertexDescriptor.attributes[2] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
            
            let metalAllocator = MTKMeshBufferAllocator(device: device)
            
            // Use ModelIO to create a box mesh as our object
            let mesh = MDLMesh(boxWithExtent: vector3(1.0, 1.0, 1.0), segments: vector3(1, 1, 1), inwardNormals: false, geometryType: .triangles, allocator: metalAllocator)
            
            // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
            //   Model IO mesh
            mesh.vertexDescriptor = vertexDescriptor
            
            // Create a MetalKit mesh (and submeshes) backed by Metal buffers
            do {
                try cubeMesh = MTKMesh(mesh: mesh, device: device)
            } catch let error {
                print("Error creating MetalKit mesh, error \(error)")
            }
            
            let instanceUniformSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
            cubeInstanceUniformBuffer = device.makeBuffer(length: instanceUniformSize, options: .storageModeShared)
            cubeInstanceUniformAddress = cubeInstanceUniformBuffer.contents()
        }
        
        private func makeUniformTexture(colorValues: vector_float3, device: MTLDevice) -> MTLTexture {
            let textureDescriptor = MTLTextureDescriptor()
            textureDescriptor.height = 8
            textureDescriptor.width = 8
            textureDescriptor.pixelFormat = .rgba8Unorm
            textureDescriptor.mipmapLevelCount = 1
            textureDescriptor.storageMode = .managed
            textureDescriptor.arrayLength = 1
            textureDescriptor.sampleCount = 1
            textureDescriptor.cpuCacheMode = .writeCombined
            textureDescriptor.textureType = .type2D
            textureDescriptor.usage = .shaderRead
            let texture = device.makeTexture(descriptor: textureDescriptor)!
            let origin = MTLOrigin(x: 0, y: 0, z: 0)
                    let size = MTLSize(width: texture.width, height: texture.height, depth: texture.depth)
                    let region = MTLRegion(origin: origin, size: size)
            let mappedColor = simd_uchar4(simd_float4(colorValues, 0.4) * 255)
                    Array<simd_uchar4>(repeating: mappedColor, count: 64).withUnsafeBytes { ptr in
                        texture.replace(region: region, mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: 32)
                    }
            return texture
        }
        
        func updateBufferStates() {
            uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
            
            sharedUniformsBufferOffset = kAlignedCubeSharedUniformsSize * uniformBufferIndex
            cubeInstanceUniformBufferOffset = kAlignedInstanceUniformsSize * uniformBufferIndex
            
            sharedUniformsBufferAddress = sharedUniformsBuffer.contents().advanced(by: sharedUniformsBufferOffset)
            cubeInstanceUniformAddress = cubeInstanceUniformBuffer.contents().advanced(by: cubeInstanceUniformBufferOffset)
        }
        
        func updateState() {
            let uniforms = sharedUniformsBufferAddress.assumingMemoryBound(to: CubeSharedUniforms.self)
            
            let rot = simd_quatf(parent.renderer.camera.transform.matrix)
            let rotMatrix = float4x4(rot)
            let translationMatrix = Transform.init(translationX: 0.0, translationY: 0.0, translationZ: -13.0).matrix
            let camMatrix = rotMatrix * translationMatrix
            camera = .init(transform: .init(transform: camMatrix))
            
            // Flip z to convert geometry from right hand to left hand
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            var modelMatrix = simd_mul(matrix_identity_float4x4, coordinateSpaceTransform)
            let modelTranslation = Transform.init(translationX: 0.0, translationY: 0.0, translationZ: 0.0).matrix
            modelMatrix = simd_mul(modelTranslation, modelMatrix)
            
            uniforms.pointee.projectionMatrix = projection
            uniforms.pointee.viewMatrix = camera.viewMatrix
            
            cubeInstanceUniformAddress.assumingMemoryBound(to: InstanceUniforms.self).pointee.transform = modelMatrix
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            viewportSize = size
            viewportSizeDidChange = true
        }
        
        func draw(in view: MTKView) {
            let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
            
            if let commandBuffer = commandQueue.makeCommandBuffer() {
                commandBuffer.label = "CubeRenderCommandBuffer"
                
                commandBuffer.addCompletedHandler { buffer in
                    self.inFlightSemaphore.signal()
                }
                
                updateBufferStates()
                updateState()
                
                if let renderPassDescriptor = view.currentRenderPassDescriptor, let currentDrawable = view.currentDrawable, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    
                    renderEncoder.label = "CubeRenderEncoder"
                    
                    renderPassDescriptor.colorAttachments[0].loadAction = .clear
                    renderPassDescriptor.colorAttachments[0].storeAction = .store
                    
                    renderPassDescriptor.depthAttachment.clearDepth = 1.0
                    renderPassDescriptor.depthAttachment.loadAction = .clear
                    renderPassDescriptor.depthAttachment.storeAction = .store
                    
                    //drawCube(encoder: renderEncoder)
                    drawCube(encoder: renderEncoder)
                    
                    // We're done encoding commands
                    renderEncoder.endEncoding()
                    
                    // Schedule a present once the framebuffer is complete using the current drawable
                    commandBuffer.present(currentDrawable)
                }
                
                // Finalize rendering here & push the command buffer to the GPU
                commandBuffer.commit()
            }
        }
        
        func drawCube(encoder: MTLRenderCommandEncoder) {
            encoder.pushDebugGroup("DrawCube")
            
            encoder.setCullMode(.back)
            encoder.setRenderPipelineState(renderState)
            encoder.setDepthStencilState(depthState)
            
            encoder.setVertexBuffer(sharedUniformsBuffer, offset: sharedUniformsBufferOffset, index: CubeBufferIndex.sharedUniforms.rawValue)
            encoder.setVertexBuffer(cubeInstanceUniformBuffer, offset: cubeInstanceUniformBufferOffset, index: CubeBufferIndex.instanceUniforms.rawValue)
            
            for bufferIndex in 0..<cubeMesh.vertexBuffers.count {
                let vertexBuffer = cubeMesh.vertexBuffers[bufferIndex]
                encoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: bufferIndex)
            }
            
            for submesh in cubeMesh.submeshes {
                encoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                              indexCount: submesh.indexCount,
                                              indexType: submesh.indexType,
                                              indexBuffer: submesh.indexBuffer.buffer,
                                              indexBufferOffset: submesh.indexBuffer.offset)
            }
        }
    }
}
