//
//  PanView.swift
//  NURBSRendering
//
//  Created by Reza on 10/28/23.
//

import SwiftUI

struct PanView: View {
    @StateObject var renderer: Renderer
    
    var drag: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                let xTranslationNormalized = Float(value.translation.width / 120.0)
                let yTranslationNormalized = Float(value.translation.height / 120.0)
                
                renderer.panSceneCamera(xNormalizedTranslation: xTranslationNormalized,
                                        yNormalizedTranslation: yTranslationNormalized)
            }
    }
    
    var body: some View {
        Image(systemName: "dot.arrowtriangles.up.right.down.left.circle")
            .resizable()
            .scaledToFit()
            .gesture(drag)
    }
}

#Preview {
    PanView(renderer: Renderer())
}
