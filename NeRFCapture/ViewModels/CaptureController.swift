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
import CoreGraphics
import ImageIO

// MARK: - Capture Settings Model

public enum ImageFormat: String, Codable, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case png = "PNG"
    
    public var id: String { self.rawValue }
}

public enum DepthFormat: String, Codable, CaseIterable, Identifiable {
    case depth32f = "Float32 Raw (.depth32f)"
    case grayscalePNG = "Grayscale 16-bit PNG"
    
    public var id: String { self.rawValue }
    
    public var fileExtension: String {
        switch self {
        case .depth32f: return "depth32f"
        case .grayscalePNG: return "depth.png"
        }
    }
}

public enum CaptureInterval: Double, Codable, CaseIterable, Identifiable {
    case continuous = 0.0
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
    private let writeQueue = DispatchQueue(label: "com.rgbd.spatialcapture.framewriter", qos: .utility)
    private let sizeTracker: DatasetSizeTracker
    
    public init(sizeTracker: DatasetSizeTracker) {
        self.sizeTracker = sizeTracker
    }
    
    public func write(pixelBuffer: CVPixelBuffer, to url: URL, format: ImageFormat, jpegQuality: Double) {
        guard let pixelBufferCopy = deepCopy(pixelBuffer: pixelBuffer) else {
            print("FrameWriter: Failed to copy pixel buffer for writing")
            return
        }
        
        writeQueue.async { [weak self] in
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
                    self?.sizeTracker.addBytes(Int64(data.count))
                } catch {
                    print("FrameWriter: Failed to write image: \(error)")
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
        
        let status = CVPixelBufferCreate(nil, width, height, format, attributes as CFDictionary, &pixelBufferCopy)
        guard status == kCVReturnSuccess, let copy = pixelBufferCopy else { return nil }
        
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
                memcpy(destAddr, srcAddr, CVPixelBufferGetBytesPerRow(pixelBuffer) * height)
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
    private let writeQueue = DispatchQueue(label: "com.rgbd.spatialcapture.depthwriter", qos: .utility)
    private let sizeTracker: DatasetSizeTracker
    
    public init(sizeTracker: DatasetSizeTracker) {
        self.sizeTracker = sizeTracker
    }
    
    public func write(depthBuffer: CVPixelBuffer, to url: URL, format: DepthFormat) {
        guard let depthCopy = deepCopy(depthBuffer: depthBuffer) else {
            print("DepthWriter: Failed to copy depth buffer")
            return
        }
        
        writeQueue.async { [weak self] in
            CVPixelBufferLockBaseAddress(depthCopy, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthCopy, .readOnly) }
            
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthCopy) else {
                print("DepthWriter: No base address for depth buffer")
                return
            }
            
            let width = CVPixelBufferGetWidth(depthCopy)
            let height = CVPixelBufferGetHeight(depthCopy)
            let count = width * height
            let floatPtr = baseAddress.bindMemory(to: Float32.self, capacity: count)
            
            switch format {
            case .depth32f:
                let data = Data(bytes: floatPtr, count: count * MemoryLayout<Float32>.size)
                do {
                    try data.write(to: url, options: .atomic)
                    self?.sizeTracker.addBytes(Int64(data.count))
                } catch {
                    print("DepthWriter: Failed to write float32 depth: \(error)")
                }
                
            case .grayscalePNG:
                // Convert Float32 depth to 16-bit grayscale PNG.
                // IMPORTANT: Must read row-by-row using bytesPerRow stride,
                // because CVPixelBuffer rows have padding bytes at the end.
                let bytesPerRow = CVPixelBufferGetBytesPerRow(depthCopy)
                let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size
                
                // First pass: find min/max for normalization (row-aware)
                var minDepth: Float = .greatestFiniteMagnitude
                var maxDepth: Float = 0.0
                for row in 0..<height {
                    let rowBase = baseAddress.advanced(by: row * bytesPerRow)
                        .bindMemory(to: Float32.self, capacity: width)
                    for col in 0..<width {
                        let v = rowBase[col]
                        if v.isFinite && v > 0 {
                            minDepth = min(minDepth, v)
                            maxDepth = max(maxDepth, v)
                        }
                    }
                }
                let range = maxDepth - minDepth
                
                // Second pass: normalize to 0–65535, store as big-endian UInt16
                var pixels = [UInt16](repeating: 0, count: width * height)
                for row in 0..<height {
                    let rowBase = baseAddress.advanced(by: row * bytesPerRow)
                        .bindMemory(to: Float32.self, capacity: width)
                    for col in 0..<width {
                        let v = rowBase[col]
                        if v.isFinite && v > 0 && range > 0 {
                            let normalized = (v - minDepth) / range
                            let val = UInt16(min(max(normalized * 65535.0, 0), 65535))
                            pixels[row * width + col] = val.bigEndian
                        }
                    }
                }
                
                // Create a 16-bit grayscale CGImage and write as PNG
                let outBytesPerRow = width * MemoryLayout<UInt16>.size
                pixels.withUnsafeMutableBufferPointer { bufferPtr in
                    guard let provider = CGDataProvider(data: Data(
                        bytesNoCopy: bufferPtr.baseAddress!,
                        count: width * height * MemoryLayout<UInt16>.size,
                        deallocator: .none
                    ) as CFData) else { return }
                    
                    guard let cgImage = CGImage(
                        width: width,
                        height: height,
                        bitsPerComponent: 16,
                        bitsPerPixel: 16,
                        bytesPerRow: outBytesPerRow,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageByteOrderInfo.order16Big.rawValue),
                        provider: provider,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: .defaultIntent
                    ) else {
                        print("DepthWriter: Failed to create 16-bit grayscale CGImage")
                        return
                    }
                    
                    let pngUTI = "public.png" as CFString
                    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, pngUTI, 1, nil) else {
                        print("DepthWriter: Failed to create PNG destination")
                        return
                    }
                    CGImageDestinationAddImage(dest, cgImage, nil)
                    if CGImageDestinationFinalize(dest) {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let size = attrs[.size] as? Int64 {
                            self?.sizeTracker.addBytes(size)
                        }
                    }
                }
            }
        }
    }
    
    private func deepCopy(depthBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let format = CVPixelBufferGetPixelFormatType(depthBuffer)
        
        var depthCopy: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(nil, width, height, format, nil, &depthCopy)
        guard status == kCVReturnSuccess, let copy = depthCopy else { return nil }
        
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        
        if let destAddr = CVPixelBufferGetBaseAddress(copy),
           let srcAddr = CVPixelBufferGetBaseAddress(depthBuffer) {
            memcpy(destAddr, srcAddr, CVPixelBufferGetBytesPerRow(depthBuffer) * height)
        }
        return copy
    }
}

