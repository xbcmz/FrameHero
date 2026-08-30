import SwiftUI

struct SettingsView: View {
    @AppStorage("detectionMode") private var detectionMode: DetectionMode = .fast
    @AppStorage("autoCaptureEnabled") private var autoCaptureEnabled = true
    @AppStorage("captureDelay") private var captureDelay: Double = 1.0
    @AppStorage("colorScheme") private var colorScheme: String = "system"

    // AI 配置（Key 存 Keychain，其余存 UserDefaults）
    @ObservedObject private var aiConfig = AIConfigurationStore.shared
    @AppStorage("aiAdviceEnabled") private var aiAdviceEnabled: Bool = true
    @State private var apiKeyDraft: String = ""
    @State private var showAPIKey: Bool = false
    @State private var showAdvancedAI: Bool = false
    @State private var isTestingConnection: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    headerSection

                    themeSection

                    captureSection

                    aiSection

                    modelSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
        }
        .onAppear {
            // 草稿只回填 Keychain 中用户自己保存的 Key；
            // Info.plist 兜底的 Key 不回填，避免误导"已在设置里配置"
            apiKeyDraft = aiConfig.apiKey
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(DesignSystem.Typography.largeTitle)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("外观")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 15))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("主题模式")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("切换深色 / 浅色外观")
                            .font(DesignSystem.Typography.caption1)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    Spacer()
                    Picker("主题", selection: $colorScheme) {
                        Text("系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, DesignSystem.Spacing.medium)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundSecondary)
            )
        }
    }

    // MARK: - Capture Section

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("拍摄设置")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            VStack(spacing: 0) {
                ToggleRow(
                    icon: "bolt.fill",
                    title: "自动拍照",
                    description: "对准构图框后自动触发拍摄",
                    isOn: $autoCaptureEnabled
                )

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.system(size: 15))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .frame(width: 24)
                        Text("拍照延迟")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Text("\(String(format: "%.1f", captureDelay))秒")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }

                    Picker("延迟", selection: $captureDelay) {
                        Text("0.5秒").tag(0.5)
                        Text("1.0秒").tag(1.0)
                        Text("1.5秒").tag(1.5)
                        Text("2.0秒").tag(2.0)
                    }
                    .pickerStyle(.segmented)

                    Text("对齐中心后等待此时间再自动拍摄")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, DesignSystem.Spacing.medium)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundSecondary)
            )
        }
    }

    // MARK: - AI Section

    /// 统一卡片背景（全区块共用，避免嵌套卡片）
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
            .fill(DesignSystem.Colors.backgroundSecondary)
    }

    /// 主开关下方的状态行（连接状态摘要）
    private var aiStatus: (text: String, color: Color) {
        if !aiConfig.cloudAIEnabled {
            return ("已关闭 · 使用本地模拟建议", DesignSystem.Colors.textTertiary)
        }
        guard aiConfig.effectiveAPIKey != nil else {
            return ("未配置 API Key · 在高级设置中配置", DesignSystem.Colors.warning)
        }
        switch aiConfig.lastConnectionTest {
        case .success(let latency):
            return (String(format: "已连接 · %.0f ms", latency * 1000), DesignSystem.Colors.success)
        case .failure(let message):
            return ("连接失败 · \(message)", DesignSystem.Colors.error)
        case nil:
            return ("已配置 · 连接未测试", DesignSystem.Colors.textTertiary)
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("AI 助手")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // 主卡片：用户关心的三件事——总开关 / 模型 / 拍摄辅助
            VStack(spacing: 0) {
                masterToggleRow

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                modelRow

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                analysisModeRow

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                ToggleRow(
                    icon: "lightbulb",
                    title: "AI 构图助手",
                    description: "拍摄页提供场景识别与实时构图引导",
                    isOn: $aiAdviceEnabled
                )
            }
            .background(cardBackground)

            // 技术配置收纳进高级设置，默认收起
            advancedAISection

            Text("未配置 API Key 时自动使用本地模拟建议。Key 在 platform.deepseek.com 申请，保存在系统 Keychain。")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .lineSpacing(3)
        }
    }

    // MARK: 主开关行

    private var masterToggleRow: some View {
        let status = aiStatus
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesignSystem.Colors.primaryGradient)
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("AI 拍摄助手")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(status.text)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(status.color)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $aiConfig.cloudAIEnabled)
                .labelsHidden()
                .tint(DesignSystem.Colors.primary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    // MARK: 模型行

    /// 模型行：标题一行、选择器一行、说明一行（垂直分层，
    /// 标题与「V4 Flash Vision」这类长模型名不再争抢水平空间）
    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            modelSubRow(
                icon: "text.bubble",
                title: "文本模型",
                description: AIConfigurationStore.availableModels
                    .first { $0.id == aiConfig.model }?.description ?? ""
            ) {
                Picker("文本模型", selection: $aiConfig.model) {
                    ForEach(AIConfigurationStore.availableModels, id: \.id) { info in
                        Text(info.name).tag(info.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()
                .background(DesignSystem.Colors.backgroundTertiary)

            modelSubRow(
                icon: "eye",
                title: "视觉模型",
                description: AIConfigurationStore.availableVisionModels
                    .first { $0.id == aiConfig.visionModel }?.description ?? ""
            ) {
                Picker("视觉模型", selection: $aiConfig.visionModel) {
                    ForEach(AIConfigurationStore.availableVisionModels, id: \.id) { info in
                        Text(info.name).tag(info.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .disabled(!aiConfig.cloudAIEnabled)
        .opacity(aiConfig.cloudAIEnabled ? 1.0 : 0.4)
    }

    // MARK: 构图分析模式行

    /// 本地/云端对比测试开关：控制「AI 构图」点击后走本地、云端还是两者并行
    private var analysisModeRow: some View {
        modelSubRow(
            icon: "bolt.badge.clock",
            title: "构图分析模式",
            description: aiConfig.compositionAnalysisMode.description
        ) {
            Picker("构图分析模式", selection: $aiConfig.compositionAnalysisMode) {
                ForEach(AIConfigurationStore.CompositionAnalysisMode.allCases) { mode in
                    Text(mode.shortName).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// 单个模型子行：图标+标题 → 右对齐选择器 → 说明文字
    private func modelSubRow<PickerContent: View>(icon: String, title: String,
                                                  description: String,
                                                  @ViewBuilder picker: () -> PickerContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 24)
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }

            HStack {
                Spacer(minLength: 0)
                picker()
            }

            Text(description)
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 高级设置（API Key / 连接测试 / 接口地址）

    private var advancedAISection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Button {
                HapticManager.shared.light()
                withAnimation(DesignSystem.Animation.smooth) {
                    showAdvancedAI.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Text("高级设置")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("API Key · 连接测试 · 接口地址")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .rotationEffect(.degrees(showAdvancedAI ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if showAdvancedAI {
                VStack(spacing: 0) {
                    apiKeyRow

                    Divider()
                        .background(DesignSystem.Colors.backgroundSecondary)

                    connectionTestRow

                    Divider()
                        .background(DesignSystem.Colors.backgroundSecondary)

                    baseURLRow
                }
                .background(cardBackground)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: API Key 行（高级）

    private var apiKeyDraftChanged: Bool {
        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != aiConfig.apiKey
    }

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("API Key")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(aiConfig.apiKeySourceDescription)
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Spacer()
                if !aiConfig.apiKey.isEmpty {
                    Button("清除") {
                        HapticManager.shared.light()
                        aiConfig.setAPIKey("")
                        apiKeyDraft = ""
                    }
                    .font(DesignSystem.Typography.footnote)
                    .foregroundColor(DesignSystem.Colors.error)
                }
            }

            HStack(spacing: 8) {
                Group {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("sk-...", text: $apiKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .font(DesignSystem.Typography.monoCaption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                )

                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .frame(width: 32, height: 32)
                }

                Button("保存") {
                    let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    aiConfig.setAPIKey(trimmed)
                    apiKeyDraft = trimmed
                    HapticManager.shared.success()
                }
                .font(DesignSystem.Typography.footnote.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primary)
                .disabled(!apiKeyDraftChanged)
                .opacity(apiKeyDraftChanged ? 1.0 : 0.4)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    // MARK: 连接测试行（高级）

    private var connectionTestRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15))
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("连接测试")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text("验证 Key 与接口地址是否可用")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            Spacer()

            Button {
                testAIConnection()
            } label: {
                HStack(spacing: 6) {
                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isTestingConnection ? "测试中" : "开始测试")
                }
                .font(DesignSystem.Typography.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(aiConfig.isCloudConfigured
                        ? DesignSystem.Colors.primary
                        : DesignSystem.Colors.textTertiary.opacity(0.4))
                )
            }
            .disabled(isTestingConnection || !aiConfig.isCloudConfigured)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    /// 发起连接测试（GET /models，鉴权 + 可达性，不消耗 token），
    /// 结果写入 aiConfig.lastConnectionTest，主卡片的状态行同步更新
    private func testAIConnection() {
        guard let key = aiConfig.effectiveAPIKey else { return }
        isTestingConnection = true
        HapticManager.shared.light()

        DeepSeekService.testConnection(apiKey: key, baseURL: aiConfig.baseURL) { result in
            isTestingConnection = false
            switch result {
            case .success(let latency):
                aiConfig.lastConnectionTest = .success(latency: latency)
                HapticManager.shared.success()
            case .failure(let error):
                aiConfig.lastConnectionTest = .failure(message: error.localizedDescription)
                HapticManager.shared.warning()
            }
        }
    }

    // MARK: 接口地址行（高级）

    private var baseURLRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("接口地址")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text("缺路径时自动补 /chat/completions")
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Spacer()
                if aiConfig.baseURL != AIConfigurationStore.defaultBaseURL {
                    Button("恢复默认") {
                        HapticManager.shared.light()
                        aiConfig.baseURL = AIConfigurationStore.defaultBaseURL
                    }
                    .font(DesignSystem.Typography.footnote)
                    .foregroundColor(DesignSystem.Colors.primary)
                }
            }

            TextField(AIConfigurationStore.defaultBaseURL, text: $aiConfig.baseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(DesignSystem.Typography.monoCaption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("构图引擎")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Picker("构图引擎", selection: $detectionMode) {
                ForEach(DetectionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: modelIcon)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.primary)
                    Text(detectionMode.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                Text(detectionMode.description)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .lineSpacing(3)
            }
            .padding(DesignSystem.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundSecondary)
            )
        }
    }

    private var modelIcon: String {
        switch detectionMode {
        case .vision: return "eye"
        case .fast:   return "bolt"
        case .pro:    return "sparkles"
        }
    }
}

// MARK: - Subviews

private struct ToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(description)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(DesignSystem.Colors.primary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }
}