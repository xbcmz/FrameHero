//
//  APIKeyProvider.swift
//  FrameHero
//
//  API Key 读取工具
//
//  读取顺序：
//  1. AIConfigurationStore（Keychain，设置页内配置）—— 首选
//  2. Info.plist 中的 DeepSeekAPIKey —— 老配置兜底
//  3. 都没有则返回 nil（App 自动降级到 Mock 模式）
//
//  ⚠️ 重要：API Key 禁止硬编码在代码中
//

import Foundation

/// API Key 提供者
///
/// 负责读取和管理 API 密钥。设置页（AIConfigurationStore）是首选来源，
/// Info.plist 仅作为升级前的旧配置兜底。
final class APIKeyProvider {

    /// 单例
    static let shared = APIKeyProvider()

    private init() {}

    // MARK: - DeepSeek

    /// Info.plist 中的旧配置（只读兜底，不再推荐）
    var infoPlistAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "DeepSeekAPIKey") as? String,
              !key.isEmpty,
              key != "YOUR_DEEPSEEK_API_KEY_HERE" else {
            return nil
        }
        return key
    }

    /// DeepSeek API Key（Keychain 优先，Info.plist 兜底）
    var deepSeekAPIKey: String? {
        AIConfigurationStore.shared.effectiveAPIKey
    }

    /// 是否有有效的 DeepSeek API Key
    var hasDeepSeekKey: Bool {
        deepSeekAPIKey != nil
    }

    // MARK: - 服务类型判断

    /// 根据配置判断应该使用哪种 AI 服务
    var recommendedAIService: AIServiceType {
        hasDeepSeekKey ? .deepSeek : .mock
    }
}
