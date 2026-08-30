//
//  CaptureViewModel.swift
//  FrameHero
//
//  拍摄功能的视图模型（AI 构图版）
//
//  ## 文件作用
//  协调相机、运动传感器与 AI 构图引擎，为 CaptureView 提供状态与动作。
//
//  ## 产品范式（借鉴 Doka Cam）
//  相机平时是纯净的；用户点一次 AI 按钮 → 进入「AI 构图会话」：
//  场景识别（Vision 分类器，多帧投票）→ 场景参数预设 → 极简实时引导
//  （淡三分线 + 一条建议 chip）→ 构图完成提示（可选自动拍摄）。
//  没有魔法棒、没有裁切框中心圆、没有实时评分上屏、没有逐帧 LLM 文本。
//
//  ## 数据流
//  相机帧(30-60fps)
//    └→ AI 构图会话激活时（10fps 节流 + 单帧防抖）
//        ├→ SceneClassifier：VNClassifyImageRequest 多帧投票 → SceneKind
//        │    └→ 场景参数预设（经 PhotographyStrategy 三态过滤下发）
//        └→ PhotographyAdvisor（Vision 人体/人脸检测 → CompositionEngine 评分）
//             └→ CompositionGuidanceEngine → GuidanceResult → 极简引导 UI
//  快门：AVCapturePhotoOutput → 3:4 裁剪(保EXIF) → PhotoStorageService
//
//  ## 线程约定
//  sessionQueue（会话/硬件）、videoOutputQueue（帧）、主线程（UI/@Published）
//

import Foundation
import Combine
import AVFoundation
import CoreImage
import CoreMotion

#if os(iOS)
import SwiftUI
import Vision

/// 拍摄功能的视图模型
final class CaptureViewModel: ObservableObject {
	// MARK: - Dependencies

	private(set) var camera = CameraManager()
	private let motion = MotionStabilityMonitor()
	private let photographyAdvisor: PhotographyAdvisor
	private let sceneClassifier = SceneClassifier()
	private let guidanceEngine = CompositionGuidanceEngine()

	// MARK: - AI 构图会话

	/// 会话阶段
	enum CoachPhase: Equatable {
		case idle        // 会话未激活（纯净相机）
		case analyzing   // 正在分析场景
		case plans       // 展示构图方案（等待用户选择）
		case guiding     // 实时引导中
		case achieved    // 构图完成
	}

	@Published private(set) var coachPhase: CoachPhase = .idle
	/// 场景标签（如"美食场景"，未识别稳定时为 nil）
	@Published private(set) var coachSceneLabel: String?
	/// 一行建议指令（chip 文案）
	@Published private(set) var coachSuggestion: String = ""
	/// 实时引导结果（供 UI 显示，前置摄像头已做镜像校正）
	@Published private(set) var coachGuidance: GuidanceResult?

	// MARK: - 构图方案（Composition Plan）
	/// 分析产出的构图方案（最多 3 个，按推荐度排序）
	@Published private(set) var compositionPlans: [CompositionPlan] = []
	/// 当前选中方案的序号
	@Published private(set) var selectedPlanIndex: Int?
	/// 方案生成器（MVP：本地启发式；后续可换 VLM 实现）
	private let planProvider: CompositionPlanProviding = LocalHeuristicPlanProvider()
	/// AdaCrop 参谋：方案生成时一次性预测最佳构图区（Vision 档位不启用）
	private lazy var adaCropPlanAdvisor: AdaCropPlanAdvisor? = {
		switch detectionMode {
		case .fast: return AdaCropPlanAdvisor(mode: .fast)
		case .pro: return AdaCropPlanAdvisor(mode: .pro)
		case .vision: return nil
		}
	}()
	private var adaCropRunning = false
	/// 本会话的 AdaCrop 裁切区建议（显著性方案首帧校准用）
	private var sessionCropHint: CGRect?
	private var selectedPlan: CompositionPlan?
	/// 方案分析开始时间（积累 ~0.9s 场景/主体证据后出方案）
	private var planAnalysisStartedAt: Date?
	private var planGenerationDone = false

	// MARK: - 显著性跟踪（非人物方案）
	private var saliencyCenter: CGPoint?
	private var saliencySize: CGSize?
	private var saliencySmoother = UniformPointSmoother(response: 0.4)
	/// 自动拍摄倒计时（remain/total 秒）；nil = 不在倒计时
	@Published private(set) var autoCaptureCountdown: (remain: Double, total: Double)?
	/// 场景推荐焦段（变焦盘上高亮提示），nil = 无推荐
	@Published private(set) var sceneRecommendedFactor: CGFloat?

	/// 会话是否激活（帧分析的总开关）
	private var isCoachActive = false
	/// 当前稳定场景
	private var currentScene: SceneClassifier.SceneKind?

	// MARK: - 目标锁定（治"左右乱指"）
	// 旧逻辑每帧取"最近三分线"作目标：主体在画面中央时到左右三分线等距，
	// 检测抖动会让目标左右翻转，chip 就永远在"向左/向右"之间横跳。
	// 现在主体首次稳定出现时锁定目标，整个会话不变；
	// 主体丢失超 1.5s 才解锁，重新出现时按朝向重新选择。
	/// 锁定的目标点（归一化图像坐标，y 向上）
	private var lockedTargetPoint: CGPoint?
	/// 主体从画面消失的时刻（用于解锁目标）
	private var subjectLostSince: Date?

	// MARK: - Published State

