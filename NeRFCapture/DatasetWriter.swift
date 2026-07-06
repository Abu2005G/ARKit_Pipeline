//
//  DatasetWriter.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 11/1/2023.
//

import Foundation
import ARKit
import Zip

extension UIImage {
    func resizeImageTo(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        self.draw(in: CGRect(origin: CGPoint.zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return resizedImage
    }
}

class DatasetWriter {
    
    enum SessionState {
        case SessionNotStarted
        case SessionStarted
    }
    
    var manifest = Manifest()
    var projectName = ""
    var projectDir = getDocumentsDirectory()
    var useDepthIfAvailable = true
    
    @Published var currentFrameCounter = 0
    @Published var writerState = SessionState.SessionNotStarted
    
    func projectExists(_ projectDir: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: projectDir.path, isDirectory: &isDir) && isDir.boolValue
    }
    
    func initializeProject() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYMMddHHmmss"
        projectName = dateFormatter.string(from: Date())
        projectDir = getDocumentsDirectory()
            .appendingPathComponent(projectName)
        if projectExists(projectDir) {
            throw AppError.projectAlreadyExists
        }
        do {
            try FileManager.default.createDirectory(at: projectDir.appendingPathComponent("images"), withIntermediateDirectories: true)
        }
        catch {
            print(error)
        }
        
        manifest = Manifest()
        
        // The first frame will set these properly
        manifest.w = 0
        manifest.h = 0
        
        // These don't matter since every frame will redefine them
        manifest.flX = 1.0
        manifest.flY =  1.0
        manifest.cx =  320
        manifest.cy =  240
        
        manifest.depthIntegerScale = 1.0
        writerState = .SessionStarted
    }
    
    func clean() {
        guard case .SessionStarted = writerState else { return; }
        writerState = .SessionNotStarted
        DispatchQueue.global().async {
            do {
                try FileManager.default.removeItem(at: self.projectDir)
            }
            catch {
                print("Could not cleanup project files")
            }
        }
    }
    
    func finalizeProject(zip: Bool = true) {
        writerState = .SessionNotStarted
        let manifest_path = getDocumentsDirectory()
            .appendingPathComponent(projectName)
            .appendingPathComponent("transforms.json")
        
        writeManifestToPath(path: manifest_path)
        DispatchQueue.global().async {
            do {
                if zip {
                    let _ = try Zip.quickZipFiles([self.projectDir], fileName: self.projectName)
                }
                try FileManager.default.removeItem(at: self.projectDir)
            }
            catch {
                print("Could not zip")
            }
        }
    }
    
    func getCurrentFrameName() -> String {
        let frameName = String(currentFrameCounter)
        return frameName
    }
    
    func getFrameMetadata(_ frame: ARFrame, withDepth: Bool = false) -> Manifest.Frame {
        let frameName = getCurrentFrameName()
        let filePath = "images/\(frameName)"
        let depthPath = "images/\(frameName).depth32f"
        let manifest_frame = Manifest.Frame(
            filePath: filePath,
            depthPath: withDepth ? depthPath : nil,
            transformMatrix: arrayFromTransform(frame.camera.transform),
            timestamp: frame.timestamp,
            flX:  frame.camera.intrinsics[0, 0],
            flY:  frame.camera.intrinsics[1, 1],
            cx:  frame.camera.intrinsics[2, 0],
            cy:  frame.camera.intrinsics[2, 1],
            w: Int(frame.camera.imageResolution.width),
            h: Int(frame.camera.imageResolution.height)
        )
        return manifest_frame
    }
    
    private func saveFloat32DepthBuffer(_ depthBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(depthBuffer) == kCVPixelFormatType_DepthFloat32,
              let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer)
        else {
            throw NSError(domain: "DatasetWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Depth buffer is not Float32 depth format."])
        }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let count = width * height
        let floatPtr = baseAddress.bindMemory(to: Float32.self, capacity: count)
        let data = Data(bytes: floatPtr, count: count * MemoryLayout<Float32>.size)
        try data.write(to: url, options: .atomic)
    }

    private func writeFrameMetadata(_ frame: ARFrame, jsonURL: URL, depthPath: String?, rgbPath: String) {
        let metadata: [String: Any] = [
            "file_path": rgbPath,
            "depth_path": depthPath as Any,
            "transform_matrix": arrayFromTransform(frame.camera.transform),
            "timestamp": frame.timestamp,
            "fl_x": frame.camera.intrinsics[0, 0],
            "fl_y": frame.camera.intrinsics[1, 1],
            "cx": frame.camera.intrinsics[2, 0],
            "cy": frame.camera.intrinsics[2, 1],
            "w": Int(frame.camera.imageResolution.width),
            "h": Int(frame.camera.imageResolution.height)
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) {
            try? jsonData.write(to: jsonURL, options: .atomic)
        }
    }

    func writeManifestToPath(path: URL) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .withoutEscapingSlashes
        if let encoded = try? encoder.encode(manifest) {
            do {
                try encoded.write(to: path)
            } catch {
                print(error)
            }
        }
    }
    
    func writeFrameToDisk(frame: ARFrame, useDepthIfAvailable: Bool = true) {
        let baseName = "\(getCurrentFrameName())"
        let rgbFileName = "\(baseName).png"
        let depthPngFileName = "\(baseName).depth.png"
        let depthFloatFileName = "\(baseName).depth32f"
        let jsonFileName = "\(baseName).json"

        let baseDir = projectDir.appendingPathComponent("images")
        let rgbURL = baseDir.appendingPathComponent(rgbFileName)
        let depthPngURL = baseDir.appendingPathComponent(depthPngFileName)
        let depthFloatURL = baseDir.appendingPathComponent(depthFloatFileName)
        let jsonURL = baseDir.appendingPathComponent(jsonFileName)

        if manifest.w == 0 {
            manifest.w = Int(frame.camera.imageResolution.width)
            manifest.h = Int(frame.camera.imageResolution.height)
            manifest.flX = frame.camera.intrinsics[0, 0]
            manifest.flY = frame.camera.intrinsics[1, 1]
            manifest.cx = frame.camera.intrinsics[2, 0]
            manifest.cy = frame.camera.intrinsics[2, 1]
        }

        let useDepth = frame.sceneDepth != nil && useDepthIfAvailable
        let frameMetadata = getFrameMetadata(frame, withDepth: useDepth)
        let rgbBuffer = pixelBufferToUIImage(pixelBuffer: frame.capturedImage)

        DispatchQueue.global().async {
            do {
                if let rgbData = rgbBuffer.pngData() {
                    try rgbData.write(to: rgbURL, options: .atomic)
                }

                if useDepth, let sceneDepth = frame.sceneDepth {
                    if let depthImage = pixelBufferToUIImage(pixelBuffer: sceneDepth.depthMap).resizeImageTo(size: frame.camera.imageResolution),
                       let depthPngData = depthImage.pngData() {
                        try depthPngData.write(to: depthPngURL, options: .atomic)
                    }

                    try self.saveFloat32DepthBuffer(sceneDepth.depthMap, to: depthFloatURL)
                }

                let rgbPath = "images/\(rgbFileName)"
                let depthPath = useDepth ? "images/\(depthFloatFileName)" : nil
                self.writeFrameMetadata(frame, jsonURL: jsonURL, depthPath: depthPath, rgbPath: rgbPath)
            } catch {
                print(error)
            }

            DispatchQueue.main.async {
                self.manifest.frames.append(frameMetadata)
            }
        }
        currentFrameCounter += 1
    }
}
