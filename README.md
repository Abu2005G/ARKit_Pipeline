# RGB-D Capture

RGB-D Capture is a professional dataset acquisition application for iOS designed specifically for Computer Vision researchers. It transforms your iPhone or iPad into a spatial data capture tool, making it easy to build synchronized RGB-D datasets for Robotics, SLAM, 3D Gaussian Splatting, SplaTAM, and Neural Reconstruction.

<img src="docs/assets_readme/AppIcon.png" height="200" />

*(Note: RGB-D Capture is a fork and complete reimagining of the original [NeRFCapture](https://github.com/jc211/NeRFCapture) project, now optimized for general-purpose spatial computing research.)*

---

## Features

- **Precise Timing Controls**: Capture data at specific time intervals (0.1s, 0.2s, 0.5s, 1.0s), continuously (60 FPS), or manually using a shutter button.
- **Synchronized Data Streams**: Simultaneously records RGB frames, Depth maps (if LiDAR is available), 6-DoF Camera Poses, Camera Intrinsics, and timestamps.
- **Multiple Depth Formats**: 
  - `Float32 Raw (.depth32f)` for absolute physical accuracy (meters).
  - `Grayscale 16-bit PNG` for immediate compatibility with standard SLAM and visualization pipelines.
- **Export Control**: Capable of saving huge datasets directly to device storage. Real-time file size tracking lets you monitor dataset size, and everything is bundled into a neatly named `.zip` archive on device for easy sharing via AirDrop, Email, or Files.

## Usage

1. **Launch the App**: When you open the application, it will begin initializing AR tracking. Ensure the area is well lit.
2. **Configure Settings**: Tap the gear icon in the top left to open Settings.
   - **Capture Interval**: Choose how often frames should be saved. For walking scans, `0.2 sec` or `0.5 sec` is recommended to reduce dataset size.
   - **Depth Format**: Choose between raw 32-bit floats or normalized 16-bit grayscale PNGs.
   - **Max Dataset Size**: Limit the maximum number of frames to prevent running out of storage.
3. **Capture**: 
   - Enter a custom dataset name at the bottom of the screen if desired.
   - Tap the large record button. The HUD will display the number of frames saved and the current size of the dataset on disk.
   - If using `Manual` mode, tap the orange "Save Frame" button to capture individual viewpoints.
4. **Export**: Stop the recording. The app will compile your images and a `transforms.json` file into a ZIP archive. Tap the **Share Captured Dataset** button to AirDrop it to your computer.

## Dataset Structure

The exported ZIP archive unzips into a folder containing:

```text
DatasetName/
├── transforms.json
└── images/
    ├── frame_000000.jpg
    ├── frame_000000.depth.png (or .depth32f)
    ├── frame_000000.json
    ├── frame_000001.jpg
    ├── frame_000001.depth.png (or .depth32f)
    ├── frame_000001.json
    ...
```

- **`images/frame_xxxxxx.json`**: Contains per-frame metadata (timestamp, pose transform, intrinsics matrix, exposure data).
- **`transforms.json`**: A master manifest file aggregating all poses and camera intrinsics for the entire sequence, formatted similarly to the standard NeRF `transforms.json` but containing full spatial matrices for general SLAM integration.

## Requirements

- **iOS 15.0+**
- For depth capture, a device equipped with a **LiDAR scanner** (e.g., iPhone 12 Pro or newer, iPad Pro) is required. RGB-only capture will function on non-LiDAR devices.

## Building from Source

1. Clone this repository.
2. Open the project in Xcode.
3. Select your development team in the project settings.
4. Build and run on your iOS device.

## Acknowledgements

This project was built upon the foundation of [NeRFCapture](https://github.com/jc211/NeRFCapture) by Jad Abou-Chakra. It has been extensively modified to serve as a general-purpose RGB-D dataset generator rather than a streaming client for InstantNGP.