	@Published private(set) var compositionRectInView: CGRect = .zero
	@Published private(set) var motionIsStable: Bool = false
	@Published private(set) var zoomState: CameraManager.ZoomState
	@Published private(set) var zoomPresets: [CameraManager.ZoomPreset]
	@Published private(set) var zoomRange: ClosedRange<CGFloat>
	/// 顶部瞬态提示（如"照片已保存"）
	@Published private(set) var userGuidanceText: String = ""
	@Published var isAutoCaptureEnabled: Bool = true
	@Published var captureDelay: Double = 1.0
	@Published var isSwitchingCamera: Bool = false

	// MARK: - 相机能力与环境

	/// 当前设备的相机能力（启动时读取，切换摄像头时更新）
	@Published private(set) var cameraCapability: CameraCapability = .empty
	/// 当前相机环境状态（实时参数）
	@Published private(set) var cameraEnvironment: CameraEnvironment = .empty
	/// 当前摄影策略（AI + 用户共同决定）
	@Published var photographyStrategy: PhotographyStrategy = .default

	// MARK: - AI 构图按钮开关

	/// 拍摄页是否显示 AI 构图入口（设置页控制，无历史设置时默认开）
	@Published private(set) var isAICompositionEnabled: Bool = {
		let defaults = UserDefaults.standard
		return defaults.object(forKey: "aiAdviceEnabled") as? Bool ?? true
	}()

	var onCaptureTriggered: (() -> Void)?

	// MARK: - Computed Properties

	var isFrontCamera: Bool { camera.currentPosition == .front }

	var zoomDisplayText: String {
		let factor = zoomState.displayedFactor
		if abs(Double(factor.rounded()) - Double(factor)) < 0.001 {
			return "\(Int(factor.rounded()))×"
		}
		return String(format: "%.2f×", factor)
	}

	var session: AVCaptureSession { camera.session }

	/// 供 UI 显示的引导结果（前置摄像头画面是镜像的，水平方向需要翻转）
	var displayGuidance: GuidanceResult? {
		guard var result = coachGuidance else { return nil }
		guard isFrontCamera else { return result }

		switch result.horizontalDirection {
		case .moveLeft: result.horizontalDirection = .moveRight
		case .moveRight: result.horizontalDirection = .moveLeft
		default: break
		}
		return result
	}

	// MARK: - Private State

	private static let ciContext = CIContext()
	private var cancellables: Set<AnyCancellable> = []
	private var autoCaptureWorkItem: DispatchWorkItem?
	/// 自动拍摄倒计时定时器（主线程 20Hz tick）
	private var countdownTimer: DispatchSourceTimer?
	private var countdownDeadline: Date?

	// MARK: - chip 防抖（B5）
	/// 上次 chip 文案变更时间
	private var lastSuggestionChange = Date.distantPast
	/// 被防抖延迟的最新意图
	private var pendingSuggestion: String?
	private var suggestionDebounceWork: DispatchWorkItem?

	/// 单帧分析在途标志（10fps 节流 + 防抖，会话期间持续运行）
	private var isFrameAnalysisInFlight = false
	private var lastAnalysisTime: Date?
	private let analysisInterval: TimeInterval = 0.1

	/// 运动稳定性发布节流时间戳
	private var lastMotionUIUpdate: Date = .distantPast

	/// 快门时刻的构图评分快照（随照片入库）
	private var pendingCompositionScore: Int?

	/// 会话启动/镜头切换后的第一帧待分析标记（跳过节流窗口）
	private var pendingFrameForAnalysis = false

	/// 相机控制引擎：将 PhotographyStrategy 翻译成硬件参数
	private let controlEngine = CameraControlEngine()

	// MARK: - Lifecycle

	private let detectionMode: DetectionMode

	init(detectionMode: DetectionMode = .fast) {
		self.detectionMode = detectionMode
		// 构图分析始终用 Vision（人脸/人体检测），CoreML 裁切模型已随魔法棒下线
		photographyAdvisor = PhotographyAdvisor()
		photographyAdvisor.isCloudAdviceEnabled = false

		zoomState = camera.zoomState
		zoomPresets = camera.zoomPresets
		zoomRange = camera.zoomRange

		controlEngine.setCamera(camera)
		bindMotion()
		bindCamera()
	}

	deinit {
		autoCaptureWorkItem?.cancel()
	}

	// MARK: - Public API

	func onAppear() {
		camera.shouldBeRunning = true
		camera.checkAndConfigure { [weak self] result in
			guard let self else { return }
			switch result {
			case .success:
				self.camera.startSession()
			case .failure:
				DispatchQueue.main.async {
					self.userGuidanceText = "相机启动失败"
				}
			}
		}
		motion.start()
		setupCallbacks()
	}

	func onDisappear() {
		cancelAutoCapture()
		suggestionDebounceWork?.cancel()
		motion.stop()
		camera.stopSession()
	}

	func registerCompositionRect(_ rect: CGRect) {
		guard compositionRectInView != rect else { return }
		compositionRectInView = rect
	}

	func capturePhoto() {
		// 快照此刻的构图评分随照片入库（仅在 AI 会话中有值）
		pendingCompositionScore = photographyAnalysis?.composition.score
		camera.capturePhoto()
	}

	func selectZoomPreset(_ preset: CameraManager.ZoomPreset) {
		camera.selectZoomPreset(preset)
	}

	func updateZoomInteractively(to factor: CGFloat) {
		camera.updateInteractiveZoom(to: factor)
	}

	func finalizeZoomInteractively(at factor: CGFloat, smooth: Bool) {
		camera.finalizeInteractiveZoom(at: factor, smooth: smooth)
	}

