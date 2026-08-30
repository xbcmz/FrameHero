//
//  AIConfigurationStore.swift
//  FrameHero
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
    static let defaultVisionModel = "deepseek-v4-flash-vision-exp"

    /// 文本模型（拍后点评等云端文本能力）
    static let availableModels: [(id: String, name: String, description: String)] = [
        (chatModel, "通用 V3", "响应快，适合实时建议"),
        (reasonerModel, "深度思考 R1", "更细腻但更慢，消耗更多 token")
    ]

    /// 视觉模型（图片理解，独立于文本模型的能力线）
    static let availableVisionModels: [(id: String, name: String, description: String)] = [
        (defaultVisionModel, "V4 Flash Vision", "实验版多模态：看懂画面，输出结构化场景分析")
    ]

    /// 构图分析模式：本地启发式 vs 云端 Vision，决定「AI 构图」点按后走哪条路径
    ///
    /// - auto：本地优先 + 云端增强（默认）。本地管线（场景分类 + 人物检测 + AdaCrop）
    ///   立即并行启动，通常 ~1 秒出方案；云端方案若在用户选定前送达，无感升级，
    ///   来迟了或用户已选定/已退出则直接丢弃，不会二次打扰。
    /// - localOnly：仅本地，即使配置了云端 Key 也不发起网络请求。用于对比测试本地路径体验。
    /// - cloudOnly：仅云端（旧版行为），本地管线不参与出方案。用于对比测试云端路径体验。
    enum CompositionAnalysisMode: String, CaseIterable, Identifiable, Codable {
        case auto
        case localOnly
        case cloudOnly

        var id: String { rawValue }

        var shortName: String {
            switch self {
            case .auto: return "自动"
            case .localOnly: return "仅本地"
            case .cloudOnly: return "仅云端"
            }
        }

        var description: String {
            switch self {
            case .auto: return "本地优先 + 云端增强：本地先出方案，云端就绪后无感升级"
            case .localOnly: return "只用本地启发式方案，不联网，测试本地路径速度"
            case .cloudOnly: return "只等云端方案（旧版行为），测试云端路径速度"
            }
        }
    }

    private static let keychainAccount = "deepseek.apiKey"
    private enum DefaultsKey {
        static let cloudEnabled = "ai.cloudAIEnabled"
        static let baseURL = "ai.baseURL"
        static let model = "ai.model"
        static let visionModel = "ai.visionModel"
        static let compositionAnalysisMode = "ai.compositionAnalysisMode"
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

    /// 文本模型 ID
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }

    /// 视觉模型 ID（图片理解，独立于文本模型的能力线）
    @Published var visionModel: String {
        didSet { UserDefaults.standard.set(visionModel, forKey: DefaultsKey.visionModel) }
    }

    /// 构图分析模式（自动 / 仅本地 / 仅云端），拍摄页「AI 构图」按此选择路径
    @Published var compositionAnalysisMode: CompositionAnalysisMode {
        didSet { UserDefaults.standard.set(compositionAnalysisMode.rawValue, forKey: DefaultsKey.compositionAnalysisMode) }
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

        let storedVision = defaults.string(forKey: DefaultsKey.visionModel)
        self.visionModel = (storedVision?.isEmpty == false)
            ? storedVision!
            : Self.defaultVisionModel

        let storedMode = defaults.string(forKey: DefaultsKey.compositionAnalysisMode)
            .flatMap(CompositionAnalysisMode.init(rawValue:))
        self.compositionAnalysisMode = storedMode ?? .auto

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
        visionModel = Self.defaultVisionModel
    }
}

// MARK: - AI 使用计数

/// AI 建议交付次数计数器（首页"今日数据"展示用）。
/// 按天滚动的轻量计数：UserDefaults 存今日次数 + 日期戳 + 累计值，
/// 跨天首次读取时自动归零。线程安全（UserDefaults 原子写）。
enum AIUsageCounter {

    private enum Key {
        static let todayCount = "aiUsage.adviceToday"
        static let todayStamp = "aiUsage.adviceTodayStamp"
        static let total = "aiUsage.adviceTotal"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 记一次 AI 建议交付（Advisor 成功返回建议时调用）
    static func recordAdviceDelivered() {
        let d = UserDefaults.standard
        let today = dayFormatter.string(from: Date())
        if d.string(forKey: Key.todayStamp) != today {
            d.set(today, forKey: Key.todayStamp)
            d.set(0, forKey: Key.todayCount)
        }
        d.set(d.integer(forKey: Key.todayCount) + 1, forKey: Key.todayCount)
        d.set(d.integer(forKey: Key.total) + 1, forKey: Key.total)
    }

    /// 今天的 AI 建议次数（日期戳不匹配时视为 0）
    static var adviceCountToday: Int {
        let d = UserDefaults.standard
        guard d.string(forKey: Key.todayStamp) == dayFormatter.string(from: Date()) else { return 0 }
        return d.integer(forKey: Key.todayCount)
    }

    /// 累计 AI 建议次数
    static var adviceCountTotal: Int {
        UserDefaults.standard.integer(forKey: Key.total)
    }
}
