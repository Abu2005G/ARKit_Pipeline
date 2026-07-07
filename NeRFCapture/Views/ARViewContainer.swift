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
        
        #if canImport(ARKit) && !targetEnvironment(simulator)
        // Create a default ARWorldTrackingConfiguration if available
        if ARWorldTrackingConfiguration.isSupported {
            let configuration = ARWorldTrackingConfiguration()
            configuration.environmentTexturing = .automatic
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            arView.session.run(configuration)
        }
        #endif
        
        arView.debugOptions = [.showWorldOrigin]
        arView.session.delegate = (viewModel.sessionManager as! any ARSessionDelegate)
        
        return arView
    }
    
    public func updateUIView(_ uiView: ARView, context: Context) {}
}

