//
//  SettingsView 2.swift
//  RGB-D Spatial Capture
//

import SwiftUI

struct SettingsView: View {
    @Binding var settings: CaptureSettings
    var onSave: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Capture Controls")) {
                    Picker("Capture Interval", selection: $settings.captureInterval) {
                        ForEach(CaptureInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    
                    Toggle("RGB Camera Capture", isOn: $settings.rgbEnabled)
                    Toggle("LiDAR Depth Capture", isOn: $settings.depthEnabled)
                }
                
                Section(header: Text("Data Serialization")) {
                    Picker("Image Format", selection: $settings.imageFormat) {
                        ForEach(ImageFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    
                    if settings.imageFormat == .jpeg {
                        HStack {
                            Text("JPEG Quality")
                            Spacer()
                            Slider(value: $settings.jpegQuality, in: 0.1...1.0, step: 0.05)
                                .frame(width: 150)
                            Text(String(format: "%.0f%%", settings.jpegQuality * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Picker("Depth Format", selection: $settings.depthFormat) {
                        ForEach(DepthFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }
                
                Section(header: Text("Acquisition Settings")) {
                    Toggle("Auto-Export ZIP on Stop", isOn: $settings.autoExport)
                    
                    Picker("Max Dataset Size", selection: $settings.maxDatasetSize) {
                        ForEach(MaxDatasetLimit.allCases) { limit in
                            Text(limit.displayName).tag(limit)
                        }
                    }
                }
            }
            .navigationTitle("Acquisition Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onSave()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
