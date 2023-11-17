//
//  ToolsPanelView.swift
//  NURBSRendering
//
//  Created by Reza on 11/14/23.
//

import SwiftUI

struct ToolsPanelView: View {
    @StateObject var session: HLNurbsSession
    
    private var insertKnotEnabled: Bool {
        if let objectIdx = session.selectedObject {
            if let curve = session.geometries[objectIdx] as? HLRCurve {
                if curve.canInsertKnot {
                    return true
                }
            }
        }
        return false
    }
    
    var body: some View {
        Grid {
            GridRow {
                Button(action: {session.insertKnot()}, label: {
                    Label(
                        title: { Text("Insert Knot") },
                        icon: { Image(systemName: "arrow.forward.to.line") }
                    )
                })
                .disabled(!insertKnotEnabled)
            }
        }
        .background(Color.init(white: 0.3).opacity(0.6))
        .clipShape(.rect(cornerRadius: 5.0))
        
    }
}

#Preview {
    ToolsPanelView(session: HLNurbsSession())
}
