//
//  VisionAIService.swift
//  FrameHero
//
//  视觉理解服务抽象（多模态）—— Phase 0.2 / 0.5
//
//  ## Phase 0.1 架构勘察结论（2026-08-29）
//  1. 现用模型：deepseek-chat / deepseek-reasoner（设置页可选），均为纯文本模型
//  2. API 格式：POST {baseURL}/chat/completions，OpenAI 兼容 JSON
//  3. 是否纯文本：是 —— messages[].content 为纯字符串
//  4. 能否发图：不能 —— 无多模态 content 数组、无 base64 图片通道
//  5. API 层是否支持多模态：不支持（解析端也只认 String）
//  6. 抽象可换模型：可以 —— 已有 Provider 协议体系，但视觉能力需要
//     独立新抽象（文本聊天与图像分析不混用，见 Phase 0.2 要求）
//
//  ## 设计
//  VisionAIService（协议，传输层）：图片 + 提示词 → 模型原始文本
//  ├─ DeepSeekVisionService   ← 当前实现（DeepSeek-V4-Flash-Vision-Exp）
//  └─ 未来：Qwen-VL / 其他 VLM 只需实现同一协议
//
//  上层只依赖协议 + VisionAIConfiguration（模型名集中管理），
//  相机 / UI / 引导引擎 / Apple Vision / 构图逻辑均不感知具体模型。
//

import Foundation

// MARK: - 视觉服务配置（Phase 0.5：模型名集中管理，禁止散落硬编码）

struct VisionAIConfiguration {
    /// 提供方显示名
    var provider: String = "DeepSeek"
    /// 视觉模型 ID（来自设置页「AI 助手 → 视觉模型」选择）
    var model: String = AIConfigurationStore.defaultVisionModel
    /// 接口基地址（与文本服务共用同一配置，支持自建代理）
    var baseURL: String
    /// API Key（与文本服务共用同一把 Key）
    var apiKey: String

    /// 当前可用配置：复用全局 AI 配置的 Key、接口地址与用户选择的视觉模型。
    /// 未配置 Key 时返回 nil（上层引导用户先去设置）。
    static func current() -> VisionAIConfiguration? {
        let store = AIConfigurationStore.shared
        guard let key = store.effectiveAPIKey else { return nil }
        return VisionAIConfiguration(
            model: store.visionModel,
            baseURL: store.baseURL,
            apiKey: key
        )
    }
}

// MARK: - 场景理解结果（Phase 0.3 契约）

/// 连通性测试的结构化输出
struct SceneAnalysis: Codable, Equatable {
    let scene: String
    let mainSubject: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case scene
        case mainSubject = "main_subject"
        case description
    }

    /// Phase 0.3 测试提示词：只允许返回 JSON
    static let analysisPrompt = """
    Analyze this image.

    Return JSON only, no markdown, no extra text:
    {
      "scene": "string",
      "main_subject": "string",
      "description": "string"
    }
    """

    /// 稳健解析：容忍 ```json 围栏与前后杂文本（取首个 { 到最后一个 }）
    static func parse(from text: String) -> SceneAnalysis? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SceneAnalysis.self, from: data)
    }
}

// MARK: - 服务协议（Phase 0.2：可替换的视觉抽象）

protocol VisionAIService {
    var configuration: VisionAIConfiguration { get }

    /// 发送图片（JPEG Data）+ 提示词，返回模型原始文本（主线程回调）
    /// - Parameter systemPrompt: 可选的系统角色提示（如"AI 摄影指导"）
    func sendVisionRequest(jpegData: Data, prompt: String,
                           systemPrompt: String?,
                           completion: @escaping (Result<String, Error>) -> Void)
}

extension VisionAIService {
    /// 无系统提示的便捷重载
    func sendVisionRequest(jpegData: Data, prompt: String,
                           completion: @escaping (Result<String, Error>) -> Void) {
        sendVisionRequest(jpegData: jpegData, prompt: prompt, systemPrompt: nil, completion: completion)
    }
}

extension VisionAIService {
    /// Phase 0.3：场景理解（图片 → SceneAnalysis 结构化结果）
    func analyzeScene(jpegData: Data,
                      completion: @escaping (Result<SceneAnalysis, Error>) -> Void) {
        sendVisionRequest(jpegData: jpegData, prompt: SceneAnalysis.analysisPrompt) { result in
            switch result {
            case .success(let text):
                if let analysis = SceneAnalysis.parse(from: text) {
                    completion(.success(analysis))
                } else {
                    completion(.failure(DeepSeekError.parseFailed))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - DeepSeek Vision 实现

final class DeepSeekVisionService: VisionAIService {

    let configuration: VisionAIConfiguration

    init(configuration: VisionAIConfiguration) {
        self.configuration = configuration
    }

    func sendVisionRequest(jpegData: Data, prompt: String,
                           systemPrompt: String? = nil,
                           completion: @escaping (Result<String, Error>) -> Void) {
        var trimmed = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard trimmed.lowercased().hasPrefix("https://"),
              let url = URL(string: trimmed + "/chat/completions") else {
            DispatchQueue.main.async { completion(.failure(DeepSeekError.invalidBaseURL)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 视觉请求带 base64 图片，给比文本更宽的超时
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenAI 兼容多模态消息格式：content 为 text + image_url（data URL）数组
        var messages: [[String: Any]] = []
        if let systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append([
            "role": "user",
            "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url",
                 "image_url": ["url": "data:image/jpeg;base64," + jpegData.base64EncodedString()]]
            ]
        ])

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "temperature": 0.3,
            "max_tokens": 800,
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard request.httpBody != nil else {
            DispatchQueue.main.async { completion(.failure(DeepSeekError.parseFailed)) }
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(DeepSeekError.noData)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(DeepSeekError.noData)) }
                return
            }
            switch http.statusCode {
            case 200:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async { completion(.success(content)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(DeepSeekError.parseFailed)) }
                }
            case 401, 403:
                DispatchQueue.main.async { completion(.failure(DeepSeekError.invalidAPIKey)) }
            case 429:
                DispatchQueue.main.async { completion(.failure(DeepSeekError.rateLimit)) }
            default:
                let bodyText = String(data: data.prefix(200), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(DeepSeekError.serverError("HTTP \(http.statusCode) \(bodyText)")))
                }
            }
        }.resume()
    }
}

// MARK: - 服务工厂

enum VisionAIServiceFactory {
    /// 按当前全局配置创建视觉服务；未配置 Key 时返回 nil
    static func make() -> (service: any VisionAIService, configuration: VisionAIConfiguration)? {
        guard let configuration = VisionAIConfiguration.current() else { return nil }
        return (DeepSeekVisionService(configuration: configuration), configuration)
    }
}
