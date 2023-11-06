//
//  RightBar.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import SwiftUI

struct RightBar: View {
    @StateObject var renderer: Renderer
    @State private var insertKnotU: Float = 0.0
    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    private func insertKnot() {
        //renderer.curveInsertKnot(at: insertKnotU)
        renderer.surfaceInsertKnot(at: insertKnotU, direction: .v)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15.0) {
            HStack {
                Toggle(isOn: $renderer.wireframe, label: {
                    Text("wireframe")
                })
            }
            Slider(value: $renderer.edgeFactor, in: 1...64, step: 1, label: {
                Text("edge factor:")
            }, minimumValueLabel: {
                Text("1")
            }, maximumValueLabel: {
                Text("64")
            })
            
            Slider(value: $renderer.insideFactor, in: 1...64, step: 1, label: {
                Text("inside factor:")
            }, minimumValueLabel: {
                Text("1")
            }, maximumValueLabel: {
                Text("64")
            })
            
            HStack {
                Toggle(isOn: $renderer.showControlPoints, label: {
                    Text("Show control points ")
                })
            }
            
            HStack {
                Button(action: {insertKnot()}) {
                    Text("Insert Knot")
                }
                
                Slider(value: $insertKnotU, in: 0...1, step: 0.05, label: {
                    Text(formatter.string(for: insertKnotU) ?? "")
                        .font(.caption2)
                        .frame(width: 30.0)
                })
            }
            
            List(renderer.selectedPoints, id: \.self) { id in
                PointPositionView(title: "Point \(id)", point: $renderer.controlPointList[id])
            }
            .background(.clear)
            
            Spacer()
        }
        .frame(width: 300.0)
    }
}

#Preview {
    RightBar(renderer: Renderer())
}
