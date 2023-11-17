//
//  HMTKView.swift
//  NURBSRendering
//
//  Created by Reza on 11/15/23.
//

import Foundation
import MetalKit

class HMTKView: MTKView {
    var pointerLocation: CGPoint?
    var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        if trackingArea != nil {
            self.removeTrackingArea(trackingArea!)
        }
        let options : NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: self.bounds, options: options,
                                      owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        let point = event.locationInWindow
        if let size = event.window?.contentView?.bounds {
            let relX = point.x / size.width
            var relY = point.y / size.height
            relY = 1.0 - relY
            
            pointerLocation = .init(x: relX, y: relY)
        }
        
    }
    
    override func mouseExited(with event: NSEvent) {
        pointerLocation = nil
    }
    
    override func mouseMoved(with event: NSEvent) {
        let point = event.locationInWindow
        if let size = event.window?.contentView?.bounds {
            let relX = point.x / size.width
            var relY = point.y / size.height
            relY = 1.0 - relY
            
            pointerLocation = .init(x: relX, y: relY)
        }
    }
}
