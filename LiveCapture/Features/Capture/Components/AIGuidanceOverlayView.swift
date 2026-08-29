//
//  AIGuidanceOverlayView.swift
//  LiveCapture
//
//  AI 构图引导覆盖层（极简版）
//
//  ## 设计理念
//  用户只需要知道"下一步怎么做"，不需要知道坐标。
//  一个大箭头 + 一句话建议 + 进度条 + 状态提示。
//
//  ## 三态设计
//  adjusting（调整中）：大箭头 + 方向建议 + 进度条黄色
//  nearlyOptimal（接近最佳）：✨ 闪烁 + "接近最佳" + 黄绿渐变
//  optimal（达到最佳）：✓ + "这个角度可以拍" + 全绿色
//

import SwiftUI
import CoreGraphics

#if os(iOS)

/// AI 构图引导覆盖层（极简风格）
struct AIGuidanceOverlayView: View {
	/// 引导结果（已考虑前置摄像头镜像，直接显示即可）
	let guidanceResult: GuidanceResult?
	
	/// 是否处于激活状态
	let isActive: Bool
	
	/// AI 建议标题（来自 DeepSeek / Mock）
	let adviceTitle: String?
	
	/// 构图区域
	let compositionRect: CGRect
	
	@State private var pulseAnimation = false
	
	var body: some View {
		ZStack {
			if isActive, let guidance = guidanceResult {
				// 主引导区域（垂直居中偏上）
				VStack(spacing: 20) {
					Spacer()
					
					// 方向箭头 / 状态图标
					ZStack {
						switch guidance.state {
						case .adjusting:
							// 大方向箭头
							Image(systemName: directionArrowName(for: guidance))
								.font(.system(size: 56, weight: .medium))
								.foregroundColor(.white)
								.shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
							
						case .nearlyOptimal:
							Image(systemName: "sparkles")
								.font(.system(size: 52, weight: .medium))
								.foregroundColor(.yellow)
								.shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
								.opacity(pulseAnimation ? 1.0 : 0.6)
								.scaleEffect(pulseAnimation ? 1.1 : 0.9)
							
						case .optimal:
							Image(systemName: "checkmark.circle.fill")
								.font(.system(size: 56, weight: .medium))
								.foregroundColor(.green)
								.shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
								.scaleEffect(pulseAnimation ? 1.1 : 1.0)
						}
					}
					.frame(height: 80)
					.animation(.easeInOut(duration: 0.3), value: guidance.state)
					
					// 建议文字
					Text(adviceText(for: guidance))
						.font(.system(size: 18, weight: .medium))
						.foregroundColor(.white)
						.multilineTextAlignment(.center)
						.shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
					
					// 进度条 + 分数
					VStack(spacing: 10) {
						// 分数
						HStack(spacing: 6) {
							Text("\(guidance.currentScore)")
								.font(.system(size: 32, weight: .bold))
								.foregroundColor(scoreColor(for: guidance))
							
							Text("/ \(guidance.targetScore)")
								.font(.system(size: 16, weight: .medium))
								.foregroundColor(.white.opacity(0.7))
						}
						
						// 进度条
						GeometryReader { geo in
							ZStack(alignment: .leading) {
								Capsule()
									.fill(Color.white.opacity(0.2))
									.frame(height: 8)
								
								Capsule()
									.fill(progressGradient(for: guidance))
									.frame(width: max(0, geo.size.width * guidance.progress), height: 8)
							}
						}
						.frame(width: 200, height: 8)
						
						// 状态文字
						Label(guidance.state.displayText, systemImage: guidance.state.iconName)
							.font(.system(size: 14, weight: .medium))
							.foregroundColor(stateTextColor(for: guidance))
					}
					.padding(.horizontal, 24)
					.padding(.vertical, 16)
					.background(
						RoundedRectangle(cornerRadius: 16)
							.fill(Color.black.opacity(0.55))
					)
					
					Spacer()
					Spacer()
				}
			}
		}
		.onAppear {
			startPulseAnimation()
		}
		.animation(.easeInOut(duration: 0.3), value: isActive)
	}
	
	// MARK: - 辅助方法
	
	/// 根据引导状态获取方向箭头名称
	private func directionArrowName(for guidance: GuidanceResult) -> String {
		let h = guidance.horizontalDirection
		let v = guidance.verticalDirection
		let d = guidance.distanceDirection
		
		// 组合方向
		switch (h, v) {
		case (.moveLeft, .moveUp): return "arrow.up.left"
		case (.moveLeft, .moveDown): return "arrow.down.left"
		case (.moveRight, .moveUp): return "arrow.up.right"
		case (.moveRight, .moveDown): return "arrow.down.right"
		case (.moveLeft, _): return "arrow.left"
		case (.moveRight, _): return "arrow.right"
		case (_, .moveUp): return "arrow.up"
		case (_, .moveDown): return "arrow.down"
		default:
			// 水平垂直都不动，看距离
			if d == .moveCloser { return "plus.magnifyingglass" }
			if d == .moveFarther { return "minus.magnifyingglass" }
			return "checkmark"
		}
	}
	
	/// 生成建议文字
	private func adviceText(for guidance: GuidanceResult) -> String {
		if guidance.state == .optimal {
			return "这个角度可以拍了"
		}
		
		var parts: [String] = []
		
		switch guidance.horizontalDirection {
		case .moveLeft: parts.append("往左一点")
		case .moveRight: parts.append("往右一点")
		default: break
		}
		
		switch guidance.verticalDirection {
		case .moveUp: parts.append("举高一点")
		case .moveDown: parts.append("放低一点")
		default: break
		}
		
		switch guidance.distanceDirection {
		case .moveCloser: parts.append("靠近一点")
		case .moveFarther: parts.append("退后一点")
		default: break
		}
		
		if parts.isEmpty {
			return "构图很不错"
		}
		
		return parts.joined(separator: " · ")
	}
	
	/// 分数颜色
	private func scoreColor(for guidance: GuidanceResult) -> Color {
		switch guidance.state {
		case .adjusting: return .white
		case .nearlyOptimal: return .yellow
		case .optimal: return .green
		}
	}
	
	/// 状态文字颜色
	private func stateTextColor(for guidance: GuidanceResult) -> Color {
		switch guidance.state {
		case .adjusting: return .white.opacity(0.8)
		case .nearlyOptimal: return .yellow
		case .optimal: return .green
		}
	}
	
	/// 进度条渐变色
	private func progressGradient(for guidance: GuidanceResult) -> LinearGradient {
		switch guidance.state {
		case .adjusting:
			return LinearGradient(
				colors: [.orange, .yellow],
				startPoint: .leading,
				endPoint: .trailing
			)
		case .nearlyOptimal:
			return LinearGradient(
				colors: [.yellow, .green],
				startPoint: .leading,
				endPoint: .trailing
			)
		case .optimal:
			return LinearGradient(
				colors: [.green, .mint],
				startPoint: .leading,
				endPoint: .trailing
			)
		}
	}
	
	/// 启动脉冲动画
	private func startPulseAnimation() {
		withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
			pulseAnimation.toggle()
		}
	}
}

#endif
