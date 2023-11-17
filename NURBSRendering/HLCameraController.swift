//
//  HLCameraController.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import Foundation
import RenderTools
import Transform

class HLCameraController: ObservableObject {
    // MARK: - Properties
    @Published var camera: Camera
    private var focalLength: Float = 3.0
    
    // MARK: - Initialization
    init(transform: Transform = .init(translation: [0.0, 0.0, -3.0])) {
        camera = Camera(transform: transform)
    }
    
    // MARK: - Methods
    func pan(xNormalized: Float, yNormalized: Float) {
        DispatchQueue.main.async { [weak self] in
            let localPanDirection: SIMD4<Float> = [xNormalized, -yNormalized, 0.0, 0.0]
            let worldPanDirection = self!.camera.transform.matrix * localPanDirection
            
            let worldPanDirectionScaled = worldPanDirection * 0.2
            let translationMatrix = Transform(translation: worldPanDirectionScaled.xyz)
            self!.camera.transform = translationMatrix * self!.camera.transform
        }
    }
    
    func arcballRotate(xNormalized: Float, yNormalized: Float) {
        DispatchQueue.main.async { [weak self] in
            let localFocalPointV: SIMD4<Float> = [0.0, 0.0, self!.focalLength, 1.0]
            let focalPointWorldV = self!.camera.transform.matrix * localFocalPointV
            
            
            // get vector from focal point pointing to camera
            let vector = self!.camera.transform.translation - focalPointWorldV.xyz
            
            let camUpV: SIMD4<Float> = [0.0, 1.0, 0.0, 0.0]
            let camUpWorldV = self!.camera.transform.matrix * camUpV
            let camRightV: SIMD4<Float> = [1.0, 0.0, 0.0, 0.0]
            let camRightWorldV = self!.camera.transform.matrix * camRightV
            let yRot = simd_quaternion((yNormalized / 8.0) / 2.0 * .pi, normalize(camRightWorldV.xyz))
            let xRot = simd_quaternion((xNormalized / 8.0) / 2.0 * .pi, normalize(camUpWorldV.xyz))
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
    
    func zoomIn(length: Float = 0.2) {
        focalLength -= length
        DispatchQueue.main.async { [weak self] in
            let front: SIMD4<Float> = [0.0, 0.0, length, 0.0]
            let worldFront = self!.camera.transform.matrix * front
            
            let translationMatrix = Transform(translation: worldFront.xyz)
            self!.camera.transform = translationMatrix * self!.camera.transform
        }
    }
    
    func zoomOut(length: Float = 0.2) {
        focalLength += length
        DispatchQueue.main.async { [weak self] in
            let front: SIMD4<Float> = [0.0, 0.0, -length, 0.0]
            let worldFront = self!.camera.transform.matrix * front
            
            let translationMatrix = Transform(translation: worldFront.xyz)
            self!.camera.transform = translationMatrix * self!.camera.transform
        }
    }
}
