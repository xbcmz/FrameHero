//
//  CaptureViewModel.swift
//  LiveCapture
//
//  拍摄功能的视图模型
//
//  ## 文件作用
//  协调相机、运动传感器和 AI 检测模块
//  管理整个智能拍摄流程的状态机
//  为 CaptureView 提供所有业务逻辑和状态
//
//  ## 主要类
//  ### CaptureViewModel
//  拍摄功能视图模型（ObservableObject）
//
//  ## Dependencies（依赖项）
//  - camera: CameraManager - 相机管理器
//  - motion: MotionStabilityMonitor - 运动监控器
//  - aestheticDetector: AestheticCropDetector - 美学检测器
//  - boxCenterManager: BoxCenterManager - 追踪点管理器
//
//  ## Published 状态
//  - cropRectInView: CGRect? - 当前裁切框位置
//  - initialCropRectInView: CGRect? - 初始检测的裁切框
//  - compositionRectInView: CGRect - 构图区域
//  - isAligned: Bool - 是否对齐中心
//  - debugMessage: String - 调试信息
//  - pipelineStage: PipelineStage - 当前流程阶段
//  - distanceToCenter: CGFloat? - 到中心的距离
//  - detectionReady: Bool - 检测是否就绪
//  - motionIsStable: Bool - 设备是否稳定
//  - zoomState/zoomPresets/zoomRange - 变焦相关状态
//  - userGuidanceText: String - 用户引导文字
//  - isAutoCaptureEnabled: Bool - 是否启用自动拍照
//  - captureDelay: Double - 拍照延迟（秒）
//  - isSwitchingCamera: Bool - 是否正在切换摄像头
//  - isCompositionPipelineEnabled: Bool - 是否启用构图自动化流水线
//
//  ## 计算属性
//  - baseBoxCenterInView: CGPoint? - 基准中心点
//  - boxCenterInView: CGPoint? - 当前中心点
//  - isFrontCamera: Bool - 是否为前置摄像头
//  - adjustedCropRectInView: CGRect? - 调整后的裁切框
//  - zoomDisplayText: String - 变焦显示文本
//  - focalLengthText: String - 焦距显示文本
//  - session: AVCaptureSession - 相机会话
//
//  ## 主要方法
//
//  ### 生命周期
//  - init(): 初始化依赖和绑定
//  - onAppear(): 视图出现时启动相机和传感器
//  - onDisappear(): 视图消失时停止所有服务
//
//  ### 相机控制
//  - capturePhoto(): 触发拍照
//  - toggleCameraPosition(): 切换前后摄像头
//    包含翻转动画和状态重置
//
//  ### 变焦控制
//  - selectZoomPreset(_:): 选择变焦预设
//  - updateZoomInteractively(to:): 交互式变焦
//  - finalizeZoomInteractively(at:smooth:): 完成交互式变焦
//
//  ### 状态管理
//  - registerCompositionRect(_:): 注册构图区域尺寸
//  - resetDetectionState(): 重置所有检测状态
//  - toggleAutoCapture(): 切换自动拍照开关
//  - setCaptureDelay(_:): 设置拍照延迟
//  - toggleCompositionPipeline(): 切换构图自动化流水线开关
//    开启时显示"构图流水线已开启"提示
//    关闭时显示"点击魔术棒开启智能构图"提示
//
//  ### 其他功能
//  - openSystemPhotoLibrary(): 打开系统相册
//
//  ## 私有方法
//
//  ### 绑定
//  - bindMotion(): 绑定运动传感器事件
//    - 订阅 deviceMotion 更新追踪点
//    - 订阅 isStable 控制检测流程
//    - 订阅 largeMotionDetected 自动重置
//
//  - bindCamera(): 绑定相机事件
//    - 订阅 lastPhotoSaved 显示保存结果
//    - 订阅 zoomState 更新变焦显示
//    - 订阅 zoomPresets/zoomRange
//
//  ### 处理流程
//  - setupCallbacks(): 设置相机帧回调
//  - handleSampleBuffer(_:): 处理视频帧
//    - 等待稳定
//    - 触发 AI 检测
//    - 传递给检测管线
//
//  - detectCropRegion(using:orientation:): 执行裁切区域检测
//    - 调用 AestheticCropDetector
//    - 转换坐标到视图空间
//    - 设置基准中心点
//    - 锁定参考姿态
//
//  ### 自动拍照
//  - scheduleAutoCapture(): 调度自动拍照任务
//    在对齐后延迟执行
//
//  - cancelAutoCapture(): 取消自动拍照任务
//
//  ### 对齐检测
//  - checkAlignmentByDistance(): 检查距离对齐
//    - 调用 BoxCenterManager 检测
//    - 对齐时触发自动拍照
//    - 失去对齐时取消拍照
//
//  ### 状态控制
//  - setStage(_:message:): 设置流程阶段
//    - 更新 pipelineStage
//    - 更新 debugMessage
//    - 调用统一刷新机制更新 userGuidanceText
//    - 线程安全
//
//  - refreshUserGuidance(): 统一的用户引导文本刷新机制
//    - 根据 isCompositionPipelineEnabled 状态决定显示内容
//    - 流水线开启时：显示当前阶段引导或"构图流水线已开启"
//    - 流水线关闭时：显示"点击魔术棒开启智能构图"
//    - 被所有需要更新引导文本的方法调用
//
//  ### 几何转换
//  - makeCompositionPixelBuffer(from:orientation:): 
//    创建 3:4 构图像素缓冲
//
//  - pixelOrientation(for:): 判断像素缓冲方向
//
//  - rotateNormalizedRect(_:for:): 旋转归一化矩形
//
//  - rectInCompositionSpace(from:orientation:): 
//    转换检测框到视图坐标系
//
//  ## 流程状态机（PipelineStage）
//  - idle: 空闲
//  - startingCamera: 启动相机
//  - waitingForStability: 等待稳定
//  - detectingRegion: 检测区域
//  - templateReady: 模板就绪（追踪中）
//  - readyToCapture: 准备拍照
//  - capturingPhoto: 正在拍照
//  - savingPhoto: 保存照片
//  - error: 错误
//
//  每个阶段有对应的：
//  - progress: Double - 进度值
//  - guidanceText: String - 引导文字
//
//  ## 线程处理
//  - 视频帧在 videoOutputQueue 处理
//  - AI 检测在专用队列异步执行
//  - UI 状态更新确保在主线程
//  - 使用 Combine 管理异步事件流
//
//  ## 性能优化
//  - detectionInProgress 标志避免重复检测
//  - 使用 static ciContext 共享 Core Image 上下文
//  - 帧处理前检查稳定性减少无效计算
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
	private let detector: CropDetectionStrategy
	private let boxCenterManager = BoxCenterManager()
	private let photographyAdvisor: PhotographyAdvisor
	private let visionDetector: AestheticCropDetector?  // 只有 vision 模式才有

	// MARK: - Published State
	
	@Published private(set) var cropRectInView: CGRect?
	@Published private(set) var initialCropRectInView: CGRect?
	@Published private(set) var compositionRectInView: CGRect = .zero
	@Published private(set) var isAligned: Bool = false
	@Published private(set) var debugMessage: String = "等待相机启动..."
	@Published private(set) var pipelineStage: PipelineStage = .idle
	@Published private(set) var distanceToCenter: CGFloat?
	@Published private(set) var detectionReady: Bool = false
	@Published private(set) var motionIsStable: Bool = false
	@Published private(set) var zoomState: CameraManager.ZoomState
	@Published private(set) var zoomPresets: [CameraManager.ZoomPreset]
	@Published private(set) var zoomRange: ClosedRange<CGFloat>
	@Published private(set) var userGuidanceText: String = ""
	@Published var isAutoCaptureEnabled: Bool = true
	@Published var captureDelay: Double = 1.0
	@Published var isSwitchingCamera: Bool = false
	@Published var isCompositionPipelineEnabled: Bool = false
	
	// MARK: - 相机能力与环境（Phase 0）
	
	/// 当前设备的相机能力（启动时读取，切换摄像头时更新）
	@Published private(set) var cameraCapability: CameraCapability = .empty
	
	/// 当前相机环境状态（实时参数）
	@Published private(set) var cameraEnvironment: CameraEnvironment = .empty
	
	/// 当前摄影策略（AI + 用户共同决定）
	@Published var photographyStrategy: PhotographyStrategy = .default
	
	// MARK: - AI 摄影建议
	
	@Published private(set) var photographyAnalysis: PhotographyAnalysisResult?
	@Published private(set) var isPhotographyAnalyzing: Bool = false
	/// 是否在拍摄页显示 AI 建议（全局设置）。
	/// 开关在「设置 → AI 助手」里（AppStorage key: aiAdviceEnabled），
	/// 这里按 VM 创建时读取一次——CaptureView 每次全屏弹出都会新建 VM，
	/// 设置页的改动自然带到下一次拍摄会话。
	@Published private(set) var isPhotographyAdviceEnabled: Bool =
		UserDefaults.standard.bool(forKey: "aiAdviceEnabled")
	
	// MARK: - 构图引导（AI 目标 + 实时导航）
	
	/// 当前构图状态（每帧更新）
	@Published private(set) var currentComposition: CurrentComposition?
	
	/// 目标构图状态（AI 分析后生成，固定不变）
	@Published private(set) var compositionTarget: CompositionTarget?
	
	/// 实时引导结果（方向、进度、是否达标）
	@Published private(set) var guidanceResult: GuidanceResult?
	
	/// 引导引擎
	private let guidanceEngine = CompositionGuidanceEngine()
	
	/// 引导模式
	enum GuidanceMode {
		case none               // 没有引导
		case cropAutoCapture    // 原有的裁切自动拍照
		case aiTarget           // AI 推荐目标引导
	}
	
	/// 当前引导模式
	private var guidanceMode: GuidanceMode = .none
	
	var onCaptureTriggered: (() -> Void)?
	
	// MARK: - Computed Properties
	
	var baseBoxCenterInView: CGPoint? { boxCenterManager.baseCenterInView }
	var boxCenterInView: CGPoint? { boxCenterManager.currentCenterInView }
	var isFrontCamera: Bool { camera.currentPosition == .front }
	
	var adjustedCropRectInView: CGRect? {
		guard let initialRect = initialCropRectInView,
			  let baseCenter = baseBoxCenterInView,
			  let currentCenter = boxCenterInView else {
			return nil
		}
		let dx = currentCenter.x - baseCenter.x
		let dy = currentCenter.y - baseCenter.y
		return initialRect.offsetBy(dx: dx, dy: dy)
	}
	
	var zoomDisplayText: String {
		let factor = zoomState.displayedFactor
		if abs(Double(factor.rounded()) - Double(factor)) < 0.001 {
			return "\(Int(factor.rounded()))×"
		}
		return String(format: "%.2f×", factor)
	}
	
	var focalLengthText: String {
		"\(zoomState.focalLength)mm"
	}
	
	var session: AVCaptureSession { camera.session }
	
	// MARK: - 显示控制计算属性
	
	/// 是否显示裁切引导 UI（旧的魔法棒模式）
	/// 当 AI 引导激活时，隐藏旧的裁切引导，只显示统一的 AI 引导
	var showCropGuide: Bool {
		isCompositionPipelineEnabled && !isAIGuidanceActive
	}
	
	/// AI 引导是否处于激活状态
	var isAIGuidanceActive: Bool {
		isPhotographyAdviceEnabled && guidanceResult != nil
	}
	
	/// 供 UI 显示的引导结果（前置摄像头时水平方向翻转）
	var displayGuidanceResult: GuidanceResult? {
		guard var result = guidanceResult else { return nil }
		guard isFrontCamera else { return result }
		
		// 前置摄像头画面是镜像的，水平方向需要翻转
		switch result.horizontalDirection {
		case .moveLeft: result.horizontalDirection = .moveRight
		case .moveRight: result.horizontalDirection = .moveLeft
		default: break
		}
		
		return result
	}
	
	// MARK: - Private State
	
	private static let ciContext = CIContext()
	private let alignmentTolerance: CGFloat = 15.0
	private var detectionInProgress: Bool = false
	private var cancellables: Set<AnyCancellable> = []
	private var autoCaptureWorkItem: DispatchWorkItem?

	/// 单帧分析在途标志（本地防抖，不依赖 AI 请求时长，
	/// 避免网络请求期间整条构图/引导流水线停摆）
	private var isFrameAnalysisInFlight = false

	/// 检测失败后的冷却时间戳（避免逐帧重试推理）
	private var lastDetectionFailureTime: Date?

	/// 追踪点更新的节流时间戳（CoreMotion 60Hz → 主线程 ~30Hz）
	private var lastMotionUIUpdate: Date = .distantPast
	
	// MARK: - 相机控制引擎（Phase 1）
	
	/// 相机控制引擎，负责将 PhotographyStrategy 转换成硬件参数
	private let controlEngine = CameraControlEngine()
	
	// MARK: - Lifecycle
	
	private let detectionMode: DetectionMode

	init(detectionMode: DetectionMode = .fast) {
		self.detectionMode = detectionMode
		switch detectionMode {
		case .vision:
			let visionDet = AestheticCropDetector()
			detector = visionDet
			visionDetector = visionDet
			photographyAdvisor = PhotographyAdvisor(detector: visionDet)
		case .fast, .pro:
			detector = CoreMLCropDetector(mode: detectionMode)
			visionDetector = nil
			// CoreML 模式下也用 Vision 检测器做人物分析（因为 Composition 需要原始检测数据）
			photographyAdvisor = PhotographyAdvisor()
		}

		zoomState = camera.zoomState
		zoomPresets = camera.zoomPresets
		zoomRange = camera.zoomRange
		
		// 初始化控制引擎
		controlEngine.setCamera(camera)

		boxCenterManager.setFrontCamera(camera.currentPosition == .front)

		bindMotion()
		bindCamera()
		refreshUserGuidance()
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
				// 🔥 相机启动成功后，刷新引导文字
				DispatchQueue.main.async {
					self.refreshUserGuidance()
				}
			case .failure:
				DispatchQueue.main.async {
					self.setStage(.error, message: "相机启动失败")
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
		boxCenterManager.updateCompositionRect(rect)
	}
	
	func capturePhoto() {
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
	
	// MARK: - 曝光控制（Phase 1）
	
	/// 调整曝光偏差（EV）
	///
	/// - Parameter bias: EV 值，通常范围 -2...+2
	///
	/// 调用后会自动将曝光模式切换为 manual
	func setExposureBias(_ bias: Float) {
		photographyStrategy.exposureControl = .manual
		photographyStrategy.manualExposureBias = bias
	}
	
	/// 切换曝光控制模式
	func setExposureControlMode(_ mode: ControlMode) {
		let previousMode = photographyStrategy.exposureControl
		photographyStrategy.exposureControl = mode

		// 如果切回 aiAuto，重置手动 EV
		if mode == .aiAuto {
			photographyStrategy.manualExposureBias = 0
			photographyStrategy.brightnessPreference = .auto
		}

		// 如果切到 locked，锁定当前值
		if mode == .locked {
			// 当前 EV 值就是锁定值
			photographyStrategy.manualExposureBias = cameraEnvironment.currentExposureBias
		}

		// 从自动切到手动时，用当前真实 EV 作为起点（与对焦/白平衡语义一致），
		// 否则滑杆会从默认 0 起跳，画面亮度突变
		if mode == .manual, previousMode == .aiAuto {
			photographyStrategy.manualExposureBias = cameraEnvironment.currentExposureBias
		}
	}
	
	/// 设置 AI 亮度偏好
	///
	/// 仅在 exposureControl == .aiAuto 时生效
	func setBrightnessPreference(_ preference: BrightnessPreference) {
		photographyStrategy.brightnessPreference = preference
	}
	
	/// 重置曝光为全自动
	func resetExposureToAuto() {
		photographyStrategy.exposureControl = .aiAuto
		photographyStrategy.manualExposureBias = 0
		photographyStrategy.brightnessPreference = .auto
		camera.resetExposureToAuto()
	}
	
	// MARK: - 对焦控制（Phase 2）
	
	/// 设置手动对焦位置
	///
	/// - Parameter position: 0.0...1.0（最近...无穷远）
	///
	/// 调用后自动切换到 manual 模式
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
			// 切回自动对焦，重置手动位置
			photographyStrategy.manualFocusPosition = nil
			photographyStrategy.focusPreference = .auto
			
		case .locked:
			// 锁定当前对焦位置
			photographyStrategy.manualFocusPosition = cameraEnvironment.focusLensPosition
			camera.lockFocus()
			
		case .manual:
			// 如果之前是自动，用当前位置作为初始值
			if previousMode == .aiAuto {
				photographyStrategy.manualFocusPosition = cameraEnvironment.focusLensPosition
			}
		}
	}
	
	/// 设置 AI 对焦偏好
	///
	/// 仅在 focusControl == .aiAuto 时生效
	func setFocusPreference(_ preference: FocusPreference) {
		photographyStrategy.focusPreference = preference
	}
	
	/// 设置对焦点（画面坐标）
	///
	/// - Parameter point: 视图坐标中的对焦点
	///
	/// 会自动切换到 auto 模式并触发对焦
	func setFocusPointOfInterest(_ point: CGPoint, in viewSize: CGSize) {
		// 将视图坐标转换为 0...1 范围
		let normalizedPoint = CGPoint(
			x: point.x / viewSize.width,
			y: point.y / viewSize.height
		)
		photographyStrategy.focusControl = .aiAuto
		photographyStrategy.focusPointOfInterest = normalizedPoint
		photographyStrategy.focusPreference = .subjectLock

		// 直接调用相机设置对焦点（更直接）
		camera.setFocusPointOfInterest(normalizedPoint)
	}

	/// 点按对焦/曝光（设备归一化坐标，由预览层 captureDevicePointConverted 转换而来，
	/// 前置摄像头的镜像已在调用方处理）
	func focusAtDevicePoint(_ point: CGPoint) {
		photographyStrategy.focusControl = .aiAuto
		photographyStrategy.focusPointOfInterest = point
		photographyStrategy.focusPreference = .subjectLock
		camera.setFocusPointOfInterest(point)
	}
	
	/// 重置对焦为全自动
	func resetFocusToAuto() {
		photographyStrategy.focusControl = .aiAuto
		photographyStrategy.focusPreference = .auto
		photographyStrategy.manualFocusPosition = nil
		photographyStrategy.focusPointOfInterest = nil
		camera.resetFocusToAuto()
	}
	
	// MARK: - 白平衡控制（Phase 3）
	
	/// 设置手动白平衡色温
	///
	/// - Parameter temperature: 色温（开尔文），通常 2000K...10000K
	///
	/// 调用后自动切换到 manual 模式
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
			// 切回自动白平衡，重置手动值
			photographyStrategy.manualWhiteBalanceTemp = nil
			photographyStrategy.whiteBalancePreference = .auto
			camera.resetWhiteBalanceToAuto()
			
		case .locked:
			// 锁定当前白平衡
			photographyStrategy.manualWhiteBalanceTemp = cameraEnvironment.estimatedColorTemperature
			camera.lockWhiteBalance()
			
		case .manual:
			// 如果之前是自动，用当前色温作为初始值
			if previousMode == .aiAuto {
				photographyStrategy.manualWhiteBalanceTemp = cameraEnvironment.estimatedColorTemperature
			}
		}
	}
	
	/// 设置 AI 白平衡偏好
	///
	/// 仅在 whiteBalanceControl == .aiAuto 时生效
	func setWhiteBalancePreference(_ preference: WhiteBalancePreference) {
		photographyStrategy.whiteBalancePreference = preference
	}
	
	/// 重置白平衡为全自动
	func resetWhiteBalanceToAuto() {
		photographyStrategy.whiteBalanceControl = .aiAuto
		photographyStrategy.whiteBalancePreference = .auto
		photographyStrategy.manualWhiteBalanceTemp = nil
		camera.resetWhiteBalanceToAuto()
	}
	
	// MARK: - 镜头/变焦控制（Phase 4）
	
	/// 设置镜头偏好
	///
	/// 仅在 lensControl == .aiAuto 时由 AI 调用
	func setLensPreference(_ preference: LensPreference) {
		photographyStrategy.lensPreference = preference
	}
	
	/// 切换镜头控制模式
	func setLensControlMode(_ mode: ControlMode) {
		let previousMode = photographyStrategy.lensControl
		photographyStrategy.lensControl = mode
		
		switch mode {
		case .aiAuto:
			// 切回 AI 自动
			photographyStrategy.manualZoomFactor = nil
			photographyStrategy.lensPreference = .auto
			
		case .locked:
			// 锁定当前变焦倍率
			photographyStrategy.manualZoomFactor = zoomState.currentFactor
			
		case .manual:
			// 手动模式，用当前倍率作为初始值
			if previousMode == .aiAuto {
				photographyStrategy.manualZoomFactor = zoomState.currentFactor
			}
		}
	}
	
	/// 设置手动变焦倍率
	func setManualZoomFactor(_ factor: CGFloat) {
		photographyStrategy.lensControl = .manual
		photographyStrategy.manualZoomFactor = factor
	}
	
	func toggleCameraPosition() {
		isSwitchingCamera = true
		resetDetectionState()
		
		// 🔥 在切换前计算下一个位置（因为 toggleCameraPosition 是异步的）
		let nextPosition: AVCaptureDevice.Position = camera.currentPosition == .back ? .front : .back
		
		camera.toggleCameraPosition()
		
		// 更新前置摄像头状态到 BoxCenterManager（使用计算出的下一个位置）
		boxCenterManager.setFrontCamera(nextPosition == .front)
		
		// 🔥 如果流水线开启，显示等待稳定；否则使用统一刷新机制
		if isCompositionPipelineEnabled {
			setStage(.waitingForStability, message: "切换镜头，等待稳定")
		} else {
			refreshUserGuidance()
		}
		
		// 切换动画完成后重置标志
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			self.isSwitchingCamera = false
		}
	}
	
	func openSystemPhotoLibrary() {
		#if canImport(UIKit)
		if let url = URL(string: "photos-redirect://") {
			DispatchQueue.main.async {
				UIApplication.shared.open(url, options: [:], completionHandler: nil)
			}
		}
		#endif
	}
	
	func resetDetectionState() {
		detectionReady = false
		isAligned = false
		cropRectInView = nil
		initialCropRectInView = nil
		boxCenterManager.reset()
		autoCaptureWorkItem?.cancel()
		motion.resetReferenceAttitude()
		detectionInProgress = false
		// 🔥 统一刷新引导文本
		refreshUserGuidance()
	}
	
	func toggleAutoCapture() {
		isAutoCaptureEnabled.toggle()
	}
	
	func setCaptureDelay(_ delay: Double) {
		captureDelay = delay
	}
	
	func toggleCompositionPipeline() {
		isCompositionPipelineEnabled.toggle()
		
		if isCompositionPipelineEnabled {
			// 开启时显示提示
			HapticManager.shared.success()
		} else {
			// 关闭时刷新检测状态
			HapticManager.shared.light()
			resetDetectionState()
		}
		// 🔥 统一刷新引导文本
		refreshUserGuidance()
	}
	
	// MARK: - User Guidance
	
	/// 统一的用户引导文本刷新机制
	/// 根据当前状态决定显示的引导文字
	private func refreshUserGuidance() {
		if isCompositionPipelineEnabled {
			// 流水线开启时，根据当前阶段显示引导
			if detectionReady {
				userGuidanceText = pipelineStage.guidanceText
			} else {
				userGuidanceText = "构图流水线已开启"
			}
		} else {
			// 流水线关闭时，显示开启提示
			userGuidanceText = "点击魔术棒开启智能构图"
		}
	}
	
	// MARK: - Bindings
	
	private func bindMotion() {
		motion.$deviceMotion
			.receive(on: DispatchQueue.main)
			.sink { [weak self] motion in
				guard let self else { return }
				// 节流到 ~30Hz：追踪点足够顺滑，主线程负载减半
				let now = Date()
				guard now.timeIntervalSince(self.lastMotionUIUpdate) >= 0.033 else { return }
				self.lastMotionUIUpdate = now

				self.boxCenterManager.updateCenter(with: motion)

				// 没有锁定的检测目标时，对齐/裁切框计算都是无效功
				guard self.detectionReady else { return }

				self.distanceToCenter = self.boxCenterManager.distanceToCenter()

				if let adjusted = self.adjustedCropRectInView {
					self.cropRectInView = adjusted
				}
				self.checkAlignmentByDistance()
			}
			.store(in: &cancellables)

		motion.$isStable
			.receive(on: DispatchQueue.main)
			.sink { [weak self] stable in
				guard let self else { return }
				self.motionIsStable = stable
			}
			.store(in: &cancellables)

		motion.$largeMotionDetected
			.receive(on: DispatchQueue.main)
			.sink { [weak self] detected in
				guard let self, detected, self.detectionReady else { return }
				// 检测到大幅度运动时自动重置状态
				HapticManager.shared.warning()
				self.resetDetectionState()
			}
			.store(in: &cancellables)
	}
	
	private func bindCamera() {
		camera.$lastPhotoSaved
			.receive(on: DispatchQueue.main)
			.sink { [weak self] saved in
				guard let self, saved else { return }
				HapticManager.shared.success()
				self.setStage(.savingPhoto, message: "照片已保存")
				// 短暂展示保存结果后回到就绪态。
				// 注意：不能关闭构图流水线——用户连续拍摄时每次都要重新开魔法棒是重大体验 bug
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					if self.pipelineStage == .savingPhoto {
						self.resetDetectionState()
						self.refreshUserGuidance()
					}
				}
			}
			.store(in: &cancellables)
		
		camera.$zoomState
			.receive(on: DispatchQueue.main)
			.sink { [weak self] state in
				guard let self else { return }
				self.zoomState = state
				self.boxCenterManager.updateZoomFactor(state.currentFactor)
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
		
		// MARK: - 相机能力与环境订阅（Phase 0）
		
		camera.$cameraCapability
			.receive(on: DispatchQueue.main)
			.sink { [weak self] capability in
				guard let self = self else { return }
				self.cameraCapability = capability
				self.controlEngine.updateCapability(capability)
			}
			.store(in: &cancellables)
		
		camera.$cameraEnvironment
			.receive(on: DispatchQueue.main)
			.sink { [weak self] environment in
				guard let self = self else { return }
				self.cameraEnvironment = environment
				self.controlEngine.updateEnvironment(environment)
			}
			.store(in: &cancellables)
		
		// MARK: - 摄影策略订阅（Phase 1）
		// 策略变化时自动应用到相机
		
		$photographyStrategy
			.dropFirst()  // 跳过初始值
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
			PhotoStorageService.shared.savePhoto(data: data, detectionMethod: self.detectionMode.displayName)
		}
	}
	
	private func handleSampleBuffer(_ sample: CMSampleBuffer) {
		guard let rawPixel = CMSampleBufferGetImageBuffer(sample) else { return }
		let orientation = pixelOrientation(for: rawPixel)

		// AI 摄影构图分析（节流控制，内部 10fps 节流，生成目标构图与策略）
		analyzePhotographyIfNeeded(pixel: rawPixel, orientation: orientation)

		// 实时引导计算需要跟手，但仅在 AI 引导激活时才有意义，
		// 避免空闲状态下每帧向主线程派发
		if guidanceMode == .aiTarget {
			DispatchQueue.main.async {
				self.updateGuidanceResult()
			}
		}

		// 只有在流水线开启时才执行检测流程
		guard isCompositionPipelineEnabled else {
			return
		}

		guard motion.isStable else {
			if !detectionReady {
				DispatchQueue.main.async {
					self.setStage(.waitingForStability, message: "等待设备稳定...")
				}
			}
			return
		}

		// 上次识别失败后的冷却期，避免逐帧重试推理
		if let failure = lastDetectionFailureTime,
		   Date().timeIntervalSince(failure) < 1.5 {
			return
		}

		guard let compositionPixel = makeCompositionPixelBuffer(from: rawPixel, orientation: orientation) else {
			DispatchQueue.main.async {
				self.setStage(.error, message: "无法处理画面")
			}
			return
		}

		if !detectionReady && !detectionInProgress {
			DispatchQueue.main.async {
				self.setStage(.detectingRegion, message: "设备已稳定，开始识别目标区域...")
				self.detectionInProgress = true
			}
			detectCropRegion(using: compositionPixel, orientation: orientation)
		}
	}
	
	// MARK: - AI 摄影分析
	
	/// 节流控制：上次分析时间
	private var lastPhotographyAnalysisTime: Date?
	
	/// AI 分析间隔（秒），避免太频繁
	/// Vision 检测很快，可以高频跑保证引导流畅
	/// AI 网络请求较慢，在 PhotographyAdvisor 内部单独节流
	private let photographyAnalysisInterval: TimeInterval = 0.1  // 10fps，足够流畅
	
	/// 判断是否需要执行摄影分析，并在需要时执行
	private func analyzePhotographyIfNeeded(
		pixel: CVPixelBuffer,
		orientation: CGImagePropertyOrientation
	) {
		guard isPhotographyAdviceEnabled else { return }

		// 节流控制
		let now = Date()
		if let last = lastPhotographyAnalysisTime,
		   now.timeIntervalSince(last) < photographyAnalysisInterval {
			return
		}
		lastPhotographyAnalysisTime = now

		// 防抖：上一帧分析尚未返回时跳过。
		// 注意：这个标志只覆盖单帧分析本身，与 AI 网络请求无关，
		// 否则网络慢时整条构图/引导流水线会跟着冻结
		guard !isFrameAnalysisInFlight else { return }
		isFrameAnalysisInFlight = true

		DispatchQueue.main.async {
			self.isPhotographyAnalyzing = true
		}

		photographyAdvisor.analyzeFrame(
			pixel,
			orientation: orientation,
			zoomFactor: zoomState.currentFactor,
			focalLength: zoomState.focalLength
		) { [weak self] result in
			guard let self = self else { return }
			self.isFrameAnalysisInFlight = false
			DispatchQueue.main.async {
				self.photographyAnalysis = result
				self.isPhotographyAnalyzing = false

				// 更新目标构图
				self.compositionTarget = result.target

				// 更新当前构图状态
				self.currentComposition = self.makeCurrentComposition(from: result.composition)

				// 如果检测到了人，切换到 AI 引导模式，并计算引导结果
				if result.composition.person.detected {
					self.guidanceMode = .aiTarget
					self.updateGuidanceResult()
				} else {
					self.guidanceMode = .none
					self.guidanceResult = nil
				}

				// 自动应用 AI 相机策略建议
				// 只改写处于 .aiAuto 模式的参数（用户锁定/手动的不覆盖）。
				// 不在这里直接调 controlEngine——统一走 $photographyStrategy
				// 的 debounce 订阅，避免同一策略被两条通道重复下发到硬件
				self.applyAICameraStrategy(result.cameraStrategy)
			}
		}
	}

	// MARK: - AI 相机策略自动应用（Phase 4）

	/// 应用 AI 推荐的相机策略偏好
	///
	/// **核心规则**：只有当参数处于 `.aiAuto` 模式时才会应用 AI 建议。
	/// 用户切换到 `.manual` 或 `.locked` 后，AI 不再干预该参数。
	private func applyAICameraStrategy(_ suggestion: CameraStrategySuggestion) {
		let strategy = photographyStrategy

		// 镜头偏好
		if strategy.lensControl == .aiAuto {
			photographyStrategy.lensPreference = suggestion.lensPreference
		}

		// 曝光偏好
		if strategy.exposureControl == .aiAuto {
			photographyStrategy.brightnessPreference = suggestion.brightnessPreference
			photographyStrategy.motionPriority = suggestion.motionPriority
		}

		// 对焦偏好
		if strategy.focusControl == .aiAuto {
			photographyStrategy.focusPreference = suggestion.focusPreference
		}

		// 白平衡偏好
		if strategy.whiteBalanceControl == .aiAuto {
			photographyStrategy.whiteBalancePreference = suggestion.whiteBalancePreference
		}

		// 景深偏好（与镜头联动，仅在镜头处于 AI 自动时跟随）
		if strategy.lensControl == .aiAuto {
			photographyStrategy.depthPreference = suggestion.depthPreference
		}
	}
	
	// MARK: - 构图引导计算
	
	/// 从 CompositionResult 构建 CurrentComposition
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
			minEdgeDistance: 0, // 简化：暂时不计算，后续优化
			isSubjectComplete: person.isFullBody,
			overallScore: result.score,
			subjectPosition: result.subjectPosition
		)
	}
	
	/// 根据当前构图和目标，计算引导结果
	private func updateGuidanceResult() {
		guard let current = currentComposition,
			  let target = compositionTarget,
			  guidanceMode == .aiTarget else {
			return
		}
		
		let viewSize = compositionRectInView.size
		
		// 如果视图大小还没确定，先不用计算
		guard viewSize.width > 0 && viewSize.height > 0 else {
			return
		}
		
		guidanceResult = guidanceEngine.compute(
			current: current,
			target: target,
			viewSize: viewSize
		)
	}
	
	private func detectCropRegion(using pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
		let aspectRatio: CGFloat = compositionRectInView != .zero
			? compositionRectInView.width / compositionRectInView.height
			: 3.0 / 4.0
		
		detector.detectBestCrop(
			in: pixel,
			orientation: orientation,
			targetAspectRatio: aspectRatio
		) { [weak self] crop in
			guard let self, let crop else {
				DispatchQueue.main.async {
					self?.setStage(.waitingForStability, message: "目标识别失败，等待重试...")
					self?.lastDetectionFailureTime = Date()
					self?.resetDetectionState()
				}
				return
			}
			
			DispatchQueue.main.async {
				if let rectInView = self.rectInCompositionSpace(from: crop.rect, orientation: orientation) {
					self.initialCropRectInView = rectInView
					self.cropRectInView = rectInView
					
					let center = CGPoint(x: rectInView.midX, y: rectInView.midY)
					self.boxCenterManager.setBaseCenter(
						center,
						with: self.motion.deviceMotion?.attitude
					)
					self.motion.lockReferenceAttitude()
					
					self.detectionReady = true
					HapticManager.shared.success()
					self.setStage(.templateReady, message: "目标已锁定: \(crop.detectionType)，移动设备对齐中心圆")
					self.isAligned = false
				} else {
					self.initialCropRectInView = nil
					self.cropRectInView = nil
					self.boxCenterManager.reset()
				}
				
				self.detectionInProgress = false
			}
		}
	}
	
	private func scheduleAutoCapture() {
		guard isAutoCaptureEnabled else { return }
		
		autoCaptureWorkItem?.cancel()
		setStage(.readyToCapture, message: "对准成功，准备拍照...")
		
		let work = DispatchWorkItem { [weak self] in
			guard let self, self.isAligned else { return }
			self.setStage(.capturingPhoto, message: "正在拍照")
			
			DispatchQueue.main.async {
				self.onCaptureTriggered?()
			}
			
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
	
	// MARK: - Alignment Detection
	
	private func checkAlignmentByDistance() {
		let alignedNow = boxCenterManager.isAlignedWithCenter(tolerance: alignmentTolerance)
		
		if alignedNow && !isAligned {
			HapticManager.shared.focusLock()
			scheduleAutoCapture()
		} else if !alignedNow && isAligned {
			HapticManager.shared.warning()
			cancelAutoCapture()
			setStage(.templateReady, message: "请重新对准中心点")
		}
		
		isAligned = alignedNow
	}
	
	private func setStage(_ stage: PipelineStage, message: String? = nil) {
		let applyChange = {
			self.pipelineStage = stage
			if let message {
				self.debugMessage = message
			}
			// 🔥 使用统一的刷新机制
			self.refreshUserGuidance()
		}
		if Thread.isMainThread {
			applyChange()
		} else {
			DispatchQueue.main.async(execute: applyChange)
		}
	}
	
	// MARK: - Geometry Helpers
	
	private func makeCompositionPixelBuffer(from pixelBuffer: CVPixelBuffer,
											orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
		let orientedImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
		let extent = orientedImage.extent
		let desiredAspect: CGFloat = 3.0 / 4.0
		var cropRect = extent
		let currentAspect = extent.width / extent.height
		
		if currentAspect > desiredAspect {
			let newWidth = extent.height * desiredAspect
			cropRect.origin.x = extent.midX - newWidth * 0.5
			cropRect.size.width = newWidth
		} else if currentAspect < desiredAspect {
			let newHeight = extent.width / desiredAspect
			cropRect.origin.y = extent.midY - newHeight * 0.5
			cropRect.size.height = newHeight
		}
		
		let croppedImage = orientedImage.cropped(to: cropRect)
		
		var outputBuffer: CVPixelBuffer?
		let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
		let attributes: [String: Any] = [
			kCVPixelBufferCGImageCompatibilityKey as String: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
		]
		
		let status = CVPixelBufferCreate(kCFAllocatorDefault,
										 Int(cropRect.width),
										 Int(cropRect.height),
										 pixelFormat,
										 attributes as CFDictionary,
										 &outputBuffer)
		guard status == kCVReturnSuccess, let buffer = outputBuffer else { return nil }
		
		CaptureViewModel.ciContext.render(croppedImage, to: buffer)
		return buffer
	}
	
	private func pixelOrientation(for pixelBuffer: CVPixelBuffer) -> CGImagePropertyOrientation {
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		return width > height ? .right : .up
	}
	
	private func rotateNormalizedRect(_ rect: CGRect,
									  for orientation: CGImagePropertyOrientation) -> CGRect {
		switch orientation {
		case .up, .upMirrored:
			return rect
		case .right, .rightMirrored:
			return CGRect(x: 1.0 - rect.origin.y - rect.size.height,
						  y: rect.origin.x,
						  width: rect.size.height,
						  height: rect.size.width)
		case .down, .downMirrored:
			return CGRect(x: 1.0 - rect.origin.x - rect.size.width,
						  y: 1.0 - rect.origin.y - rect.size.height,
						  width: rect.size.width,
						  height: rect.size.height)
		case .left, .leftMirrored:
			return CGRect(x: rect.origin.y,
						  y: 1.0 - rect.origin.x - rect.size.width,
						  width: rect.size.height,
						  height: rect.size.width)
		@unknown default:
			return rect
		}
	}
	
	private func rectInCompositionSpace(from rect: CGRect,
										orientation: CGImagePropertyOrientation) -> CGRect? {
		guard compositionRectInView != .zero else { return nil }
		let composition = compositionRectInView
		let rotated = rotateNormalizedRect(rect, for: orientation)
		let x = composition.minX + rotated.origin.x * composition.width
		let y = composition.minY + (1.0 - rotated.origin.y - rotated.size.height) * composition.height
		let width = rotated.size.width * composition.width
		let height = rotated.size.height * composition.height
		let mapped = CGRect(x: x, y: y, width: width, height: height)
		guard mapped.intersects(composition) else { return nil }
		return mapped.intersection(composition)
	}
}

// MARK: - Pipeline Stage

extension CaptureViewModel {
	enum PipelineStage: Equatable {
		case idle
		case startingCamera
		case waitingForStability
		case detectingRegion
		case templateReady
		case readyToCapture
		case capturingPhoto
		case savingPhoto
		case error
		
		var progress: Double {
			switch self {
			case .idle: return 0.05
			case .startingCamera: return 0.15
			case .waitingForStability: return 0.3
			case .detectingRegion: return 0.55
			case .templateReady: return 0.7
			case .readyToCapture: return 0.92
			case .capturingPhoto: return 0.95
			case .savingPhoto: return 1.0
			case .error: return 0.2
			}
		}
		
		var guidanceText: String {
			switch self {
			case .idle:
				return ""
			case .startingCamera:
				return "正在启动相机"
			case .waitingForStability:
				return "请保持稳定"
			case .detectingRegion:
				return "正在识别最佳构图..."
			case .templateReady:
				return "请将圆点移动到画面中心"
			case .readyToCapture:
				return "即将拍照，请保持稳定"
			case .capturingPhoto:
				return "正在拍照..."
			case .savingPhoto:
				return "照片已保存"
			case .error:
				return "发生错误，请重试"
			}
		}
	}
}

#endif
