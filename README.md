# LiveCapture - AI Photography Assistant

English | [简体中文](README_CN.md)

LiveCapture is an iOS AI photography assistant that combines real-time composition analysis with intelligent camera control. It analyzes the live preview, provides composition guidance, and automatically adjusts camera parameters (exposure, focus, white balance, lens selection) based on the scene — letting AI handle the technical details so you can focus on framing the shot.

Based on the [LiveCompose](https://github.com/LiveCompose) open-source project, with significant architecture upgrades for professional camera control.

![Platform](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Framework](https://img.shields.io/badge/Framework-SwiftUI%20%2B%20AVFoundation%20%2B%20CoreML-red)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![AI](https://img.shields.io/badge/AI-DeepSeek%20%2B%20Local%20Engine-blue)

> 📸 **Screenshots coming soon** — PRs welcome!

## Key Features

### 🎯 AI Composition Guidance
- **Real-time analysis** of camera preview using CoreML and Vision frameworks
- **Magic Wand mode** — live guidance arrows and alignment dots to help you frame the shot
- **Two detection engines** — CoreML (AdaCrop student/teacher models) and Vision (face/body/saliency)
- **Gyroscope tracking** — device motion compensation for stable composition alignment
- **Rule of thirds / center composition** — multiple composition targets

### 📷 Intelligent Camera Control

| Parameter | Control | AI Support |
|-----------|---------|------------|
| **Exposure** | EV bias slider (±2 EV) | Brightness preference (darker/brighter/preserve highlights/night) |
| **Focus** | Manual focus slider (0-1) | Auto / subject lock / macro |
| **White Balance** | Color temp slider (2000K-10000K) | Auto / warm / cool / natural |
| **Lens** | Zoom ring + preset switching | Ultra-wide / wide / telephoto auto-select |
| **Depth** | Semantic preference | Shallow / deep / auto |

### ⚙️ Three-State Control Mechanism

Every camera parameter has an independent three-state control:

| Mode | Icon | Description | AI Can Override? |
|------|------|-------------|------------------|
| **AI Auto** | ✨ | AI adjusts based on scene analysis | Yes |
| **Manual** | 🎚 | User controls via sliders | No |
| **Locked** | 🔒 | Lock current value | No |

> 💡 **Pro tip**: For night shots, lock white balance to cool tones and let AI auto-control exposure and focus for the best results.

### 🧠 Two-Layer AI Strategy

- **Cloud AI (DeepSeek)** — scene-semantic intelligent judgment, highest priority
- **Local Engine (rule-based)** — based on composition analysis, works offline
- **Smart merge** — cloud AI only overrides fields it's confident about, the rest falls to the local engine

## Quick Start

### 1. Install

```bash
git clone https://github.com/xbcmz/LiveCapture.git
cd LiveCapture
open LiveCapture.xcodeproj
```

### 2. Configure (Optional)

Add your DeepSeek API Key in Xcode to enable cloud AI:

1. Open `Info.plist`
2. Add a new row with key `DeepSeekAPIKey`, type String
3. Paste your DeepSeek API Key

> No API Key? No problem — the app automatically falls back to the local rule engine + Mock AI. Core composition features work fully offline.

### 3. Run

1. Connect your iPhone via USB
2. Select your device in Xcode (not simulator)
3. Press `⌘R`
4. First run requires trusting the developer certificate in **Settings → General → VPN & Device Management**

## Usage Guide

### Basic Controls

| Action | Description |
|--------|-------------|
| 🔘 Shutter button | Take a photo (supports auto-capture) |
| 🪄 Magic Wand button | Toggle AI composition guidance |
| 🔄 Switch button | Switch front/back camera |
| 🔍 Zoom ring | Switch lens / slide to zoom |

### Camera Control Panel

Three vertical control panels on the right side, from top to bottom:

1. **Exposure** — drag the slider to adjust exposure compensation
2. **Focus** — drag the slider for manual focus
3. **White Balance** — drag the slider to adjust color temperature

Each panel has three buttons at the top to switch AI Auto / Manual / Locked modes.

### AI Advice Card

When Magic Wand is on, an AI advice card appears at the bottom with:

- **Composition advice** — current composition score and improvement suggestions
- **AI Camera Parameters** — AI-recommended lens, focus, white balance, and depth settings
- Displayed as capsule chips for quick reading

### Capture Modes

- **Manual capture** — press the shutter button
- **Auto capture** — enabled in Settings; automatically triggers when composition is aligned AND device is stable

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
│   │   ├── CameraManager+Zoom.swift       # Zoom & lens control
│   │   ├── CameraManager+Photo.swift      # Photo capture & JPEG encoding
│   │   ├── CameraManager+VideoOutput.swift # Frame output → detection
│   │   ├── CameraManager+Control.swift    # Exposure/Focus/WB control APIs
│   │   ├── CameraManager+Capability.swift # Device capability detection
│   │   ├── CameraPreviewView.swift        # Camera preview (UIViewRepresentable)
│   │   ├── CameraCapability.swift         # Hardware capability model
│   │   ├── CameraControlEngine.swift      # Strategy → hardware translation
│   │   └── PhotographyStrategy.swift      # Semantic strategy model
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

### Device Capability Matrix

| Feature | Single-camera | Dual-camera | Triple-camera (Pro) |
|---------|--------------|-------------|---------------------|
| Ultra-wide | ❌ | ✅ | ✅ |
| Telephoto | ❌ | ✅ (2x) | ✅ (3x+) |
| Manual exposure | ✅ | ✅ | ✅ |
| Manual focus | ✅ | ✅ | ✅ |
| Manual white balance | Partial | ✅ | ✅ |

## FAQ

### Q: Why don't I see the white balance control panel?
A: Manual color temperature adjustment requires "custom white balance gain lock" support. Front cameras and older devices (iPhone X and earlier) don't support this, so the panel auto-hides. You can still use the "lock white balance" feature.

### Q: The AI advice card doesn't show parameters?
A: Check the following:
1. Make sure Magic Wand is enabled
2. Make sure the camera is pointed at a scene with a clear subject
3. If using cloud AI, check network connection and API key
4. Offline mode: the local engine also generates strategies, but they may be simpler

### Q: Why doesn't auto-capture trigger?
A: Auto-capture requires both conditions to be met:
1. Composition aligned (tracking point enters center alignment zone)
2. Device stable (gyroscope detects handheld stability)
3. Auto-capture is enabled in Settings

### Q: How do I switch detection engines?
A: Go to **Settings → Engine**. CoreML engine is more accurate but slightly slower; Vision engine is faster but only detects faces/bodies/saliency regions.

### Q: Where are photos stored?
A: Photos are saved in the app's Application Support directory and are not automatically added to the system photo library. You can manually save to album from the detail view, or generate a share card.

### Q: What languages are supported?
A: Currently the UI is primarily in Chinese. The architecture supports internationalization — PRs welcome!

## Roadmap

- [x] **Phase 0** — Lens capability detection + multi-lens switching
- [x] **Phase 1** — Exposure control (EV slider + 3-state mechanism)
- [x] **Phase 2** — Focus control (manual focus + 3-state mechanism)
- [x] **Phase 3** — White balance control (color temp slider + 3-state)
- [x] **Phase 4** — Local AI camera strategy engine
- [x] **Phase 5** — Cloud AI strategy integration (DeepSeek)
- [ ] **Phase 6** — Low-light detection + night mode
- [ ] **Phase 7** — HDR / exposure bracketing
- [ ] **Phase 8** — Pro mode control panel UI redesign
- [ ] **Phase 9** — Shooting presets (portrait/landscape/food one-tap presets)

## Contributing

Contributions are welcome! Here's how to get involved:

### Report Issues
- Use GitHub Issues to submit bugs or feature requests
- When submitting a bug, please include device model, iOS version, and reproduction steps

### Submit Code
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Guidelines
- Use SwiftUI + MVVM architecture
- Add a comment at the top of each file explaining its purpose
- UI components go in `UI/Components/`, feature modules in `Features/`
- Camera operations must be executed on the `sessionQueue` thread
- Never hardcode API keys or other sensitive information

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

Based on the [LiveCompose](https://github.com/LiveCompose) open-source project. Original composition detection models (AdaCrop student/teacher) and motion tracking system are used with modifications.

Thanks to all contributors and the open source community.
