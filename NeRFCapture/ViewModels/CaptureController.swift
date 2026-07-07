//
//  CaptureController.swift
//  RGB-D Spatial Capture
//

import Foundation
import ARKit
import Combine
import UIKit
import CoreVideo
import Zip

// MARK: - Capture Settings Model

public enum ImageFormat: String, Codable, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case png = "PNG"
    
    public var id: String { self.rawValue }
}

public enum DepthFormat: String, Codable, CaseIterable, Identifiable {
    case depth32f = ".depth32f"
    
    public var id: String { self.rawValue }
}

public enum CaptureInterval: Double, Codable, CaseIterable, Identifiable {
    case continuous = 0.0 // 60 FPS
    case interval0_1 = 0.1
    case interval0_2 = 0.2
    case interval0_5 = 0.5
    case interval1_0 = 1.0
    case manual = -1.0
    
    public var id: Double { self.rawValue }
    
    public var displayName: String {
        switch self {
        case .continuous: return "Continuous (60 FPS)"
        case .interval0_1: return "0.1 sec"
        case .interval0_2: return "0.2 sec"
        case .interval0_5: return "0.5 sec"
        case .interval1_0: return "1.0 sec"
        case .manual: return "Manual"
        }
    }
}

public enum MaxDatasetLimit: Int, Codable, CaseIterable, Identifiable {
    case unlimited = 0
    case limit100 = 100
    case limit500 = 500
    case limit1000 = 1000
    case limit5000 = 5000
    
    public var id: Int { self.rawValue }
    
    public var displayName: String {
        switch self {
        case .unlimited: return "Unlimited"
        default: return "\(self.rawValue) frames"
        }
    }
}

public struct CaptureSettings: Codable {
    public var captureInterval: CaptureInterval = .interval0_5
    public var depthEnabled: Bool = true
    public var rgbEnabled: Bool = true
    public var autoExport: Bool = true
    public var imageFormat: ImageFormat = .jpeg
    public var jpegQuality: Double = 0.8
    public var depthFormat: DepthFormat = .depth32f
    public var maxDatasetSize: MaxDatasetLimit = .unlimited
    
    public init() {}
}

// MARK: - Frame Writer

public class FrameWriter {
    private let writeQueue = DispatchQueue(label: "com.rgbd.spatialcapture.framewriter", qos: .background)
    
    public init() {}
    
    public func write(pixelBuffer: CVPixelBuffer, to url: URL, format: ImageFormat, jpegQuality: Double) {
        guard let pixelBufferCopy = deepCopy(pixelBuffer: pixelBuffer) else {
            print("FrameWriter: Failed to copy pixel buffer for writing")
            return
        }
        
        writeQueue.async {
            let ciImage = CIImage(cvPixelBuffer: pixelBufferCopy)
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("FrameWriter: Failed to create CGImage from pixel buffer")
                return
            }
            let uiImage = UIImage(cgImage: cgImage)
            
            let data: Data?
            switch format {
            case .jpeg:
                data = uiImage.jpegData(compressionQuality: CGFloat(jpegQuality))
            case .png:
                data = uiImage.pngData()
            }
            
            if let data = data {
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("FrameWriter: Failed to write image data to \(url): \(error)")
                }
            }
        }
    }
    
    private func deepCopy(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        var pixelBufferCopy: CVPixelBuffer? = nil
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            format,
            attributes as CFDictionary,
            &pixelBufferCopy
        )
        
        guard status == kCVReturnSuccess, let copy = pixelBufferCopy else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        if planeCount == 0 {
            if let destAddr = CVPixelBufferGetBaseAddress(copy),
               let srcAddr = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytes = CVPixelBufferGetBytesPerRow(pixelBuffer) * height
                memcpy(destAddr, srcAddr, bytes)
            }
        } else {
            for plane in 0..<planeCount {
                if let destAddr = CVPixelBufferGetBaseAddressOfPlane(copy, plane),
                   let srcAddr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) {
                    let bytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane) * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                    memcpy(destAddr, srcAddr, bytes)
                }
            }
        }
        
        return copy
    }
}

// MARK: - Depth Writer

public class DepthWriter {
    private let writeQueue = DispatchQueue(label: "com.rgbd.spatialcapture.depthwriter", qos: .background)
    
    public init() {}
    
