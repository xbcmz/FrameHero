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
//  ## UI 设计（2026-08 重设计）
//  细白外环 + 品牌渐变内圆：
//  - 外环：直径 84pt，白色细描边（3pt），与内圆留呼吸缝隙
//  - 内圆：直径 68pt，纯白填充（iOS 相机经典样式）
//  - 倒计时：最外圈绿色进度环 + 白色剩余秒数
//  - 达标：绿色呼吸脉冲外圈
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
	/// 连拍结束（松手）回调，供上层统一评分优选连拍组照片
	var onBurstEnded: (() -> Void)? = nil
	let action: () -> Void

	@State private var achievedPulse = false
	@State private var isBursting = false
	@State private var burstTimer: DispatchSourceTimer?
	/// 连拍会话结束时刻（长按松手后 0.3s 内忽略快门动作，防收尾多拍一张）
	@State private var burstEndedAt: Date?

	var body: some View {
		Button(action: performAction) {
			ZStack {
				// 达标脉冲外圈（绿色呼吸，钓用户按快门）
				if isAchieved {
					Circle()
						.stroke(Color.green.opacity(achievedPulse ? 0.85 : 0.25), lineWidth: 3)
						.frame(width: 98, height: 98)
						.scaleEffect(achievedPulse ? 1.05 : 0.97)
						.onAppear { achievedPulse = true }
						.animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: achievedPulse)
				}

				// 倒计时进度环（最外圈，随时间消耗）
				if let progress = countdownProgress {
					Circle()
						.trim(from: 0, to: max(0.001, progress))
						.stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
						.frame(width: 94, height: 94)
						.rotationEffect(.degrees(-90))
						.shadow(color: .green.opacity(0.55), radius: 4)
						.animation(.linear(duration: 0.1), value: progress)
				}

				// 外圈细环（留出与内圆的呼吸缝隙，经典相机造型）
				Circle()
					.stroke(Color.white, lineWidth: 3)
					.frame(width: 84, height: 84)
					.shadow(color: .black.opacity(0.35), radius: 6, y: 2)

				// 内圆：纯白（iOS 相机经典样式）
				Circle()
					.fill(Color.white)
					.frame(width: 68, height: 68)
					.shadow(color: .black.opacity(0.3), radius: 6, y: 2)

				// 倒计时剩余数字（深字压白底）
				if let left = countdownSecondsLeft, left > 0 {
					Text("\(left)")
						.font(.system(size: 30, weight: .bold, design: .rounded))
						.foregroundColor(.black.opacity(0.82))
				}
			}
		}
		.scaleEffect(isBursting ? 0.96 : (isScaled ? 0.95 : 1.0))
		.animation(DesignSystem.Animation.quick, value: isScaled)
		.animation(DesignSystem.Animation.quick, value: isBursting)
		// 长按连拍（iOS 相机肌肉记忆）：按住 0.45s 才进入连拍。
		// 注意：连拍必须在长按成功后才开火——若在按下瞬间（onPressingChanged）
		// 就拍第一张，快速点按会变成"按下 1 张 + 松开快门动作 1 张"的双拍
		.onLongPressGesture(minimumDuration: 0.45, maximumDistance: 40) {
			startBurst()
		} onPressingChanged: { pressing in
			if !pressing { stopBurst() }
		}
	}

	/// 快门动作（带连拍收尾保护）
	private func performAction() {
		if let ended = burstEndedAt, Date().timeIntervalSince(ended) < 0.3 {
			burstEndedAt = nil
			return
		}
		action()
	}

	private func startBurst() {
		guard let burst = burstAction else { return }
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
	}

	private func stopBurst() {
		let wasBursting = burstTimer != nil
		if wasBursting { burstEndedAt = Date() }
		isBursting = false
		burstTimer?.cancel()
		burstTimer = nil
		if wasBursting { onBurstEnded?() }
	}

}

#endif
