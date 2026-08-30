# LiveCapture 优化交接文档

> 用途：开新对话时让 AI 先读本文件（说「先读 OPTIMIZATION_HANDOFF.md」即可接上进度）。
> 更新时间：2026-08-29（dev 分支完成第七批：产品范式重构，AI 构图成为主体验）。GitHub origin: git@github.com:xbcmz/FrameHero.git；main = v1.0.0 稳定基线（旧范式），dev = 新范式开发线。

## 第七批（dev 分支，2026-08-29：产品范式重构——AI 构图成为主体验）

> 背景：用户判断原方向（LiveCapture 魔法棒 + AI 贴片）与初衷背离，对标可颂「灵感跟拍」（场景识别→配方建议）与 Doka Cam（一次触发→极简 AR 引导）重构拍摄页。

- **魔法棒流水线整体下线**：构图流水线开关、裁切框/追踪点/中心圆、BoxCenterManager 对齐、CoreML AdaCrop 裁切检测、9 阶段状态机全部移除；CameraControlEngine 三态控制、点按对焦、变焦盘保留，自动拍摄改造后复用（构图达标触发）
- **新增「AI 构图会话」（Doka 式一次触发）**：快门左侧 sparkle 按钮 → CoachPhase 状态机（idle/analyzing/guiding/achieved）
  - SceneClassifier（新文件）：VNClassifyImageRequest 多帧投票 + 滞回 → 7 类场景（人像/美食/夜景/风景/街拍/文档/通用）
  - 场景 → 参数预设：只改写 aiAuto 参数（人像=主体锁定+浅景深，美食=微距+自然白平衡，夜景=夜景+低噪，风景=超广角+深景深，街拍=凝固运动）
  - 构图引导：CompositionGuidanceEngine 数据层复用 → CompositionCoachOverlayView（新文件）：淡三分线 + 场景标签 + 一行建议 chip，达标即绿色确认 + 可选自动拍摄
- **DeepSeek 退出实时路径**：PhotographyAdvisor 新增 `isCloudAdviceEnabled`（默认 false），实时引导纯本地 Vision 零延迟；LLM 留给拍后点评（未实现），换模型只需换 aiProvider 实现
- **删除文件（6）**：DebugPanel / AIGuidanceOverlayView / CompositionAdviceCard / ContentOverlayView / BoxCenterManager / CoreMLCropDetector（检测协议 CropDetectionStrategy.swift 保留，DetectionMode 枚举在其中）；UniformPointSmoother 从 BoxCenterManager 迁回 UniformSmoother.swift
- CaptureViewModel 1322 行 → ~700 行；快门评分快照仅在 AI 会话中产生（未开会话的照片无评分）；`aiAdviceEnabled` 语义改为「AI 构图入口开关」，默认开
- 已知待调：场景识别粒度（系统分类器较粗）、无主体场景的目标构图质量、chip 文案节奏；真机验证清单：会话首帧分析速度、场景切换滞回手感、前置镜像指令方向

## 第八批（dev 分支，2026-08-29：交互节奏与反馈打磨 A/B/C 三批）

### A 批：出片时刻的反馈闭环
- **自动拍摄倒计时可视化**（修"静默拍照"）：达标 → 快门键出现绿色进度环 + 剩余秒数，`HapticManager.countdown` 逐步渐强震动；**倒计时中失稳自动取消**（coachPhase 退回 guiding，chip 提示"手抖了，稳住重新构图"），比拍糊再删好
- **达标仪式感**：三分线 spring 渐隐至 35% + 快门绿色呼吸脉冲描边（倒计时启动后脉冲让位给进度环）
- **场景宣告**：具体场景识别成功 → selection 震动 + 场景标签弹性入场（scale+opacity transition）

### B 批：指令可读性
- 状态图标只表达三态（viewfinder/sparkles/checkmark），方向全部文字化；复合指令可叠加（"再靠近一点，向左移一点"）
- chip 防抖状态机 `publishSuggestion`：相同文案不发布、最小驻留 400ms、反向指令（左↔右/近↔远/高↔低）冷却 600ms，未到期保留最新意图延迟补发；首条文案直达

