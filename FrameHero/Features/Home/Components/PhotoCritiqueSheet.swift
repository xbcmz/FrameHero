//
//  PhotoCritiqueSheet.swift
//  FrameHero
//
//  拍后 AI 点评面板（图库照片浏览器入口）
//
//  流程：载入原图 → 预处理（ImagePreparationService）→
//  DeepSeek Vision（用户选择的视觉模型）→ 结构化点评展示
//

import SwiftUI
import UIKit

#if os(iOS)

struct PhotoCritiqueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var aiConfig = AIConfigurationStore.shared

    let record: PhotoRecord
    let photoProvider: (UUID) -> UIImage?

    private enum Phase { case loadingImage, analyzing, success, failed }
    @State private var phase: Phase = .loadingImage
    @State private var thumbnail: UIImage?
    @State private var critique: PhotoCritique?
    @State private var errorMessage: String?
    @State private var modelLabel: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    modelInfo

                    previewArea

                    statusArea
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("AI 点评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear { run() }
    }

    // MARK: - 子视图

    private var modelInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(DesignSystem.Colors.primary)
                Text("视觉模型")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            Text(modelLabel.isEmpty ? "未配置" : modelLabel)
                .font(DesignSystem.Typography.monoCaption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
        .padding(.top, 12)
    }

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
            // 得分
            HStack(spacing: 10) {
                Text(critique.score.map { "\($0)" } ?? "—")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(critique.score))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 构图评分")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    if let summary = critique.summary {
                        Text(summary)
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                Spacer()
            }
            .padding(DesignSystem.Spacing.medium)
            .background(card)

            // 亮点
            if let strengths = critique.strengths, !strengths.isEmpty {
                critiqueList(title: "亮点", icon: "plus.circle.fill",
                             color: DesignSystem.Colors.success, items: strengths)
            }

            // 改进建议
            if let improvements = critique.improvements, !improvements.isEmpty {
                critiqueList(title: "下次可以这样拍", icon: "arrow.up.circle.fill",
                             color: DesignSystem.Colors.warning, items: improvements)
            }
        }
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

    private func run() {
        guard let (service, configuration) = VisionAIServiceFactory.make() else {
            phase = .failed
            errorMessage = "请先在设置 → AI 助手 中配置 API Key"
            return
        }
        modelLabel = "\(configuration.provider) · \(configuration.model)"

        // 1. 载入原图
        DispatchQueue.global(qos: .userInitiated).async {
            let image = photoProvider(record.id)
            guard let image else {
                DispatchQueue.main.async {
                    phase = .failed
                    errorMessage = "照片文件缺失"
                }
                return
            }
            DispatchQueue.main.async { thumbnail = image }

            // 2. 预处理 + 上下文 + 请求
            guard let payload = ImagePreparationService.prepareVisionPayload(from: image) else {
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.errorMessage = "照片预处理失败"
                }
                return
            }
            DispatchQueue.main.async {
                self.runAnalysis(service: service, payload: payload)
            }
        }
    }

    private func runAnalysis(service: any VisionAIService, payload: Data) {
        phase = .analyzing

        // 拍摄上下文：EXIF + 快门时刻的构图评分，让点评回应"当时引导的效果"
        var context: [String] = []
        if let iso = record.iso { context.append("ISO \(Int(iso))") }
        if let shutter = record.shutterSpeed {
            context.append(shutter >= 1 ? "快门 \(Int(shutter))s" : String(format: "快门 1/%.0fs", 1.0 / shutter))
        }
        if let aperture = record.aperture { context.append(String(format: "光圈 f/%.1f", aperture)) }
        if let score = record.compositionScore { context.append("拍摄时 AI 构图评分 \(score)") }
        if let method = record.detectionMethod { context.append("检测引擎 \(method)") }

        service.sendVisionRequest(
            jpegData: payload,
            prompt: PhotoCritique.prompt(context: context.joined(separator: "，")),
            systemPrompt: "你是一位严格的手机摄影评委，点评必须基于照片本身，语言简洁具体。"
        ) { result in
            switch result {
            case .success(let text):
                if let parsed = PhotoCritique.parse(from: text) {
                    critique = parsed
                    phase = .success
                    HapticManager.shared.success()
                } else {
                    errorMessage = "点评解析失败，请重试"
                    phase = .failed
                    HapticManager.shared.warning()
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                phase = .failed
                HapticManager.shared.warning()
            }
        }
    }
}
#endif