    public func write(depthBuffer: CVPixelBuffer, to url: URL, format: DepthFormat) {
        guard let depthCopy = deepCopy(depthBuffer: depthBuffer) else {
            print("DepthWriter: Failed to copy depth buffer")
            return
        }
        
        writeQueue.async {
            switch format {
            case .depth32f:
                CVPixelBufferLockBaseAddress(depthCopy, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(depthCopy, .readOnly) }
                
                guard CVPixelBufferGetPixelFormatType(depthCopy) == kCVPixelFormatType_DepthFloat32,
                      let baseAddress = CVPixelBufferGetBaseAddress(depthCopy) else {
                    print("DepthWriter: Depth buffer is not Float32 depth format")
                    return
                }
                
                let width = CVPixelBufferGetWidth(depthCopy)
                let height = CVPixelBufferGetHeight(depthCopy)
                let count = width * height
                let floatPtr = baseAddress.bindMemory(to: Float32.self, capacity: count)
                let data = Data(bytes: floatPtr, count: count * MemoryLayout<Float32>.size)
                
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("DepthWriter: Failed to write float32 depth map: \(error)")
                }
            }
        }
    }
    
    private func deepCopy(depthBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let format = CVPixelBufferGetPixelFormatType(depthBuffer)
        
        var depthCopy: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            format,
            nil,
            &depthCopy
        )
        
        guard status == kCVReturnSuccess, let copy = depthCopy else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        
        if let destAddr = CVPixelBufferGetBaseAddress(copy),
           let srcAddr = CVPixelBufferGetBaseAddress(depthBuffer) {
            let bytes = CVPixelBufferGetBytesPerRow(depthBuffer) * height
            memcpy(destAddr, srcAddr, bytes)
        }
        
        return copy
    }
}

// MARK: - Metadata Writer

public class MetadataWriter {
    private let writeQueue = DispatchQueue(label: "com.rgbd.spatialcapture.metadatawriter", qos: .background)
    
    public struct TransformsManifest: Codable {
        public var w: Int = 0
        public var h: Int = 0
        public var flX: Float = 0
        public var flY: Float = 0
        public var cx: Float = 0
        public var cy: Float = 0
        public var depthIntegerScale: Float? = 1.0
        public var depthSource: String? = "LiDAR"
        public var cameraModel: String? = "PINHOLE"
        public var frames: [FrameItem] = []
    }
    
    public struct FrameItem: Codable {
        public let filePath: String?
        public let depthPath: String?
        public let transformMatrix: [[Float]]
        public let timestamp: TimeInterval
        public let flX: Float
        public let flY: Float
        public let cx: Float
        public let cy: Float
        public let w: Int
        public let h: Int
    }
    
    private var frames: [FrameItem] = []
    private let framesLock = NSLock()
    
    public init() {}
    
    public func startSession(projectDir: URL) {
        framesLock.lock()
        frames.removeAll()
        framesLock.unlock()
    }
    
