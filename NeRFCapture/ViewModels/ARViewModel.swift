//
//  ARViewModel.swift
//  RGB-D Spatial Capture
//

import Foundation
import Combine
import ARKit

public class ARViewModel: ObservableObject {
    public let sessionManager: ARSessionManager
    public let captureController: CaptureController
    
    @Published public var trackingState: String = "Not Available"
    @Published public var supportsDepth: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var savedFrameCount: Int = 0
    @Published public var currentProjectName: String = ""
    @Published public var isExporting: Bool = false
    @Published public var exportURL: URL? = nil
    
    public var session: ARSession { sessionManager.session }
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        let manager = ARSessionManager()
        self.sessionManager = manager
        self.captureController = CaptureController(sessionManager: manager)
        
        setupObservers()
    }
    
    private func setupObservers() {
        sessionManager.$trackingState
            .receive(on: RunLoop.main)
            .assign(to: \.trackingState, on: self)
            .store(in: &cancellables)
        
        sessionManager.$supportsDepth
            .receive(on: RunLoop.main)
            .assign(to: \.supportsDepth, on: self)
            .store(in: &cancellables)
        
        captureController.$isRecording
            .receive(on: RunLoop.main)
            .assign(to: \.isRecording, on: self)
            .store(in: &cancellables)
        
        captureController.$savedFrameCount
            .receive(on: RunLoop.main)
            .assign(to: \.savedFrameCount, on: self)
            .store(in: &cancellables)
        
        captureController.$currentProjectName
            .receive(on: RunLoop.main)
            .assign(to: \.currentProjectName, on: self)
            .store(in: &cancellables)
        
        captureController.$isExporting
            .receive(on: RunLoop.main)
            .assign(to: \.isExporting, on: self)
            .store(in: &cancellables)
        
        captureController.$exportURL
            .receive(on: RunLoop.main)
            .assign(to: \.exportURL, on: self)
            .store(in: &cancellables)
    }
    
    public func startCapture() {
        captureController.startCapture()
    }
    
    public func stopCapture() {
        captureController.stopCapture()
    }
    
    public func cancelCapture() {
        captureController.cancelCapture()
    }
    
    public func triggerManualSave() {
        captureController.triggerManualSave()
    }
    
    public func resetWorldOrigin() {
        sessionManager.reset()
    }
}
