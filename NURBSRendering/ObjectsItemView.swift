//
//  ObjectsItemView.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import SwiftUI

struct ObjectsItemView: View {
    @StateObject var session: HLNurbsSession
    @StateObject var item: HLParametricGeometry
    private var isCurve: Bool {
        item.type == .curve
    }
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { _ in
                session.selectObject(item)
            }
    }
    
    var body: some View {
        HStack {
            Text(item.name ?? "untitled")
            Image(systemName: isCurve ? "point.topleft.down.to.point.bottomright.curvepath" :
                                         "squareshape.split.3x3")
            Spacer()
            Button(action: {item.hidden.toggle()}) {
                Image(systemName: item.hidden ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            
            Button(action: {session.deleteObjectWithid(item.id)}) {
                Image(systemName: "delete.left")
            }
            .buttonStyle(.plain)
        }
        .gesture(tapGesture)
    }
}

#Preview {
    ObjectsItemView(session: HLNurbsSession(), item: .init(type: .curve))
}
