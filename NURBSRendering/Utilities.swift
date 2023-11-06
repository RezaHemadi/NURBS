//
//  Utilities.swift
//  NURBSRendering
//
//  Created by Reza on 11/5/23.
//

import Foundation
import Matrix
import Transform

// Return the angle between points PQR, assume Q is in middle
func angle(_ P: RVec3f, _ Q: RVec3f, _ R: RVec3f) -> Angle {
    let d1: RVec3f = P - Q
    let d2: RVec3f = R - Q
    let num: Float = d1.cross(d2).norm()
    let den: Float = d1.dot(d2)
    
    // in [-pi, pi] range
    var theta: Float = atan2f(num, den)
    
    theta = (theta + 2.0 * .pi).truncatingRemainder(dividingBy: 2.0 * .pi)
    
    return .init(radians: theta)
}
