//
//  AttributesView.swift
//  NURBSRendering
//
//  Created by Reza on 11/10/23.
//

import SwiftUI
import Transform

struct AttributesView: View {
    @Binding var transform: Transform
    @State private var size: CGSize = .zero
    @State private var xPos: Float = 0.0
    @State private var yPos: Float = 0.0
    @State private var zPos: Float = 0.0
    @State private var pitch: Float = 0.0
    @State private var yaw: Float = 0.0
    @State private var roll: Float = 0.0
    @State private var xScale: Float = 1.0
    @State private var yScale: Float = 1.0
    @State private var zScale: Float = 1.0
    
    private var labelWidth: CGFloat { 35.0 }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Attributes")
                .font(.headline)
                
            Text("Position")
                .font(.subheadline)
            VStack {
                HStack(spacing: 0.0) {
                    Text("x")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("x", value: $xPos, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            xPos = transform.translation.x
                        }
                        .onChange(of: xPos) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.translation.x = newValue
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            xPos = newValue.translation.x
                        }
                    
                    Text("y")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("y", value: $yPos, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            yPos = transform.translation.y
                        }
                        .onChange(of: yPos) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.translation.y = newValue
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            yPos = newValue.translation.y
                        }
                    
                    Text("z")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("z", value: $zPos, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            zPos = transform.translation.z
                        }
                        .onChange(of: zPos) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.translation.z = newValue
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            zPos = newValue.translation.z
                        }
                }
                
            }
            .padding([.leading], 4.0)
            
            Text("Eulers")
                .font(.subheadline)
            VStack {
                HStack(spacing: 0.0) {
                    Text("pitch")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("pitch", value: $pitch, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            pitch = Angle(radians: transform.eulerAngles.x).degress
                        }
                        .onChange(of: pitch) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.eulerAngles.x = Angle(degrees: newValue).radians
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            pitch = Angle(radians: newValue.eulerAngles.x).degress
                        }
                        .onSubmit {
                            pitch = Angle(radians: transform.eulerAngles.x).degress
                        }
                    
                    Text("yaw")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("yaw", value: $yaw, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            yaw = Angle(radians: transform.eulerAngles.y).degress
                        }
                        .onChange(of: yaw) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.eulerAngles.y = Angle(degrees: newValue).radians
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            yaw = Angle(radians: newValue.eulerAngles.y).degress
                        }
                        .onSubmit {
                            yaw = Angle(radians: transform.eulerAngles.y).degress
                        }
                    
                    Text("roll")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("roll", value: $roll, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            roll = Angle(radians: transform.eulerAngles.z).degress
                        }
                        .onChange(of: roll) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.eulerAngles.z = Angle(degrees: newValue).radians
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            roll = Angle(radians: newValue.eulerAngles.z).degress
                        }
                        .onSubmit {
                            roll = Angle(radians: transform.eulerAngles.z).degress
                        }
                }
            }
            .padding([.leading], 4.0)
            
            Text("Scale")
                .font(.subheadline)
            VStack {
                HStack(spacing: 0.0) {
                    Text("x")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("x", value: $xScale, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            xScale = transform.scale.x
                        }
                        .onChange(of: xScale) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.scale.x = newValue
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            xScale = newValue.scale.x
                        }
                    
                    Text("y")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("y", value: $yScale, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            yScale = transform.scale.y
                        }
                        .onChange(of: yScale) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.scale.y = yScale
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            yScale = newValue.scale.y
                        }
                    
                    Text("z")
                        .font(.callout)
                        .frame(width: labelWidth, alignment: .center)
                    TextField("z", value: $zScale, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            zScale = transform.scale.z
                        }
                        .onChange(of: zScale) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            transform.scale.z = newValue
                        }
                        .onChange(of: transform) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            zScale = newValue.scale.z
                        }
                }
            }
        }
        .padding(4.0)
        .background(Color.init(white: 0.3).opacity(0.6))
        .clipShape(.rect(cornerRadius: 10.0))
    }
}
/*
#Preview {
    AttributesView(session: .init())
}*/
