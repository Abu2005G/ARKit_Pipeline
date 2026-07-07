//
//  ARViewContainer.swift
//  RGB-D Spatial Capture
//

import SwiftUI
import RealityKit
#if canImport(ARKit)
import ARKit
#endif

public struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARViewModel
    
    public init(_ vm: ARViewModel) {
        viewModel = vm
    }
    
    public func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Assign the ARView's session to our session manager FIRST,
        // then configure and run it. This ensures the delegate, the
        // session manager, and the ARView all share the same ARSession.
        viewModel.sessionManager.session = arView.session
        arView.session.delegate = viewModel.sessionManager
        
        #if !targetEnvironment(simulator)
        let configuration = viewModel.sessionManager.createARConfiguration()
        arView.session.run(configuration)
        #endif
        
        arView.debugOptions = [.showWorldOrigin]
        
        return arView
    }
    
    public func updateUIView(_ uiView: ARView, context: Context) {}
}
