# FrameHero - AI Composition Camera

English | [简体中文](README_CN.md)

FrameHero is an iOS AI composition camera built around one question:

> **"Given this scene, how should I shoot it better?"**

Open the camera → tap **AI Composition** → AI analyzes the scene and proposes **1–3 composition plans** → pick one → follow the live guidance → **composition achieved** → shoot. The AI thinks, the phone judges in real time, you just move the phone.

Based on the [LiveCompose](https://github.com/LiveCompose) open-source project, with deeply rebuilt camera-control and composition-guidance architecture.

![Platform](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Framework](https://img.shields.io/badge/Framework-SwiftUI%20%2B%20AVFoundation%20%2B%20CoreML%20%2B%20Vision-red)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![AI](https://img.shields.io/badge/AI-Local%20Realtime%20%2B%20Cloud%20Optional-blue)

## The Core Experience: AI Photographer

Tap the ✨ button next to the shutter — the AI photographer starts working:

```text
Analyze the scene (~1s, fully on-device)
    ↓
"AI Photographer · Found 3 ways to shoot this"
    ┌──────────────────────────┐
    │ Person & Scene  Spatial  │  ← recommended (green)
    ├──────────────────────────┤
    │ Close-up  Emphasize      │
    ├──────────────────────────┤
    │ Negative Space  Minimal  │
    └──────────────────────────┘
    ↓ pick one
Target marker ring + one-line suggestion appear
    ↓ follow the guidance
Subject enters the ring → turns green ✓ done
    ↓
Shoot (optional auto-capture countdown)
```

- **Plans are structured**: composition type / target subject position / distance / focal-length suggestion / confidence — not vague sentences
- **Seven composition types in MVP**: rule of thirds · centered symmetry · leading lines · framing · foreground layering · negative space · environment portrait
- **Scene recognition**: portrait / food / night / landscape / street / document (Vision classifier with multi-frame voting, offline)

## Smart Details

- **Three composition-engine tiers** (Settings → Composition Engine):
  - **Vision** — rule-based target positions, no model
  - **Fast** — AdaCrop Student model predicts the "best-composition crop" once to calibrate plan targets
  - **Pro** — AdaCrop Teacher model, full precision
- **Group awareness**: with 2+ people, switches to group plans (centered group / full panorama / front-row close-up), tracking the group bounding box
- **Leading room**: detects face direction, target automatically leaves looking-space
- **Subject continuity**: frame-to-frame IoU matching keeps the tracked subject stable among similar people
- **Scene presets**: night/food/landscape scenes automatically shift camera parameter preferences (only touches AI-Auto parameters, never ones you locked manually)
- **Completion ritual**: marker turns green and shrinks + third-lines fade + shutter pulse; with auto-capture on, a countdown ring with escalating haptics appears — **hand-shake cancels it** to avoid blurred shots

## Pro Camera Controls (three-state mechanism)

| Parameter | Manual control | AI-Auto mode |
|-----------|---------------|--------------|
| **Exposure** | EV slider (±2 EV, shows live hardware value) | brightness preference (darker/brighter/highlights/night) |
| **Focus** | manual focus slider (0–1) | subject lock / macro |
| **White balance** | temperature slider (2000K–10000K) | warm / cool / natural |
| **Lens** | zoom dial (preset pills + long-press fine dial) | ultra-wide / wide / telephoto suggestions |

Each parameter has an independent three-state switch: **AI Auto ✨ / Manual 🎚 / Locked 🔒** — let AI drive exposure while you lock white balance, without interference. Sliders show the camera's real hardware values in AI-Auto mode.

## Home Workbench

- Greeting header + large "Start AI Capture" entry
- Assistant status card: composition guidance / scene recognition / person detection readiness
- Recent shots carousel with the **composition score captured at shutter time**
- "Today" stats: photos / AI advice count / average score

## Gallery

- 3-column grid + fullscreen browser + multi-select delete (select mode / context menu, with delete confirmation)
- Two export styles: **original photo** (raw JPEG bytes, no re-encoding) or **info card** (photo + date + EXIF, watermark-free)

## Settings

- **AI Assistant**: composition-entry toggle; cloud AI (DeepSeek) reserved — API key stored in the system **Keychain**, connection test (zero token cost), model choice (V3 chat / R1 reasoner), custom base URL (self-hosted proxy)
- **Capture prefs**: auto-capture toggle, capture delay, composition-engine tier, appearance

## AI vs On-Device Responsibilities

```text
                 Camera (AVFoundation)
                        │
     [tap AI Composition] one-shot analysis (~1s, on-device)
                        │
      ┌─────────────────┼──────────────────┐
      ↓                 ↓                  ↓
  Scene classifier   Person/face      AdaCrop crop model
  (multi-frame       detection        (Fast/Pro target
   voting)           (group box/facing)  calibration)
      └─────────────────┼──────────────────┘
                        ↓
              3 structured composition plans
                        ↓ user picks
        ┌─── realtime guidance loop (10fps, all local) ───┐
        │ subject tracking (person / saliency)            │
        │ deviation → direction text → completion check   │
        └──────────────────────┬──────────────────────────┘
                               ↓
                    ✓ composition achieved → shoot
```

> A cloud LLM (DeepSeek) **never runs in the realtime loop** — per-frame requests are slow, costly, and unreadable while shooting. It is reserved for "post-shot review" (on the roadmap), pluggable via the `CompositionPlanProviding` / `AIAdviceProvider` protocols — swapping in any vision model only replaces the implementation.

## Key Technical Implementations

### Composition plan generation
- **Local heuristic** (`CompositionPlan.LocalHeuristicPlanProvider`): pure rule-based plans from scene kind + person/face geometry, zero latency, always available.
- **Cloud plans** (`CompositionPlanGeneration.swift`): DeepSeek Vision returns one structured JSON payload (`scene` / `main_subject` / `plans[]`, each plan carrying `subject_target`, `camera_action.{horizontal,vertical,distance}`, `focal_length`) once per AI-composition session; `CompositionPlanMapper` maps it into local `CompositionPlan` models. Parsing/mapping are pure, stateless functions (`static func`), independent of `CaptureViewModel`'s retry/fallback orchestration — easy to unit test without mocking the network layer.
- **AdaCrop calibration**: `AdaCropPlanAdvisor` runs the Fast/Pro CoreML model once per session to predict the "best-composition crop"; `PlanGeometry.mapThroughCrop` remaps the plan's subject target into that crop, refining "where exactly to put the subject" beyond pure rule-of-thumb positions.

### Pose level (attitude horizon)
`MotionStabilityMonitor.attitude.roll` (CoreMotion device-motion) drives a live horizon-line overlay and tilt coaching text in `CaptureView`/`CaptureViewModel` (`cameraRollDegrees`, throttled to ~6.7fps to avoid excess SwiftUI re-render).

### Distance estimation
`CaptureViewModel.distanceEstimateText` buckets `person.heightRatio × zoomState.currentFactor` (subject's on-screen height ratio scaled by current zoom) into coarse "~5m / 3-5m / 2m / 1m / <0.5m" hints — a cheap, model-free heuristic that only needs the person bounding box already produced by the tracking pipeline. Combined with the AI plan's `camera_action.distance` (`closer`/`keep`/`farther`), this is what drives "move closer / step back" guidance.

### Concurrency model
Every background worker owns exactly one serial queue and a **queue-confined mirror** of any state it needs to branch on internally; `@Published` properties are write-only outputs towards the main thread and must never be read back from a background queue (async main writes race with background reads). This project-wide rule was formalized after fixing two real races:
- `MotionStabilityMonitor`: hysteresis must branch on the internal `stableState` mirror (mutated only on `dataQueue`), not the `@Published isStable` (mutated only on main); `largeMotionFlag`'s delayed reset was moved from `DispatchQueue.main.asyncAfter` back onto `dataQueue` for the same reason.
- `SceneClassifier`: `classify()` runs on the camera's `videoOutputQueue`, while `reset()` is triggered by main-thread UI actions; both now go through a dedicated `stateQueue` to serialize access to `votes`/`currentDecision`.

## Project Layout

```text
FrameHero/
├── FrameHeroApp.swift                      # App entry
├── Info.plist
├── Assets.xcassets/                        # Icon (light/dark/tinted)
├── Core/
│   ├── AI/
│   │   ├── AIConfigurationStore.swift      # AI config hub (+ usage counter)
│   │   ├── KeychainStore.swift             # Keychain wrapper (API key)
│   │   ├── APIKeyProvider.swift            # API key reader (Keychain first)
│   │   ├── DeepSeekService.swift           # DeepSeek API (+ connection test)
│   │   ├── MockPhotographer.swift          # Offline mock advice
│   │   ├── AIAdviceProvider.swift          # Advice provider protocol
│   │   └── PhotographyAdvisor.swift        # Analysis orchestrator
│   ├── Camera/
│   │   ├── CameraManager.swift             # Session lifecycle (+Session/Zoom/Photo/
│   │   │                                   #   VideoOutput/Control/Capability/Models)
│   │   ├── CameraCapability.swift          # Hardware capability + environment model
│   │   ├── CameraControlEngine.swift       # Strategy → hardware (differential apply)
│   │   ├── PhotographyStrategy.swift       # Semantic three-state strategy
│   │   └── CameraPreviewView.swift         # Preview layer
│   ├── Composition/
│   │   ├── CompositionPlan.swift           # Plan model + local plan generator
│   │   ├── SceneClassifier.swift           # Scene recognition (multi-frame voting)
│   │   ├── AdaCropPlanAdvisor.swift        # AdaCrop best-crop prediction (Fast/Pro)
│   │   ├── CompositionEngine.swift         # Scoring + subject extraction (group/continuity)
│   │   ├── CompositionGuidanceEngine.swift # Deviation → direction/progress/done
│   │   └── ...(result/target/guidance models)
│   ├── Detection/
│   │   ├── CropDetectionStrategy.swift     # Detection mode enum (Vision/Fast/Pro)
│   │   └── AestheticCropDetector.swift     # Vision face/body raw detections (feeds CompositionEngine)
│   ├── Models/                             # AdaCrop CoreML models (student/teacher)
│   ├── Motion/MotionStabilityMonitor.swift # Gyro stability
│   └── Storage/                            # Photo store (score saved per shot)
├── Features/
│   ├── Main/MainTabView.swift              # TabBar + AppRouter
│   ├── Capture/
│   │   ├── Views/CaptureView.swift         # Main camera UI
│   │   ├── ViewModels/CaptureViewModel.swift # AI composition session state machine
│   │   └── Components/
│   │       ├── CompositionCoachOverlayView.swift  # Plan cards + guidance overlay
│   │       ├── CameraPreviewSection.swift  # Preview + overlay container
│   │       ├── CaptureButton.swift         # Shutter (countdown ring/burst/pulse)
│   │       └── TopControlBar.swift         # Top bar
│   ├── Home/
│   │   ├── Views/HomeView.swift            # Home workbench
│   │   ├── Views/GalleryView.swift         # Gallery (multi-select delete)
│   │   ├── Views/PhotoDetailView.swift     # Browser + export (original/card)
│   │   └── ViewModels/HomeViewModel.swift
│   ├── Settings/Views/SettingsView.swift   # Settings (incl. AI assistant)
│   └── ShareCard/ShareCardGenerator.swift  # Info card renderer (watermark-free)
├── UI/
│   ├── Design/DesignSystem.swift           # Design tokens
│   └── Components/                         # Zoom dial / EV / focus / WB sliders
└── Utilities/Helpers/                      # Haptics / smoothing filters
```

## Getting Started

```bash
git clone https://github.com/xbcmz/FrameHero.git
cd FrameHero
open FrameHero.xcodeproj
```

1. Select your iPhone in Xcode (iOS 17+, real device)
2. `⌘R` to run
3. AI composition works **out of the box** — on-device inference, zero configuration

### Optional: Cloud AI (DeepSeek)

1. Go to **Settings → AI Assistant**
2. Toggle **Cloud AI Advice**, paste your API key and save (stored in Keychain)
3. Tap **Test Connection** to verify

> No key? AI composition still works fully — realtime guidance is all local; cloud is reserved for upcoming post-shot review.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 17+) |
| Camera | AVFoundation |
| Scene recognition | Vision (VNClassifyImageRequest, multi-frame voting) |
| People/saliency | Vision (faces / bodies / attention saliency) |
| Composition model | CoreML (AdaCrop Student/Teacher, optional tiers) |
| Cloud AI | DeepSeek API (reserved, any VLM swappable) |
| Motion | CoreMotion |
| Persistence | Keychain + FileManager + JSON |
| Dependencies | None |

## FAQ

### Q: Does AI composition need internet?
A: No. Scene recognition, person detection, plan generation and realtime guidance all run on-device with zero latency, fully offline. Cloud LLM is only for the roadmap's post-shot review.

### Q: Difference between the three composition-engine tiers?
A: **Vision** positions targets with pure photography rules; **Fast/Pro** additionally run the AdaCrop CoreML model (Student/Teacher) once to predict the best-composition crop and calibrate plan targets. Realtime guidance is identical across tiers — the difference is where the AI places your target.

### Q: How does it decide "move left / move right"?
A: The target position comes from the selected plan (rules + model calibration); live deviation is computed by the guidance engine. The locked target is drawn as a dashed marker ring on screen — put the subject inside the ring, no left-right oscillation.

### Q: Front-camera directions correct?
A: Yes — both instruction text and the marker position are mirrored to match the preview.

### Q: Why is the white-balance slider missing?
A: Manual temperature requires "custom white-balance gain lock" support; unsupported devices hide the panel automatically. Locking WB still works.

### Q: Where are photos stored?
A: Inside the app sandbox (Application Support), not the system library. Export from the photo browser: **original photo** (raw JPEG bytes) or **info card**.

## Roadmap

- [x] **Phase 0–5** — lens capability / exposure / focus / WB three-state control + local strategy engine + cloud strategy
- [x] **Phase 6–8** — pro control panel refactor / zoom dial / AI composition session paradigm
- [x] **Phase 9** — AI Photographer MVP: scene recognition → composition plans → live guidance
- [x] **Phase 10** — group awareness / subject continuity / AdaCrop engine tiers
- [x] **Post-shot review** — DeepSeek Vision structured critique (score / strengths / improvements)
- [x] **VLM plan provider** — scene-aware plans from DeepSeek Vision
- [x] **Pose level** — CoreMotion roll → horizon line + tilt coaching (ARKit optional later)
- [x] **Auto focal switch** — plan focal suggestions execute on selection

## Contributing

Issues and PRs welcome. Please keep: SwiftUI + MVVM, camera operations on `sessionQueue`, a purpose header comment per file, no secrets in code, and — for any new background worker — never read a `@Published` property from that worker's own queue; keep a queue-confined mirror instead (see *Concurrency model* above).

## License

MIT License — see [LICENSE](LICENSE).

## Acknowledgments

Formerly named LiveCapture, now **FrameHero**. Based on the [LiveCompose](https://github.com/LiveCompose) open-source project; the original composition detection models (AdaCrop Student/Teacher) and motion-tracking system are used with deep modifications.
