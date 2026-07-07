//
//  ContentView.swift
//  RGB-D Spatial Capture
//

import SwiftUI
import ARKit
import RealityKit

struct ContentView : View {
    @StateObject private var viewModel: ARViewModel
    @State private var showSettings: Bool = false
    @State private var shareURL: URL? = nil
    
    init(viewModel vm: ARViewModel) {
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    private var settingsBinding: Binding<CaptureSettings> {
        Binding(
            get: { viewModel.captureController.settings },
            set: { viewModel.captureController.settings = $0 }
        )
    }
    
    private var datasetNameBinding: Binding<String> {
        Binding(
            get: { viewModel.captureController.datasetName },
            set: { viewModel.captureController.datasetName = $0 }
        )
    }
    
    var body: some View {
        ZStack {
            // AR Camera Preview
            ARViewContainer(viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // HUD Overlay
            VStack {
                // Top Bar
                HStack {
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .disabled(viewModel.isRecording)
                    .padding(.leading, 20)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    Text("RGB-D Capture")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                        .padding(.top, 10)
                    
                    Spacer()
                    
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 48, height: 48)
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                }
                
                // Status Panel
                HStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(trackingStateColor(viewModel.trackingState))
                                .frame(width: 8, height: 8)
                            Text(viewModel.trackingState)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        if viewModel.supportsDepth {
                            Text("LiDAR Depth: Supported")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("LiDAR Depth: Not Available")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        if viewModel.isRecording {
                            Divider().background(Color.white.opacity(0.3))
                            
                            Text("Project: \(viewModel.currentProjectName)")
                                .font(.caption)
                                .fontWeight(.bold)
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Frames")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(viewModel.savedFrameCount)")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("Size")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(viewModel.formattedDatasetSize)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.cyan)
                                }
                            }
                            
                            Text("Interval: \(viewModel.captureController.settings.captureInterval.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.7)))
                    .foregroundColor(.white)
                    .frame(maxWidth: 260)
                    .padding(.trailing, 20)
                }
                .padding(.top, 10)
                
                Spacer()
                
                // Bottom Controls
                VStack(spacing: 20) {
                    // Dataset Name Field (before recording)
                    if !viewModel.isRecording && viewModel.exportURL == nil {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.gray)
                            TextField("Dataset Name (optional)", text: datasetNameBinding)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.subheadline)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    // Share Button
                    if let url = viewModel.exportURL {
                        Button(action: { self.shareURL = url }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Captured Dataset")
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                        }
                    }
                    
                    HStack(spacing: 30) {
                        // Reset
                        Button(action: { viewModel.resetWorldOrigin() }) {
                            VStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title2)
                                Text("Reset Pose")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                        }
                        .disabled(viewModel.isRecording)
                        
                        // Record / Stop
                        Button(action: {
                            if viewModel.isRecording {
                                viewModel.stopCapture()
                            } else {
                                viewModel.startCapture()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isRecording ? Color.red : Color.white)
                                    .frame(width: 72, height: 72)
                                
                                if viewModel.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white)
                                        .frame(width: 24, height: 24)
                                } else {
                                    Circle()
                                        .stroke(Color.black, lineWidth: 3)
                                        .frame(width: 64, height: 64)
                                }
                            }
                        }
                        .shadow(radius: 5)
                        
                        // Manual Save (only shown in manual mode while recording)
                        if viewModel.isRecording && viewModel.captureController.settings.captureInterval == .manual {
                            Button(action: { viewModel.triggerManualSave() }) {
                                VStack {
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                    Text("Save Frame")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .cornerRadius(12)
                                .foregroundColor(.white)
                            }
                        } else {
                            // Invisible spacer for alignment
                            VStack {
                                Image(systemName: "camera.fill").font(.title2)
                                Text("Save Frame").font(.caption)
                            }
                            .opacity(0)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            
            // Export Overlay
            if viewModel.isExporting {
                Color.black.opacity(0.75)
                    .edgesIgnoringSafeArea(.all)
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Compiling and zipping dataset...")
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settingsBinding, onSave: {
                viewModel.captureController.saveSettings()
            })
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(activityItems: [url])
        }
    }
    
    private func trackingStateColor(_ state: String) -> Color {
        switch state {
        case "Tracking Normal": return .green
        case "Tracking Initializing": return .yellow
        default: return .red
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { self.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
