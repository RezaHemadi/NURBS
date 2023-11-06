//
//  NetSize.swift
//  NURBSRendering
//
//  Created by Reza on 10/25/23.
//

import Foundation

struct NetSize {
    // number of points in the v direction
    let m: UInt32
    // number of points in the u direction
    let n: UInt32
}

extension NetSize: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: UInt32...) {
        assert(elements.count == 2)
        m = elements[0]
        n = elements[1]
    }
}
