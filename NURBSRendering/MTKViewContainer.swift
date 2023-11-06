//
//  MTKViewContainer.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import Foundation
import SwiftUI
import MetalKit

struct MTKViewContainer: NSViewRepresentable {
    var renderer: Renderer
    
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = GPUDevice.shared
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.clearColor = .init(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
        renderer.device = view.device
        renderer.renderDestination = view
        view.delegate = renderer
        
        return view
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        
    }
    
    class Coordinator: NSObject {
        var parent: MTKViewContainer
        
        init(_ container: MTKViewContainer) {
            parent = container
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}
