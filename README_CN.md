# LiveCapture - AI 摄影助手

[English](README.md) | 简体中文

LiveCapture 是一款 iOS AI 摄影助手，结合实时构图分析与智能相机控制。它分析取景画面、提供构图引导，并根据场景自动调节相机参数（曝光、对焦、白平衡、镜头选择）——让 AI 处理技术细节，你只需专注于构图。

基于 [LiveCompose](https://github.com/LiveCompose) 开源项目二次开发，新增了专业级相机控制架构。

![Platform](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Framework](https://img.shields.io/badge/Framework-SwiftUI%20%2B%20AVFoundation%20%2B%20CoreML-red)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![AI](https://img.shields.io/badge/AI-DeepSeek%20%2B%20Local%20Engine-blue)

## 核心功能

### AI 构图引导
- **实时分析**取景画面，基于 CoreML 和 Vision 框架
- **魔法棒模式** — 实时引导箭头和对齐绿点，帮助你调整构图
- **双检测引擎** — CoreML（AdaCrop student/teacher 模型）和 Vision（人脸/人体/显著性）
- **陀螺仪追踪** — 设备运动补偿，稳定构图对齐

### 智能相机控制（Phase 0-5）
- **曝光控制** — EV 偏移滑块，自动/手动/锁定三态
- **对焦控制** — 手动对焦滑块，自动/锁定主体/手动三态
- **白平衡控制** — 色温滑块（2000K-10000K），暖/冷/自然偏好
- **镜头选择** — 超广角 / 广角 / 长焦，AI 自动切换
- **AI 相机策略** — 云端 AI（DeepSeek）+ 本地规则引擎，双层合并优先级

### 三态控制机制
每个相机参数都支持三种状态：

| 模式 | 说明 | AI 能覆盖？ |
|------|------|-------------|
| **AI Auto ✨** | AI 根据场景自动调节 | 是 |
| **Manual 🎚** | 用户通过滑块控制 | 否 |
| **Locked 🔒** | 锁定当前参数 | 否 |

## 架构

### 数据流

```
相机帧 (60fps)
    │
    ├──→ 构图引擎 ──→ 引导箭头 / 对齐绿点
    │
    ├──→ Vision 检测 ──→ 场景分析（人脸/人体/显著性）
    │                              │
    │                              ▼
    │                    Photography Advisor
    │                     ├── 本地引擎（规则驱动）
    │                     └── 云端 AI（DeepSeek，JSON 策略）
    │                              │
    │                              ▼  （合并：云端覆盖本地）
    │                    PhotographyStrategy
    │                              │
    │                              ▼  （过滤：只应用 .aiAuto 参数）
    │                    CameraControlEngine
    │                              │
    │                              ▼
    │                    硬件参数
    │                    （曝光 / 对焦 / 白平衡 / 镜头）
    │
    └──→ 拍摄流水线（9 阶段状态机）
```

### 目录结构

```
LiveCapture/
├── LiveCaptureApp.swift                  # App 入口
├── Info.plist                             # 权限与配置
├── Assets.xcassets/                       # App 图标与 Logo
├── Core/
│   ├── AI/                                # AI 服务层
│   │   ├── APIKeyProvider.swift           # 安全读取 API Key
│   │   ├── DeepSeekService.swift          # 云端 AI（DeepSeek API）
│   │   ├── MockPhotographer.swift         # 离线 Mock AI
│   │   ├── AIAdviceProvider.swift         # AI 建议编排
│   │   └── PhotographyAdvisor.swift       # 策略生成与合并
│   ├── Camera/                            # 相机子系统
│   │   ├── CameraManager.swift            # 会话生命周期管理
│   │   ├── CameraManager+Session.swift    # 权限、配置、前后摄切换
│   │   ├── CameraManager+Models.swift     # 枚举：镜头、变焦、错误
│   │   ├── CameraManager+Zoom.swift       # 变焦与镜头控制
│   │   ├── CameraManager+Photo.swift      # 拍照与 JPEG 编码
│   │   ├── CameraManager+VideoOutput.swift # 视频帧输出 → 检测
│   │   ├── CameraManager+Control.swift    # 曝光/对焦/白平衡控制 API
│   │   ├── CameraManager+Capability.swift # 设备能力检测
│   │   ├── CameraPreviewView.swift        # 相机预览（UIViewRepresentable）
│   │   ├── CameraCapability.swift         # 硬件能力模型
│   │   ├── CameraControlEngine.swift      # 策略 → 硬件参数转换
│   │   └── PhotographyStrategy.swift      # 语义策略模型
│   ├── Composition/                       # 构图分析
│   │   ├── CompositionEngine.swift        # 构图评分
│   │   ├── CompositionGuidanceEngine.swift # 引导箭头生成
│   │   ├── CompositionResult.swift        # 分析结果模型
│   │   ├── CompositionTarget.swift        # 目标位置模型
│   │   ├── CurrentComposition.swift       # 当前构图状态
│   │   └── GuidanceResult.swift           # 引导输出模型
│   ├── Detection/                         # AI 检测引擎
│   │   ├── CropDetectionStrategy.swift    # 检测策略协议
│   │   ├── CoreMLCropDetector.swift       # CoreML 两阶段检测器
│   │   ├── AestheticCropDetector.swift    # Vision 框架检测器
│   │   └── BoxCenterManager.swift         # 中心追踪与对齐
│   ├── Motion/
│   │   └── MotionStabilityMonitor.swift   # 陀螺仪/加速度计
│   ├── Storage/                           # 照片持久化
│   │   ├── PhotoRecord.swift              # 数据模型（Codable）
│   │   ├── PhotoStorageService.swift      # 文件存储 + JSON 索引
│   │   └── ThumbnailGenerator.swift       # 缩略图生成
│   └── Models/                           # CoreML 模型包
│       ├── student/                      # 快速模式（轻量）
│       └── teacher/                      # 专业模式（完整精度）
├── Features/
│   ├── Main/
│   │   └── MainTabView.swift              # TabBar 根视图（4 Tab）
│   ├── Capture/                           # 核心拍摄功能
│   │   ├── Views/CaptureView.swift       # 拍摄主界面
│   │   ├── ViewModels/CaptureViewModel.swift  # 流水线状态机
│   │   └── Components/
│   │       ├── AIGuidanceOverlayView.swift    # 引导箭头覆盖层
│   │       ├── CameraPreviewSection.swift     # 预览 + 覆盖层
│   │       ├── CaptureButton.swift            # 快门按钮
│   │       ├── CompositionAdviceCard.swift    # AI 建议卡片
│   │       ├── DebugPanel.swift               # 调试信息
│   │       ├── TopControlBar.swift            # 顶部控制栏
│   │       └── UserGuidanceView.swift         # 引导文字
│   ├── Home/                             # 照片图库
│   │   ├── Views/HomeView.swift          # 网格图库
│   │   ├── Views/PhotoDetailView.swift   # 全屏浏览
│   │   ├── ViewModels/HomeViewModel.swift
│   │   └── Components/PhotoCard.swift
│   ├── Settings/
│   │   └── Views/SettingsView.swift      # 设置页
│   ├── ShareCard/
│   │   └── ShareCardGenerator.swift      # 分享卡片（1080×1440）
│   └── LiveCompose/
│       └── Views/LiveComposeView.swift   # 关于页
├── UI/
│   ├── Design/DesignSystem.swift         # 设计 Token
│   └── Components/
│       ├── CircleButton.swift            # 圆形按钮
│       ├── ContentOverlayView.swift      # 网格线 / 追踪点
│       ├── ExposureControlView.swift     # EV 滑块 + 三态切换
│       ├── FocusControlView.swift        # 对焦滑块 + 三态切换
│       ├── WhiteBalanceControlView.swift # 色温滑块 + 三态切换
│       └── ZoomRingView.swift            # 变焦预设环
└── Utilities/
    └── Helpers/
        ├── HapticManager.swift           # 触觉反馈
        └── UniformSmoother.swift         # EWMA 平滑滤波
```

### 导航

```
MainTabView (TabView, 4 Tab)
├── Tab 1 "LiveCompose"  → LiveComposeView        # 关于 / 品牌
├── Tab 2 "图库"          → HomeView                # 照片网格 → 详情
├── Tab 3 "拍摄"          → CaptureView (全屏)       # 相机 + AI 引导
└── Tab 4 "设置"          → SettingsView             # 偏好设置
```

### 相机控制架构

相机控制系统基于四个核心模型：

| 模型 | 职责 |
|------|------|
| `CameraCapability` | 设备硬件能力（支持的镜头、EV 范围、对焦范围、白平衡支持） |
| `CameraEnvironment` | 实时相机状态（ISO、曝光时间、色温、环境光） |
| `PhotographyStrategy` | 语义偏好（镜头、亮度、运动、对焦、白平衡、景深） |
| `CameraControlEngine` | 将策略翻译为硬件参数并执行 |

**策略字段与控制模式：**

```swift
struct PhotographyStrategy {
    // 每个参数都有独立的 ControlMode: .aiAuto / .manual / .locked
    var lensControl: ControlMode
    var exposureControl: ControlMode
    var focusControl: ControlMode
    var whiteBalanceControl: ControlMode
    var depthPreference: DepthPreference     // .auto / .shallow / .deep

    // 手动覆盖（仅 control == .manual 时应用）
    var manualExposureBias: Float?
    var manualFocusPosition: Float?
    var manualWhiteBalanceTemp: Float?

    // AI 语义偏好（control == .aiAuto 时应用）
    var brightnessPreference: BrightnessPreference
    var motionPreference: MotionPreference
    var whiteBalancePreference: WhiteBalancePreference
}
```

### AI 策略：双层合并

```
┌─────────────────────────────────────────┐
│       云端 AI 策略（最高优先级）           │
│    DeepSeek 返回 JSON 格式的相机参数       │
│    只有值 != "auto" 的字段                │
│    会覆盖本地引擎                          │
└──────────────────┬──────────────────────┘
                   │ 合并
┌──────────────────▼──────────────────────┐
│       本地引擎策略（兜底）                  │
│    基于规则，使用构图分析结果              │
│    无网络也能工作                         │
└──────────────────┬──────────────────────┘
                   │ 按 ControlMode 过滤
┌──────────────────▼──────────────────────┐
│       最终 PhotographyStrategy           │
│    只有 .aiAuto 的参数会被应用             │
│    .manual 和 .locked 的参数保持不变       │
└──────────────────────────────────────────┘
```

AI 可通过 JSON 控制 6 个维度：

| 字段 | 可选值 |
|------|--------|
| `lens` | ultraWide / wide / telephoto / auto |
| `brightness` | auto / darker / brighter / preserveHighlights / night |
| `motion` | freezeMotion / balanced / lowNoise |
| `focus` | auto / subjectLock / manual / macro |
| `whiteBalance` | auto / warm / cool / natural |
| `depth` | auto / shallow / deep |

## 技术栈

| 层面 | 技术 |
|------|------|
| UI | SwiftUI (iOS 17+) |
| 相机 | AVFoundation |
| AI 推理 | CoreML（端侧模型） |
| 视觉分析 | Vision（人脸、人体、显著性） |
| 云端 AI | DeepSeek API |
| 运动感知 | CoreMotion (60Hz) |
| 图片处理 | CoreImage / ImageIO |
| 响应式 | Combine |
| 数据持久化 | FileManager + JSON (Codable) |
| 第三方依赖 | 无 |

## 环境要求

- **设备**：iPhone iOS 17.0+（推荐 iPhone 11 及以上，以支持长焦和手动白平衡）
- **Xcode**：16.0+
- **相机**：后置多摄像头（完整功能需要）
- **网络**：可选（云端 AI 需要网络；本地引擎离线可用）

## 配置

1. 克隆仓库
2. 用 Xcode 打开 `LiveCapture.xcodeproj`
3. （可选）在 `Info.plist` 中添加 `DeepSeekAPIKey` 字段，填入你的 DeepSeek API Key
4. 选择你的 iPhone 设备并运行

> 没有 DeepSeek API Key 时，App 会自动降级到本地规则引擎和 Mock AI。

## 许可证

MIT License — 详见 [LICENSE](LICENSE)。

## 致谢

基于 [LiveCompose](https://github.com/LiveCompose) 开源项目。原始的构图检测模型（AdaCrop student/teacher）和运动追踪系统在使用时做了修改。
