//
//  ObjectsViewer.swift
//  NURBSRendering
//
//  Created by Reza on 11/8/23.
//

import SwiftUI

struct ObjectsViewer: View {
    @StateObject var session: HLNurbsSession
    
    private func addNewCurve() {
        session.newCurve()
    }
    
    private func addNewSurface() {
        session.newSurface()
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Geometries")
                    .font(.headline)
                Spacer()
                
                Menu("", systemImage: "plus.app") {
                    Button("curve", action: {addNewCurve()})
                    Button("surface", action: {addNewSurface()})
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(4.0)
            
            List(session.geometries) { geometry in
                ObjectsItemView(session: session,item: geometry)
                    .padding(4.0)
                    .background(geometry.selected ? Color(nsColor: .systemGreen).opacity(0.5) :
                                                         Color(.clear))
                    .clipShape(.rect(cornerRadius: 5.0))
            }
            .scrollContentBackground(.hidden)
            .padding(-10.0)
            
        }
        .background(Color.init(white: 0.3).opacity(0.6))
        .clipShape(.rect(cornerRadius: 10.0))
    }
}

#Preview {
    ObjectsViewer(session: HLNurbsSession())
}
