# 构图侠 FrameHero - AI 构图相机

[English](README.md) | 简体中文

FrameHero 是一款 iOS AI 摄影助手，结合实时构图分析与智能相机控制。它分析取景画面、提供构图引导，并根据场景自动调节相机参数（曝光、对焦、白平衡、镜头选择）——让 AI 处理技术细节，你只需专注于构图。

基于 [LiveCompose](https://github.com/LiveCompose) 开源项目二次开发，新增了专业级相机控制架构。

![Platform](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Framework](https://img.shields.io/badge/Framework-SwiftUI%20%2B%20AVFoundation%20%2B%20CoreML-red)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![AI](https://img.shields.io/badge/AI-DeepSeek%20%2B%20Local%20Engine-blue)

> 📸 **截图即将更新** — 欢迎提交 PR 分享你的使用截图

## 核心功能

### 🎯 AI 构图引导
- **实时分析**取景画面，基于 CoreML 和 Vision 框架
- **魔法棒模式** — 实时引导箭头和对齐绿点，帮助你调整构图
- **双检测引擎** — CoreML（AdaCrop student/teacher 模型）和 Vision（人脸/人体/显著性）
- **陀螺仪追踪** — 设备运动补偿，稳定构图对齐
- **三分法 / 居中构图** — 多种构图目标可选

### 📷 智能相机控制

| 参数 | 控制方式 | AI 支持 |
|------|---------|--------|
| **曝光** | EV 偏移滑块（±2 EV） | 亮度偏好（暗/亮/高光保留/夜景） |
| **对焦** | 手动对焦滑块（0-1） | 自动 / 主体锁定 / 微距 |
| **白平衡** | 色温滑块（2000K-10000K） | 自动 / 暖 / 冷 / 自然 |
| **镜头** | 变焦环 + 预设切换 | 超广角 / 广角 / 长焦自动选择 |
| **景深** | 语义偏好 | 浅景深 / 深景深 / 自动 |

### ⚙️ 三态控制机制

每个相机参数都有独立的三态控制，互不干扰：

| 模式 | 图标 | 说明 | AI 能覆盖？ |
|------|------|------|-------------|
| **AI Auto** | ✨ | AI 根据场景自动调节 | 是 |
| **Manual** | 🎚 | 用户通过滑块控制 | 否 |
| **Locked** | 🔒 | 锁定当前参数值 | 否 |

> 💡 **小贴士**：拍夜景时可以手动锁定白平衡到冷色调，再让 AI 自动控制曝光和对焦，获得最佳的夜景效果。

### 🧠 双层 AI 策略

- **云端 AI（DeepSeek）** — 基于场景语义的智能判断，优先级最高
- **本地引擎（规则驱动）** — 基于构图分析结果，无网络也能工作
- **智能合并** — 云端 AI 只覆盖它有把握的字段，其余交给本地引擎

## 快速开始

### 1. 安装

```bash
git clone https://github.com/xbcmz/FrameHero.git
cd FrameHero
open FrameHero.xcodeproj
```

### 2. 配置（可选）

启用云端 AI 建议（DeepSeek）：

1. 运行 App，进入「设置 → AI 助手」
2. 打开「云端 AI 建议」开关，粘贴 DeepSeek API Key 并保存（存储在系统 Keychain，不明文落盘）
3. 点「开始测试」验证连通性；模型可选通用 V3 / 深度思考 R1

> 没有 API Key 也没关系，App 会自动降级到本地规则引擎 + 本地模拟建议，核心构图功能不受影响。

### 3. 运行

1. 用数据线连接 iPhone
2. Xcode 顶部选择你的设备（不是模拟器）
3. 按 `⌘R` 运行
4. 首次运行需在 iPhone **设置 → 通用 → VPN与设备管理** 中信任开发者证书

## 使用指南

### 基础操作

| 操作 | 说明 |
|------|------|
| 🔘 快门按钮 | 拍照（支持自动拍摄） |
| 🪄 魔法棒按钮 | 开启/关闭 AI 构图引导 |
| 🔄 切换按钮 | 切换前后摄像头 |
| 🔍 变焦环 | 切换镜头 / 滑动变焦 |

### 相机控制面板

右侧竖排的三个控制面板，从上到下分别是：

1. **曝光控制** — 拖动滑块调节曝光补偿
2. **对焦控制** — 拖动滑块手动对焦
3. **白平衡控制** — 拖动滑块调节色温

每个面板顶部有三个按钮，切换 AI Auto / Manual / Locked 模式。

### AI 建议卡片

在「设置 → AI 助手」开启「拍摄时给出 AI 建议」后，屏幕顶部会出现 AI 建议卡片，包含：

- **构图建议** — 当前画面的构图评分和改进建议
- **AI 相机参数** — AI 当前推荐的镜头、对焦、白平衡、景深设置
- 参数以胶囊标签形式展示，一眼就能看懂

### 拍摄模式

- **手动拍摄** — 按快门按钮拍照
- **自动拍摄** — 在设置中开启后，构图对齐且设备稳定时自动触发快门

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
FrameHero/
├── FrameHeroApp.swift                  # App 入口
├── Info.plist                             # 权限与配置
├── Assets.xcassets/                       # App 图标与 Logo
├── Core/
│   ├── AI/                                # AI 服务层
│   │   ├── AIConfigurationStore.swift     # AI 配置中心（设置页数据源）
│   │   ├── KeychainStore.swift            # Keychain 封装（API Key 存储）
│   │   ├── APIKeyProvider.swift           # API Key 读取（Keychain 优先）
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
│   │   └── MainTabView.swift              # TabBar 根视图（4 Tab）+ AppRouter
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
│   ├── Home/                             # 首页工作台 + 图库
│   │   ├── Views/HomeView.swift          # 首页（工作台：状态/最近拍摄/数据）
│   │   ├── Views/GalleryView.swift       # 照片网格
│   │   ├── Views/PhotoDetailView.swift   # 全屏浏览
│   │   ├── ViewModels/HomeViewModel.swift
│   │   └── Components/PhotoCard.swift
│   ├── Settings/
│   │   └── Views/SettingsView.swift      # 设置页（含 AI 助手配置）
│   ├── ShareCard/
│   │   └── ShareCardGenerator.swift      # 分享卡片（1080×1440，无水印）
├── UI/
│   ├── Design/DesignSystem.swift         # 设计 Token
│   └── Components/
│       ├── CircleButton.swift            # 圆形按钮
│       ├── ContentOverlayView.swift      # 网格线 / 追踪点
│       ├── ExposureControlView.swift     # EV 滑块 + 三态切换
│       ├── FocusControlView.swift        # 对焦滑块 + 三态切换
│       ├── WhiteBalanceControlView.swift # 色温滑块 + 三态切换
│       └── ZoomDialView.swift            # 变焦盘（胶囊焦段 + 长按细分盘）
└── Utilities/
    └── Helpers/
        ├── HapticManager.swift           # 触觉反馈
        └── UniformSmoother.swift         # EWMA 平滑滤波
```

### 导航

```
MainTabView (TabView, 4 Tab + AppRouter)
├── Tab 1 "首页"  → HomeView                   # AI 摄影工作台
├── Tab 2 "图库"  → GalleryView                # 照片网格 → 浏览 / 导出
├── Tab 3 "拍摄"  → CaptureView (全屏)          # 相机 + AI 引导
└── Tab 4 "设置"  → SettingsView               # AI 助手 / 拍摄偏好
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

### 设备能力差异

| 功能 | 单摄设备 | 双摄设备 | 三摄设备 (Pro) |
|------|---------|---------|---------------|
| 超广角 | ❌ | ✅ | ✅ |
| 长焦 | ❌ | ✅ (2x) | ✅ (3x+) |
| 手动曝光 | ✅ | ✅ | ✅ |
| 手动对焦 | ✅ | ✅ | ✅ |
| 手动白平衡 | 部分设备 | ✅ | ✅ |

## 常见问题

### Q: 为什么我的设备没有白平衡控制面板？
A: 手动调节色温需要设备支持「自定义白平衡增益锁定」。前置摄像头和部分较老设备（iPhone X 及更早）不支持，控制面板会自动隐藏。你仍然可以使用「锁定白平衡」功能。

### Q: AI 建议卡片不显示参数怎么办？
A: 检查以下几点：
1. 确保已开启魔法棒
2. 确保相机对准了有明确主体的场景
3. 如果使用云端 AI，检查网络连接和 API Key 配置
4. 无网络时本地引擎也会生成策略，但可能较简单

### Q: 为什么自动拍摄不触发？
A: 自动拍摄需要同时满足两个条件：
1. 构图对齐（追踪点进入中心对齐区）
2. 设备稳定（陀螺仪检测到手持稳定）
3. 已在设置中开启自动拍摄

### Q: 怎么换检测引擎？
A: 在「设置 → 构图引擎」中切换。CoreML 引擎精度更高但稍慢，Vision 引擎更快但只检测人脸/人体/显著性区域。

### Q: 照片存在哪里？
A: 照片保存在 App 的 Application Support 目录中，不会自动存入系统相册。你可以在详情页手动保存到相册，或生成分享卡片。

### Q: 支持哪些语言？
A: 当前 UI 主要为中文。架构支持国际化，欢迎提交 PR 增加其他语言。

## 开发路线图

- [x] **Phase 0** — 镜头能力检测 + 多镜头切换
- [x] **Phase 1** — 曝光控制（EV 滑块 + 三态机制）
- [x] **Phase 2** — 对焦控制（手动对焦 + 三态机制）
- [x] **Phase 3** — 白平衡控制（色温滑块 + 三态机制）
- [x] **Phase 4** — 本地 AI 相机策略引擎
- [x] **Phase 5** — 云端 AI 策略集成（DeepSeek）
- [ ] **Phase 6** — 低光检测 + 夜景模式
- [ ] **Phase 7** — HDR / 曝光包围
- [x] **Phase 8** — 专业模式控制面板 UI 重构（右侧折叠面板 + 变焦盘）
- [ ] **Phase 9** — 拍摄参数预设（人像/风景/美食等一键预设）

## 贡献指南

欢迎贡献代码！以下是参与方式：

### 报告问题
- 使用 GitHub Issues 提交 bug 或功能建议
- 提交 bug 时请注明设备型号、iOS 版本和复现步骤

### 提交代码
1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 代码规范
- 使用 SwiftUI + MVVM 架构
- 每个文件顶部添加注释说明用途
- UI 组件放在 `UI/Components/`，功能模块放在 `Features/`
- 相机操作必须在 `sessionQueue` 线程执行
- API Key 等敏感信息禁止硬编码

## 许可证

MIT License — 详见 [LICENSE](LICENSE)。

## 致谢

项目原名 LiveCapture，现更名 **构图侠 FrameHero**。

基于 [LiveCompose](https://github.com/LiveCompose) 开源项目。原始的构图检测模型（AdaCrop student/teacher）和运动追踪系统在使用时做了修改。

感谢所有贡献者，以及开源社区的支持。
