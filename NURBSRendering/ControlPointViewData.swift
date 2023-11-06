//
//  ControlPointViewData.swift
//  NURBSRendering
//
//  Created by Reza on 11/1/23.
//

import Foundation
import Matrix

struct ControlPointViewData: Identifiable {
    let id: Int
    var x: Float
    var y: Float
    var z: Float
    var weight: Float
    private var row: MatrixRow<Float>
    private let weightPtr: UnsafeMutablePointer<Float>
    
    init(id: Int, row: MatrixRow<Float>, weight: UnsafeMutablePointer<Float>) {
        self.id = id
        self.row = row
        self.weightPtr = weight
        
        x = row[0]
        y = row[1]
        z = row[2]
        self.weight = weightPtr.pointee
    }
    
    mutating func setX(_ newX: Float) {
        row[0] = newX
        x = newX
    }
    
    mutating func setY(_ newY: Float) {
        row[1] = newY
        y = newY
    }
    
    mutating func setZ(_ newZ: Float) {
        row[2] = newZ
        z = newZ
    }
    
    mutating func setWeight(_ newWeight: Float) {
        weightPtr.pointee = newWeight
        weight = newWeight
    }
    
    mutating func refresh() {
        x = row[0]
        y = row[1]
        z = row[2]
        weight = weightPtr.pointee
    }
}
