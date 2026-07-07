//
//  ARSessionManager.swift
//  RGB-D Spatial Capture
//

import Foundation
import ARKit
import Combine


public protocol ARSessionManagerDelegate: AnyObject {
    func arSessionManager(_ manager: ARSessionManager, didUpdateFrame frame: ARFrame)
    func arSessionManager(_ manager: ARSessionManager, didChangeTrackingState state: ARCamera.TrackingState)
}

public class ARSessionManager: NSObject, ARSessionDelegate, ObservableObject {
    public var session: ARSession = ARSession()
    public weak var delegate: ARSessionManagerDelegate?
    
    @Published public var trackingState: String = "Not Available"
    @Published public var supportsDepth: Bool = false
    
    public override init() {
        super.init()
        self.session.delegate = self
    }
    
    public func start() {
        let configuration = createARConfiguration()
        #if !targetEnvironment(simulator)
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        #endif
    }
    
    public func pause() {
        session.pause()
    }
    
    public func reset() {
        session.pause()
        let configuration = createARConfiguration()
        #if !targetEnvironment(simulator)
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        #endif
    }
    
    private func selectBestWideAngleVideoFormat() -> ARConfiguration.VideoFormat? {
        let supportedFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        return supportedFormats.max { lhs, rhs in
            let lhsPixels = lhs.imageResolution.width * lhs.imageResolution.height
            let rhsPixels = rhs.imageResolution.width * rhs.imageResolution.height
            if lhsPixels != rhsPixels {
                return lhsPixels < rhsPixels
            }
            return lhs.framesPerSecond < rhs.framesPerSecond
        }
    }

    public func createARConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = .sceneDepth
            DispatchQueue.main.async {
                self.supportsDepth = true
            }
        } else {
            DispatchQueue.main.async {
                self.supportsDepth = false
            }
        }

        if let bestFormat = selectBestWideAngleVideoFormat() {
            configuration.videoFormat = bestFormat
        }

        return configuration
    }
    
    // MARK: - ARSessionDelegate
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        delegate?.arSessionManager(self, didUpdateFrame: frame)
    }
    
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let stateStr = trackingStateToString(camera.trackingState)
        DispatchQueue.main.async {
            self.trackingState = stateStr
        }
        delegate?.arSessionManager(self, didChangeTrackingState: camera.trackingState)
    }
}
