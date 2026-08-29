//
//  CameraPreviewSection.swift
//  FrameHero
//
//  相机预览区域组件（AI 构图版）
//
//  ## 文件作用
//  组合相机预览视图与 AI 构图引导覆盖层，
//  负责计算和管理 3:4 构图区域、处理视图尺寸变化。
//
//  ## 覆盖层
//  - CompositionCoachOverlayView：AI 构图会话激活时绘制
//    （淡三分线 + 场景标签 + 一行建议 chip），平时完全透明
//

import SwiftUI
import AVFoundation

#if os(iOS)

/// 相机预览区域
struct CameraPreviewSection: View {
	let session: AVCaptureSession
	let compositionRect: CGRect
	let canvasSize: CGSize

	/// 构图区域尺寸变化回调（引导计算需要视图尺寸）
	let onCompositionRectUpdate: (CGRect) -> Void

	// MARK: - 点按对焦
	/// 预览层持有者（用于坐标转换）
	var previewHolder: PreviewLayerHolder? = nil
	/// 点按预览回调（参数为预览视图内的局部坐标）
	var onTapInPreview: ((CGPoint) -> Void)? = nil

	// MARK: - AI 构图会话
	let coachPhase: CaptureViewModel.CoachPhase
	let coachSceneLabel: String?
	let coachSuggestion: String
	let coachGuidance: GuidanceResult?
	let coachMarkerPoint: CGPoint?
	let coachAligned: Bool

	var body: some View {
		GeometryReader { previewGeo in
			let composition = Self.compositionRect(in: previewGeo.size)

			ZStack {
				CameraPreviewView(session: session, holder: previewHolder)
					.frame(width: composition.width, height: composition.height)
					.clipped()
					.contentShape(Rectangle())
					// 手势必须挂在 .position() 之前，
					// 这样回调坐标才是与预览层 bounds 一致的本地坐标
					.gesture(
						SpatialTapGesture()
							.onEnded { value in
								onTapInPreview?(value.location)
							}
					)
					.position(x: composition.midX, y: composition.midY)

				CompositionCoachOverlayView(
					phase: coachPhase,
					sceneLabel: coachSceneLabel,
					suggestion: coachSuggestion,
					guidance: coachGuidance,
					markerPoint: coachMarkerPoint,
					isAligned: coachAligned,
					compositionRect: composition
				)
				.frame(width: composition.width, height: composition.height)
				.position(x: composition.midX, y: composition.midY)
				// 会话进入/退出过渡：浮现与收缩（Doka 式"魔法感"）
				.opacity(coachPhase == .idle ? 0 : 1)
				.scaleEffect(coachPhase == .idle ? 0.94 : 1.0, anchor: .top)
				.animation(.spring(response: 0.35, dampingFraction: 0.8), value: coachPhase)
			}
			.onAppear {
				onCompositionRectUpdate(composition)
			}
			.onChange(of: previewGeo.size) { _, newSize in
				onCompositionRectUpdate(Self.compositionRect(in: newSize))
			}
		}
	}

	/// 根据容器尺寸计算 3:4 构图区域
	private static func compositionRect(in size: CGSize) -> CGRect {
		let width = size.width
		let targetHeight = width * 4.0 / 3.0
		let height = min(size.height, targetHeight)
		let originY = (size.height - height) * 0.5
		return CGRect(x: 0, y: originY, width: width, height: height)
	}
}

#endif
