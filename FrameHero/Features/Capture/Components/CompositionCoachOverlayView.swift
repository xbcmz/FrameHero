//
//  CompositionCoachOverlayView.swift
//  FrameHero
//
//  AI 构图引导覆盖层（借鉴 Doka Cam 的极简范式）
//
//  ## 设计原则
//  - 平时不出现任何东西；AI 构图会话激活后才绘制
//  - 极简元素：淡三分线（参照系）+ 一条建议 chip（一行动作指令）+ 小状态图标
//  - 达标即退场：构图完成时三分线淡出，只留绿色确认态
//  - 无分数、无满屏箭头、无常驻卡片
//

import SwiftUI

#if os(iOS)

/// AI 构图引导覆盖层
struct CompositionCoachOverlayView: View {

    /// 会话阶段（定义在 CaptureViewModel，idle = 会话未激活不渲染）
    let phase: CaptureViewModel.CoachPhase
    /// 场景标签（如"美食场景"，nil 不显示）
    let sceneLabel: String?
    /// 一行建议指令
    let suggestion: String
    /// 实时引导结果（驱动状态图标，已做前置镜像校正）
    let guidance: GuidanceResult?
    /// 目标标记点（构图区域视图坐标，前置已镜像校正）；nil = 不显示
    let markerPoint: CGPoint?
    /// 主体是否已对准目标（标记圈变绿）
    let isAligned: Bool
    /// 3:4 构图区域（线与 chip 都画在这个区域内）
    let compositionRect: CGRect

    // MARK: - 构图方案（.plans 阶段）
    let plans: [CompositionPlan]
    let selectedPlanIndex: Int?
    let onSelectPlan: (Int) -> Void
    let onCancelPlans: () -> Void

    @State private var pulse = false
    @State private var scanProgress: CGFloat = 0

    var body: some View {
        ZStack {
            if phase == .idle { Color.clear }

            // 方案选择：AI 摄影师给出最多 3 种拍法
            if phase == .plans {
                plansPanel
            }

            if phase == .guiding || phase == .achieved {
                thirdsGrid
                    .opacity(phase == .achieved ? 0.35 : 1.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: phase)
            }

            // 目标标记圈：AI 选定的构图位置，把主体放进去即变绿（最终指示）
            if phase == .guiding || phase == .achieved, let markerPoint {
                targetMarker
                    .position(markerPoint)
            }

            // 顶部集群：状态图标 + 建议 chip。
            // 放在预览区顶部（而非底部）——底部是变焦盘/快门区，
            // 全屏出血的预览区底边会与它们重叠。
            // 没有可显示内容时整体零占位（不渲染空框）
            VStack(spacing: 8) {
                if hasVisibleContent {
                    statusIcon
                        .frame(height: 44)
                        .padding(.top, 10)

                    if phase == .guiding || phase == .achieved, hasChipContent {
                        suggestionChip
                    }
                }

                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .animation(.easeInOut(duration: 0.25), value: suggestion)
        .allowsHitTesting(phase == .plans)
    }

    /// 是否有可见内容（都没有时整体不渲染，避免空框/占位）
    private var hasVisibleContent: Bool {
        switch phase {
        case .idle: return false
        case .analyzing, .plans, .achieved: return true
        case .guiding: return guidance != nil || hasChipContent || markerPoint != nil
        }
    }

    /// chip 是否有内容（空文案 + 无场景标签时不渲染，避免空心胶囊）
    private var hasChipContent: Bool {
        !suggestion.isEmpty || (sceneLabel != nil && !sceneLabel!.isEmpty)
    }

    // MARK: - 三分构图线

    private var thirdsGrid: some View {
        Canvas { context, size in
            let alpha: Double = phase == .achieved ? 0.10 : 0.28
            var path = Path()
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 方案面板（.plans 阶段）

    private var plansPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.yellow)
                Text("AI 摄影师 · 发现 \(plans.count) 种拍法")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    HapticManager.shared.light()
                    onCancelPlans()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 4)

            ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                Button {
                    HapticManager.shared.selection()
                    onSelectPlan(index)
                } label: {
                    PlanCard(plan: plan, recommended: index == 0)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// 方案卡片：标题 + 风格词 + 一句说明
    private struct PlanCard: View {
        let plan: CompositionPlan
        let recommended: Bool

        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(plan.styleWord)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.16)))
                        if recommended {
                            Text("推荐")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    Text(plan.detail)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(recommended ? Color.green.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - 目标标记圈

    private var targetMarker: some View {
        let reached = isAligned || phase == .achieved
        let color = reached ? Color.green : Color.white
        let size: CGFloat = reached ? 76 : 88

        return ZStack {
            Circle()
                .stroke(
                    color.opacity(reached ? 0.95 : 0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .frame(width: size, height: size)
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: reached)
    }

    // MARK: - 状态图标

    @ViewBuilder
    private var statusIcon: some View {
        switch phase {
        case .analyzing:
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .opacity(pulse ? 1.0 : 0.45)
                Text("正在分析场景")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .onAppear { pulse = true }
        case .guiding:
            if let guidance {
                let name = iconName(for: guidance)
                let color = tintColor(for: guidance)
                Image(systemName: name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(color)
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                    .opacity(pulse ? 1.0 : 0.7)
            }
        case .achieved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.green)
                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
        case .plans:
            EmptyView()
        case .idle:
            EmptyView()
        }
    }

    // MARK: - 建议 chip

    private var suggestionChip: some View {
        HStack(spacing: 8) {
            if let sceneLabel, !sceneLabel.isEmpty {
                Text(sceneLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(chipAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(chipAccent.opacity(0.18)))
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }

            Text(suggestion)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.black.opacity(0.55))
        )
        .overlay(
            Capsule().stroke(chipAccent.opacity(phase == .achieved ? 0.9 : 0.35), lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: sceneLabel)
    }

    private var chipAccent: Color {
        switch phase {
        case .analyzing, .idle, .plans: return .white
        case .achieved: return .green
        case .guiding:
            if let guidance {
                return tintColor(for: guidance)
            }
            return .yellow
        }
    }

    // MARK: - Helpers

    private func iconName(for guidance: GuidanceResult) -> String {
        // 图标只表达"状态"，具体方向由 chip 文字承载（方向常是复合的，
        // 单箭头表达不了"向左+靠近"这类组合指令）
        switch guidance.state {
        case .adjusting: return "camera.viewfinder"
        case .nearlyOptimal: return "sparkles"
        case .optimal: return "checkmark.circle.fill"
        }
    }

    private func tintColor(for guidance: GuidanceResult) -> Color {
        switch guidance.state {
        case .adjusting: return .white
        case .nearlyOptimal: return .yellow
        case .optimal: return .green
        }
    }
}
#endif
