//
//  GPUDevice.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import Foundation
import Metal

class GPUDevice {
    static var shared: MTLDevice {
        return MTLCreateSystemDefaultDevice()!
    }
}
