import SwiftUI

struct SettingsView: View {
    @AppStorage("detectionMode") private var detectionMode: DetectionMode = .fast
    @AppStorage("autoCaptureEnabled") private var autoCaptureEnabled = true
    @AppStorage("captureDelay") private var captureDelay: Double = 1.0
    @AppStorage("colorScheme") private var colorScheme: String = "system"

    // AI 配置（Key 存 Keychain，其余存 UserDefaults）
    @ObservedObject private var aiConfig = AIConfigurationStore.shared
    @State private var apiKeyDraft: String = ""
    @State private var showAPIKey: Bool = false
    @State private var showAdvancedAI: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestMessage: String?
    @State private var connectionTestSucceeded: Bool?

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

    /// 当前生效的 AI 通道描述（云端 DeepSeek / 本地模拟）
    private var activeAIDescription: String {
        if aiConfig.isCloudConfigured {
            let modelName = AIConfigurationStore.availableModels
                .first { $0.id == aiConfig.model }?.name ?? aiConfig.model
            return "云端 DeepSeek · \(modelName)"
        }
        return aiConfig.cloudAIEnabled ? "本地模拟（未配置 API Key）" : "本地模拟（云端已关闭）"
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("AI 助手")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            VStack(spacing: 0) {
                // 云端开关
                ToggleRow(
                    icon: "sparkles",
                    title: "云端 AI 建议",
                    description: activeAIDescription,
                    isOn: $aiConfig.cloudAIEnabled
                )

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                // API Key
                apiKeyRow

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                // 模型选择
                modelPickerRow

                Divider()
                    .background(DesignSystem.Colors.backgroundSecondary)

                // 连接测试
                connectionTestRow
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.backgroundSecondary)
            )

            // 高级设置
            advancedAISection

            Text("API Key 存储在系统 Keychain 中，不会明文写入文件。可在 platform.deepseek.com 申请。")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .lineSpacing(3)
        }
    }

    // MARK: API Key 输入行

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
                        connectionTestMessage = nil
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
                    connectionTestMessage = nil
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

    // MARK: 模型选择行

    private var modelPickerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 15))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .frame(width: 24)
                Text("模型")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Text(aiConfig.model)
                    .font(DesignSystem.Typography.monoCaption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            Picker("模型", selection: $aiConfig.model) {
                ForEach(AIConfigurationStore.availableModels, id: \.id) { info in
                    Text(info.name).tag(info.id)
                }
            }
            .pickerStyle(.segmented)

            Text(AIConfigurationStore.availableModels
                .first { $0.id == aiConfig.model }?.description ?? "")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    // MARK: 连接测试行

    private var connectionTestRow: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            if let message = connectionTestMessage {
                HStack(spacing: 6) {
                    Image(systemName: connectionTestSucceeded == true
                        ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(connectionTestSucceeded == true
                            ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                    Text(message)
                        .font(DesignSystem.Typography.caption1)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DesignSystem.Spacing.medium)
    }

    /// 发起连接测试（GET /models，鉴权 + 可达性，不消耗 token）
    private func testAIConnection() {
        guard let key = aiConfig.effectiveAPIKey else { return }
        isTestingConnection = true
        connectionTestMessage = nil
        HapticManager.shared.light()

        DeepSeekService.testConnection(apiKey: key, baseURL: aiConfig.baseURL) { result in
            isTestingConnection = false
            switch result {
            case .success(.success(let latency)):
                connectionTestSucceeded = true
                connectionTestMessage = String(format: "连接成功 · %.0f ms", latency * 1000)
                HapticManager.shared.success()
            case .failure(let error):
                connectionTestSucceeded = false
                connectionTestMessage = error.localizedDescription
                HapticManager.shared.warning()
            }
        }
    }

    // MARK: 高级设置

    private var advancedAISection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Button {
                withAnimation(DesignSystem.Animation.smooth) {
                    showAdvancedAI.toggle()
                }
            } label: {
                HStack {
                    Label("高级设置", systemImage: "gearshape.2")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .rotationEffect(.degrees(showAdvancedAI ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if showAdvancedAI {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("接口地址（Base URL）")
                            .font(DesignSystem.Typography.footnote)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
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
                        Text("缺路径时自动补 /chat/completions，可填自建代理或中转地址")
                            .font(DesignSystem.Typography.caption1)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }

                    Button {
                        HapticManager.shared.light()
                        aiConfig.resetAdvancedSettings()
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                            .font(DesignSystem.Typography.footnote)
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignSystem.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(DesignSystem.Colors.backgroundSecondary)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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