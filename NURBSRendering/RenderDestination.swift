//
//  RenderDestination.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import Foundation
import MetalKit

protocol RenderDestination {
    var colorPixelFormat: MTLPixelFormat { get }
    var depthStencilPixelFormat: MTLPixelFormat { get }
}

extension MTKView: RenderDestination {}