    public func writeFrameMetadata(
        frame: ARFrame,
        frameIndex: Int,
        rgbPath: String?,
        depthPath: String?,
        to url: URL
    ) {
        let timestamp = frame.timestamp
        let transform = arrayFromTransform(frame.camera.transform)
        let intrinsics = arrayFromTransform(frame.camera.intrinsics)
        let w = Int(frame.camera.imageResolution.width)
        let h = Int(frame.camera.imageResolution.height)
        let flX = frame.camera.intrinsics[0, 0]
        let flY = frame.camera.intrinsics[1, 1]
        let cx = frame.camera.intrinsics[2, 0]
        let cy = frame.camera.intrinsics[2, 1]
        let trackingState = trackingStateToString(frame.camera.trackingState)
        
        let exposureDuration = frame.camera.exposureDuration
        let exposureOffset = frame.camera.exposureOffset
        
        let depthWidth = frame.sceneDepth != nil ? CVPixelBufferGetWidth(frame.sceneDepth!.depthMap) : 0
        let depthHeight = frame.sceneDepth != nil ? CVPixelBufferGetHeight(frame.sceneDepth!.depthMap) : 0
        
        let item = FrameItem(
            filePath: rgbPath,
            depthPath: depthPath,
            transformMatrix: transform,
            timestamp: timestamp,
            flX: flX,
            flY: flY,
            cx: cx,
            cy: cy,
            w: w,
            h: h
        )
        
        framesLock.lock()
        frames.append(item)
        framesLock.unlock()
        
        writeQueue.async {
            var metadata: [String: Any] = [
                "frame_index": frameIndex,
                "timestamp": timestamp,
                "camera_transform": transform,
                "camera_intrinsics": intrinsics,
                "image_resolution": ["w": w, "h": h],
                "depth_resolution": ["w": depthWidth, "h": depthHeight],
                "tracking_state": trackingState,
                "exposure_duration": exposureDuration,
                "exposure_offset": exposureOffset
            ]
            
            if let rgbPath = rgbPath {
                metadata["file_path"] = rgbPath
            }
            if let depthPath = depthPath {
                metadata["depth_path"] = depthPath
            }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) {
                do {
                    try jsonData.write(to: url, options: .atomic)
                } catch {
                    print("MetadataWriter: Failed to write frame metadata to \(url): \(error)")
                }
            }
        }
    }
    
    public func finalizeSession(projectDir: URL, completion: @escaping () -> Void) {
        framesLock.lock()
        let framesToSave = self.frames
        framesLock.unlock()
        
        writeQueue.async {
            let w = framesToSave.first?.w ?? 0
            let h = framesToSave.first?.h ?? 0
            let flX = framesToSave.first?.flX ?? 1.0
            let flY = framesToSave.first?.flY ?? 1.0
            let cx = framesToSave.first?.cx ?? 0.0
            let cy = framesToSave.first?.cy ?? 0.0
            
            let manifest = TransformsManifest(
                w: w,
                h: h,
                flX: flX,
                flY: flY,
                cx: cx,
                cy: cy,
                depthIntegerScale: 1.0,
                depthSource: "LiDAR",
                cameraModel: "PINHOLE",
                frames: framesToSave
            )
            
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            
            let fileURL = projectDir.appendingPathComponent("transforms.json")
            if let data = try? encoder.encode(manifest) {
                do {
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    print("MetadataWriter: Failed to write transforms.json: \(error)")
                }
            }
            
            completion()
        }
    }
}

// MARK: - Dataset Exporter

public class DatasetExporter {
    private let exportQueue = DispatchQueue(label: "com.rgbd.spatialcapture.datasetexporter", qos: .userInitiated)
    
    public init() {}
    
    public func export(projectDir: URL, zipName: String, completion: @escaping (URL?) -> Void) {
        exportQueue.async {
            do {
                let zipURL = try Zip.quickZipFiles([projectDir], fileName: zipName)
                try FileManager.default.removeItem(at: projectDir)
                completion(zipURL)
            } catch {
                print("DatasetExporter: Failed to export dataset: \(error)")
                completion(nil)
            }
        }
    }
}

// MARK: - Capture Controller

public class CaptureController: NSObject, ARSessionManagerDelegate, ObservableObject {
    @Published public var settings = CaptureSettings()
    @Published public var isRecording = false
    @Published public var savedFrameCount = 0
    @Published public var currentProjectName: String = ""
    @Published public var isExporting = false
    @Published public var exportURL: URL? = nil
    
    public let sessionManager: ARSessionManager
    private let frameWriter = FrameWriter()
    private let depthWriter = DepthWriter()
    private let metadataWriter = MetadataWriter()
    private let exporter = DatasetExporter()
    
    private var previousSavedTimestamp: TimeInterval = 0.0
    private var projectDir: URL? = nil
    
