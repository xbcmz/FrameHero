//
//  CaptureButton.swift
//  FrameHero
//
//  主拍照按钮组件
//
//  ## 文件作用
//  提供拍摄界面的主要拍照按钮
//  模拟相机应用的经典圆形快门按钮设计
//  支持缩放动画效果
//
//  ## 主要组件
//  ### CaptureButton
//  主拍照按钮视图
//
//  ## 输入参数
//  - isScaled: Bool - 是否处于缩放状态
//  - action: () -> Void - 点击回调
//
//  ## UI 设计
//  双圆环设计：
//  - 外层大圆：
//    - 直径 84pt
//    - 白色渐变描边（6pt 宽度）
//    - 顶部到底部渐变透明度
//    - 外发光阴影效果
//  
//  - 内层圆：
//    - 直径 70pt
//    - 放射状渐变填充
//    - 从中心向外透明度递减
//    - 底部投影
//
//  ## 交互效果
//  - 按下时缩放到 0.95
//  - 松开恢复到 1.0
//  - 使用 spring 动画提供弹性感
//  - 响应 isScaled 参数（用于拍照动画）
//
//  ## 视觉特点
//  - 经典快门按钮造型
//  - 渐变和阴影增加立体感
//  - 流畅的交互反馈
//

import SwiftUI

#if os(iOS)

/// 主拍照按钮
struct CaptureButton: View {
	let isScaled: Bool
	/// 自动拍摄倒计时进度（归一化 0...1，1 = 刚开始），nil = 不在倒计时
	var countdownProgress: Double? = nil
	/// 倒计时剩余整秒数（快门内显示数字）
	var countdownSecondsLeft: Int? = nil
	/// AI 构图达标提示（绿色脉冲描边）
	var isAchieved: Bool = false
	/// 长按连拍回调（nil = 不启用连拍）
	var burstAction: (() -> Void)? = nil
	let action: () -> Void

	@State private var achievedPulse = false
	@State private var isBursting = false
	@State private var burstTimer: DispatchSourceTimer?

	var body: some View {
		Button(action: action) {
			ZStack {
				// 达标脉冲外圈（绿色呼吸，钓用户按快门）
				if isAchieved {
					Circle()
						.stroke(Color.green.opacity(achievedPulse ? 0.85 : 0.25), lineWidth: 3)
						.frame(width: 96, height: 96)
						.scaleEffect(achievedPulse ? 1.04 : 0.98)
						.onAppear { achievedPulse = true }
						.animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: achievedPulse)
				}

				// 倒计时进度环（贴外圈，随时间消耗）
				if let progress = countdownProgress {
					Circle()
						.trim(from: 0, to: max(0.001, progress))
						.stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
						.frame(width: 92, height: 92)
						.rotationEffect(.degrees(-90))
						.shadow(color: .green.opacity(0.5), radius: 4)
						.animation(.linear(duration: 0.1), value: progress)
				}

				// 外层大圆
				Circle()
					.strokeBorder(
						LinearGradient(
							colors: [
								Color.white,
								Color.white.opacity(0.8)
							],
							startPoint: .top,
							endPoint: .bottom
						),
						lineWidth: 6
					)
					.frame(width: 84, height: 84)
					.shadow(color: .white.opacity(0.4), radius: 10, y: 0)

				// 内层圆
				Circle()
					.fill(
						RadialGradient(
							colors: [
								Color.white.opacity(0.9),
								Color.white.opacity(0.3)
							],
							center: .center,
							startRadius: 10,
							endRadius: 35
						)
					)
					.frame(width: 70, height: 70)
					.shadow(color: .black.opacity(0.3), radius: 8, y: 4)

				// 倒计时剩余数字
				if let left = countdownSecondsLeft, left > 0 {
					Text("\(left)")
						.font(.system(size: 26, weight: .bold, design: .rounded))
						.foregroundColor(.black.opacity(0.85))
				}
			}
		}
		.scaleEffect(isBursting ? 0.96 : (isScaled ? 0.95 : 1.0))
		.animation(DesignSystem.Animation.quick, value: isScaled)
		.animation(DesignSystem.Animation.quick, value: isBursting)
		// 长按连拍（iOS 相机肌肉记忆）：长按 0.45s 进入连拍，松手结束
		.onLongPressGesture(minimumDuration: 0.45, maximumDistance: 40) {
			// 长按完成
		} onPressingChanged: { pressing in
			handleBurstPressing(pressing)
		}
	}

	private func handleBurstPressing(_ pressing: Bool) {
		guard let burst = burstAction else { return }
		if pressing {
			isBursting = true
			burst()
			HapticManager.shared.light()
			let timer = DispatchSource.makeTimerSource(queue: .main)
			timer.schedule(deadline: .now() + 0.35, repeating: 0.35)
			timer.setEventHandler {
				burst()
				HapticManager.shared.light()
			}
			timer.resume()
			burstTimer = timer
		} else {
			isBursting = false
			burstTimer?.cancel()
			burstTimer = nil
		}
	}

}

#endif
