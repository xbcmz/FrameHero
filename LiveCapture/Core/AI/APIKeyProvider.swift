//
//  APIKeyProvider.swift
//  LiveCapture
//
//  API Key 安全读取工具
//
//  V1 实现：从 Info.plist 读取（开发阶段方便）
//  未来可升级：Keychain 存储（生产环境更安全）
//
//  ⚠️ 重要：API Key 禁止硬编码在代码中
//

import Foundation

/// API Key 提供者
///
/// 负责安全地读取和管理各种 API 的密钥。
/// V1 版本从 Info.plist 读取，后续可无缝升级到 Keychain。
final class APIKeyProvider {
    
    /// 单例
    static let shared = APIKeyProvider()
    
    private init() {}
    
    // MARK: - DeepSeek
    
    /// DeepSeek API Key
    ///
    /// 读取顺序：
    /// 1. Info.plist 中的 DeepSeekAPIKey
    /// 2. 如果为空，返回 nil（App 自动降级到 Mock 模式）
    var deepSeekAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "DeepSeekAPIKey") as? String,
              !key.isEmpty,
              key != "YOUR_DEEPSEEK_API_KEY_HERE" else {
            return nil
        }
        return key
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
