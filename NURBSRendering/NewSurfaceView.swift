//
//  NewSurfaceView.swift
//  NURBSRendering
//
//  Created by Reza on 11/9/23.
//

import SwiftUI
import Matrix

enum AxisOfRevolution: String, CaseIterable {
    case x
    case y
    case z
    
    var vector: RVec3f {
        switch self {
        case .x: return [1.0, 0.0, 0.0]
        case .y: return [0.0, 1.0, 0.0]
        case .z: return [0.0, 0.0, 1.0]
        }
    }
}

struct NewSurfaceView: View {
    @StateObject var session: HLNurbsSession
    @State private var surfaceTypeSelection: SurfaceType = .grid
    @State private var widthSpacing: Float = 0.2
    @State private var heightSpacing: Float = 0.2
    @State private var widthDegree: Int = 1
    @State private var heightDegree: Int = 1
    @State private var width: Float = 1.0
    @State private var height: Float = 1.0
    @State private var name: String = ""
    @State private var curves: [HLRCurve]
    @State private var curveSelected: [Bool]
    let curveCount: Int
    @State private var revAxisSelection: AxisOfRevolution = .x
    @State private var revAngle: Float = 180.0
    
    init(session: HLNurbsSession) {
        _session = StateObject(wrappedValue: session)
        surfaceTypeSelection = .grid
        widthSpacing = 0.2
        heightSpacing = 0.2
        widthDegree = 1
        heightDegree = 1
        width = 1.0
        height = 1.0
        name = ""
        curves = session.geometries.compactMap({$0 as? HLRCurve})
        curveSelected = []
        curveCount = session.geometries.compactMap({$0 as? HLRCurve}).count
    }
    
    private var submitDisabled: Bool {
        switch surfaceTypeSelection {
        case .grid:
            return false
        case .combine:
            if curveSelected.filter({$0 == true}).count > 1 {
                return false
            }
            return true
        case .revolution:
            if curveSelected.filter({$0 == true}).count == 1 {
                return false
            }
            return true
            
        case .ruled:
            if curveSelected.filter({$0 == true}).count == 2 {
                return false
            }
            return true
        }
    }
    
    private func dismiss() {
        clear()
        session.dismissNewSurfaceView()
    }
    
    private func submit() {
        switch surfaceTypeSelection {
        case .grid:
            session.createGridSurface(width: width, height: height, widthSpacing: widthSpacing, heightSpacing: heightSpacing, widthDegree: widthDegree, heightDegree: heightDegree, name: name)
        case .combine:
            var curveOneIdx: Int?
            var curveTwoIdx: Int?
            for i in 0..<curveSelected.count {
                if curveSelected[i] {
                    if curveOneIdx == nil {
                        curveOneIdx = i
                    } else if curveTwoIdx == nil {
                        curveTwoIdx = i
                    } else {
                        break
                    }
                }
            }
            session.createSurfaceByCombination(curveOne: curves[curveOneIdx!],
                                               curveTwo: curves[curveTwoIdx!],
                                               name: name)
            
        case .revolution:
            if let index = curveSelected.firstIndex(where: {$0 == true}) {
                session.createSurfaceOfRevolution(curve: curves[index],
                                                  axis: revAxisSelection,
                                                  sweepAngle: revAngle,
                                                  name: name)
            }
            
        case .ruled:
            var selected: [HLRCurve] = []
            for i in 0..<curveSelected.count {
                if curveSelected[i] {
                    selected.append(curves[i])
                }
            }
            assert(selected.count == 2)
            session.createRuledSurface(firstCurve: selected[0], secondCurve: selected[1], name: name)
        }
        dismiss()
    }
    
    private func clear() {
        widthSpacing = 0.2
        heightSpacing = 0.2
        width = 1.0
        height = 1.0
        name = ""
    }
    
    private var RuledSelectionView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("name:")
                    .frame(width: 60.0, alignment: .leading)
                TextField(name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
                Spacer()
            }
            