### B/C 批：会话过渡与手势
- AI 会话进入/退出：覆盖层 scale+opacity spring 过渡（idle 时缩至 0.94 隐去）
- **点按预览区 = 退出 AI 会话**（会话中点按对焦让位），空闲时仍是点按对焦
- **长按快门连拍**：0.45s 进入连拍（350ms 间隔 + 轻震），松手结束；连拍走 capturePhoto（评分快照每次独立）

### C 批：布局修正与联动
- **修 bug**：右侧参数列 bottom padding 300pt 是旧三行布局遗物，会压到 AI/翻转键 → 动态计算（有变焦盘 248 / 无 148）
- **变焦联动**：场景推荐镜头（风景→超广角等）与当前倍率差 >0.3 时，变焦盘对应焦段黄色呼吸高亮

真机验收链路：开自动拍摄 → 达标看倒计时/听震动 → 故意晃手看取消 → 稳住重新达标 → 长按快门连拍；前置模式下确认指令方向语义。

## 第九批（dev 分支，2026-08-29：AI 摄影师 MVP——构图方案）

> 依据用户提供的《AI 构图拍照 MVP 开发方案》实施 P0：一次分析 → 结构化构图方案（1~3 个）→ 用户选择 → 实时引导 → 完成判断 → 拍摄。

- **新增 `CompositionPlan.swift`**：
  - 模型：CompositionPlan（title/styleWord/detail/composition/subjectTarget/distance/focalHint/tracking/confidence），PlanCompositionStyle 七类（三分/居中对称/引导线/框架/前景层次/留白/人物环境），PlanDistance，PlanTracking（person/saliency/none）
  - 坐标约定：方案 y 从顶部计（0=顶），选中时转 1-y 给引擎
  - **`CompositionPlanProviding` 协议 = AI 扩展点**：MVP 默认 `LocalHeuristicPlanProvider`（本地启发式：场景+主体快照→方案，零网络离线可用）；接 VLM 时实现同协议即可（AI 仅在点「AI 构图」时调用一次，实时跟踪仍全本地）
- **CoachPhase 新增 `.plans`**：会话流程 idle → analyzing（积累 0.9s 场景/主体证据）→ **plans（方案卡片）** → guiding → achieved
- **方案卡片 UI**（CompositionCoachOverlayView，.plans 阶段可点击）："AI 摄影师·发现 N 种拍法" + 卡片（标题/风格词/说明/推荐标记）+ 取消；选中 → selection 震动 → 进入引导
- **方案驱动的目标系统**：目标位置/距离目标来自所选方案；距离建议映射目标主体高度（closer≥0.68 / farther≤0.3 / keep=当前）；chip 标签用方案标题
- **显著性跟踪**：非人物方案用 VNGenerateAttentionBasedSaliencyImageRequest 跟踪"当前主体"（EWMA 平滑防抖），人物方案仍走 Vision 人脸/人体；none 方案（正对文档）静态标记圈无位置反馈
- 焦段建议：方案 focalHint（"2x"/"0.5x"）→ 变焦盘黄色高亮提示（P1 的自动切换暂不做）
- 人物离开画面 >1.5s：取消自动拍摄 + 提示重新取景
- 真机待验证：方案卡片出现节奏（~1s）、显著性跟踪稳定性、无人物场景方案实用性

## 版本基线与分支约定

## 项目位置与验证命令

- 项目名：**FrameHero**（原名 LiveCapture，2026-08-29 全量更名，见第五批）
- 路径：`/Users/mr./Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6a905bc7582b3f8001d2a591/LiveCapture-main`
  （外层文件夹还叫 LiveCapture-main，是 TRAE 工作区目录，建议用户自行在 IDE 里改名）
- 编译验证（已验证可用，无签名）：
  ```bash
  xcodebuild -project FrameHero.xcodeproj -scheme FrameHero \
    -destination 'generic/platform=iOS Simulator' -configuration Debug \
    build CODE_SIGNING_ALLOWED=NO
  ```
- 注意：`project.yml` / `generate_xcode_project.py` 已被删除，**新增 .swift 文件必须手动注册进 `LiveCapture.xcodeproj/project.pbxproj`**（PBXBuildFile + PBXFileReference + 组 children + Sources phase 四处）。
- git 有完整历史：`7ea6b6c` 是修复前基线，随时可 diff/回滚。

