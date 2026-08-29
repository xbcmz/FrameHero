# LiveCapture 优化交接文档

> 用途：开新对话时让 AI 先读本文件（说「先读 OPTIMIZATION_HANDOFF.md」即可接上进度）。
> 更新时间：2026-08-29。GitHub 已同步（origin: git@github.com:xbcmz/LiveCapture.git，分支 main）。

## 项目位置与验证命令

- 路径：`/Users/mr./Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6a905bc7582b3f8001d2a591/LiveCapture-main`
- 编译验证（已验证可用，无签名）：
  ```bash
  xcodebuild -project LiveCapture.xcodeproj -scheme LiveCapture \
    -destination 'generic/platform=iOS Simulator' -configuration Debug \
    build CODE_SIGNING_ALLOWED=NO
  ```
- 注意：`project.yml` / `generate_xcode_project.py` 已被删除，**新增 .swift 文件必须手动注册进 `LiveCapture.xcodeproj/project.pbxproj`**（PBXBuildFile + PBXFileReference + 组 children + Sources phase 四处）。
- git 有完整历史：`7ea6b6c` 是修复前基线，随时可 diff/回滚。

## 已完成（本轮 2026-08-29，约 20 项修复）

### 可用性根因（「不如原生相机」的主因，已全修）
- 硬件参数 10-20Hz 全量重放 → ControlEngine 已下发状态差异化应用，只在值变化时下发
- 白平衡色温→增益公式域错误（差 100 倍，画面全偏蓝绿）→ 重写为 Tanner-Helland + 归一化中和增益
- 构图引导方向物理反转 + 魔法棒目标点 Y 镜像 → 统一为「手机移动方向」语义
- AI 网络请求冻结整条构图/引导流水线 → 分析防抖与网络解耦（VM 本地 in-flight 标志）
- CoreML 每次检测重新加载模型 + 失败伪造结果 → init 加载一次、失败返回 nil + 1.5s 重试冷却
- 拍照后强制关闭魔法棒流水线 → 已移除；照片裁剪 3:4 对齐取景（保留 EXIF）
- 自动拍摄误触：BoxCenterManager 换目标不清锁 → setBaseCenter 清除锁定态

### 稳定性与性能
- Motion 只留 deviceMotion 融合流（去加速度计/陀螺仪冗余）；稳定性/大幅运动仅变化时发布；CoreMotion→主线程 60→30Hz
- 移除每帧 lastPixelBuffer 强引用（缓冲池回收受阻导致丢帧）
- detectPeople 高频路径跳过显著性检测；AestheticCrop 中心裁切 0.1→0.5
- Advisor 把真实变焦传给构图引擎（原来镜头推荐永远按 1.0x 算）

### UI/交互（原生相机化）
- 布局重排：全宽单列（顶栏/底栏贴边），右侧参数改为折叠式圆钮（一次只展开一个面板，展开时只留当前按钮）
- 前置画面双重镜像修复（系统连接层自动镜像 + 手动 transform 叠加所致）；3D 翻转动画移除（会镜像整个覆盖层）
- 恢复点按对焦/曝光（预览层 captureDevicePointConverted + 黄框指示器）
- 原生风格变焦盘 ZoomDialView：胶囊焦段（.5/1/2）+ 长按唤出细分盘；上限 25×、分段非线性刻度、相机指令 30Hz 节流、整数格式标签、碰撞跳过、远段无刻度点
- 变焦归还用户：lensControl 默认 .locked（原 .aiAuto 且无 UI 可关，导致画面忽大忽小）；AI 控镜路径加 3s 冷却 + 推荐阈值滞回
- 「检测到人就单次锁焦」改为连续自动对焦
- 前置变焦封顶 2×；点按焦段 ramp 速率 5-10 → 12-20

## 未完成 / 已知问题（下轮优化清单，按优先级）

### P1（直接影响体验）
1. **曝光/对焦/白平衡滑块不反映相机真实状态**：CaptureView 里传给三个 ControlView 的 Binding 是假双向（set 为空），AI Auto 模式下滑块位置与实际参数脱节；且 `cameraEnvironment.currentZoomFactor` 只在 Control 操作后更新，变焦手势后不更新
2. **PhotoStorageService.records 跨线程数据竞争**：loadRecords 主线程读 vs storageQueue 写，非原子 Array
3. **自动拍摄流水线与新布局的整合**：魔法棒开启后引导 UI（裁切框/追踪点/中心圆）仍是旧交互逻辑，与其余原生化的 UI 风格割裂；需要重新设计「对齐 → 倒计时 → 拍摄」的呈现
4. **点按对焦的前置坐标**需真机验证（captureDevicePointConverted 已接管连接镜像，理论正确）

### P2（代码质量）
5. CoreML 预处理：非等比缩放拉伸到 224×224（破坏宽高比）、逐像素手写循环（应 Accelerate/vImage）、orientation 参数收下但没传给模型
6. DeepSeekService：无请求超时/代际标记，迟到的旧响应仍会覆盖 lastResult；API Key 明文在 Info.plist（上线前换 Keychain 或服务端代理）
7. MotionStabilityMonitor.start() 若被调用两次会开双份数据流（无重入保护）
8. VideoOutput/Preview 的视频稳定配置是死代码（#available(iOS 13) 分支为空，实际从未设置 stabilization）
9. ZoomRingView.swift 已不再被引用（被 ZoomDialView 替代），可删（注意 pbxproj 同步清理）
10. debugMessage/DebugPanel 仍是开发向文案，量产应隐藏

### P3（功能演进，设计文档里有规划）
11. 夜景/低光检测（路线图 Phase 6）、HDR（Phase 7）
12. 拍摄参数预设（人像/风景/美食，Phase 9）
13. 设计文档 `../ai-photography-assistant-design/ai-photography-assistant-design.html` 里有五维构图评分、机位推荐、Qwen3-VL、ARKit 的演进方案，可与代码对照推进
14. 图库（HomeView/GalleryView/SettingsView/ShareCardGenerator）尚未审查过

## 关键架构速记

```
数据流：相机帧(30-60fps)
  ├→ 构图引擎 → 引导箭头/目标点（AI 开启时 10fps 分析，目标慢、引导计算每帧）
  ├→ PhotographyAdvisor（Vision 检测 → 构图评分 → 本地规则 + DeepSeek 云端合并）
  │     ↓ PhotographyStrategy（语义偏好，每参数三态 aiAuto/manual/locked）
  │   CameraControlEngine（差异化应用，默认 lens locked）
  │     ↓
  │   CameraManager 硬件（曝光/对焦/白平衡/变焦）
  └→ 拍照：AVCapturePhotoOutput → 3:4 裁剪(保EXIF) → PhotoStorageService(App 私有目录)

变焦：ZoomDialView（胶囊+长按盘）| 捏合手势 → CameraManager+Zoom → videoZoomFactor
相机三态控制 UI：CaptureView.professionalControlColumn（折叠式，右缘）
线程约定：sessionQueue（会话/硬件）、videoOutputQueue（帧）、主线程（UI/@Published）
```

- 核心文件：`CaptureViewModel.swift`（1266 行，中枢）、`CameraControlEngine.swift`、`CameraManager+*.swift`、`ZoomDialView.swift`
- AI 建议默认关闭（`isPhotographyAdviceEnabled = false`），顶部「···」菜单可开
- 视频帧方向：竖屏下 buffer 已是 3:4 portrait，`pixelOrientation` 用宽高判断