            List(0..<curveCount) { index in
                HStack {
                    Toggle(isOn: $curveSelected[index], label: {
                        Text(curves[index].name ?? "untitled")
                    })
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
    
    private var GridSelectionView: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 20.0) {
                Text("Width:")
                    .frame(width: 60.0, alignment: .leading)
                TextField("1", value: $width, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
                
                Text("Spacing: ")
                    .frame(width: 60.0, alignment: .leading)
                TextField("0.2", value: $widthSpacing, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
                
                Text("Degree: ")
                    .frame(width: 60.0, alignment: .leading)
                TextField("1", value: $widthDegree, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
            }
            
            HStack(spacing: 20.0) {
                Text("Height:")
                    .frame(width: 60.0, alignment: .leading)
                TextField("1", value: $height, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
                
                Text("Spacing: ")
                    .frame(width: 60.0, alignment: .leading)
                TextField("0.2", value: $heightSpacing, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
                
                Text("Degree: ")
                    .frame(width: 60.0, alignment: .leading)
                TextField("1", value: $heightDegree, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50.0)
            }
            
            HStack {
                Text("Name:")
                    .frame(width: 60.0, alignment: .leading)
                TextField(name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
            }
            
            
            Spacer()
        }
    }
    
    private var CombineSelectionView: some View {
        VStack {
            HStack {
                Text("Name:")
                    .frame(width: 60.0, alignment: .leading)
                TextField(name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
                Spacer()
            }
            
            List(0..<curveCount) { index in
                HStack {
                    Toggle(isOn: $curveSelected[index], label: {
                        Text(curves[index].name ?? "untitled")
                    })
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
    
    private var RevolutionView: some View {
        VStack {
            HStack {
                Text("Name:")
                    .frame(width: 90.0, alignment: .leading)
                TextField(name, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
                Spacer()
            }
            
            HStack {
                Picker(selection: $revAxisSelection, content: {
                    ForEach(AxisOfRevolution.allCases, id: \.self) { axis in
                        Text(axis.rawValue)
                    }
                }, label: {
                    Text("Axis:")
                        .frame(width: 90.0, alignment: .leading)
                })
                .pickerStyle(.palette)
                .frame(width: 190.0)
                
                Spacer()
            }
            
            HStack {
                Text("Sweep Angle:")
                    .frame(width: 90.0)
                TextField("180.0", value: $revAngle, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100.0)
                Spacer()
            }
            
            List(0..<curveCount) { index in
                HStack {
                    Toggle(isOn: $curveSelected[index], label: {
                        Text(curves[index].name ?? "untitled")
                    })
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20.0) {
            HStack {
                Button(action: {dismiss()}) {
                    Image(systemName: "xmark.circle")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .padding([.leading, .top], -5.0)
                Spacer()
            }
            Picker(selection: $surfaceTypeSelection, label: Text("Surface type")) {
                ForEach(SurfaceType.allCases, id: \.self) { surfaceType in
                    Text(surfaceType.rawValue)
                }
            }
            .pickerStyle(.palette)
            
            switch surfaceTypeSelection {
            case .grid:
                GridSelectionView
            case .combine:
                CombineSelectionView
            case .revolution:
                RevolutionView
            case .ruled:
                RuledSelectionView
            }
            HStack {
                Spacer()
                Button(action: {submit()}) {
                    Text("Create")
                }
                .buttonStyle(.bordered)
                .disabled(submitDisabled)
                Spacer()
            }
        }
        .padding()
        .frame(width: 480.0, height: 300.0, alignment: .top)
        .background(Color.init(white: 0.3).opacity(0.6))
        .clipShape(.rect(cornerRadius: 20.0))
        .onAppear(perform: {
            curveSelected = .init(repeating: false, count: curves.count)
        })
    }
}

#Preview {
    NewSurfaceView(session: HLNurbsSession())
}

extension NewSurfaceView {
    enum SurfaceType: String, CaseIterable {
        case grid = "Grid"
        case combine = "Combine"
        case revolution = "Revolution"
        case ruled = "Ruled"
    }
}