	// MARK: - AI 构图会话

	/// 点按 AI 按钮：开/关构图会话（Doka 式一次触发）
	func toggleAIComposition() {
		if isCoachActive {
			stopAIComposition()
		} else {
			startAIComposition()
		}
	}

	func startAIComposition() {
		HapticManager.shared.light()
		sceneClassifier.reset()
		currentScene = nil
		lockedTargetPoint = nil
		subjectLostSince = nil
		compositionPlans = []
		selectedPlan = nil
		selectedPlanIndex = nil
		planGenerationDone = false
		planAnalysisStartedAt = nil
		saliencyCenter = nil
		saliencySize = nil
		saliencySmoother.reset()
		sessionCropHint = nil
		coachSceneLabel = nil
		coachGuidance = nil
		compositionTarget = nil
		currentComposition = nil
		photographyAnalysis = nil
		coachSuggestion = "正在分析场景"
		lastSuggestionChange = Date()
		pendingSuggestion = nil
		suggestionDebounceWork?.cancel()
		coachPhase = .analyzing
		isCoachActive = true
		sceneRecommendedFactor = nil
		// 标记待分析帧：下一帧到达立即分析，不等节流窗口
		pendingFrameForAnalysis = true
	}

	func stopAIComposition() {
		HapticManager.shared.light()
		isCoachActive = false
		lockedTargetPoint = nil
		subjectLostSince = nil
		compositionPlans = []
		selectedPlan = nil
		selectedPlanIndex = nil
		planGenerationDone = false
		planAnalysisStartedAt = nil
		saliencyCenter = nil
		saliencySize = nil
		coachPhase = .idle
		coachGuidance = nil
		sceneRecommendedFactor = nil
		cancelAutoCapture()
	}

	// MARK: - 曝光控制

	/// 调整曝光偏差（EV），自动切换到 manual
	func setExposureBias(_ bias: Float) {
		photographyStrategy.exposureControl = .manual
		photographyStrategy.manualExposureBias = bias
	}

	/// 切换曝光控制模式
	func setExposureControlMode(_ mode: ControlMode) {
		let previousMode = photographyStrategy.exposureControl
		photographyStrategy.exposureControl = mode

		if mode == .aiAuto {
			photographyStrategy.manualExposureBias = 0
			photographyStrategy.brightnessPreference = .auto
		}

		if mode == .locked {
			photographyStrategy.manualExposureBias = cameraEnvironment.currentExposureBias
		}

		// 从自动切到手动时，用当前真实 EV 作为起点（与对焦/白平衡语义一致）
		if mode == .manual, previousMode == .aiAuto {
			photographyStrategy.manualExposureBias = cameraEnvironment.currentExposureBias
		}
	}

	/// 设置 AI 亮度偏好（仅 aiAuto 时生效）
	func setBrightnessPreference(_ preference: BrightnessPreference) {
		photographyStrategy.brightnessPreference = preference
	}

	// MARK: - 对焦控制

	/// 设置手动对焦位置（0=最近，1=无穷远），自动切换到 manual
	func setManualFocusPosition(_ position: Float) {
		photographyStrategy.focusControl = .manual
		photographyStrategy.manualFocusPosition = position
	}

	/// 切换对焦控制模式
	func setFocusControlMode(_ mode: ControlMode) {
		let previousMode = photographyStrategy.focusControl
		photographyStrategy.focusControl = mode

		switch mode {
		case .aiAuto:
			photographyStrategy.manualFocusPosition = nil
			photographyStrategy.focusPreference = .auto

		case .locked:
			photographyStrategy.manualFocusPosition = cameraEnvironment.focusLensPosition
			camera.lockFocus()

		case .manual:
			if previousMode == .aiAuto {
				photographyStrategy.manualFocusPosition = cameraEnvironment.focusLensPosition
			}
		}
	}

	/// 设置 AI 对焦偏好（仅 aiAuto 时生效）
	func setFocusPreference(_ preference: FocusPreference) {
		photographyStrategy.focusPreference = preference
	}

	/// 点按对焦/曝光（设备归一化坐标，预览层 captureDevicePointConverted 已处理镜像）
	func focusAtDevicePoint(_ point: CGPoint) {
		photographyStrategy.focusControl = .aiAuto
		photographyStrategy.focusPointOfInterest = point
		photographyStrategy.focusPreference = .subjectLock
		camera.setFocusPointOfInterest(point)
	}

	// MARK: - 白平衡控制

	/// 设置手动白平衡色温（开尔文），自动切换到 manual
	func setWhiteBalanceTemperature(_ temperature: Float) {
		photographyStrategy.whiteBalanceControl = .manual
		photographyStrategy.manualWhiteBalanceTemp = temperature
	}

	/// 切换白平衡控制模式
	func setWhiteBalanceControlMode(_ mode: ControlMode) {
		let previousMode = photographyStrategy.whiteBalanceControl
		photographyStrategy.whiteBalanceControl = mode

		switch mode {
		case .aiAuto:
			photographyStrategy.manualWhiteBalanceTemp = nil
			photographyStrategy.whiteBalancePreference = .auto
			camera.resetWhiteBalanceToAuto()

		case .locked:
			photographyStrategy.manualWhiteBalanceTemp = cameraEnvironment.estimatedColorTemperature
			camera.lockWhiteBalance()

		case .manual:
			if previousMode == .aiAuto {
				photographyStrategy.manualWhiteBalanceTemp = cameraEnvironment.estimatedColorTemperature
			}
		}
	}