## 已完成（第五批 2026-08-29：项目更名为 FrameHero，全量）

- 命名：App 名统一用英文 **FrameHero**（显示名/首页标题/工程/仓库/代码标识），不用中文名；「FrameHero」候选名检索无同名 App，排除出片（已有竞品「出片相机」）
- 全量替换范围：~50 个 swift 文件的头部注释与标识、队列标签（framehero.*）、KeychainStore 服务名（com.xbcmz.FrameHero）、PhotoStorageService 存储子目录（FrameHero）、Info.plist（显示名=FrameHero、权限文案）、pbxproj（Target/Product/Bundle ID 全部 FrameHero，com.xbcmz.FrameHero）
- 目录重命名：源码目录 LiveCapture/ → FrameHero/、LiveCapture.xcodeproj → FrameHero.xcodeproj、LiveCaptureApp.swift → FrameHeroApp.swift
- 首页大标题「AI 摄影助手」→「FrameHero」；README.md / README_CN.md 全局改名 + 修正过时内容（配置方式改为设置页 Keychain、目录树、导航、ZoomDialView、Phase 8 完成态），上游 LiveCompose 署名保留
- ⚠️ Bundle ID 已变：设备上旧 App（LiveCapture）需卸载重装，照片记录与 Keychain 中的 API Key 不会迁移（用户已确认接受）
- 用户待办：①GitHub 仓库改名（gh CLI 未安装：网页 Settings → General → Rename，或安装 gh 后 `gh repo rename FrameHero`；GitHub 会自动重定向旧地址，本地 remote 无需改）②TRAE 工作区外层文件夹名 ③App 图标重绘

## 已完成（第六批 2026-08-29：新 App 图标 + 导出原图直出/样式切换）

- **App 图标重绘**：Swift + CoreGraphics 程序化渲染（脚本可复用调参），取景框角标 + AI 星芒 + 三分构图线，底色沿用 primaryGradient；三变体 icon-light / icon-dark / icon-tinted（tinted 为新增灰阶版，此前复用 dark），1024×1024 单尺寸
- **导出样式切换**（照片浏览器导出预览页顶部）：「信息卡片 / 原图直出」segmented 切换，AppStorage key `exportUsesCard` 持久化记忆选择
- 原图直出：PhotoStorageService 新增 `photoData(for:)` 读原始 JPEG 字节，保存时直接写入相册不经重编码（卡片模式仍存渲染 PNG）；卡片模式本身已无品牌水印（含日期/参数信息行）
- 拍照入口在首页/图库/底部 Tab 三处均可达；导出入口为照片浏览器右上角下载按钮

## 已完成（2026-08-29：移除导出卡片品牌水印）

- ShareCardGenerator 去掉底部品牌水印（Logo 图标 +「构妙 · LiveCompose」标题），loadLogo() 一并删除（logo-glass-LiveCompose 图片资源保留未删）
- 保留日期 + 拍摄参数（ISO/快门/光圈/分辨率）信息行（照片元数据非水印），日期升为主行（24pt medium 黑色）
- bottomReserved 300 → 170，腾出的空间给照片区域（maxPhotoHeight 1020 → 1150）
- Debug 编译验证通过

## 已完成（第四批 2026-08-29：首页重构为 AI 摄影工作台）