// MARK: - Dataset Size Tracker

public class DatasetSizeTracker: ObservableObject {
    private let lock = NSLock()
    private var accumulatedBytes: Int64 = 0
    
    @Published public var totalBytes: Int64 = 0
    
    public init() {}
    
    public func addBytes(_ bytes: Int64) {
        lock.lock()
        accumulatedBytes += bytes
        let newTotal = accumulatedBytes
        lock.unlock()
        DispatchQueue.main.async {
            self.totalBytes = newTotal
        }
    }
    
    public func reset() {
        lock.lock()
        accumulatedBytes = 0
        lock.unlock()
        DispatchQueue.main.async {
            self.totalBytes = 0
        }
    }
    
    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

// MARK: - Metadata Writer

public class MetadataWriter {
    private let writeQueue = DispatchQueue(label: "com.rgbd.spatialcapture.metadatawriter", qos: .utility)
    private let sizeTracker: DatasetSizeTracker
    
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
    
    public init(sizeTracker: DatasetSizeTracker) {
        self.sizeTracker = sizeTracker
    }
    
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
            filePath: rgbPath, depthPath: depthPath, transformMatrix: transform,
            timestamp: timestamp, flX: flX, flY: flY, cx: cx, cy: cy, w: w, h: h
        )
        
        framesLock.lock()
        frames.append(item)
        framesLock.unlock()
        
