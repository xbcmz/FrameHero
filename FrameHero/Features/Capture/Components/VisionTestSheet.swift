//
//  VisionTestSheet.swift
//  FrameHero
//
//  AI 视觉连通性测试（Phase 0.3 完成标准演示）
//
//  ## 流程（对齐 Phase 0 Completion Criteria）
//  打开相机 → 取当前帧 → 发送到 DeepSeek-V4-Flash-Vision-Exp →
//  收 JSON → 解析 → 展示 Scene / Subject / Description
//
//  ## 成功标准
//  ✓ 相机画面可捕获   ✓ 图片可发送   ✓ 返回有效响应
//  ✓ JSON 可解析      ✓ 结果可展示
//

import SwiftUI
import UIKit

#if os(iOS)

struct VisionTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var aiConfig = AIConfigurationStore.shared

    private enum Phase { case idle, capturing, testing, success, failed }
    @State private var phase: Phase = .idle
    @State private var thumbnail: UIImage?
    @State private var analysis: SceneAnalysis?
    @State private var errorMessage: String?
    @State private var modelLabel: String = ""

    /// 由拍摄页注入：从当前取景捕获一帧并预处理为 JPEG Data
    let captureFrame: (@escaping (Data?) -> Void) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                modelInfo

                previewArea
                    .frame(maxHeight: 320)

                statusArea

                Spacer()

                Button {
                    runTest()
                } label: {
                    HStack {
                        if phase == .capturing || phase == .testing {
                            ProgressView().tint(.white)
                        }
                        Text(buttonTitle)
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canRun ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary.opacity(0.4))
                    )
                }
                .disabled(!canRun)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("AI 视觉测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear {
            // 进入即自动跑一次（Phase 0 演示语义：点了就直接测）
            runTest()
        }
    }

    // MARK: - 子视图

    private var modelInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "eye.circle.fill")
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
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var previewArea: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .padding(.horizontal, 16)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .frame(height: 200)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .capturing:
            Label("正在捕获相机画面…", systemImage: "camera")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        case .testing:
            Label("已发送图片，等待视觉模型返回…", systemImage: "antenna.radiowaves.left.and.right")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        case .success:
            if let analysis {
                VStack(alignment: .leading, spacing: 8) {
                    resultRow(icon: "checkmark.circle.fill", color: .green,
                              title: "场景", value: analysis.scene)
                    resultRow(icon: "checkmark.circle.fill", color: .green,
                              title: "主体", value: analysis.mainSubject)
                    resultRow(icon: "checkmark.circle.fill", color: .green,
                              title: "描述", value: analysis.description)
                }
                .padding(.horizontal, 16)
            }
        case .failed:
            VStack(spacing: 4) {
                Label("测试失败", systemImage: "xmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.error)
                Text(errorMessage ?? "未知错误")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
        }
    }

    private func resultRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text(value.isEmpty ? "—" : value)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }

    // MARK: - 逻辑

    private var canRun: Bool {
        phase != .capturing && phase != .testing && aiConfig.isCloudConfigured
    }

    private var buttonTitle: String {
        switch phase {
        case .capturing: return "捕获中"
        case .testing: return "请求中"
        case .success: return "重新测试"
        case .failed: return aiConfig.isCloudConfigured ? "重试" : "需要先配置 API Key"
        case .idle: return "开始测试"
        }
    }

    private func runTest() {
        guard let (service, configuration) = VisionAIServiceFactory.make() else {
            phase = .failed
            errorMessage = "请先在设置 → AI 助手 中配置 API Key"
            return
        }
        modelLabel = "\(configuration.provider) · \(configuration.model)"
        analysis = nil
        errorMessage = nil
        thumbnail = nil
        phase = .capturing
        HapticManager.shared.light()

        // Phase 0.3：从相机取当前帧
        captureFrame { data in
            guard let data, let image = UIImage(data: data) else {
                self.phase = .failed
                self.errorMessage = "无法捕获相机画面"
                return
            }
            self.thumbnail = image
            self.phase = .testing

            // Phase 0.4：ImagePreparationService 已完成降采样/压缩/data URL
            service.analyzeScene(jpegData: data) { result in
                switch result {
                case .success(let analysis):
                    self.analysis = analysis
                    self.phase = .success
                    HapticManager.shared.success()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.phase = .failed
                    HapticManager.shared.warning()
                }
            }
        }
    }
}
#endif
