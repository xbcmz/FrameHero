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

## 设置

- **AI 助手**：AI 构图入口开关；云端 AI 建议（DeepSeek）预留——API Key 存储在系统 **Keychain**，支持连接测试（不消耗 token）、模型选择（通用 V3 / 深度思考 R1）、自定义接口地址（自建代理）
- **拍摄偏好**：自动拍照开关、拍照延迟、构图引擎档位、外观主题

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

## 目录结构

```text
FrameHero/
├── FrameHeroApp.swift                      # App 入口
├── Info.plist
├── Assets.xcassets/                        # 图标（light/dark/tinted）
├── Core/
│   ├── AI/
│   │   ├── AIConfigurationStore.swift      # AI 配置中心（设置页数据源 + 使用计数）
│   │   ├── KeychainStore.swift             # Keychain 封装（API Key 存储）
│   │   ├── APIKeyProvider.swift            # API Key 读取（Keychain 优先）
│   │   ├── DeepSeekService.swift           # DeepSeek API（含连接测试）
│   │   ├── MockPhotographer.swift          # 离线模拟建议
│   │   ├── AIAdviceProvider.swift          # 建议提供协议
│   │   └── PhotographyAdvisor.swift        # 构图分析编排（云端开关可控）
│   ├── Camera/
│   │   ├── CameraManager.swift             # 会话生命周期（+Session/Zoom/Photo/
│   │   │                                   #   VideoOutput/Control/Capability/Models）
│   │   ├── CameraCapability.swift          # 硬件能力 + 环境状态模型
│   │   ├── CameraControlEngine.swift       # 策略 → 硬件参数（差异化下发）
│   │   ├── PhotographyStrategy.swift       # 三态语义策略
│   │   └── CameraPreviewView.swift         # 预览层
│   ├── Composition/
│   │   ├── CompositionPlan.swift           # 构图方案模型 + 本地方案生成器
│   │   ├── SceneClassifier.swift           # 场景识别（Vision 分类器多帧投票）
│   │   ├── AdaCropPlanAdvisor.swift        # AdaCrop 最佳构图区预测（Fast/Pro）
│   │   ├── CompositionEngine.swift         # 构图评分 + 主体提取（群像/连续性）
│   │   ├── CompositionGuidanceEngine.swift # 目标差值 → 方向/进度/达标
│   │   └── ...(结果/目标/引导模型)
│   ├── Detection/
│   │   ├── CropDetectionStrategy.swift     # 检测模式定义
│   │   └── AestheticCropDetector.swift     # Vision 人脸/人体/显著性
│   ├── Models/                             # AdaCrop CoreML 模型（student/teacher）
│   ├── Motion/MotionStabilityMonitor.swift # 陀螺仪稳定性
│   └── Storage/                            # 照片存储（评分随片入库）
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
- [x] **姿态水平仪** — CoreMotion 侧倾角 → 水平参考线 + 倾斜纠正引导（ARKit 后续可选）
- [x] **自动焦段切换** — 选中方案时自动执行焦段建议

## 贡献

欢迎 Issue 与 PR。提交代码请保持：SwiftUI + MVVM、相机操作在 `sessionQueue`、敏感信息不入代码、每个文件顶部注明用途。

## 许可证

MIT License — 详见 [LICENSE](LICENSE)。

## 致谢

项目原名 LiveCapture，现更名 **FrameHero**。基于 [LiveCompose](https://github.com/LiveCompose) 开源项目，原始的构图检测模型（AdaCrop Student/Teacher）与运动追踪系统在使用中做了深度改造。
