//
//  KeychainStore.swift
//  FrameHero
//
//  Keychain 轻量封装：存取少量敏感字符串（当前用于 DeepSeek API Key）。
//
//  API Key 属于敏感凭据，不用 UserDefaults（明文 plist 可被导出），
//  也不放 Info.plist（会打进 ipa 分发）。Keychain 由系统加密，
//  卸载重装后保留（凭据跟随 Apple ID 恢复），符合凭据类数据的预期。
//

import Foundation
import Security

enum KeychainStore {

    private static let service = "com.xbcmz.FrameHero"

    // MARK: - Public API

    /// 保存字符串，已存在则覆盖。
    static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// 读取字符串，不存在或非 UTF-8 时返回 nil。
    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// 删除条目。条目不存在也视为成功。
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
