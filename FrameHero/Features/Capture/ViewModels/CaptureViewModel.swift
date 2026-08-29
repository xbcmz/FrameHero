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

	/// 会话是否激活（帧分析的总开关）
	private var isCoachActive = false
	/// 当前稳定场景
	private var currentScene: SceneClassifier.SceneKind?

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
		autoCaptureWorkItem?.cancel()
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
		coachSceneLabel = nil
		coachGuidance = nil
		compositionTarget = nil
		currentComposition = nil
		photographyAnalysis = nil
		coachSuggestion = "正在分析场景"
		coachPhase = .analyzing
		isCoachActive = true
		// 标记待分析帧：下一帧到达立即分析，不等节流窗口
		pendingFrameForAnalysis = true
	}

	func stopAIComposition() {
		HapticManager.shared.light()
		isCoachActive = false
		coachPhase = .idle
		coachGuidance = nil
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
			coachSceneLabel = nil
			compositionTarget = nil
			currentComposition = nil
			coachGuidance = nil
			coachPhase = .analyzing
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
		guard isCoachActive, coachPhase != .idle else { return }
		guard let pixel = CMSampleBufferGetImageBuffer(sample) else { return }
		let orientation = pixelOrientation(for: pixel)

		// 会话启动/镜头切换后的第一帧立即分析
		if pendingFrameForAnalysis {
			pendingFrameForAnalysis = false
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

		// 1. 场景识别（独立回调，多帧投票）
		sceneClassifier.classify(pixel, orientation: orientation) { [weak self] decision in
			guard let self, let decision else { return }
			self.applyScene(decision)
		}

		// 2. 主体检测 + 构图评分 + 目标构图（本地 Vision，无网络）
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

	/// 场景结论 → 标签 + 参数预设（带滞回，只在场景变化时下发）
	private func applyScene(_ decision: SceneClassifier.Decision) {
		let scene = decision.kind
		if scene == currentScene { return }

		// generic 不覆盖已识别的具体场景（避免偶发无分类帧抖动）
		if scene == .generic, currentScene != nil { return }

		currentScene = scene
		coachSceneLabel = scene.displayName.isEmpty ? nil : scene.displayName

		// 场景 → 相机参数预设：只改写 aiAuto 状态的参数（用户手动/锁定的不覆盖）
		applyAICameraStrategy(scenePreset(for: scene))
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

	/// 消费一次构图分析结果：更新目标、计算引导、迁移会话阶段
	private func ingestAnalysis(_ result: PhotographyAnalysisResult) {
		photographyAnalysis = result
		compositionTarget = result.target
		currentComposition = makeCurrentComposition(from: result.composition)

		// 计算实时引导（视图尺寸就绪才有意义）
		if compositionRectInView.width > 0 {
			let guidance = guidanceEngine.compute(
				current: currentComposition!,
				target: compositionTarget!,
				viewSize: compositionRectInView.size
			)
			coachGuidance = guidance
		}

		// 阶段迁移
		switch coachPhase {
		case .analyzing:
			// 第一份分析到达即进入引导
			coachSuggestion = chipText(for: result, guidance: coachGuidance)
			coachPhase = .guiding

		case .guiding, .achieved:
			coachSuggestion = chipText(for: result, guidance: coachGuidance)

			if coachGuidance?.state == .optimal {
				if coachPhase != .achieved {
					coachPhase = .achieved
					HapticManager.shared.focusLock()
					scheduleAutoCaptureIfEnabled()
				}
			} else if coachPhase == .achieved {
				coachPhase = .guiding
				cancelAutoCapture()
			}

		case .idle:
			break
		}
	}

	/// 一行建议指令（chip 文案）：有主体按引导方向说，没主体按场景说
	private func chipText(for result: PhotographyAnalysisResult, guidance: GuidanceResult?) -> String {
		if let guidance {
			switch guidance.state {
			case .optimal:
				return isAutoCaptureEnabled ? "构图完成，即将拍摄" : "构图完成，可以拍了"
			case .nearlyOptimal:
				return "接近最佳构图，再微调一下"
			case .adjusting:
				return directionText(for: guidance)
			}
		}
		if result.composition.person.detected {
			return "把人物调整到三分线交叉点附近"
		}
		return currentScene?.defaultInstruction ?? SceneClassifier.SceneKind.generic.defaultInstruction
	}

	/// 方向 → 口语化指令（优先级：远近 > 水平 > 垂直）
	private func directionText(for guidance: GuidanceResult) -> String {
		switch guidance.distanceDirection {
		case .moveCloser: return "再靠近一点，主体更饱满"
		case .moveFarther: return "退远一点，给主体留出空间"
		default: break
		}
		switch guidance.horizontalDirection {
		case .moveLeft: return isFrontCamera ? "向右移一点，人物靠三分线" : "向左移一点，人物靠三分线"
		case .moveRight: return isFrontCamera ? "向左移一点，人物靠三分线" : "向右移一点，人物靠三分线"
		default: break
		}
		switch guidance.verticalDirection {
		case .moveUp: return "举高一点"
		case .moveDown: return "放低一点"
		default: break
		}
		return "保持稳定，微调构图"
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
		autoCaptureWorkItem?.cancel()

		let work = DispatchWorkItem { [weak self] in
			guard let self, self.coachPhase == .achieved else { return }
			self.onCaptureTriggered?()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
				self.capturePhoto()
			}
		}
		autoCaptureWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay, execute: work)
	}

	private func cancelAutoCapture() {
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
