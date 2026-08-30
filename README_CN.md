# FrameHero 构图侠 - AI 构图相机

[English](README.md) | 简体中文

FrameHero 是一款 iOS AI 构图相机，围绕一个核心问题打造：

> **"我现在这个场景，怎么拍会更好？"**

打开相机 → 点一下「AI 构图」→ AI 分析场景并给出 **1~3 个构图方案** → 选择一个 → 实时引导你移动手机 → **构图完成** → 拍摄。AI 负责思考，手机负责实时判断，你负责移动手机。

基于 [LiveCompose](https://github.com/LiveCompose) 开源项目二次开发，相机控制与构图引导架构已深度重构。

![Platform](https://img.shields.io/badge/Platform-iOS-blueviolet)
![Framework](https://img.shields.io/badge/Framework-SwiftUI%20%2B%20AVFoundation%20%2B%20CoreML%20%2B%20Vision-red)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![AI](https://img.shields.io/badge/AI-Local%20Realtime%20%2B%20Cloud%20Optional-blue)

## 核心体验：AI 摄影师

点一下快门旁的 ✨ 按钮，AI 摄影师开始工作：

```text
分析场景（约 1 秒，全本地）
    ↓
「AI 摄影师 · 发现 3 种拍法」
    ┌────────────────┐
    │ 人物与环境  空间感 │  ← 推荐方案（绿框）
    ├────────────────┤
    │ 人物特写  突出人物 │
    ├────────────────┤
    │ 大面积留白  极简   │
    └────────────────┘
    ↓ 选择方案
画面出现目标标记圈 + 一行建议
    ↓ 跟着引导移动手机
主体进入标记圈 → 变绿 ✓ 构图完成
    ↓
拍摄（可开启自动拍摄倒计时）
```

- **方案是结构化的**：构图类型 / 目标主体位置 / 距离建议 / 焦段建议 / 置信度，不是一句空泛的文字
- **MVP 支持七类构图**：三分法 · 居中对称 · 引导线 · 框架构图 · 前景层次 · 留白 · 人物环境构图
- **场景识别**：人像 / 美食 / 夜景 / 风景 / 街拍 / 文档（Vision 分类器多帧投票，离线）

## 智能细节

- **构图引擎三档可选**（设置 → 构图引擎）：
  - **Vision** — 纯摄影规则定目标，不跑模型
  - **Fast** — AdaCrop Student 模型一次性预测"最佳构图区"校准方案目标
  - **Pro** — AdaCrop Teacher 模型，全量精度校准
- **群像感知**：多人入画自动切换合影方案（居中合影 / 全员全景 / 前排特写），跟踪群体包围盒
- **前视空间**：识别人物脸朝向，目标点自动给视线方向留白
- **主体连续性**：多人相似时主体不跳变（帧间 IoU 匹配）
- **场景参数预设**：识别到夜景/美食/风景等场景时，自动切换相机参数偏好（只动 AI Auto 档，你手动锁定的参数不碰）
- **构图完成的仪式感**：标记圈变绿收缩 + 三分线渐隐 + 快门绿色脉冲；开启自动拍摄后出现倒计时进度环与渐强震动，**手抖自动取消**防糊片
- **本地优先 + 云端渐进增强**（设置 → AI 助手 → 构图分析模式）：`auto` 模式下本地规则方案**瞬间出图**（不用等网络往返）；如果云端（DeepSeek）带来更细腻场景推理的方案在你选定前赶到，UI 会无缝升级为云端方案。`localOnly` 完全跳过云端请求；`cloudOnly` 始终等云端（失败/超时自动回退本地）。会话级递增计数器会丢弃任何在你已开始引导或已开启新会话后才姗姗来迟的过期云端响应。

## 拍摄辅助

一组即使在**没有开启 AI 构图会话的纯净相机模式下也常驻生效**的小助手：

- **常驻水平仪**：设备侧倾角随时驱动取景器里的水平参考线（不再局限于 AI 引导阶段），倾斜超过 2.5° 转黄提醒。
- **实时曝光风险提示**：1Hz 节流分析实时预览的高光/阴影裁剪，过曝/欠曝时弹出提示条，带**一键 ±1EV 补偿**按钮，直接复用已有的曝光控制。
- **自拍倒计时**：顶部工具栏可选经典的 3 秒/10 秒倒计时，与 AI 自动拍摄倒计时互斥独立，复用同一套倒计时环 UI 与震动节奏。
- **拍后清晰度预审**：单张拍摄落盘后立即跑一次拉普拉斯方差清晰度检测；判糊时弹出提示，**一键重拍**（删除糊片、重新触发快门）。
- **连拍自动优选**：长按快门连拍，松手后对该组所有照片评分（清晰度优先，其次是 AI 会话当时的构图分），最佳一张在图库里打上星标。

## 专业相机控制（三态机制）

| 参数 | 手动控制 | AI Auto 档 |
|------|---------|-----------|
| **曝光** | EV 滑块（±2 EV，实时显示硬件真实值） | 亮度偏好（暗/亮/高光保留/夜景） |
| **对焦** | 手动对焦滑块（0-1） | 主体锁定 / 微距 |
| **白平衡** | 色温滑块（2000K-10000K） | 暖 / 冷 / 自然 |
| **镜头** | 变焦盘（胶囊焦段 + 长按细分盘） | 超广角 / 广角 / 长焦建议 |

每个参数独立三态：**AI Auto ✨ / Manual 🎚 / Locked 🔒**——可以让 AI 管曝光、自己锁白平衡，互不干扰。滑杆在 AI Auto 档实时显示相机硬件真实值。

## 首页工作台

- 问候语 + 大型「开始 AI 拍摄」入口
- AI 助手状态卡：构图引导 / 场景识别 / 人物检测 是否就绪
- 最近拍摄横滑预览，右上角显示**按下快门那一刻的 AI 构图评分**
- 「今天」数据卡：拍摄照片 / AI 建议 / 平均评分

## 图库

- 三列网格 + 全屏浏览 + 多选删除（选择模式 / 长按菜单，删除前二次确认）
- 导出两种样式：**原图直出**（原始 JPEG 字节不经重编码）或**信息卡片**（照片 + 日期 + EXIF 参数，无水印）
- **从系统相册导入**（`PhotosPicker`，单次最多 30 张）——不需要完整相册权限，选择器本身只把你明确选中的照片交给 App
- **本地优先的 AI 点评**：点开任意照片 → 立即在设备本地跑出点评（构图/光线/主体，基于 Vision 框架的人脸/显著性/曝光启发式规则），零网络依赖；配置了云端 AI 时还可以额外请求更细腻的 DeepSeek Vision 点评，与本地点评一并持久化保存
- 缩略图角标优先显示已保存的点评分，没点评过则回退到拍摄时的构图评分；连拍优选出的最佳一张会打上 ⭐ 星标

## 设置

- **AI 助手**：AI 构图入口开关；云端 AI 建议（DeepSeek）预留——API Key 存储在系统 **Keychain**，支持连接测试（不消耗 token）、模型选择（通用 V3 / 深度思考 R1）、自定义接口地址（自建代理）；**构图分析模式**选择器（`auto`/`localOnly`/`cloudOnly`），可以直接对比本地极速方案与云端增强方案的差异
- **拍摄偏好**：自动拍照开关、拍照延迟、自拍倒计时、构图引擎档位、外观主题

## AI 与本地的分工

```text
                 Camera (AVFoundation)
                        │
        [点一下 AI 构图] 一次性分析（~1 秒，本地）
                        │
      ┌─────────────────┼──────────────────┐
      ↓                 ↓                  ↓
  场景分类器        人物/人脸检测        AdaCrop 裁切模型
 (多帧投票)        (群体包围盒/朝向)     (Fast/Pro 校准目标)
      └─────────────────┼──────────────────┘
                        ↓
                 构图方案 ×3（结构化）
                        ↓ 用户选择
              ┌─── 实时引导循环（10fps，全本地）───┐
              │ 主体跟踪（人物/显著性）             │
              │ 目标偏差 → 方向指令 → 完成判断      │
              └──────────────┬───────────────────┘
                             ↓
                    ✓ 构图完成 → 拍摄
```

> 云端 LLM（DeepSeek）**不参与实时引导**——逐帧请求延迟高、成本高、用户没空读。它留给「拍后点评」（路线图中），届时通过 `CompositionPlanProviding` / `AIAdviceProvider` 协议接入，换任何视觉大模型只需替换实现。

## 关键技术实现

### 构图方案生成
- **本地启发式**（`CompositionPlan.LocalHeuristicPlanProvider`）：基于场景类型 + 人物/人脸几何的纯规则方案，零延迟，始终可用。
- **云端方案**（`CompositionPlanGeneration.swift`）：每轮 AI 构图会话中 DeepSeek Vision 返回一次结构化 JSON（`scene` / `main_subject` / `plans[]`，每个方案带 `subject_target`、`camera_action.{horizontal,vertical,distance}`、`focal_length`），由 `CompositionPlanMapper` 映射为本地 `CompositionPlan` 模型。解析/映射都是无状态的纯函数（`static func`），与 `CaptureViewModel` 的重试/回退编排逻辑解耦，无需 mock 网络层即可单独单元测试。
- **AdaCrop 校准**：`AdaCropPlanAdvisor` 每会话跑一次 Fast/Pro CoreML 模型预测“最佳构图裁切区”，`PlanGeometry.mapThroughCrop` 把方案的主体目标位置重新映射进该裁切区，在纯规则位置之上进一步精细化“主体到底放哪”。

### 姿态水平仪
`MotionStabilityMonitor.attitude.roll`（CoreMotion 设备姿态）驱动 `CaptureView`/`CaptureViewModel` 中的实时水平参考线与候斜文案（`cameraRollDegrees`，节流到 ~6.7fps 以避免 SwiftUI 过度重渲染）。

### 距离估算
`CaptureViewModel.distanceEstimateText` 用 `person.heightRatio × zoomState.currentFactor`（主体屏幕高度占比 × 当前变焦倍率）分档为“~5 米开外/3-5 米/2 米/1 米/0.5 米内”粗略提示——不需要额外模型，直接复用跟踪管线已有的人体框。结合 AI 方案的 `camera_action.distance`（`closer`/`keep`/`farther`），共同驱动“靠近一点/退远一点”的引导文案。

### 本地优先 + 云端渐进增强管线
`CaptureViewModel` 在会话开始时无条件立即跑本地方案生成；云端请求（若 `activeAnalysisMode != .localOnly`）并行发出，成功返回后只有在用户还没选方案、会话也没往前推进的情况下才会**替换**当前展示的方案——通过请求发出时捕获的递增 `aiSessionGeneration` 计数器在完成时比对来把关，任何来自已被取代/取消会话的迟到云端响应都会被静默丢弃，而不会污染当前 UI 状态。

### 本地照片点评引擎
`LocalPhotoCritiqueEngine`（Core/AI/Vision）纯本地给照片打分：Vision 人脸/显著性检测判断主体取景，直方图亮度分析判断曝光/逆光，简单的三分法距离规则判断构图，综合成 0-100 分外加带标签的亮点/改进建议，全程不到一秒且零网络请求。`PhotoCritique` 是 `Codable` 的，带一个 `source` 字段（`local`/`cloud`），随 `PhotoRecord` 一起持久化，重新打开照片不会重复跑分析。

### 拍摄辅助启发式算法
- `BlurDetector`（Core/AI/Vision）：对降采样到约 480px 的灰度缩略图做经典 3×3 拉普拉斯卷积算方差，低于阈值判定为可能拍糊；跑在关键路径之外，JPEG 落盘后立即触发。
- `ExposureAnalyzer`（Core/Camera）：直接采样实时预览像素缓冲区的 Y 平面（不经 CIImage/Vision 的额外开销），1Hz 节流，按高光/阴影裁剪比例判定过曝/欠曝。
- 连拍分组：长按连拍期间每次快门共享同一个 `PhotoRecord.burstID`；松开快门后延迟一小段时间（等在途的保存/清晰度检测落地），再按「清晰度优先、其次构图评分」给这一组排序，把胜出者标记为 `isBurstBest`。

### 并发模型
每个后台 worker 只拥有一条专属串行队列，内部需要分支判断的状态都维护一份**队列专属镜像**；`@Published` 属性只能作为面向主线程的单向输出，绝不能在后台队列上回读（主线程异步写入会与后台读取竞争）。这条全项目约定是在修复多个真实数据竞争后正式确立的：
- `MotionStabilityMonitor`：迟滞判断必须分支内部镜像 `stableState`（仅在 `dataQueue` 上读写），而不是 `@Published isStable`（仅在主线程读写）；`largeMotionFlag` 的延迟复位也从 `DispatchQueue.main.asyncAfter` 改回 `dataQueue`，同理。
- `SceneClassifier`：`classify()` 跑在相机帧回调的 `videoOutputQueue` 上，`reset()` 由主线程 UI 操作触发，两者现在都经过专用的 `stateQueue` 串行化对 `votes`/`currentDecision` 的访问。
- `CaptureViewModel` 的曝光风险检测：`lastExposureCheckTime`（节流计时用）严格限定在相机的 `videoOutputQueue` 上读写；`exposureWarning`/`exposureSuppressedUntil` 严格限定在主线程读写——两者绝不交叉，后台采样器和主线程「一键补偿」的点击永远不会争同一个字段。`AVCapturePhotoOutput` 代理回调（苹果不保证其回调线程）在动任何连拍/会话状态之前也统一先 hop 到主线程。

## 目录结构

```text
FrameHero/
├── FrameHeroApp.swift                      # App 入口
├── Info.plist
├── Assets.xcassets/                        # 图标（light/dark/tinted）
├── Core/
│   ├── AI/
│   │   ├── AIConfigurationStore.swift      # AI 配置中心（设置页数据源 + 使用计数 + 分析模式）
│   │   ├── KeychainStore.swift             # Keychain 封装（API Key 存储）
│   │   ├── APIKeyProvider.swift            # API Key 读取（Keychain 优先）
│   │   ├── DeepSeekService.swift           # DeepSeek API（含连接测试）
│   │   ├── MockPhotographer.swift          # 离线模拟建议
│   │   ├── AIAdviceProvider.swift          # 建议提供协议
│   │   ├── PhotographyAdvisor.swift        # 构图分析编排（云端开关可控）
│   │   └── Vision/
│   │       ├── PhotoCritique.swift             # 拍后点评模型（本地/云端）
│   │       └── LocalPhotoCritiqueEngine.swift  # 本地点评（Vision 框架）
│   ├── Camera/
│   │   ├── CameraManager.swift             # 会话生命周期（+Session/Zoom/Photo/
│   │   │                                   #   VideoOutput/Control/Capability/Models）
│   │   ├── CameraCapability.swift          # 硬件能力 + 环境状态模型
│   │   ├── CameraControlEngine.swift       # 策略 → 硬件参数（差异化下发）
│   │   ├── PhotographyStrategy.swift       # 三态语义策略
│   │   ├── ExposureAnalyzer.swift          # 实时曝光风险（Y 平面采样）
│   │   └── CameraPreviewView.swift         # 预览层
│   ├── Composition/
│   │   ├── CompositionPlan.swift           # 构图方案模型 + 本地方案生成器
│   │   ├── SceneClassifier.swift           # 场景识别（Vision 分类器多帧投票）
│   │   ├── AdaCropPlanAdvisor.swift        # AdaCrop 最佳构图区预测（Fast/Pro）
│   │   ├── CompositionEngine.swift         # 构图评分 + 主体提取（群像/连续性）
│   │   ├── CompositionGuidanceEngine.swift # 目标差值 → 方向/进度/达标
│   │   └── ...(结果/目标/引导模型)
│   ├── Detection/
│   │   ├── CropDetectionStrategy.swift     # 检测模式枚举（Vision/Fast/Pro）
│   │   └── AestheticCropDetector.swift     # Vision 人脸/人体原始检测（供 CompositionEngine 使用）
│   ├── Models/                             # AdaCrop CoreML 模型（student/teacher）
│   ├── Motion/MotionStabilityMonitor.swift # 陀螺仪稳定性
│   └── Storage/                            # 照片存储（评分/点评/连拍分组）
├── Features/
│   ├── Main/MainTabView.swift              # TabBar + AppRouter
│   ├── Capture/
│   │   ├── Views/CaptureView.swift         # 拍摄主界面
│   │   ├── ViewModels/CaptureViewModel.swift # AI 构图会话状态机
│   │   └── Components/
│   │       ├── CompositionCoachOverlayView.swift  # 方案卡片 + 引导覆盖层
│   │       ├── CameraPreviewSection.swift  # 预览 + 覆盖层容器
│   │       ├── CaptureButton.swift         # 快门（倒计时环/连拍/达标脉冲）
│   │       └── TopControlBar.swift         # 顶部栏
│   ├── Home/
│   │   ├── Views/HomeView.swift            # 首页工作台
│   │   ├── Views/GalleryView.swift         # 图库（多选删除）
│   │   ├── Views/PhotoDetailView.swift     # 浏览 + 导出（原图/卡片）
│   │   └── ViewModels/HomeViewModel.swift
│   ├── Settings/Views/SettingsView.swift   # 设置（含 AI 助手区）
│   └── ShareCard/ShareCardGenerator.swift  # 信息卡片渲染（无水印）
├── UI/
│   ├── Design/DesignSystem.swift           # 设计 Token
│   └── Components/                         # 变焦盘 / EV/对焦/白平衡滑杆
└── Utilities/Helpers/                      # 触觉反馈 / 平滑滤波
```

## 快速开始

```bash
git clone https://github.com/xbcmz/FrameHero.git
cd FrameHero
open FrameHero.xcodeproj
```

1. Xcode 顶部选择你的 iPhone（需 iOS 17+，真机）
2. `⌘R` 运行
3. AI 构图**开箱即用**（本地推理，无需任何配置）

### 可选：云端 AI（DeepSeek）

1. 进入「设置 → AI 助手」
2. 打开「云端 AI 建议」，粘贴 API Key 保存（存储在 Keychain）
3. 点「开始测试」验证连通性

> 没有 Key 也不影响 AI 构图——实时引导全部本地完成，云端能力留给后续的拍后点评。

## 技术栈

| 层面 | 技术 |
|------|------|
| UI | SwiftUI (iOS 17+) |
| 相机 | AVFoundation |
| 场景识别 | Vision（VNClassifyImageRequest 多帧投票） |
| 人物/显著性 | Vision（人脸/人体/注意力显著性） |
| 构图模型 | CoreML（AdaCrop Student/Teacher，可选档位） |
| 云端 AI | DeepSeek API（预留，可换任意 VLM） |
| 运动感知 | CoreMotion |
| 数据持久化 | Keychain + FileManager + JSON |
| 第三方依赖 | 无 |

## 常见问题

### Q: AI 构图需要联网吗？
A: 不需要。场景识别、人物检测、构图方案生成、实时引导全部在设备本地完成，零延迟、离线可用。云端 LLM 仅用于路线图中的「拍后点评」。

### Q: 三个构图引擎档位有什么区别？
A: **Vision** 用纯摄影规则定目标位置；**Fast/Pro** 会额外跑一次 AdaCrop CoreML 模型（Student/Teacher），预测最佳构图区来校准方案目标。实时引导体验三档一致，差异在 AI 给你的目标位置上。

### Q: 引导的"往左移/往右移"是根据什么判断的？
A: 目标位置来自所选构图方案（规则 + 模型校准），实时偏差由构图引导引擎计算。目标点锁定后会以虚线标记圈画在画面上——把主体放进圈里就是终点，不会左右横跳。

### Q: 前置摄像头方向对吗？
A: 指令方向与标记圈位置都做了前置镜像校正，跟着说"向右移"就真的向右移。

### Q: 为什么我的设备没有白平衡滑杆？
A: 手动色温需要设备支持「自定义白平衡增益锁定」，部分前置/老设备不支持时面板自动隐藏，锁定白平衡功能仍可用。

### Q: 照片存在哪里？
A: App 沙盒内的 Application Support 目录，不进系统相册。在照片浏览页可导出：**原图直出**（原始 JPEG 字节）或**信息卡片**。

## 路线图

- [x] **Phase 0-5** — 镜头能力 / 曝光 / 对焦 / 白平衡三态控制 + 本地策略引擎 + 云端策略
- [x] **Phase 6-8** — 专业控制面板重构 / 变焦盘 / AI 构图会话范式
- [x] **Phase 9** — AI 摄影师 MVP：场景识别 → 构图方案 → 实时引导
- [x] **Phase 10** — 群像感知 / 主体连续性 / AdaCrop 引擎档位
- [x] **拍后点评** — DeepSeek Vision 单张照片结构化点评（得分/亮点/改进建议）
- [x] **VLM 方案提供方** — DeepSeek Vision 驱动构图方案
- [x] **姿态水平仪** — CoreMotion 侧倾角 → 水平参考线 + 倾斜纠正引导（ARKit 后续可选），现已从“仅 AI 引导阶段显示”升级为**常驻显示**
- [x] **自动焦段切换** — 选中方案时自动执行焦段建议
- [x] **本地优先 + 云端渐进增强** — 本地方案瞬间出图，云端方案在赶得上时无缝升级 UI
- [x] **相册导入 + 本地优先 AI 点评** — `PhotosPicker` 导入，基于 Vision 的本地点评 + 可选 DeepSeek Vision 增强
- [x] **拍摄辅助套件** — 拍后模糊重拍、自拍倒计时、实时曝光风险提示与一键补偿、连拍自动优选

## 贡献

欢迎 Issue 与 PR。提交代码请保持：SwiftUI + MVVM、相机操作在 `sessionQueue`、每个文件顶部注明用途、敏感信息不入代码；新增后台 worker 时绝不在它自己的队列上回读 `@Published` 属性，改用队列专属镜像（见上文「并发模型」）。

## 许可证

MIT License — 详见 [LICENSE](LICENSE)。

## 致谢

项目原名 LiveCapture，现更名 **FrameHero**。基于 [LiveCompose](https://github.com/LiveCompose) 开源项目，原始的构图检测模型（AdaCrop Student/Teacher）与运动追踪系统在使用中做了深度改造。
