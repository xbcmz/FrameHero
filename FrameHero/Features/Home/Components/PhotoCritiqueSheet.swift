//
//  PhotoCritiqueSheet.swift
//  FrameHero
//
//  拍后 AI 点评面板（图库照片浏览器入口）
//
//  ## 流程：本地优先 + 云端增强
//  1. 有缓存（record.critique）→ 直接展示，不重新分析
//  2. 没缓存 → 先跑本地 Vision 引擎（LocalPhotoCritiqueEngine，零网络、
//     近乎瞬时），立刻展示结果并写入缓存
//  3. 若云端已配置，后台并行请求 DeepSeek Vision；请求会附带本地引擎预先提取的
//     “构图原语”（对称/平衡/引导线方向/前景），让云端不必单凭像素猜测；
//     到达后无感升级为更懂语义的点评并覆盖缓存；失败则静默保留本地结果，不打扰用户
//  4. 顶部「重新分析」可强制重跑（本地 + 云端都会再来一轮）
//

import SwiftUI
import UIKit

#if os(iOS)

struct PhotoCritiqueSheet: View {
    @Environment(\.dismiss) private var dismiss

    let record: PhotoRecord
    let photoProvider: (UUID) -> UIImage?

    private enum Phase { case loadingImage, analyzing, success, failed }
    @State private var phase: Phase = .loadingImage
    @State private var thumbnail: UIImage?
    @State private var critique: PhotoCritique?
    @State private var errorMessage: String?
    /// 云端点评仍在后台跑（本地结果已展示，云端到达后无感升级）
    @State private var isUpgrading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewArea

