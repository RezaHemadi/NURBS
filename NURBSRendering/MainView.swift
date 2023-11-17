//
//  MainView.swift
//  NURBSRendering
//
//  Created by Reza on 11/7/23.
//

import SwiftUI
import RenderTools
import Matrix

struct MainView: View {
    @StateObject var camControl = HLCameraController()
    @StateObject var session = HLNurbsSession()
    @State private var sessionSize: CGSize = .init(width: 800.0, height: 800.0)
    
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0.0)
            .onChanged { value in
                let xTranslationNormalized = value.translation.width / 120.0
                let yTranslationNormalized = value.translation.height / 120.0
                
                camControl.arcballRotate(xNormalized: Float(xTranslationNormalized),
                                         yNormalized: Float(yTranslationNormalized))
            }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HLCurveRenderer(camera: $camControl.camera,
                                geometries: $session.geometries,
                                bodies: $session.bodies,
                                wireframe: $session.wireframe,
                                renderControlPoints: $session.showControlPoints,
                                selectedControlPoints: $session.selectedControlPoints,
                                showAxes: $session.showAxes,
                                snapToGrid: $session.snapToGrid,
                                sessionConfig: $session.sessionConfig)
                
                if session.showNewCurveView {
                    NewCurveView(session: session)
                }
                
                if session.showNewSurfaceView {
                    NewSurfaceView(session: session)
                }
                
                VStack {
                    HStack(alignment: .top) {
                        // wireframe mode control
                        Button(action: {session.wireframe.toggle()}) {
                            Image(systemName: !session.wireframe ? "rectangle.split.3x3" : "rectangle.fill")
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .padding(4.0)
                        
                        // show control points
                        Button(action: {session.showControlPoints.toggle()}) {
                            Image(systemName: !session.showControlPoints ? "point.3.connected.trianglepath.dotted" :
                                                                          "point.3.filled.connected.trianglepath.dotted")
                            .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .padding(4.0)
                        
                        // show axes
                        Button(action: {session.showAxes.toggle()}) {
                            Image(systemName: "move.3d")
                                .imageScale(.large)
                                .foregroundStyle(session.showAxes ? Color.teal : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(4.0)
                        
                        // snap to grid
                        Button(action: {session.snapToGrid.toggle()}) {
                            Text("Snap")
                                .foregroundStyle(session.snapToGrid ? Color.teal : Color.secondary)
                        }
                        .padding(4.0)
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                        PanView(camControl: camControl)
                            .frame(width: sessionSize.width / 9.0, height: sessionSize.width / 9.0)
                            .padding()
                    }
                    Spacer()
                    HStack {
                        ToolsPanelView(session: session)
                            .frame(height: sessionSize.height / 4.0, alignment: .top)
                            .padding()
                        Spacer()
                        VStack {
                            ObjectsViewer(session: session)
                                .frame(width: sessionSize.width / 7.0, height: sessionSize.height / 4.0)
                                .padding()
                            AttributesView(transform: $session.objectForAttributes.transform)
                                .frame(width: sessionSize.width / 7.0, height: sessionSize.height / 4.0)
                                .padding()
                                .disabled(session.selectedObject == nil)
                        }
                    }
                    Spacer()
                    
                    HStack {
                        Spacer()
                        ZStack {
                            CubeView(camera: $camControl.camera)
                                .clipShape(Circle())
                                .gesture(drag)
                            VStack {
                                Button(action: {camControl.topView()}) {
                                    Image(systemName: "circle.grid.cross.up.filled")
                                }
                                Spacer()
                                HStack {
                                    Button(action: {camControl.leftView()}) {
                                        Image(systemName: "circle.grid.cross.left.filled")
                                    }
                                    Spacer()
                                    Button(action: {camControl.rightView()}) {
                                        Image(systemName: "circle.grid.cross.right.filled")
                                    }
                                }
                                Spacer()
                                HStack {
                                    Button(action: {camControl.zoomIn()}) {
                                        Image(systemName: "plus.magnifyingglass")
                                            .foregroundStyle(.black)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {camControl.bottomView()}) {
                                        Image(systemName: "circle.grid.cross.down.filled")
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {camControl.zoomOut()}) {
                                        Image(systemName: "minus.magnifyingglass")
                                            .foregroundStyle(.black)
                                    }
                                }
                            }
                        }
                        .frame(width: sessionSize.width / 9.0, height: sessionSize.width / 9.0)
                        .padding()
                    }
                }
            }
            .onChange(of: geometry.size) { oldValue, newValue in
                sessionSize = geometry.size
            }
        }
    }
}

#Preview {
    MainView()
}