    public init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
        super.init()
        self.sessionManager.delegate = self
        loadSettings()
    }
    
    public func startCapture() {
        guard !isRecording else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        currentProjectName = "Capture_\(dateFormatter.string(from: Date()))"
        
        let docs = getDocumentsDirectory()
        let projectFolder = docs.appendingPathComponent(currentProjectName)
        self.projectDir = projectFolder
        
        do {
            try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("images"), withIntermediateDirectories: true)
        } catch {
            print("CaptureController: Failed to create project folder: \(error)")
            return
        }
        
        savedFrameCount = 0
        previousSavedTimestamp = 0.0
        exportURL = nil
        
        metadataWriter.startSession(projectDir: projectFolder)
        
        isRecording = true
    }
    
    public func stopCapture() {
        guard isRecording else { return }
        isRecording = false
        
        guard let projectFolder = projectDir else { return }
        
        isExporting = true
        
        metadataWriter.finalizeSession(projectDir: projectFolder) { [weak self] in
            guard let self = self else { return }
            
            if self.settings.autoExport {
                self.exporter.export(projectDir: projectFolder, zipName: self.currentProjectName) { zipURL in
                    DispatchQueue.main.async {
                        self.isExporting = false
                        self.exportURL = zipURL
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isExporting = false
                }
            }
        }
    }
    
    public func cancelCapture() {
        guard isRecording else { return }
        isRecording = false
        savedFrameCount = 0
        previousSavedTimestamp = 0.0
        
        guard let projectFolder = projectDir else { return }
        
        DispatchQueue.global(qos: .background).async {
            try? FileManager.default.removeItem(at: projectFolder)
        }
    }
    
    public func triggerManualSave() {
        guard isRecording else { return }
        if let frame = sessionManager.session.currentFrame {
            saveFrameData(frame)
        }
    }
    
    // MARK: - ARSessionManagerDelegate
    
    public func arSessionManager(_ manager: ARSessionManager, didUpdateFrame frame: ARFrame) {
        guard isRecording else { return }
        
        let currentTimestamp = frame.timestamp
        
        switch settings.captureInterval {
        case .continuous:
            saveFrameData(frame)
        case .manual:
            break
        default:
            let interval = settings.captureInterval.rawValue
            if previousSavedTimestamp == 0.0 {
                previousSavedTimestamp = currentTimestamp
                saveFrameData(frame)
            } else if (currentTimestamp - previousSavedTimestamp) >= interval {
                previousSavedTimestamp = currentTimestamp
                saveFrameData(frame)
            }
        }
    }
    
    public func arSessionManager(_ manager: ARSessionManager, didChangeTrackingState state: ARCamera.TrackingState) {
    }
    
    private func saveFrameData(_ frame: ARFrame) {
        guard let projectFolder = projectDir else { return }
        
        if settings.maxDatasetSize != .unlimited && savedFrameCount >= settings.maxDatasetSize.rawValue {
            DispatchQueue.main.async { [weak self] in
                self?.stopCapture()
            }
            return
        }
        
        let frameIndex = savedFrameCount
        savedFrameCount += 1
        
        let frameIndexStr = String(format: "%06d", frameIndex)
        let baseImageName = "frame_\(frameIndexStr)"
        
        let hasDepth = frame.sceneDepth != nil && settings.depthEnabled && sessionManager.supportsDepth
        let hasRGB = settings.rgbEnabled
        
        var depthPath: String? = nil
        var rgbPath: String? = nil
        
        let imageExt = settings.imageFormat == .jpeg ? "jpg" : "png"
        let rgbFileName = "\(baseImageName).\(imageExt)"
        let depthFileName = "\(baseImageName).\(settings.depthFormat.rawValue)"
        
        let imagesDir = projectFolder.appendingPathComponent("images")
        
        if hasRGB {
            rgbPath = "images/\(rgbFileName)"
            let rgbURL = imagesDir.appendingPathComponent(rgbFileName)
            frameWriter.write(
                pixelBuffer: frame.capturedImage,
                to: rgbURL,
                format: settings.imageFormat,
                jpegQuality: settings.jpegQuality
            )
        }
        
        if hasDepth, let sceneDepth = frame.sceneDepth {
            depthPath = "images/\(depthFileName)"
            let depthURL = imagesDir.appendingPathComponent(depthFileName)
            depthWriter.write(
                depthBuffer: sceneDepth.depthMap,
                to: depthURL,
                format: settings.depthFormat
            )
        }
        
        let jsonURL = imagesDir.appendingPathComponent("\(baseImageName).json")
        metadataWriter.writeFrameMetadata(
            frame: frame,
            frameIndex: frameIndex,
            rgbPath: rgbPath,
            depthPath: depthPath,
            to: jsonURL
        )
    }
    
    // MARK: - Settings Persistence
    
    public func saveSettings() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(settings) {
            UserDefaults.standard.set(data, forKey: "captureSettings")
        }
    }
    
    public func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "captureSettings") {
            do {
                let decoder = JSONDecoder()
                settings = try decoder.decode(CaptureSettings.self, from: data)
            } catch {
                print("CaptureController: Failed to load settings: \(error)")
                settings = CaptureSettings()
            }
        }
    }
}

// MARK: - CVPixelBuffer Dimensions Helper

extension CVPixelBuffer {
    var width: Int { CVPixelBufferGetWidth(self) }
    var height: Int { CVPixelBufferGetHeight(self) }
}
