//
//  CaptureView.swift
//  FrameHero
//
//  主拍摄界面（AI 构图版）
//
//  ## 设计（借鉴 Doka Cam 的极简范式）
//  - 平时是纯净相机：预览 + 变焦盘 + 快门 + 翻转 + 折叠式专业参数
//  - AI 构图 = 一个 sparkle 按钮的一次点按：
//    进入会话后叠加淡三分线 + 场景标签 + 一行建议 chip，达标即提示可拍
//  - 点按对焦/曝光保留（黄框指示器）
//  - 没有魔法棒、没有裁切框/追踪点/中心圆、没有调试面板、没有常驻建议卡片
//

import SwiftUI
import AVFoundation

#if os(iOS)

/// 主拍摄界面
struct CaptureView: View {
	@StateObject private var viewModel: CaptureViewModel

	init(detectionMode: DetectionMode = .fast, isAutoCaptureEnabled: Bool = true, captureDelay: Double = 1.0) {
		let vm = CaptureViewModel(detectionMode: detectionMode)
		vm.isAutoCaptureEnabled = isAutoCaptureEnabled
		vm.captureDelay = captureDelay
		_viewModel = StateObject(wrappedValue: vm)
	}

	@State private var pinchInitialFactor: CGFloat = 1.0
	@State private var pinchActive = false
	@State private var captureAnimationScale: CGFloat = 1.0
	@State private var captureFlashOpacity: Double = 0.0
	// 点按对焦指示器
	@State private var focusIndicatorPoint: CGPoint? = nil
	@State private var focusIndicatorOpacity: Double = 0.0
	@State private var previewHolder = PreviewLayerHolder()
	// 右侧专业控制面板：nil = 收起，一次只展开一个
	@State private var expandedPanel: ProPanel? = nil
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		GeometryReader { geo in
			let safeInsets = geo.safeAreaInsets

			ZStack {
				// 黑色背景
				Color.black
					.ignoresSafeArea()
					.zIndex(0)

				// 相机预览 + AI 构图引导覆盖层
				CameraPreviewSection(
					session: viewModel.session,
					compositionRect: viewModel.compositionRectInView,
					canvasSize: geo.size,
					onCompositionRectUpdate: { rect in
						viewModel.registerCompositionRect(rect)
					},
					previewHolder: previewHolder,
					onTapInPreview: { point in
						handleTapToFocus(at: point)
					},
					coachPhase: viewModel.coachPhase,
					coachSceneLabel: viewModel.coachSceneLabel,
					coachSuggestion: viewModel.coachSuggestion,
					coachGuidance: viewModel.displayGuidance,
					coachMarkerPoint: viewModel.displayTargetMarkerPoint,
					coachAligned: viewModel.coachGuidance?.isAligned ?? false,
					coachPlans: viewModel.compositionPlans,
					coachSelectedPlanIndex: viewModel.selectedPlanIndex,
					onSelectPlan: { index in
						viewModel.selectPlan(at: index)
					},
					onCancelPlans: {
						viewModel.stopAIComposition()
					}
				)
				.frame(width: geo.size.width, height: geo.size.height)
				.scaleEffect(captureAnimationScale)
				.animation(.spring(response: 0.3, dampingFraction: 0.6), value: captureAnimationScale)
				// 切换镜头用轻微"眨眼"过渡
				.opacity(viewModel.isSwitchingCamera ? 0.2 : 1.0)
				.animation(.easeInOut(duration: 0.2), value: viewModel.isSwitchingCamera)
				.ignoresSafeArea()
				.zIndex(0)
				.gesture(pinchZoomGesture)

				// 拍照闪光效果
				if captureFlashOpacity > 0 {
					Color.white
						.opacity(captureFlashOpacity)
						.ignoresSafeArea()
						.zIndex(0.5)
						.allowsHitTesting(false)
				}

				// 点按对焦指示器
				if focusIndicatorOpacity > 0, let focusPoint = focusIndicatorPoint {
					RoundedRectangle(cornerRadius: 4)
						.stroke(Color.yellow, lineWidth: 1.5)
						.frame(width: 64, height: 64)
						.position(focusPoint)
						.opacity(focusIndicatorOpacity)
						.allowsHitTesting(false)
						.zIndex(0.6)
				}

				// UI 层：全宽单列布局，顶栏/底栏贴屏幕左右边缘
				VStack(spacing: 0) {
					topSection

					// 瞬态提示（照片已保存等）
					if !viewModel.userGuidanceText.isEmpty {
						Text(viewModel.userGuidanceText)
							.font(.system(size: 13, weight: .medium))
							.foregroundColor(.white)
							.padding(.horizontal, 12)
							.padding(.vertical, 6)
							.background(Capsule().fill(Color.black.opacity(0.55)))
							.padding(.top, 6)
							.transition(.opacity.combined(with: .move(edge: .top)))
					}

					Spacer()

					bottomSection(bottomInset: max(safeInsets.bottom, 16))
						.padding(.bottom, safeInsets.bottom > 0 ? 0 : 16)
				}
				.zIndex(1)

				// 右侧专业控制列：默认收起为小圆钮，点按展开对应滑杆
				professionalControlColumn
					.zIndex(2)
			}
		}
		.navigationBarBackButtonHidden(true)
		.onAppear {
			viewModel.onAppear()
			viewModel.onCaptureTriggered = {
				triggerCaptureAnimation()
			}
		}
		.onDisappear {
			viewModel.onDisappear()
		}
	}

	// MARK: - UI Sections

	private var topSection: some View {
		TopControlBar(
			userGuidanceText: viewModel.userGuidanceText,
			isAutoCaptureEnabled: viewModel.isAutoCaptureEnabled,
			captureDelay: viewModel.captureDelay,
			onBack: {
				dismiss()
			},
			onToggleCamera: {
				viewModel.toggleCameraPosition()
			},
			onToggleAutoCapture: {
				viewModel.toggleAutoCapture()
			},
			onSetCaptureDelay: { delay in
				viewModel.setCaptureDelay(delay)
			}
		)
		.padding(.horizontal, 20)
	}

	private func bottomSection(bottomInset: CGFloat) -> some View {
		VStack(spacing: 18) {
			// 变焦盘
			zoomDialRow

			// 快门居中，AI 构图（左）与前置翻转（右）对称分布。
			// 两侧用等宽弹性容器，关掉 AI 开关时快门也保持正中
			HStack(alignment: .center) {
				ZStack {
					if viewModel.isAICompositionEnabled {
						aiCompositionButton
					}
				}
				.frame(maxWidth: .infinity)

				CaptureButton(
					isScaled: captureAnimationScale > 1.5,
					countdownProgress: viewModel.autoCaptureCountdown.map {
						$0.total > 0 ? $0.remain / $0.total : 0
					},
					countdownSecondsLeft: viewModel.autoCaptureCountdown.map {
						Int(ceil($0.remain))
					},
					isAchieved: viewModel.coachPhase == .achieved
						&& viewModel.autoCaptureCountdown == nil,
					burstAction: viewModel.isAICompositionEnabled ? { viewModel.capturePhoto() } : nil
				) {
					HapticManager.shared.capture()
					viewModel.capturePhoto()
				}

				ZStack {
					SecondaryCircleButton(systemName: "arrow.triangle.2.circlepath.camera") {
						HapticManager.shared.light()
						viewModel.toggleCameraPosition()
					}
				}
				.frame(maxWidth: .infinity)
			}
		}
		.padding(.horizontal, 24)
	}

	/// AI 构图入口（Doka 式一次触发）
	private var aiCompositionButton: some View {
		Button {
			viewModel.toggleAIComposition()
		} label: {
			ZStack {
				Circle()
					.fill(viewModel.coachPhase == .idle
						  ? Color.white.opacity(0.25)
						  : Color.white.opacity(0.92))
					.frame(width: 56, height: 56)

				Image(systemName: viewModel.coachPhase == .idle ? "sparkles" : "sparkles")
					.font(.system(size: 22, weight: .semibold))
					.foregroundColor(viewModel.coachPhase == .idle ? .white : DesignSystem.Colors.primary)
					.symbolEffect(.pulse, options: .repeating, isActive: viewModel.coachPhase == .analyzing)
			}
			.overlay(
				Circle().stroke(
					viewModel.coachPhase == .achieved ? Color.green : Color.clear,
					lineWidth: 2
				)
			)
		}
		.accessibilityLabel("AI 构图")
	}

	private var zoomDialRow: some View {
		let span = viewModel.zoomRange.upperBound - viewModel.zoomRange.lowerBound
		let showZoomDial = span > CGFloat(0.05) || viewModel.zoomPresets.count > 1

		return Group {
			if showZoomDial {
				// 变焦盘必须用 maxWidth: .infinity 占满可用宽度，
				// 否则 GeometryReader 被压缩，刻度标签会叠在一起
				ZoomDialView(
					presets: viewModel.zoomPresets,
					range: viewModel.zoomRange,
					currentFactor: viewModel.zoomState.currentFactor,
					recommendedFactor: viewModel.sceneRecommendedFactor,
					onPresetTap: { preset in
						viewModel.selectZoomPreset(preset)
					},
					onLiveZoom: { factor in
						viewModel.updateZoomInteractively(to: factor)
					},
					onCommitZoom: { factor in
						viewModel.finalizeZoomInteractively(at: factor, smooth: true)
					}
				)
				.frame(maxWidth: .infinity)
				.padding(.horizontal, 8)
				.frame(height: 96)
			}
		}
	}

	// MARK: - 右侧专业控制列（收起为圆钮，点按展开，一次只开一个）

	private enum ProPanel: Equatable {
		case exposure, focus, whiteBalance
	}

	@ViewBuilder
	private var professionalControlColumn: some View {
		VStack(spacing: 12) {
			// 展开的滑杆面板（在入口按钮上方弹出）
			if let expanded = expandedPanel {
				expandedPanelView(for: expanded)
					.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
			}

			// 入口按钮（仅显示设备支持的参数）
			if expandedPanel == nil {
				if viewModel.cameraCapability.isoRange.upperBound > 0 {
					proEntryButton(panel: .exposure)
				}
				if viewModel.cameraCapability.supportsManualFocus {
					proEntryButton(panel: .focus)
				}
				if viewModel.cameraCapability.supportsManualWhiteBalance {
					proEntryButton(panel: .whiteBalance)
				}
			} else if let active = expandedPanel {
				proEntryButton(panel: active)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.padding(.trailing, 10)
		.padding(.bottom, proColumnBottomPadding)
	}

	/// 参数列底部避让高度 = 变焦盘(96) + 间距(18) + 快门行(84) + 呼吸空间；
	/// 前置等无变焦盘场景相应减小（旧值 300 是三行布局的遗物，会压到 AI/翻转键）
	private var proColumnBottomPadding: CGFloat {
		let span = viewModel.zoomRange.upperBound - viewModel.zoomRange.lowerBound
		let hasZoomDial = span > CGFloat(0.05) || viewModel.zoomPresets.count > 1
		return hasZoomDial ? 248 : 148
	}

	/// 参数对应的入口按钮样式
	private func proPanelStyle(_ panel: ProPanel) -> (icon: String, accent: Color) {
		switch panel {
		case .exposure:
			return ("plusminus.circle.fill", .yellow)
		case .focus:
			return ("camera.viewfinder", Color(red: 0.35, green: 0.70, blue: 1.0))
		case .whiteBalance:
			return ("circle.lefthalf.filled", .orange)
		}
	}

	/// 专业参数入口按钮
	private func proEntryButton(panel: ProPanel) -> some View {
		let style = proPanelStyle(panel)
		let isActive = expandedPanel == panel
		return Button {
			HapticManager.shared.light()
			withAnimation(DesignSystem.Animation.smooth) {
				expandedPanel = (expandedPanel == panel) ? nil : panel
			}
		} label: {
			ZStack {
				Circle()
					.fill(isActive ? style.accent : Color.black.opacity(0.45))
					.frame(width: 40, height: 40)
					.overlay(
						Circle().stroke(Color.white.opacity(isActive ? 0.9 : 0.15), lineWidth: 1)
					)
				Image(systemName: style.icon)
					.font(.system(size: 16, weight: .medium))
					.foregroundColor(isActive ? Color.black.opacity(0.85) : .white)
			}
			.contentShape(Circle())
		}
		.accessibilityLabel(proPanelName(panel))
	}

	private func proPanelName(_ panel: ProPanel) -> String {
		switch panel {
		case .exposure: return "曝光"
		case .focus: return "对焦"
		case .whiteBalance: return "白平衡"
		}
	}

	/// 滑杆面板取值规则：manual/locked 显示策略值，aiAuto 显示硬件回读值
	@ViewBuilder
	private func expandedPanelView(for panel: ProPanel) -> some View {
		switch panel {
		case .exposure:
			ExposureControlView(
				exposureBias: Binding(
					get: {
						if viewModel.photographyStrategy.exposureControl == .aiAuto {
							return viewModel.cameraEnvironment.currentExposureBias
						}
						return viewModel.photographyStrategy.manualExposureBias
					},
					set: { viewModel.setExposureBias($0) }
				),
				controlMode: Binding(
					get: { viewModel.photographyStrategy.exposureControl },
					set: { viewModel.setExposureControlMode($0) }
				),
				evRange: viewModel.cameraCapability.exposureBiasRange,
				onModeChange: { mode in
					viewModel.setExposureControlMode(mode)
				},
				onBiasChange: { bias in
					viewModel.setExposureBias(bias)
				}
			)

		case .focus:
			FocusControlView(
				focusPosition: Binding(
					get: {
						viewModel.photographyStrategy.manualFocusPosition
							?? viewModel.cameraEnvironment.focusLensPosition
					},
					set: { viewModel.setManualFocusPosition($0) }
				),
				controlMode: Binding(
					get: { viewModel.photographyStrategy.focusControl },
					set: { viewModel.setFocusControlMode($0) }
				),
				supportsManualFocus: viewModel.cameraCapability.supportsManualFocus,
				onModeChange: { mode in
					viewModel.setFocusControlMode(mode)
				},
				onPositionChange: { position in
					viewModel.setManualFocusPosition(position)
				}
			)

		case .whiteBalance:
			WhiteBalanceControlView(
				temperature: Binding(
					get: {
						viewModel.photographyStrategy.manualWhiteBalanceTemp
							?? viewModel.cameraEnvironment.estimatedColorTemperature
					},
					set: { viewModel.setWhiteBalanceTemperature($0) }
				),
				controlMode: Binding(
					get: { viewModel.photographyStrategy.whiteBalanceControl },
					set: { viewModel.setWhiteBalanceControlMode($0) }
				),
				supportsManualWB: viewModel.cameraCapability.supportsManualWhiteBalance,
				temperatureRange: 2000...10000,
				onModeChange: { mode in
					viewModel.setWhiteBalanceControlMode(mode)
				},
				onTemperatureChange: { temp in
					viewModel.setWhiteBalanceTemperature(temp)
				}
			)
		}
	}

	// MARK: - Gestures

	/// 点按预览：AI 会话中 = 退出会话（单手也能结束引导，不必去够 sparkle 键）；
	/// 空闲时 = 点按对焦/曝光
	private func handleTapToFocus(at point: CGPoint) {
		if viewModel.coachPhase != .idle {
			viewModel.stopAIComposition()
			return
		}
		guard let layer = previewHolder.layer else { return }
		let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
		viewModel.focusAtDevicePoint(devicePoint)
		HapticManager.shared.light()

		let rect = viewModel.compositionRectInView
		focusIndicatorPoint = CGPoint(x: point.x + rect.minX, y: point.y + rect.minY)
		withAnimation(.easeOut(duration: 0.15)) {
			focusIndicatorOpacity = 1.0
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
			withAnimation(.easeIn(duration: 0.25)) {
				focusIndicatorOpacity = 0.0
			}
		}
	}

	private var pinchZoomGesture: some Gesture {
		MagnificationGesture()
			.onChanged { scale in
				if !pinchActive {
					pinchInitialFactor = viewModel.zoomState.currentFactor
					pinchActive = true
				}
				let target = clampedZoomFactor(for: pinchInitialFactor * scale)
				viewModel.updateZoomInteractively(to: target)
			}
			.onEnded { scale in
				let target = clampedZoomFactor(for: pinchInitialFactor * scale)
				viewModel.finalizeZoomInteractively(at: target, smooth: true)
				pinchActive = false
			}
	}

	private func clampedZoomFactor(for factor: CGFloat) -> CGFloat {
		min(max(factor, viewModel.zoomRange.lowerBound), viewModel.zoomRange.upperBound)
	}

	// MARK: - Animations

	private func triggerCaptureAnimation() {
		// 闪光效果
		withAnimation(.easeOut(duration: 0.1)) {
			captureFlashOpacity = 0.8
		}
		withAnimation(.easeIn(duration: 0.2).delay(0.1)) {
			captureFlashOpacity = 0.0
		}

		// 缩放效果
		withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
			captureAnimationScale = 2.0
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
				captureAnimationScale = 1.0
			}
		}
	}
}

#endif
