# LiveCapture - AI Photography Assistant

English | [简体中文](README_CN.md)

LiveCapture is an iOS AI photography assistant that combines real-time composition analysis with intelligent camera control. It analyzes the live preview, provides composition guidance, and automatically adjusts camera parameters (exposure, focus, white balance, lens selection) based on the scene — letting AI handle the technical details so you can focus on framing the shot.

Based on the [LiveCompose](https://github.com/LiveCompose) open-source project, with significant architecture upgrades for professional camera control.

![Platform](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Framework](https://img.shields.io/badge/Framework-SwiftUI%20%2B%20AVFoundation%20%2B%20CoreML-red)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![AI](https://img.shields.io/badge/AI-DeepSeek%20%2B%20Local%20Engine-blue)

## Key Features

### AI Composition Guidance
- **Real-time analysis** of camera preview using CoreML and Vision frameworks
- **Magic Wand mode** — live guidance arrows and alignment dots to help you frame the shot
- **Two detection engines** — CoreML (AdaCrop student/teacher models) and Vision (face/body/saliency)
- **Gyroscope tracking** — device motion compensation for stable composition alignment

### Intelligent Camera Control (Phase 0-5)
- **Exposure control** — EV bias slider, auto/manual/locked modes
- **Focus control** — manual focus slider, auto/subject-lock/manual modes
- **White balance control** — color temperature slider (2000K-10000K), warm/cool/natural presets
- **Lens selection** — ultra-wide / wide / telephoto with auto-switching
- **AI camera strategy** — cloud AI (DeepSeek) + local rule engine, two-layer merge with priority

### Three-State Control
Every camera parameter supports three states:

| Mode | Description | AI Can Override? |
|------|-------------|------------------|
| **AI Auto** | AI adjusts based on scene analysis | Yes |
| **Manual** | User controls via sliders | No |
| **Locked** | Lock current value | No |

## Architecture

### Data Flow

```
Camera Frame (60fps)
    │
    ├──→ Composition Engine ──→ Guidance Arrows / Alignment Dots
    │
    ├──→ Vision Detection ──→ Scene Analysis (person/face/saliency)
    │                              │
    │                              ▼
    │                    Photography Advisor
    │                     ├── Local Engine (rule-based)
    │                     └── Cloud AI (DeepSeek, JSON strategy)
    │                              │
    │                              ▼  (merge: cloud overrides local)
    │                    PhotographyStrategy
    │                              │
    │                              ▼  (filter: only .aiAuto params)
    │                    CameraControlEngine
    │                              │
    │                              ▼
    │                    Hardware Parameters
    │                    (exposure / focus / WB / lens)
    │
    └──→ CapturePipeline (9-stage state machine)
```

### Directory Structure

```
LiveCapture/
├── LiveCaptureApp.swift                  # App entry
├── Info.plist                             # Permissions & config
├── Assets.xcassets/                       # App icon & logo
├── Core/
│   ├── AI/                                # AI service layer
│   │   ├── APIKeyProvider.swift           # Secure API key reading
│   │   ├── DeepSeekService.swift          # Cloud AI (DeepSeek API)
│   │   ├── MockPhotographer.swift         # Offline mock AI
│   │   ├── AIAdviceProvider.swift         # AI advice orchestration
│   │   └── PhotographyAdvisor.swift       # Strategy generation & merge
│   ├── Camera/                            # Camera subsystem
│   │   ├── CameraManager.swift            # Session lifecycle
│   │   ├── CameraManager+Session.swift    # Permissions, config, switching
│   │   ├── CameraManager+Models.swift     # Enums: lens, zoom, errors
│   │   ├── CameraManager+Zoom.swift        # Zoom & lens control
│   │   ├── CameraManager+Photo.swift      # Photo capture & JPEG encoding
│   │   ├── CameraManager+VideoOutput.swift # Frame output → detection
│   │   ├── CameraManager+Control.swift     # Exposure/Focus/WB control APIs
│   │   ├── CameraManager+Capability.swift  # Device capability detection
│   │   ├── CameraPreviewView.swift         # Camera preview (UIViewRepresentable)
│   │   ├── CameraCapability.swift          # Hardware capability model
│   │   ├── CameraControlEngine.swift       # Strategy → hardware translation
│   │   └── PhotographyStrategy.swift       # Semantic strategy model
│   ├── Composition/                       # Composition analysis
│   │   ├── CompositionEngine.swift        # Composition scoring
│   │   ├── CompositionGuidanceEngine.swift # Guidance arrow generation
│   │   ├── CompositionResult.swift        # Analysis result model
│   │   ├── CompositionTarget.swift        # Target position model
│   │   ├── CurrentComposition.swift       # Current composition state
│   │   └── GuidanceResult.swift           # Guidance output model
│   ├── Detection/                         # AI detection engines
│   │   ├── CropDetectionStrategy.swift    # Strategy protocol
│   │   ├── CoreMLCropDetector.swift       # CoreML two-stage detector
│   │   ├── AestheticCropDetector.swift    # Vision-based detector
│   │   └── BoxCenterManager.swift         # Center tracking & alignment
│   ├── Motion/
│   │   └── MotionStabilityMonitor.swift   # Gyroscope/accelerometer
│   ├── Storage/                           # Photo persistence
│   │   ├── PhotoRecord.swift              # Data model (Codable)
│   │   ├── PhotoStorageService.swift      # File storage + JSON index
│   │   └── ThumbnailGenerator.swift      # Thumbnail generation
│   └── Models/                           # CoreML model bundles
│       ├── student/                      # Fast mode (lightweight)
│       └── teacher/                      # Pro mode (full precision)
├── Features/
│   ├── Main/
│   │   └── MainTabView.swift              # TabBar root (4 tabs)
│   ├── Capture/                           # Core capture feature
│   │   ├── Views/CaptureView.swift       # Capture main screen
│   │   ├── ViewModels/CaptureViewModel.swift  # Pipeline state machine
│   │   └── Components/
│   │       ├── AIGuidanceOverlayView.swift    # Guidance arrows overlay
│   │       ├── CameraPreviewSection.swift     # Preview + overlays
│   │       ├── CaptureButton.swift            # Shutter button
│   │       ├── CompositionAdviceCard.swift    # AI advice card
│   │       ├── DebugPanel.swift               # Debug info
│   │       ├── TopControlBar.swift            # Top control bar
│   │       └── UserGuidanceView.swift         # Guidance text
│   ├── Home/                             # Photo gallery
│   │   ├── Views/HomeView.swift          # Grid gallery
│   │   ├── Views/PhotoDetailView.swift   # Full-screen browser
│   │   ├── ViewModels/HomeViewModel.swift
│   │   └── Components/PhotoCard.swift
│   ├── Settings/
│   │   └── Views/SettingsView.swift      # Settings page
│   ├── ShareCard/
│   │   └── ShareCardGenerator.swift      # Share card (1080×1440)
│   └── LiveCompose/
│       └── Views/LiveComposeView.swift   # About page
├── UI/
│   ├── Design/DesignSystem.swift         # Design tokens
│   └── Components/
│       ├── CircleButton.swift            # Circular button
│       ├── ContentOverlayView.swift      # Gridlines / tracking point
│       ├── ExposureControlView.swift     # EV slider + 3-state toggle
│       ├── FocusControlView.swift        # Focus slider + 3-state toggle
│       ├── WhiteBalanceControlView.swift # Color temp slider + 3-state
│       └── ZoomRingView.swift            # Zoom preset ring
└── Utilities/
    └── Helpers/
        ├── HapticManager.swift           # Haptic feedback
        └── UniformSmoother.swift         # EWMA smoothing filter
```

### Navigation

```
MainTabView (TabView, 4 Tabs)
├── Tab 1 "LiveCompose"  → LiveComposeView        # About / branding
├── Tab 2 "Gallery"      → HomeView                # Photo grid → detail
├── Tab 3 "Capture"      → CaptureView (fullScreen) # Camera + AI guidance
└── Tab 4 "Settings"     → SettingsView             # Preferences
```

### Camera Control Architecture

The camera control system is built on four core models:

| Model | Responsibility |
|-------|---------------|
| `CameraCapability` | Device hardware capabilities (supported lenses, EV range, focus range, WB support) |
| `CameraEnvironment` | Real-time camera state (ISO, exposure duration, color temperature, ambient light) |
| `PhotographyStrategy` | Semantic preferences (lens, brightness, motion, focus, white balance, depth) |
| `CameraControlEngine` | Translates strategy into hardware parameters and executes on `CameraManager` |

**Strategy fields and control modes:**

```swift
struct PhotographyStrategy {
    // Each parameter has an independent ControlMode: .aiAuto / .manual / .locked
    var lensControl: ControlMode
    var exposureControl: ControlMode
    var focusControl: ControlMode
    var whiteBalanceControl: ControlMode
    var depthPreference: DepthPreference     // .auto / .shallow / .deep

    // Manual overrides (only applied when control == .manual)
    var manualExposureBias: Float?
    var manualFocusPosition: Float?
    var manualWhiteBalanceTemp: Float?

    // AI semantic preferences (applied when control == .aiAuto)
    var brightnessPreference: BrightnessPreference
    var motionPreference: MotionPreference
    var whiteBalancePreference: WhiteBalancePreference
}
```

### AI Strategy: Two-Layer Merge

```
┌─────────────────────────────────────────┐
│       Cloud AI Strategy (highest priority) │
│    DeepSeek returns JSON with camera params │
│    Only fields with values != "auto"       │
│    override the local engine                │
└──────────────────┬──────────────────────┘
                   │ merge
┌──────────────────▼──────────────────────┐
│       Local Engine Strategy (fallback)      │
│    Rule-based, uses composition analysis    │
│    Works offline                            │
└──────────────────┬──────────────────────┘
                   │ filter by ControlMode
┌──────────────────▼──────────────────────┐
│       Final PhotographyStrategy             │
│    Only .aiAuto params are applied          │
│    .manual and .locked are preserved        │
└──────────────────────────────────────────┘
```

AI can control 6 dimensions via JSON:

| Field | Options |
|-------|---------|
| `lens` | ultraWide / wide / telephoto / auto |
| `brightness` | auto / darker / brighter / preserveHighlights / night |
| `motion` | freezeMotion / balanced / lowNoise |
| `focus` | auto / subjectLock / manual / macro |
| `whiteBalance` | auto / warm / cool / natural |
| `depth` | auto / shallow / deep |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 17+) |
| Camera | AVFoundation |
| AI Inference | CoreML (on-device models) |
| Visual Analysis | Vision (face, body, saliency) |
| Cloud AI | DeepSeek API |
| Motion | CoreMotion (60Hz) |
| Image Processing | CoreImage / ImageIO |
| Reactive | Combine |
| Persistence | FileManager + JSON (Codable) |
| Dependencies | None |

## Requirements

- **Device**: iPhone with iOS 17.0+ (iPhone 11+ recommended for telephoto and manual white balance)
- **Xcode**: 16.0+
- **Camera**: Rear camera with multiple lenses (for full feature support)
- **Network**: Optional (cloud AI features require internet; local engine works offline)

## Setup

1. Clone the repository
2. Open `LiveCapture.xcodeproj` in Xcode
3. (Optional) Add your DeepSeek API key to `Info.plist` under `DeepSeekAPIKey` for cloud AI features
4. Select your iPhone device and run

> Without a DeepSeek API key, the app automatically falls back to the local rule-based engine and mock AI.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

Based on the [LiveCompose](https://github.com/LiveCompose) open-source project. Original composition detection models (AdaCrop student/teacher) and motion tracking system are used with modifications.