- **删除全部静态介绍内容**（核心功能卡片、工作原理、技术栈、版本路线图、关于），首页不再复用介绍页
- 新首页结构（自上而下）：问候语（按时段变化）+ 标题 → 大型渐变「开始 AI 拍摄」入口（相机图标 + 能力摘要 + 装饰光斑）→ AI 拍摄助手状态卡（AI 建议 / 构图评分 / 人物检测 三行实时状态，右上角快捷入口进设置）→ 最近拍摄横滑预览（缩略图 + 右上角构图评分配色角标，点开进 PhotoBrowserView，无照片时整段隐藏）→ 「今天」数据卡（拍摄照片 / AI 建议次数 / 平均评分 三列）
- **修复死按钮 bug**：旧首页「开始拍摄/查看照片」发 NotificationCenter 通知但全工程无监听者。新增 `AppRouter`（MainTabView.swift 内，@MainActor ObservableObject），TabView selection 绑定 router，注入 environmentObject，首页可跳相机/图库/设置
- **构图评分随照片入库**：PhotoRecord 新增 `compositionScore: Int?`（合成 Codable 的 decodeIfPresent 天然兼容旧 records.json）；CaptureViewModel 按快门时在主线程快照当前评分传给 savePhoto
- **AI 建议次数统计**：新增 `AIUsageCounter`（AIConfigurationStore.swift 内），Advisor 每次成功交付建议时计数，按天滚动（UserDefaults：今日值 + 日期戳 + 累计值）
- **文件归位**：HomeView 定义原本在 LiveComposeView.swift、GalleryView 定义在 HomeView.swift（文件名与内容错位），已互换并移到 Features/Home/Views/，pbxproj 组结构同步（LiveCompose 组删除）
- HomeViewModel 新增 todayPhotoCount / todayAverageScore / recentRecords；Debug/Release 双配置编译通过

## 已完成（第三批 2026-08-29：设置页 AI 助手 + UI 重构）

### 功能
- 新增「AI 助手」设置区：云端开关（关 = 本地 Mock，零联网）、API Key 输入（SecureField + 显隐切换 + 保存/清除）、模型选择（deepseek-chat 通用 V3 / deepseek-reasoner 深度思考 R1）、连接测试（GET /models 鉴权 + 延迟显示，不消耗 token）、高级设置（自定义 Base URL 支持自建代理，缺路径自动补 /chat/completions，一键恢复默认）
- **API Key 迁移到 Keychain**（新文件 `KeychainStore.swift` + `AIConfigurationStore.swift`）：不再依赖 Info.plist 明文；Info.plist 里的旧 Key 仍作兜底（`effectiveAPIKey` 读取顺序 Keychain → Info.plist），老用户升级无感
- DeepSeekService 构造器支持自定义 baseURL/model，新增 static `testConnection(apiKey:baseURL:completion:)`（返回 Result<TimeInterval, Error>）
- PhotographyAdvisor 动态选路：订阅 AIConfigurationStore.objectWillChange（200ms debounce），设置页改动即时切换 DeepSeek/Mock、更新 Key 与模型，相机页无需重启
- **「AI 建议」开关从拍摄页菜单迁移到设置页**（AppStorage key `aiAdviceEnabled`）：TopControlBar 不再有该菜单项；CaptureViewModel 按 VM 创建时读取一次（CaptureView 每次全屏弹出新建 VM，设置改动自然生效）

### UI 重构（面向普通用户，非开发者配置页）
- 主卡片三行突出核心信息：①总开关（渐变图标 + 状态行显示连接状态：已连接·456ms / 未配置 Key / 连接失败 等，数据源 `AIConfigurationStore.lastConnectionTest`）②建议模型（菜单式 Picker，云端关闭时置灰）③拍摄时给出 AI 建议（迁移来的开关）
- API Key / 连接测试 / 接口地址全部收纳进「高级设置」折叠区（默认收起）；统一卡片背景 cardBackground、行高 padding 14、图标 15pt/24 宽、headline/caption1 字体层级
- 新文件已手动注册进 pbxproj 四处；Debug/Release 双配置编译通过

## 已完成（第二批 2026-08-29，9 项：P1 全部可代码项 + P2 六项）

### P1：专业参数滑杆与真实状态打通（原问题：滑杆假双向、与实际参数脱节）
- 滑杆 Binding 不再是空 set：get 按「aiAuto → 硬件回读值（cameraEnvironment）、manual/locked → 策略值」取数，set 直连 CaptureViewModel 对应方法
- aiAuto 切手动曝光时用当前真实 EV 作起点（此前从 0 起跳，画面亮度突变；对焦/白平衡原本就有该语义）
- cameraEnvironment 与硬件同步三路：①变焦手势/预设（applyZoomFactor 后回读）②镜头切换（toggleCameraPosition 后回读）③新增 0.5s 周期回读计时器（sessionQueue，会话运行期间生效）
- updateCameraEnvironment 值不变不发布（去重，避免主线程 2Hz 无效刷新 + 控制引擎重复评估）

