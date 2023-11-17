//
//  NewCurveView.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import SwiftUI

struct NewCurveView: View {
    @StateObject var session: HLNurbsSession
    @State private var curveTypeSelecion: CurveType = .straight
    @State private var spacing: Float = 0.2
    @State private var degree: Int = 1
    @State private var name: String = ""
    @State private var radius: Float = 0.5
    @State private var startAngle: Float = 0.0
    @State private var endAngle: Float = 180.0
    @State private var fullCircle: Bool = false
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .none
        
        return formatter
    }
    private var degreeFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        return formatter
    }
    
    private func clear() {
        spacing = 0.2
        degree = 1
        name = ""
    }
    
    private func dismiss() {
        clear()
        session.dismissNewCurveView()
    }
    
    private func submit() {
        switch curveTypeSelecion {
        case .straight:
            session.createCurve(spacing: spacing, degree: degree, name: name)
        case .Circle:
            if fullCircle {
                session.createFullCircle(radius: radius, name: name)
            } else {
                session.createCircularArc(radius: radius, startAngle: startAngle, endAngle: endAngle, name: name)
            }
        }
        
        dismiss()
    }
    
    private var straightTypeView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Spacing: ")
                    .frame(width: 80.0, alignment: .leading)
                TextField("0.2", value: $spacing, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50.0)
            }
            
            HStack {
                Text("Degree:")
                    .frame(width: 80.0, alignment: .leading)
                TextField("1", value: $degree, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
            }
            
            HStack {
                Text("Name:")
                    .frame(width: 80.0, alignment: .leading)
                TextField(name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
            }
            
            
            Spacer()
        }
    }
    
    private var CircleView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Radius: ")
                    .frame(width: 80.0, alignment: .leading)
                TextField("0.5", value: $radius, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
            }
            HStack {
                Text("Start Angle:")
                    .frame(width: 80.0, alignment: .leading)
                TextField("0.0", value: $startAngle, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .disabled(fullCircle)
                    .frame(width: 50.0)
            }
            
            HStack {
                Text("End Angle:")
                    .frame(width: 80.0, alignment: .leading)
                TextField("180.0", value: $endAngle, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .disabled(fullCircle)
                    .frame(width: 50.0)
            }
            HStack {
                Text("Name:")
                    .frame(width: 80.0, alignment: .leading)
                TextField(name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
            }
            
            HStack {
                Text("Full Circle:")
                    .frame(width: 80.0, alignment: .leading)
                Toggle(isOn: $fullCircle) {
                    EmptyView()
                }
            }
            
            Spacer()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            HStack {
                Button(action: {dismiss()}, label: {
                    Image(systemName: "xmark.circle")
                        .imageScale(.medium)
                })
                .buttonStyle(.plain)
                .padding([.leading, .top], -5.0)
                Spacer()
            }
            Picker(selection: $curveTypeSelecion, label: Text("Curve type")) {
                ForEach(CurveType.allCases, id: \.self) { curveType in
                    Text(curveType.rawValue)
                }
            }
            .pickerStyle(.palette)
            
            switch curveTypeSelecion {
            case .straight:
                straightTypeView
            case .Circle:
                CircleView
            }
            HStack {
                Spacer()
                Button(action: {submit()}) {
                    Text("Create")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            
        }
        .padding()
        .frame(width: 400.0, height: 300.0, alignment: .top)
        .background(Color.init(white: 0.3).opacity(0.6))
        .clipShape(.rect(cornerRadius: 20.0))
    }
}

#Preview {
    NewCurveView(session: HLNurbsSession())
}

extension NewCurveView {
    enum CurveType: String, CaseIterable {
        case straight = "Straight"
        case Circle = "Circle"
    }
}