	/// 设置 AI 白平衡偏好（仅 aiAuto 时生效）
	func setWhiteBalancePreference(_ preference: WhiteBalancePreference) {
		photographyStrategy.whiteBalancePreference = preference
	}

	// MARK: - 镜头/变焦控制

	func toggleCameraPosition() {
		isSwitchingCamera = true

		let nextPosition: AVCaptureDevice.Position = camera.currentPosition == .back ? .front : .back
		camera.toggleCameraPosition()

		// 会话进行中：镜头换了场景就变了，重置场景投票重新分析
		if isCoachActive {
			sceneClassifier.reset()
			currentScene = nil
			lockedTargetPoint = nil
			subjectLostSince = nil
			coachSceneLabel = nil
			compositionTarget = nil
			currentComposition = nil
			coachGuidance = nil
			compositionPlans = []
			selectedPlan = nil
			selectedPlanIndex = nil
			planGenerationDone = false
			planAnalysisStartedAt = nil
			saliencyCenter = nil
			saliencySize = nil
			coachPhase = .analyzing
			sessionCropHint = nil
			coachSuggestion = "正在分析场景"
			pendingFrameForAnalysis = true
		}

		cancelAutoCapture()

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			self.isSwitchingCamera = false
		}
	}

	// MARK: - 拍摄设置

	func toggleAutoCapture() {
		isAutoCaptureEnabled.toggle()
		if !isAutoCaptureEnabled {
			cancelAutoCapture()
		}
	}

	func setCaptureDelay(_ delay: Double) {
		captureDelay = delay
	}

	// MARK: - Bindings

	private func bindMotion() {
		motion.$isStable
			.receive(on: DispatchQueue.main)
			.sink { [weak self] stable in
				guard let self else { return }
				let now = Date()
				guard now.timeIntervalSince(self.lastMotionUIUpdate) >= 0.2 else { return }
				self.lastMotionUIUpdate = now
				self.motionIsStable = stable

				// 倒计时中手抖了：取消拍摄并明确告知，比拍糊再删好
				if !stable, self.autoCaptureCountdown != nil {
					self.cancelAutoCapture()
					if self.coachPhase == .achieved { self.coachPhase = .guiding }
					self.publishSuggestion("手抖了，稳住重新构图")
				}
			}
			.store(in: &cancellables)
	}

	private func bindCamera() {
		camera.$lastPhotoSaved
			.receive(on: DispatchQueue.main)
			.sink { [weak self] saved in
				guard let self, saved else { return }
				HapticManager.shared.success()
				self.userGuidanceText = "照片已保存"
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
					self?.userGuidanceText = ""
				}
			}
			.store(in: &cancellables)

		camera.$zoomState
			.receive(on: DispatchQueue.main)
			.sink { [weak self] state in
				self?.zoomState = state
			}
			.store(in: &cancellables)

		camera.$zoomPresets
			.receive(on: DispatchQueue.main)
			.sink { [weak self] presets in
				self?.zoomPresets = presets
			}
			.store(in: &cancellables)

		camera.$zoomRange
			.receive(on: DispatchQueue.main)
			.sink { [weak self] range in
				self?.zoomRange = range
			}
			.store(in: &cancellables)

		camera.$cameraCapability
			.receive(on: DispatchQueue.main)
			.sink { [weak self] capability in
				guard let self else { return }
				self.cameraCapability = capability
				self.controlEngine.updateCapability(capability)
			}
			.store(in: &cancellables)

		camera.$cameraEnvironment
			.receive(on: DispatchQueue.main)
			.sink { [weak self] environment in
				guard let self else { return }
				self.cameraEnvironment = environment
				self.controlEngine.updateEnvironment(environment)
			}
			.store(in: &cancellables)

		// 策略变化 → 差异化下发硬件
		$photographyStrategy
			.dropFirst()
			.debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
			.sink { [weak self] strategy in
				self?.controlEngine.applyStrategy(strategy)
			}
			.store(in: &cancellables)
	}

	// MARK: - Camera Processing

	private func setupCallbacks() {
		camera.onSampleBuffer = { [weak self] sample in
			guard let self else { return }
			self.handleSampleBuffer(sample)
		}
		camera.onPhotoDataReady = { [weak self] data in
			guard let self else { return }
			PhotoStorageService.shared.savePhoto(
				data: data,
				detectionMethod: self.detectionMode.displayName,
				compositionScore: self.pendingCompositionScore
			)
			self.pendingCompositionScore = nil
		}
	}

	private func handleSampleBuffer(_ sample: CMSampleBuffer) {
		guard isCoachActive, coachPhase != .idle, coachPhase != .plans else { return }
		guard let pixel = CMSampleBufferGetImageBuffer(sample) else { return }
		let orientation = pixelOrientation(for: pixel)

		// 会话启动/镜头切换/选中方案后的第一帧立即分析
		if pendingFrameForAnalysis {
			pendingFrameForAnalysis = false
			if coachPhase == .analyzing {
				planAnalysisStartedAt = Date()
			}
			analyzeFrameNow(pixel, orientation: orientation)
			return
		}

		// 10fps 节流 + 单帧防抖
		let now = Date()
		if let last = lastAnalysisTime, now.timeIntervalSince(last) < analysisInterval { return }
		lastAnalysisTime = now
		guard !isFrameAnalysisInFlight else { return }
		isFrameAnalysisInFlight = true
		analyzeFrameNow(pixel, orientation: orientation)
	}

	// MARK: - 单帧分析

	/// 最近一次构图分析结果（快门评分快照来源）
	private(set) var photographyAnalysis: PhotographyAnalysisResult?

	private var currentComposition: CurrentComposition?
	private var compositionTarget: CompositionTarget?

	private func analyzeFrameNow(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
		let zoom = zoomState.currentFactor
		let focal = zoomState.focalLength

		// 方案分析阶段：场景投票积累证据；证据就绪后让 AdaCrop 参谋一次再出方案
		if coachPhase == .analyzing {
			sceneClassifier.classify(pixel, orientation: orientation) { [weak self] decision in
				guard let self, let decision else { return }
				self.applyScene(decision)
			}

			let elapsed = planAnalysisStartedAt.map { Date().timeIntervalSince($0) } ?? 0
			if !planGenerationDone, photographyAnalysis != nil, elapsed >= 0.9, !adaCropRunning {
				if let ada = adaCropPlanAdvisor {
					adaCropRunning = true
					ada.predictBestCrop(pixel, orientation: orientation) { [weak self] rect in
						guard let self else { return }
						self.adaCropRunning = false
						self.sessionCropHint = rect
						self.generatePlans()
					}
				} else {
					generatePlans()
				}
				return
			}
		}

		// 引导阶段 + 显著性方案：跑显著性跟踪（省掉人物检测）
		if coachPhase == .guiding || coachPhase == .achieved,
		   selectedPlan?.tracking == .saliency {
			runSaliencyTracking(pixel, orientation: orientation)
			return
		}

		// 分析阶段 / 人物跟踪方案：Vision 主体检测 + 构图评分
		photographyAdvisor.analyzeFrame(
			pixel,
			orientation: orientation,
			zoomFactor: zoom,
			focalLength: focal
		) { [weak self] result in
			guard let self else { return }
			self.isFrameAnalysisInFlight = false
			DispatchQueue.main.async {
				self.ingestAnalysis(result)
			}
		}
	}

	// MARK: - 显著性跟踪（非人物方案的"当前主体"来源）

	private func runSaliencyTracking(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
		defer { isFrameAnalysisInFlight = false }
		let request = VNGenerateAttentionBasedSaliencyImageRequest()
		let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation, options: [:])
		do {
			try handler.perform([request])
		} catch {
			return
		}
		guard let observation = request.results?.first,
		      let box = observation.salientObjects?.first?.boundingBox else {
			// 单帧无显著区域：保留上次位置（短暂丢失不闪断）
			DispatchQueue.main.async { self.ingestSaliencyPlanTick() }
			return
		}
		// Vision 归一化坐标 y 向上，与构图引擎一致
		let smoothed = saliencySmoother.filter(CGPoint(x: box.midX, y: box.midY))
		saliencyCenter = smoothed
		saliencySize = CGSize(width: box.width, height: box.height)
		DispatchQueue.main.async { self.ingestSaliencyPlanTick() }
	}

	/// 显著性方案的一次引导更新
	private func ingestSaliencyPlanTick() {
		guard let plan = selectedPlan,
		      coachPhase == .guiding || coachPhase == .achieved else { return }
		guard let center = saliencyCenter else {
			coachGuidance = nil
			return
		}
		// 首次显著性定位时：用 AdaCrop 裁切区校准目标（模型认为的最佳落点）
		if lockedTargetPoint == nil {
			var target = CGPoint(x: plan.subjectTarget.x, y: 1 - plan.subjectTarget.y)
			if plan.calibrateFromCrop, let crop = sessionCropHint,
			   let mapped = PlanGeometry.mapThroughCrop(center, crop: crop) {
				target = mapped
			}
			lockedTargetPoint = target
			guidanceEngine.reset()
		}
		let size = saliencySize ?? CGSize(width: 0.3, height: 0.3)
		let current = CurrentComposition(
			subjectCenterX: center.x,
			subjectCenterY: center.y,
			subjectWidthRatio: size.width,
			subjectHeightRatio: size.height,
			faceCenterX: nil,
			faceCenterY: nil,
			headRoomRatio: 0,
			minEdgeDistance: 0,
			isSubjectComplete: true,
			overallScore: photographyAnalysis?.composition.score ?? 0,
			subjectPosition: photographyAnalysis?.composition.subjectPosition ?? .unknown
		)
		applyGuidance(current: current, target: planTarget(for: plan, currentHeight: size.height))
	}

	/// 场景结论 → 标签 + 参数预设（带滞回，只在场景变化时下发）
	private func applyScene(_ decision: SceneClassifier.Decision) {
		let scene = decision.kind
		if scene == currentScene { return }

		// generic 不覆盖已识别的具体场景（避免偶发无分类帧抖动）
		if scene == .generic, currentScene != nil { return }

		currentScene = scene
		coachSceneLabel = scene.displayName.isEmpty ? nil : scene.displayName

		// 场景宣告：具体场景（非通用）识别成功给一次选择反馈
		if scene != .generic {
			HapticManager.shared.selection()
		}

		// 场景 → 相机参数预设：只改写 aiAuto 状态的参数（用户手动/锁定的不覆盖）
		let preset = scenePreset(for: scene)
		applyAICameraStrategy(preset)
		syncSceneRecommendedLens(preset)
	}

	/// 场景推荐镜头 → 变焦盘高亮提示（与当前倍率差距明显才提示）
	private func syncSceneRecommendedLens(_ preset: CameraStrategySuggestion) {
		var target: CameraManager.ZoomPreset?
		switch preset.lensPreference {
		case .ultraWide: target = zoomPresets.first { $0.lens == .ultraWide }
		case .telephoto: target = zoomPresets.first { $0.lens == .telephoto }
		default: target = nil
		}
		if let target, abs(target.zoomFactor - zoomState.currentFactor) > 0.3 {
			sceneRecommendedFactor = target.zoomFactor
		} else {
			sceneRecommendedFactor = nil
		}
	}

	/// 场景 → 参数预设（语义偏好，经三态控制过滤后生效）
	private func scenePreset(for scene: SceneClassifier.SceneKind) -> CameraStrategySuggestion {
		var s = CameraStrategySuggestion()
		switch scene {
		case .portrait:
			s.focusPreference = .subjectLock
			s.depthPreference = .shallow
		case .food:
			s.focusPreference = .macro
			s.whiteBalancePreference = .natural
		case .night:
			s.brightnessPreference = .night
			s.motionPriority = .lowNoise
		case .landscape:
			s.lensPreference = .ultraWide
			s.depthPreference = .deep
		case .street:
			s.motionPriority = .freezeMotion
		case .document:
			s.brightnessPreference = .brighter
		case .generic:
			break
		}
		return s
	}

	/// 应用 AI/场景推荐的相机策略偏好。
	/// 核心规则：只有 aiAuto 模式的参数会被改写，用户 manual/locked 的不覆盖
	private func applyAICameraStrategy(_ suggestion: CameraStrategySuggestion) {
		let strategy = photographyStrategy

		if strategy.lensControl == .aiAuto {
			photographyStrategy.lensPreference = suggestion.lensPreference
			photographyStrategy.depthPreference = suggestion.depthPreference
		}
		if strategy.exposureControl == .aiAuto {
			photographyStrategy.brightnessPreference = suggestion.brightnessPreference
			photographyStrategy.motionPriority = suggestion.motionPriority
		}
		if strategy.focusControl == .aiAuto {
			photographyStrategy.focusPreference = suggestion.focusPreference
		}
		if strategy.whiteBalanceControl == .aiAuto {
			photographyStrategy.whiteBalancePreference = suggestion.whiteBalancePreference
		}
	}

	/// 消费一次构图分析结果（人物跟踪方案 / 方案生成）
	private func ingestAnalysis(_ result: PhotographyAnalysisResult) {
		photographyAnalysis = result

		// 方案分析阶段：方案生成由 analyzeFrameNow 触发（AdaCrop 参谋完成后）
		if coachPhase == .analyzing {
			return
		}

		guard coachPhase == .guiding || coachPhase == .achieved,
		      let plan = selectedPlan else { return }

		// 方案跟踪分派
		switch plan.tracking {
		case .person:
			ingestPersonTracking(result, plan: plan)
		case .saliency:
			ingestSaliencyPlanTick()
		case .none:
			// 静态方案：无实时位置反馈，标记圈 + 方案说明常驻
			coachGuidance = nil
			publishSuggestion(plan.detail)
		}
	}

	/// 人物跟踪方案的一次引导更新
	private func ingestPersonTracking(_ result: PhotographyAnalysisResult, plan: CompositionPlan) {
		// 群像方案：以群体包围盒为"当前主体"（并集中心/高度）
		if plan.isGroup, let group = result.composition.groupBoundingBox {
			let current = CurrentComposition(
				subjectCenterX: group.midX,
				subjectCenterY: group.midY,
				subjectWidthRatio: group.width,
				subjectHeightRatio: group.height,
				faceCenterX: nil,
				faceCenterY: nil,
				headRoomRatio: 0,
				minEdgeDistance: 0,
				isSubjectComplete: true,
				overallScore: result.composition.score,
				subjectPosition: result.composition.subjectPosition
			)
			applyGuidance(current: current,
						  target: planTarget(for: plan, currentHeight: group.height))
			return
		}

		let person = result.composition.person
		guard person.detected else {
			coachGuidance = nil
			if subjectLostSince == nil { subjectLostSince = Date() }
			if let lost = subjectLostSince, Date().timeIntervalSince(lost) > 1.5 {
				cancelAutoCapture()
				if coachPhase == .achieved { coachPhase = .guiding }
				publishSuggestion("人物不在画面里了，重新取景")
			}
			return
		}
		subjectLostSince = nil
		applyGuidance(
			current: makeCurrentComposition(from: result.composition),
			target: planTarget(for: plan, currentHeight: person.heightRatio)
		)
	}

	/// 方案目标：位置来自方案，尺寸目标由距离建议决定
	private func planTarget(for plan: CompositionPlan, currentHeight: CGFloat) -> CompositionTarget {
		var target = CompositionTarget(
			targetCenterX: lockedTargetPoint?.x ?? plan.subjectTarget.x,
			// 方案 y 从顶部计，引擎 y 向上：1 - y
			targetCenterY: 1 - plan.subjectTarget.y,
			targetWidthRatio: 0.4,
			targetHeightRatio: planHeightTarget(plan, currentHeight: currentHeight),
			targetHeadRoom: 0.12,
			preferredLens: .keepCurrent,
			compositionStyle: .ruleOfThirds,
			targetScore: 85,
			adviceTitle: plan.title,
			adviceText: plan.detail,
			suggestedStyle: plan.styleWord
		)
		switch plan.composition {
		case .centerSymmetry:
			target.compositionStyle = .center
		default:
			break
		}
		return target
	}

	/// 距离建议 → 目标主体高度
	private func planHeightTarget(_ plan: CompositionPlan, currentHeight: CGFloat) -> CGFloat {
		switch plan.distance {
		case .closer: return max(currentHeight, 0.68)
		case .farther: return min(currentHeight, 0.3)
		case .keep: return currentHeight
		}
	}

	/// 统一的引导应用：计算 GuidanceResult + 达标阶段迁移
	private func applyGuidance(current: CurrentComposition, target: CompositionTarget) {
		currentComposition = current
		compositionTarget = target
		guard compositionRectInView.width > 0 else {
			coachGuidance = nil
			return
		}
		let guidance = guidanceEngine.compute(
			current: current,
			target: target,
			viewSize: compositionRectInView.size
		)
		coachGuidance = guidance

		if guidance.state == .optimal {
			if coachPhase != .achieved {
				coachPhase = .achieved
				HapticManager.shared.focusLock()
				scheduleAutoCaptureIfEnabled()
			}
		} else if coachPhase == .achieved {
			coachPhase = .guiding
			cancelAutoCapture()
		}
		publishSuggestion(chipText(guidance: guidance, plan: selectedPlan))
	}

	// MARK: - 方案生成与选择

	/// 分析证据就绪 → 生成构图方案
	private func generatePlans() {
		planGenerationDone = true
		let scene = currentScene ?? .generic
		let person = photographyAnalysis?.composition.person
		let composition = photographyAnalysis?.composition
		var plans = planProvider.generatePlans(
			scene: scene,
			person: person,
			bodyCount: composition?.bodyCount ?? 0,
			groupBox: composition?.groupBoundingBox,
			zoomFactor: zoomState.currentFactor,
			hasTelephoto: zoomPresets.contains { $0.lens == .telephoto },
			hasUltraWide: zoomPresets.contains { $0.lens == .ultraWide },
			cropHint: sessionCropHint
		)
		if plans.isEmpty {
			// 兜底：至少给一个通用方案
			plans = planProvider.generatePlans(
				scene: .generic, person: nil, bodyCount: 0, groupBox: nil,
				zoomFactor: zoomState.currentFactor,
				hasTelephoto: false, hasUltraWide: false, cropHint: nil
			)
		}
		coachGuidance = nil
		compositionPlans = plans
		coachPhase = .plans
		HapticManager.shared.soft()
	}

	/// 用户选择方案 → 进入引导（目标锁定自方案）
	func selectPlan(at index: Int) {
		guard compositionPlans.indices.contains(index) else { return }
		let plan = compositionPlans[index]
		selectedPlan = plan
		selectedPlanIndex = index

		lockedTargetPoint = CGPoint(x: plan.subjectTarget.x, y: 1 - plan.subjectTarget.y)
		subjectLostSince = nil
		guidanceEngine.reset()
		saliencySmoother.reset()
		saliencyCenter = nil

		// 焦段建议 → 变焦盘高亮（P1 的自动切换先不做，只提示）
		if let hint = plan.focalHint, let factor = Self.parseFocalHint(hint) {
			sceneRecommendedFactor = factor
		} else {
			sceneRecommendedFactor = nil
		}

		coachSceneLabel = plan.title
		coachSuggestion = plan.detail
		lastSuggestionChange = Date()
		pendingSuggestion = nil
		suggestionDebounceWork?.cancel()
		coachGuidance = nil
		coachPhase = .guiding
		HapticManager.shared.selection()
		pendingFrameForAnalysis = true
	}

	/// "2x"/"0.5x" → 变焦倍率
	private static func parseFocalHint(_ hint: String) -> CGFloat? {
		let trimmed = hint
			.replacingOccurrences(of: "x", with: "")
			.replacingOccurrences(of: "X", with: "")
			.trimmingCharacters(in: .whitespaces)
		guard let value = Double(trimmed), value > 0 else { return nil }
		return CGFloat(value)
	}

	/// chip 文案发布（防抖）：相同文案不发布；
	/// 最小驻留 400ms；反向指令（左↔右/近↔远/高↔低）冷却 600ms，
	/// 未到期时保留最新意图延迟补发
	private func publishSuggestion(_ text: String) {
		guard text != coachSuggestion else { return }
		let now = Date()
		let elapsed = now.timeIntervalSince(lastSuggestionChange)
		let required: TimeInterval = Self.isOppositeSuggestion(text, coachSuggestion) ? 0.6 : 0.4

		guard elapsed >= required else {
			pendingSuggestion = text
			suggestionDebounceWork?.cancel()
			let work = DispatchWorkItem { [weak self] in
				guard let self, let pending = self.pendingSuggestion else { return }
				self.pendingSuggestion = nil
				self.publishSuggestion(pending)
			}
			suggestionDebounceWork = work
			DispatchQueue.main.asyncAfter(deadline: .now() + (required - elapsed), execute: work)
			return
		}

		pendingSuggestion = nil
		suggestionDebounceWork?.cancel()
		coachSuggestion = text
		lastSuggestionChange = now
	}

	/// 判断两条指令是否互为反向
	private static func isOppositeSuggestion(_ a: String, _ b: String) -> Bool {
		let pairs = [("向左", "向右"), ("靠近", "退远"), ("举高", "放低")]
		return pairs.contains { pair in
			(a.contains(pair.0) && b.contains(pair.1)) || (a.contains(pair.1) && b.contains(pair.0))
		}
	}

	/// 锁定目标点的 X 选择规则（构图标准）：
	/// 1. 前视空间优先——脸朝右 → 人放左三分点，给视线留白；脸朝左反之
	/// 2. 无明确朝向 → 取最近三分点（减少用户移动量）
	/// 3. 主体居中（左右等距）→ 固定取右三分点（确定性，避免等距翻转）
	private func lockedTargetX(for person: PersonInfo) -> CGFloat {
		let left = 1.0 / 3.0
		let right = 2.0 / 3.0

		if let faceX = person.faceCenterX {
			let facing = faceX - person.centerX
			if facing > 0.015 { return left }
			if facing < -0.015 { return right }
		}
		if abs(person.centerX - 0.5) < 0.05 { return right }
		return abs(person.centerX - left) <= abs(person.centerX - right) ? left : right
	}

	/// 供 UI 显示的目标标记点（视图坐标；前置预览是镜像的，X 需翻转）
	var displayTargetMarkerPoint: CGPoint? {
		if let point = coachGuidance?.targetPointInView {
			return isFrontCamera
				? CGPoint(x: compositionRectInView.width - point.x, y: point.y)
				: point
		}
		// 静态方案（无跟踪）：方案目标点直接上屏
		if let plan = selectedPlan, plan.tracking == .none, compositionRectInView.width > 0 {
			let x = plan.subjectTarget.x * compositionRectInView.width
			let y = plan.subjectTarget.y * compositionRectInView.height
			return isFrontCamera
				? CGPoint(x: compositionRectInView.width - x, y: y)
				: CGPoint(x: x, y: y)
		}
		return nil
	}

	/// 一行建议指令（chip 文案）：有引导按方向说，无引导按方案/场景说
	private func chipText(guidance: GuidanceResult?, plan: CompositionPlan?) -> String {
		if let guidance {
			switch guidance.state {
			case .optimal:
				return isAutoCaptureEnabled ? "构图完成，即将拍摄" : "构图完成，可以拍了"
			case .nearlyOptimal:
				return "把主体对准标记圈，就差一点"
			case .adjusting:
				return directionText(for: guidance)
			}
		}
		if let plan {
			return plan.detail
		}
		return currentScene?.defaultInstruction ?? SceneClassifier.SceneKind.generic.defaultInstruction
	}

	/// 方向 → 复合口语化指令（距离/水平/垂直可叠加）
	private func directionText(for guidance: GuidanceResult) -> String {
		var parts: [String] = []
		switch guidance.distanceDirection {
		case .moveCloser: parts.append("再靠近一点")
		case .moveFarther: parts.append("退远一点")
		default: break
		}
		switch guidance.horizontalDirection {
		case .moveLeft: parts.append(isFrontCamera ? "向右移一点" : "向左移一点")
		case .moveRight: parts.append(isFrontCamera ? "向左移一点" : "向右移一点")
		default: break
		}
		switch guidance.verticalDirection {
		case .moveUp: parts.append("举高一点")
		case .moveDown: parts.append("放低一点")
		default: break
		}
		if parts.isEmpty { return "保持稳定，微调构图" }
		return parts.joined(separator: "，")
	}

	/// 从构图分析结果构建引导引擎输入
	private func makeCurrentComposition(from result: CompositionResult) -> CurrentComposition {
		let person = result.person
		return CurrentComposition(
			subjectCenterX: person.centerX,
			subjectCenterY: person.centerY,
			subjectWidthRatio: person.widthRatio,
			subjectHeightRatio: person.heightRatio,
			faceCenterX: person.faceCenterX,
			faceCenterY: person.faceCenterY,
			headRoomRatio: person.headRoom,
			minEdgeDistance: 0,
			isSubjectComplete: person.isFullBody,
			overallScore: result.score,
			subjectPosition: result.subjectPosition
		)
	}

	// MARK: - 自动拍摄（构图完成 + 可选开启）

	private func scheduleAutoCaptureIfEnabled() {
		guard isAutoCaptureEnabled else { return }
		cancelAutoCapture()

		let total = max(0.5, captureDelay)
		countdownDeadline = Date().addingTimeInterval(total)
		autoCaptureCountdown = (remain: total, total: total)
		let totalSteps = Int(ceil(total))
		var lastStep = totalSteps

		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now(), repeating: 0.05)
		timer.setEventHandler { [weak self] in
			guard let self, let deadline = self.countdownDeadline else { return }
			let remain = deadline.timeIntervalSinceNow
			self.autoCaptureCountdown = (remain: max(0, remain), total: total)

			// 每秒一步的倒计时震动（渐强）
			let step = Int(ceil(max(0, remain)))
			if step != lastStep {
				lastStep = step
				if step > 0 {
					HapticManager.shared.countdown(step: totalSteps - step + 1, total: totalSteps)
				}
			}

			guard remain <= 0 else { return }
			self.autoCaptureCountdown = nil
			self.countdownTimer?.cancel()
			self.countdownTimer = nil

			// 触发瞬间会话可能已被打断（切镜头/退出/失稳取消）
			guard self.coachPhase == .achieved else { return }
			self.onCaptureTriggered?()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
				self.capturePhoto()
			}
		}
		countdownTimer = timer
		timer.resume()
	}

	private func cancelAutoCapture() {
		countdownTimer?.cancel()
		countdownTimer = nil
		countdownDeadline = nil
		autoCaptureCountdown = nil
		autoCaptureWorkItem?.cancel()
		autoCaptureWorkItem = nil
	}

	// MARK: - Geometry Helpers

	private func pixelOrientation(for pixelBuffer: CVPixelBuffer) -> CGImagePropertyOrientation {
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		return width > height ? .right : .up
	}
}

#endif
