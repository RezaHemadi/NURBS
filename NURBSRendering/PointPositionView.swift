//
//  PointPositionView.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import SwiftUI
import Matrix

struct PointPositionView: View {
    var title: String
    @Binding var point: ControlPointViewData
    @State var x: String = ""
    @State var y: String = ""
    @State var z: String = ""
    @State var w: String = ""
    
    let formatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    private func submitX() {
        if let x = Float(x) {
            point.setX(x)
        }
    }
    
    private func submitY() {
        if let y = Float(y) {
            point.setY(y)
        }
    }
    
    private func submitZ() {
        if let z = Float(z) {
            point.setZ(z)
        }
    }
    
    private func submitW() {
        if let w = Float(w) {
            point.setWeight(w)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            HStack {
                Text("x:")
                TextField(
                    formatter.string(for: point.x) ?? "0.0",
                    text: $x
                )
                .onSubmit {
                    submitX()
                }
                .autocorrectionDisabled()
                .border(.secondary)
                
                Text("y:")
                TextField(
                    formatter.string(for: point.y) ?? "0.0",
                text: $y
                )
                .onSubmit {
                    submitY()
                }
                .autocorrectionDisabled()
                .border(.secondary)
                
                Text("z:")
                TextField(
                    formatter.string(for: point.z) ?? "0.0",
                text: $z
                )
                .onSubmit {
                    submitZ()
                }
                .autocorrectionDisabled()
                .border(.secondary)
                
                Text("w:")
                TextField(
                    formatter.string(for: point.weight) ?? "0.0",
                    text: $w
                )
                .onSubmit {
                    submitW()
                }
                .autocorrectionDisabled()
                .border(.secondary)
            }
        }
    }
}

#Preview {
    var weight: [Float] = [1.0]
    return PointPositionView(title: "Point1", point: .constant(.init(id: 1, row: Mat3.Identity().row(1), weight: &weight)))
}
