//
//  ARView.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import SwiftUI
import RealityKit
#if canImport(ARKit)
import ARKit
#endif

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARViewModel
    
    init(_ vm: ARViewModel) {
        viewModel = vm
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        #if canImport(ARKit)
        let configuration = viewModel.createARConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            viewModel.appState.supportsDepth = true
        }

        #if !targetEnvironment(simulator)
        arView.session.run(configuration)
        #endif
        #endif

        arView.debugOptions = [.showWorldOrigin]
        arView.session.delegate = viewModel
        viewModel.session = arView.session
        viewModel.arView = arView
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}