                    statusArea
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("AI 点评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if phase == .success || phase == .failed {
                        Button {
                            HapticManager.shared.light()
                            run(forceRefresh: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear { run(forceRefresh: false) }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var previewArea: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                ProgressView()
            }
            .frame(height: 200)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch phase {
        case .loadingImage:
            Label("正在载入照片…", systemImage: "photo")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity)
        case .analyzing:
            VStack(spacing: 6) {
                Label("AI 摄影师正在点评…", systemImage: "sparkles")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text("从构图、光线、主体表达三个角度分析")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        case .success:
            if let critique {
                critiqueContent(critique)
            }
        case .failed:
            VStack(spacing: 4) {
                Label("点评失败", systemImage: "xmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.error)
                Text(errorMessage ?? "未知错误")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func critiqueContent(_ critique: PhotoCritique) -> some View {
        VStack(spacing: 12) {
            scoreCard(critique)

            if let tags = critique.tags, !tags.isEmpty {
                tagRow(tags)
            }

            subDimensionCard(critique)

            if let strengths = critique.strengths, !strengths.isEmpty {
                critiqueList(title: "亮点", icon: "plus.circle.fill",
                             color: DesignSystem.Colors.success, items: strengths)
            }

            if let improvements = critique.improvements, !improvements.isEmpty {
                critiqueList(title: "下次可以这样拍", icon: "arrow.up.circle.fill",
                             color: DesignSystem.Colors.warning, items: improvements)
            }

            if isUpgrading {
                upgradingRow
            }
        }
    }

    /// 综合得分：圆环 + 一句话总评 + 引擎来源标签
    private func scoreCard(_ critique: PhotoCritique) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(DesignSystem.Colors.backgroundTertiary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(critique.score ?? 0) / 100)
                    .stroke(scoreColor(critique.score), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(critique.score.map { "\($0)" } ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(critique.score))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AI 综合评分")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    engineBadge(critique.source)
                }
                if let summary = critique.summary {
                    Text(summary)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(card)
    }

    private func engineBadge(_ source: PhotoCritique.Source?) -> some View {
        let label = source == .cloud ? "云端" : "本地"
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(DesignSystem.Colors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(DesignSystem.Colors.backgroundTertiary))
    }

    private func tagRow(_ tags: [String]) -> some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(DesignSystem.Colors.primary.opacity(0.12)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 构图 / 光线 / 主体 三个维度的分数条
    private func subDimensionCard(_ critique: PhotoCritique) -> some View {
        VStack(spacing: 10) {
            dimensionBar(title: "构图", score: critique.compositionScore)
            dimensionBar(title: "光线", score: critique.lightScore)
            dimensionBar(title: "主体表达", score: critique.subjectScore)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(card)
    }

    private func dimensionBar(title: String, score: Int?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(width: 56, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignSystem.Colors.backgroundTertiary)
                    Capsule()
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(score ?? 0) / 100)
                }
            }
            .frame(height: 6)

            Text(score.map { "\($0)" } ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var upgradingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("云端深度点评生成中，完成后会自动更新…")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func critiqueList(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(color.opacity(0.7)).frame(width: 5, height: 5).padding(.top, 6)
                    Text(item)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineSpacing(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
            .fill(DesignSystem.Colors.backgroundSecondary)
    }

    private func scoreColor(_ score: Int?) -> Color {
        guard let score else { return DesignSystem.Colors.textPrimary }
        if score >= 80 { return DesignSystem.Colors.success }
        if score >= 60 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.error
    }

    // MARK: - 逻辑

    private func run(forceRefresh: Bool) {
        // 有缓存且不是强制刷新 → 直接展示，不重新分析；
        // 若上次缓存是本地结果且现在已配置云端，静静试一次云端升级
        if !forceRefresh, let cached = record.critique {
            critique = cached
            phase = .success
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = photoProvider(record.id) else { return }
                DispatchQueue.main.async {
                    if thumbnail == nil { thumbnail = image }
                    if cached.source != .cloud {
                        requestCloudUpgrade(image: image)
                    }
                }
            }
            return
        }

        critique = nil
        errorMessage = nil
        isUpgrading = false
        phase = .loadingImage

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = photoProvider(record.id) else {
                DispatchQueue.main.async {
                    phase = .failed
                    errorMessage = "照片文件缺失"
                }
                return
            }
            DispatchQueue.main.async {
                thumbnail = image
                phase = .analyzing
            }

            // 本地优先：Vision 引擎离线分析，近乎瞬时
            guard let localCritique = LocalPhotoCritiqueEngine.analyze(image) else {
                DispatchQueue.main.async {
                    phase = .failed
                    errorMessage = "本地分析失败，请重试"
                }
                return
            }
            DispatchQueue.main.async {
                critique = localCritique
                phase = .success
                HapticManager.shared.soft()
                PhotoStorageService.shared.updateCritique(localCritique, for: record.id)
                // 云端增强：配置了 Key 才发起，成功后无感覆盖；
                // 在主线程调用才能安全读 AIConfigurationStore 的 @Published 配置
                requestCloudUpgrade(image: image)
            }
        }
    }

    /// 调用要求在主线程（读 AIConfigurationStore 的 @Published 配置需要在主线程）。
    /// 图片压缩/编码仍然放到后台，网络请求完成回调由 VisionAIService 保证回主线程。
    private func requestCloudUpgrade(image: UIImage) {
        guard AIConfigurationStore.shared.isCloudConfigured,
              let (service, _) = VisionAIServiceFactory.make() else { return }

        isUpgrading = true
        let context = cloudContext()

        DispatchQueue.global(qos: .userInitiated).async {
            guard let payload = ImagePreparationService.prepareVisionPayload(from: image) else {
                DispatchQueue.main.async { isUpgrading = false }
                return
            }
            // 本地先算好对称/平衡/引导线等“构图原语”，随 prompt 一并交给云端，
            // 让 LLM 不必单凭像素重新猜测几何关系
            let primitives = LocalPhotoCritiqueEngine.compositionPrimitivesSummary(image)
            service.sendVisionRequest(
                jpegData: payload,
                prompt: PhotoCritique.prompt(context: context, primitives: primitives),
                systemPrompt: "你是一位专业摄影构图顾问，擅长用「空间深度」「视觉平衡」「叙事感」解读画面，"
                    + "点评必须基于照片本身，语言简洁但要点出具体构图手法。"
            ) { result in
                isUpgrading = false
                guard case .success(let text) = result,
                      var parsed = PhotoCritique.parse(from: text) else { return }
                parsed.source = .cloud
                critique = parsed
                HapticManager.shared.soft()
                PhotoStorageService.shared.updateCritique(parsed, for: record.id)
            }
        }
    }

    /// 拍摄上下文：EXIF + 拍摄时刻的构图评分，让云端点评能回应“当时引导的效果”
    private func cloudContext() -> String {
        var context: [String] = []
        if let iso = record.iso { context.append("ISO \(Int(iso))") }
        if let shutter = record.shutterSpeed {
            context.append(shutter >= 1 ? "快门 \(Int(shutter))s" : String(format: "快门 1/%.0fs", 1.0 / shutter))
        }
        if let aperture = record.aperture { context.append(String(format: "光圈 f/%.1f", aperture)) }
        if let score = record.compositionScore { context.append("拍摄时 AI 构图评分 \(score)") }
        if let method = record.detectionMethod { context.append("检测引擎 \(method)") }
        return context.joined(separator: "，")
    }
}

#endif
