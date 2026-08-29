//
//  AIConfigurationStore.swift
//  LiveCapture
//
//  AI 服务配置中心（设置页 ↔ AI 服务的唯一通道）
//
//  ## 管理的配置
//  - API Key：Keychain 存储（KeychainStore），设置页内配置，不再依赖 Info.plist
//  - 云端开关：关闭后 AI 建议走本地 Mock（MockPhotographer），零联网
//  - 模型：deepseek-chat（V3 通用）/ deepseek-reasoner（R1 深度思考）
//  - 接口地址：默认官方地址，高级设置可改（自建代理/中转）
//
//  ## 兼容性
//  Info.plist 里的 DeepSeekAPIKey 仍作为兜底（老用户升级后不用重新配置），
//  但一旦在设置里保存过 Key，Keychain 优先。
//
//  ## 生效方式
//  PhotographyAdvisor 订阅 objectWillChange，配置变化时自动重建 AI 提供方，
//  相机页无需重启。
//

import Foundation
import Combine

final class AIConfigurationStore: ObservableObject {

    static let shared = AIConfigurationStore()

    // MARK: - 常量

    static let defaultBaseURL = "https://api.deepseek.com/v1"
    static let chatModel = "deepseek-chat"
    static let reasonerModel = "deepseek-reasoner"

    static let availableModels: [(id: String, name: String, description: String)] = [
        (chatModel, "通用 V3", "响应快，适合实时建议"),
        (reasonerModel, "深度思考 R1", "更细腻但更慢，消耗更多 token")
    ]

    private static let keychainAccount = "deepseek.apiKey"
    private enum DefaultsKey {
        static let cloudEnabled = "ai.cloudAIEnabled"
        static let baseURL = "ai.baseURL"
        static let model = "ai.model"
    }

    // MARK: - 状态

    /// 是否启用云端 AI（关闭 = 本地 Mock 建议）
    @Published var cloudAIEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudAIEnabled, forKey: DefaultsKey.cloudEnabled) }
    }

    /// API 接口地址（高级设置）
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: DefaultsKey.baseURL) }
    }

    /// 模型 ID
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }

    /// API Key（Keychain 持久化，内存中仅保留副本供同步读取）
    @Published private(set) var apiKey: String

    // MARK: - 初始化

    private init() {
        let defaults = UserDefaults.standard

        // 云端开关默认开：老用户（Info.plist 已配 Key）行为不变
        let enabled: Bool
        if defaults.object(forKey: DefaultsKey.cloudEnabled) != nil {
            enabled = defaults.bool(forKey: DefaultsKey.cloudEnabled)
        } else {
            enabled = true
        }
        self.cloudAIEnabled = enabled

        let storedURL = defaults.string(forKey: DefaultsKey.baseURL)
        self.baseURL = (storedURL?.isEmpty == false) ? storedURL! : Self.defaultBaseURL

        let storedModel = defaults.string(forKey: DefaultsKey.model)
        self.model = (storedModel?.isEmpty == false) ? storedModel! : Self.chatModel

        self.apiKey = KeychainStore.load(account: Self.keychainAccount) ?? ""
    }

    // MARK: - 连接状态

    /// 连接测试结果（会话内有效，不持久化；用于设置页状态行展示）
    enum ConnectionTestOutcome: Equatable {
        case success(latency: TimeInterval)
        case failure(message: String)
    }

    /// 最近一次连接测试结果，nil = 本次会话尚未测试
    @Published var lastConnectionTest: ConnectionTestOutcome?

    // MARK: - 派生状态

    /// 实际生效的 API Key：Keychain（设置页配置）优先，Info.plist 兜底
    var effectiveAPIKey: String? {
        if !apiKey.isEmpty { return apiKey }
        return APIKeyProvider.shared.infoPlistAPIKey
    }

    /// 云端 AI 是否可用（开关开 + 有 Key）
    var isCloudConfigured: Bool {
        cloudAIEnabled && effectiveAPIKey != nil
    }

    /// Key 的来源描述（设置页展示用）
    var apiKeySourceDescription: String {
        if !apiKey.isEmpty { return "已配置（存储在 Keychain）" }
        if APIKeyProvider.shared.infoPlistAPIKey != nil { return "来自 Info.plist（在下方保存后迁移到 Keychain）" }
        return "未配置"
    }

    /// 规范化后的请求端点：baseURL 缺路径时自动补 /chat/completions
    var chatCompletionsURL: URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard trimmed.lowercased().hasPrefix("https://") else { return nil }
        if trimmed.lowercased().hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed + "/chat/completions")
    }

    // MARK: - 修改

    /// 保存 API Key（空串 = 清除）。Key 变化后旧的测试结果不再可信，一并清除
    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: Self.keychainAccount)
            apiKey = ""
        } else {
            KeychainStore.save(trimmed, account: Self.keychainAccount)
            apiKey = trimmed
        }
        lastConnectionTest = nil
    }

    /// 恢复高级设置为默认值（不影响 Key）
    func resetAdvancedSettings() {
        baseURL = Self.defaultBaseURL
        model = Self.chatModel
    }
}