### P1：PhotoStorageService 跨线程数据竞争修复
- records/isLoaded 收敛到 storageQueue 单线程访问；loadRecords() 改为异步 loadRecordsIfNeeded()（结果经 recordsPublisher 发布），MainTabView 调用点同步更新

### P2 代码质量
- CoreML 预处理重写：居中裁方形等比缩放（不再把 3:4 拉伸到 224×224）、通道拆分/归一化/半精度全程 Accelerate（ARGB8888toPlanar8 + vDSP_vfltu8/vsmul + PlanarFtoPlanar16F，替代逐像素 Swift 循环）、orientation 真正参与预处理、bbox 在「方形裁剪空间 ↔ 全图空间」间正确映射（state 输入与动作微调保持在模型原生方形空间）
  - ⚠️ 风险标注：模型输入分布从「拉伸」变为「裁方形」，若真机识别质量下降可回退该提交
- DeepSeekService：15s 请求超时 + 代际标记（迟到的旧响应直接丢弃，不再覆盖新结果）
- MotionStabilityMonitor.start() 加 isMonitoring 重入保护（此前 onAppear 重复触发会叠开数据流）
- 视频防抖死代码修复：configureStabilization（Session）与 applyStabilizationIfAvailable（PreviewView）里 #available(iOS 13) 分支为空导致 iOS 13+ 从未设置防抖，现直接设置 .auto
- ZoomRingView.swift 已删除（被 ZoomDialView 替代），pbxproj 四处引用同步清理（plutil 校验通过）
- DebugPanel 与「显示调试信息」菜单入口仅在 DEBUG 构建存在（#if DEBUG 门控，Debug/Release 双配置编译验证通过）

## 已完成（第一批 2026-08-29，约 20 项修复）

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
1. **自动拍摄流水线与新布局的整合**：魔法棒开启后引导 UI（裁切框/追踪点/中心圆）仍是旧交互逻辑，与其余原生化的 UI 风格割裂；需要重新设计「对齐 → 倒计时 → 拍摄」的呈现（现在排到下轮主项）
2. **点按对焦的前置坐标**需真机验证（captureDevicePointConverted 已接管连接镜像，理论正确）
3. **真机验证清单**：变焦后滑杆/环境状态同步、方形裁剪输入的 Adacrop 识别质量、0.5s 周期回读的功耗影响

### P2（代码质量）
4. CoreML 模型输入改为方形裁剪后，建议用真机对比新旧识别质量（见上方风险标注）
5. ~~API Key 明文在 Info.plist~~ 已解决：设置页配置 + Keychain 存储（第三批），Info.plist 仅兜底，可择机从 Info.plist 移除 DeepSeekAPIKey 字段
6. CameraControlEngine/Advisor 对 debounce 策略的双通道评估还有优化空间；`cameraManager.zoomState` 在 sessionQueue 上被跨线程读取（历史模式，可择机重构为参数直传）
7. 设计文档 `../ai-photography-assistant-design/ai-photography-assistant-design.html` 里有五维构图评分、机位推荐、Qwen3-VL、ARKit 的演进方案，可与代码对照推进（AI 助手设置区已为多 provider 预留：AIConfigurationStore + AIAdviceProvider 协议，接 Qwen3-VL 只需新增实现）
8. 图库（GalleryView/PhotoBrowserView/ShareCardGenerator）尚未审查过；首页「AI 建议」次数在建议开启时会随分析频率持续累计（Advisor 内 3s 节流），语义是"建议交付次数"而非"会话数"，如需更粗粒度可在 Advisor 侧加节流计数

### P3（功能演进）
9. 夜景/低光检测（路线图 Phase 6）、HDR（Phase 7）
10. 拍摄参数预设（人像/风景/美食，Phase 9）

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
- AI 建议开关在「设置 → AI 助手」（AppStorage `aiAdviceEnabled`，默认关），拍摄页不再提供开关
- DeepSeek 配置全部在设置页（Key 存 Keychain），Info.plist 的 DeepSeekAPIKey 仅兜底
- 视频帧方向：竖屏下 buffer 已是 3:4 portrait，`pixelOrientation` 用宽高判断
