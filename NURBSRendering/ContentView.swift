//
//  ContentView.swift
//  NURBSRendering
//
//  Created by Reza on 10/23/23.
//

import SwiftUI

struct ContentView: View {
    @StateObject var renderer = Renderer()
    @State private var tryToPickControlPoint: Bool = true
    @State private var rendererViewSize: CGSize = .zero
    @State private var startDragLocation: CGPoint? = nil
    
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                let xTranslationNormalized = value.translation.width / 120.0
                let yTranslationNormalized = value.translation.height / 120.0
                
                renderer.rotateSceneCamera(xNormalizedTranslation: Float(xTranslationNormalized),
                                          yNormalizedTranslation: Float(yTranslationNormalized))
            }
    }
    
    private var rendererDrag: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                if tryToPickControlPoint {
                    tryToPickControlPoint = false
                    // try picking control point
                    let relativePickPoint: CGPoint = .init(x: value.location.x / rendererViewSize.width,
                                                           y: value.location.y / rendererViewSize.height)
                    renderer.pickControlPoint(screenRelPos: relativePickPoint)
                    
                    startDragLocation = value.location
                } else {
                    // try moving control point
                    var xTranslation = value.location.x - startDragLocation!.x
                    var yTranslation = value.location.y - startDragLocation!.y
                    xTranslation /= rendererViewSize.width
                    yTranslation /= rendererViewSize.height
                    
                    renderer.moveControlPoints(xTranslation: Float(xTranslation),
                                               yTranslation: Float(yTranslation))
                    startDragLocation = value.location
                }
            }
            .onEnded { value in
                tryToPickControlPoint = true
                startDragLocation = nil
            }
    }
    
    private var cubeViewDoubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { Void in
                print("aligning...")
                renderer.alignCamera()
            }
    }
    
    private func zoomIn() {
        renderer.zoomCamera()
    }
    
    private func zoomOut() {
        renderer.zoomOutCamera()
    }
    
    private func topView() {
        renderer.topView()
    }
    
    private func leftView() {
        renderer.leftView()
    }
    
    private func rightView() {
        renderer.rightView()
    }
    
    private func bottomView() {
        renderer.bottomView()
    }
    
    var body: some View {
        HStack {
            ZStack {
                GeometryReader { geometry in
                    MTKViewContainer(renderer: renderer)
                        .onChange(of: geometry.size) { _, newValue in
                            rendererViewSize = newValue
                        }
                        .gesture(rendererDrag)
                }
                
                VStack {
                    HStack {
                        Spacer()
                        /*
                        PanView(renderer: renderer)
                            .frame(width: 120, height: 120)
                            .padding()*/
                    }
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        ZStack {
                            /*
                            CubeView(renderer: renderer)
                                .clipShape(Circle())
                                .gesture(drag)*/
                            VStack {
                                Button(action: {topView()}) {
                                    Image(systemName: "circle.grid.cross.up.filled")
                                }
                                Spacer()
                                HStack {
                                    Button(action: {leftView()}) {
                                        Image(systemName: "circle.grid.cross.left.filled")
                                    }
                                    Spacer()
                                    Button(action: {rightView()}) {
                                        Image(systemName: "circle.grid.cross.right.filled")
                                    }
                                }
                                Spacer()
                                HStack {
                                    Button(action: {zoomIn()}) {
                                        Image(systemName: "plus.magnifyingglass")
                                            .foregroundStyle(.black)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {bottomView()}) {
                                        Image(systemName: "circle.grid.cross.down.filled")
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {zoomOut()}) {
                                        Image(systemName: "minus.magnifyingglass")
                                            .foregroundStyle(.black)
                                    }
                                }
                            }
                        }
                        .frame(width: 150, height: 150)
                        .padding()
                    }
                }
            }
            
            RightBar(renderer: renderer)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