        writeQueue.async { [weak self] in
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
            if let rgbPath = rgbPath { metadata["file_path"] = rgbPath }
            if let depthPath = depthPath { metadata["depth_path"] = depthPath }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) {
                do {
                    try jsonData.write(to: url, options: .atomic)
                    self?.sizeTracker.addBytes(Int64(jsonData.count))
                } catch {
                    print("MetadataWriter: Failed to write frame metadata: \(error)")
                }
            }
        }
    }
    
    public func finalizeSession(projectDir: URL, completion: @escaping () -> Void) {
        framesLock.lock()
        let framesToSave = self.frames
        framesLock.unlock()
        
        writeQueue.async {
            let manifest = TransformsManifest(
                w: framesToSave.first?.w ?? 0, h: framesToSave.first?.h ?? 0,
                flX: framesToSave.first?.flX ?? 1.0, flY: framesToSave.first?.flY ?? 1.0,
                cx: framesToSave.first?.cx ?? 0.0, cy: framesToSave.first?.cy ?? 0.0,
                depthIntegerScale: 1.0, depthSource: "LiDAR", cameraModel: "PINHOLE",
                frames: framesToSave
            )
            
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            
            let fileURL = projectDir.appendingPathComponent("transforms.json")
            if let data = try? encoder.encode(manifest) {
                try? data.write(to: fileURL, options: .atomic)
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
    @Published public var datasetName: String = ""
    @Published public var isExporting = false
    @Published public var exportURL: URL? = nil
    
    public let sessionManager: ARSessionManager
    public let sizeTracker = DatasetSizeTracker()
    private lazy var frameWriter = FrameWriter(sizeTracker: sizeTracker)
    private lazy var depthWriter = DepthWriter(sizeTracker: sizeTracker)
    private lazy var metadataWriter = MetadataWriter(sizeTracker: sizeTracker)
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
        let timestamp = dateFormatter.string(from: Date())
        currentProjectName = "Capture_\(timestamp)"
        
        // Use custom name if provided, otherwise use default timestamp name
        if datasetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            datasetName = currentProjectName
        }
        
        let docs = getDocumentsDirectory()
        let projectFolder = docs.appendingPathComponent(currentProjectName)
        self.projectDir = projectFolder
        
        do {
            try FileManager.default.createDirectory(
                at: projectFolder.appendingPathComponent("images"),
                withIntermediateDirectories: true
            )
        } catch {
            print("CaptureController: Failed to create project folder: \(error)")
            return
        }
        
        savedFrameCount = 0
        previousSavedTimestamp = 0.0
        exportURL = nil
        sizeTracker.reset()
        
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
                let zipName = self.datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? self.currentProjectName : self.datasetName
                
                self.exporter.export(projectDir: projectFolder, zipName: zipName) { zipURL in
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
    
    public func arSessionManager(_ manager: ARSessionManager, didChangeTrackingState state: ARCamera.TrackingState) {}
    
    private func saveFrameData(_ frame: ARFrame) {
        guard let projectFolder = projectDir else { return }
        
        if settings.maxDatasetSize != .unlimited && savedFrameCount >= settings.maxDatasetSize.rawValue {
            DispatchQueue.main.async { [weak self] in self?.stopCapture() }
            return
        }
        
        let frameIndex = savedFrameCount
        savedFrameCount += 1
        
        let idx = String(format: "%06d", frameIndex)
        let baseName = "frame_\(idx)"
        
        let hasDepth = frame.sceneDepth != nil && settings.depthEnabled && sessionManager.supportsDepth
        let hasRGB = settings.rgbEnabled
        
        var depthPath: String? = nil
        var rgbPath: String? = nil
        
        let imageExt = settings.imageFormat == .jpeg ? "jpg" : "png"
        let rgbFileName = "\(baseName).\(imageExt)"
        let depthFileName = "\(baseName).\(settings.depthFormat.fileExtension)"
        
        let imagesDir = projectFolder.appendingPathComponent("images")
        
        if hasRGB {
            rgbPath = "images/\(rgbFileName)"
            frameWriter.write(
                pixelBuffer: frame.capturedImage,
                to: imagesDir.appendingPathComponent(rgbFileName),
                format: settings.imageFormat,
                jpegQuality: settings.jpegQuality
            )
        }
        
        if hasDepth, let sceneDepth = frame.sceneDepth {
            depthPath = "images/\(depthFileName)"
            depthWriter.write(
                depthBuffer: sceneDepth.depthMap,
                to: imagesDir.appendingPathComponent(depthFileName),
                format: settings.depthFormat
            )
        }
        
        metadataWriter.writeFrameMetadata(
            frame: frame,
            frameIndex: frameIndex,
            rgbPath: rgbPath,
            depthPath: depthPath,
            to: imagesDir.appendingPathComponent("\(baseName).json")
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
            if let decoded = try? JSONDecoder().decode(CaptureSettings.self, from: data) {
                settings = decoded
            }
        }
    }
}
