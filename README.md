# RGB-D Capture

### Professional RGB-D Dataset Acquisition for Spatial AI, SLAM, and 3D Reconstruction

RGB-D Capture is an iOS application for acquiring synchronized RGB-D datasets using Apple's ARKit. It records RGB images, metric depth maps, camera poses, camera intrinsics, and timestamps, producing datasets that can be used directly in computer vision, robotics, and spatial AI research.

Designed for researchers, students, and developers, RGB-D Capture transforms a LiDAR-equipped iPhone or iPad into a portable RGB-D data acquisition system for building datasets suitable for SLAM, neural scene reconstruction, and 3D perception.

<p align="center">
  <img src="docs/assets_readme/AppIcon.png" width="220"/>
</p>

---

# Features

## High-Quality RGB-D Capture

* Capture synchronized RGB images and depth maps
* Record 6-DoF camera poses for every frame
* Save camera intrinsic parameters
* Store precise timestamps for each capture
* Automatic ARKit-based camera tracking

---

## Flexible Capture Modes

Choose the acquisition method best suited to your dataset.

* **Continuous Capture** (up to 60 FPS)
* **Timed Capture**

  * 0.1 seconds
  * 0.2 seconds
  * 0.5 seconds
  * 1.0 second
* **Manual Capture** using a shutter button

This allows efficient dataset collection for handheld scanning, robotics experiments, and controlled laboratory captures.

---

## Multiple Depth Formats

### Float32 Raw (`.depth32f`)

* Metric depth values stored as 32-bit floating-point numbers
* Preserves absolute depth measurements in meters
* Recommended for:

  * SLAM
  * 3D Gaussian Splatting
  * Neural Radiance Fields (NeRF)
  * SplaTAM
  * 3D reconstruction
  * Quantitative evaluation

### 16-bit Depth PNG (`.depth.png`)

* Normalized 16-bit grayscale depth image
* Convenient for visualization and standard image-processing pipelines
* Recommended for:

  * OpenCV
  * Dataset inspection
  * Debugging
  * Traditional vision workflows

---

## Dataset Export

Every recording is automatically organized into a portable dataset.

Features include:

* Automatic dataset naming
* Real-time dataset size monitoring
* Frame counter
* ZIP archive generation
* Native sharing through AirDrop, Files, Email, and other iOS sharing services

---

# Supported Workflows

RGB-D Capture produces datasets suitable for a wide range of computer vision applications, including:

* 3D Gaussian Splatting
* SplaTAM
* Neural Radiance Fields (NeRF)
* ORB-SLAM3
* KinectFusion
* ElasticFusion
* TSDF Fusion
* Open3D
* Robotics research
* Custom computer vision pipelines

---

# Capture Pipeline

```text
        LiDAR iPhone / iPad
                 │
                 ▼
              ARKit
                 │
      ┌──────────┼──────────┐
      │          │          │
     RGB       Depth      Tracking
      │          │          │
      └──────────┼──────────┘
                 │
                 ▼
      Camera Pose + Intrinsics
                 │
                 ▼
        Dataset Generation
                 │
                 ▼
             ZIP Archive
```

---

# Usage

## 1. Launch the Application

Open RGB-D Capture.

The application initializes ARKit tracking automatically.

For best results:

* Scan in a well-lit environment.
* Move the device smoothly.
* Allow ARKit a few seconds to establish tracking.

---

## 2. Configure Capture Settings

Open the **Settings** panel.

Configure:

### Capture Interval

Choose how frequently frames are saved.

Recommended values:

| Scenario                    | Interval   |
| --------------------------- | ---------- |
| Walking scan                | 0.2 s      |
| Indoor mapping              | 0.5 s      |
| Static scene                | Manual     |
| Maximum temporal resolution | Continuous |

---

### Depth Format

Choose either:

* Float32 Raw
* 16-bit PNG

---

### Maximum Dataset Size

Limit the number of captured frames to avoid exhausting device storage.

---

## 3. Capture a Dataset

1. Enter an optional dataset name.
2. Press **Record**.
3. Move around the scene.

The recording HUD displays:

* Captured frames
* Dataset size
* Recording status

In **Manual Mode**, press **Save Frame** whenever a viewpoint should be recorded.

---

## 4. Export

Stop the recording.

RGB-D Capture automatically:

* Finalizes metadata
* Generates `transforms.json`
* Packages the dataset into a ZIP archive

Share the archive directly through:

* AirDrop
* Files
* Email
* Any supported iOS sharing destination

---

# Dataset Structure

Each exported dataset follows the structure below.

```text
DatasetName/
│
├── transforms.json
│
└── images/
    ├── frame_000000.jpg
    ├── frame_000000.depth32f
    ├── frame_000000.depth.png
    ├── frame_000000.json
    │
    ├── frame_000001.jpg
    ├── frame_000001.depth32f
    ├── frame_000001.depth.png
    ├── frame_000001.json
    │
    └── ...
```

## File Descriptions

### `frame_xxxxxx.jpg`

RGB image captured by the device camera.

---

### `frame_xxxxxx.depth32f`

Raw metric depth values stored as 32-bit floating-point numbers.

---

### `frame_xxxxxx.depth.png`

Normalized 16-bit depth image for visualization and compatibility with traditional image-processing tools.

---

### `frame_xxxxxx.json`

Per-frame metadata including:

* Timestamp
* Camera pose
* Camera intrinsic matrix
* Exposure information

---

### `transforms.json`

Global dataset metadata containing:

* Camera intrinsics
* Camera poses
* Frame references
* Spatial transforms

The format is compatible with the standard NeRF `transforms.json` structure while extending it with complete spatial information suitable for SLAM and general computer vision applications.

---

# Requirements

* iOS 15.0 or later
* Xcode 15 or later

For RGB-D capture, a LiDAR-equipped device is required, including:

* iPhone 12 Pro and newer Pro models
* Supported iPad Pro models

On non-LiDAR devices, RGB image capture remains available while depth capture is disabled.

---

# Building from Source

1. Clone the repository.

```bash
git clone [<repository-url>](https://github.com/Abu2005G/ARKit_Pipeline)
```

2. Open the project in Xcode.

3. Select your Apple Development Team.

4. Build and run on a physical iOS device.

---

# Roadmap

Planned features include:

* Continuous video recording with synchronized RGB-D data
* IMU data export
* Live point cloud visualization
* ROS bag export
* COLMAP export
* Nerfstudio dataset exporter
* Direct 3D Gaussian Splatting dataset export
* Additional dataset statistics and validation tools

---

# Acknowledgements

RGB-D Capture originated from the excellent NeRFCapture project by Jad Abou-Chakra. While inspired by its initial architecture, the project has evolved into an independent RGB-D dataset acquisition platform focused on general-purpose spatial computing, robotics, SLAM, and 3D vision research.

---

# License

This project is released under the MIT License.

See the `LICENSE` file for details.
