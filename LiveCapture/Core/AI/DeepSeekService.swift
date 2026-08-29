//
//  DeepSeekService.swift
//  LiveCapture
//
//  DeepSeek API 服务
//
//  将结构化的 CompositionResult 转换成自然语言摄影建议。
//  遵循 AIAdviceProvider 协议，可与 MockPhotographer 无缝切换。
//
//  API 文档：https://api-docs.deepseek.com/
//

import Foundation

/// DeepSeek API 服务
final class DeepSeekService: AIAdviceProvider {

    // MARK: - 配置

    private let apiKey: String
    /// chat/completions 端点（支持设置页自定义接口地址）
    private let endpoint: URL
    private let model: String

    /// 当前请求的 task，用于取消
    private var currentTask: URLSessionDataTask?

    /// 请求代际标记：每次 generateAdvice 递增。
    /// 响应返回时代际不匹配即为被取消/过期的旧请求，直接丢弃，
    /// 否则迟到的旧响应会覆盖新一轮建议（此前只靠 cancel，超时兜不住竞态）。
    private var generation = 0

    // MARK: - 初始化

    /// - Parameters:
    ///   - apiKey: DeepSeek API Key
    ///   - baseURL: 接口基地址（默认官方地址；缺路径时自动补 /chat/completions）
    ///   - model: 模型 ID（deepseek-chat / deepseek-reasoner）
    init(apiKey: String,
         baseURL: String = AIConfigurationStore.defaultBaseURL,
         model: String = AIConfigurationStore.chatModel) {
        self.apiKey = apiKey
        self.model = model

        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.lowercased().hasSuffix("/chat/completions") {
            self.endpoint = URL(string: trimmed) ?? URL(string: "https://api.deepseek.com/v1/chat/completions")!
        } else {
            self.endpoint = URL(string: trimmed + "/chat/completions")
                ?? URL(string: "https://api.deepseek.com/v1/chat/completions")!
        }
    }

    // MARK: - 连接测试

    /// 连接测试结果
    enum ConnectionTestResult {
        /// 成功，附带往返延迟（秒）
        case success(latency: TimeInterval)
    }

    /// 测试 AI 服务连通性（设置页用）。
    /// 用 GET /models 鉴权 + 测可达性，不消耗 token。
    /// - Parameter completion: 主线程回调；成功返回往返延迟
    static func testConnection(
        apiKey: String,
        baseURL: String,
        completion: @escaping (Result<ConnectionTestResult, Error>) -> Void
    ) {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard trimmed.lowercased().hasPrefix("https://"),
              let modelsURL = URL(string: trimmed + "/models") else {
            DispatchQueue.main.async {
                completion(.failure(DeepSeekError.invalidBaseURL))
            }
            return
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let startTime = Date()
        URLSession.shared.dataTask(with: request) { data, response, error in
            let latency = Date().timeIntervalSince(startTime)

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(DeepSeekError.noData))
                }
                return
            }

            switch httpResponse.statusCode {
            case 200:
                DispatchQueue.main.async {
                    completion(.success(.success(latency: latency)))
                }
            case 401, 403:
                DispatchQueue.main.async {
                    completion(.failure(DeepSeekError.invalidAPIKey))
                }
            case 429:
                DispatchQueue.main.async {
                    completion(.failure(DeepSeekError.rateLimit))
                }
            default:
                let body = data.flatMap { String(data: $0.prefix(200), encoding: .utf8) } ?? ""
                DispatchQueue.main.async {
                    completion(.failure(DeepSeekError.serverError("HTTP \(httpResponse.statusCode) \(body)")))
                }
            }
        }.resume()
    }

    // MARK: - AIAdviceProvider

    func generateAdvice(
        for compositionResult: CompositionResult,
        completion: @escaping (Result<AIAdviceResult, Error>) -> Void
    ) {
        // 取消上一个请求（避免频繁请求时的竞态）
        cancel()
        generation += 1
        let requestGeneration = generation

        // 构建 prompt
        let prompt = buildPrompt(from: compositionResult)

        // 构建请求
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 无超时的话网络挂起时建议卡片会永远转圈
        request.timeoutInterval = 15
        
        // 请求体
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 500,
            "stream": false
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        
        // 发送请求
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // 迟到的旧响应一律丢弃，不让它覆盖新一轮结果
            guard requestGeneration == self.generation else { return }

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(DeepSeekError.noData))
                }
                return
            }

            // HTTP 状态码检查：401/429/5xx 之前全落进 parseFailed，
            // invalidAPIKey/rateLimit/serverError 三个错误永远不会被构造
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let error: DeepSeekError
                switch httpResponse.statusCode {
                case 401, 403:
                    error = .invalidAPIKey
                case 429:
                    error = .rateLimit
                default:
                    let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                    error = .serverError("HTTP \(httpResponse.statusCode) \(body)")
                }
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            // 解析响应
            do {
                let result = try self.parseResponse(data: data)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        
        currentTask = task
        task.resume()
    }
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Prompt 构建
    
    /// System Prompt：定义 AI 的身份和行为
    private var systemPrompt: String {
        """
        你是一位极简风格的手机摄影顾问，叫"小摄"。

        核心原则：
        - 只说最关键的，不说废话
        - 每条建议不超过 15 个字
        - 直接告诉用户"怎么做"，不说"为什么"
        - 用动词开头，比如"往左移"、"举高点"、"退两步"

        输出格式（严格遵守）：
        第一行：标题（6-8个字，是当前最核心的调整动作）
        第二行：核心建议（1条，最应该先做的，不超过15字）
        第三行：补充建议（1条，次要的，不超过15字）
        第四行：风格：xxx（两个字的风格名，如"电影感"、"小清新"）

        注意：
        - 不要提到分数、百分比、坐标
        - 不要说"建议你"、"可以"之类的客套话
        - 直接给动作指令
        - 如果没检测到人物，就给风景/建筑的构图建议

        --- 相机参数建议（新增，Phase 5）---

        在文字建议之后，额外输出一段 JSON 格式的相机参数建议，用 ```json 和 ``` 包裹。

        JSON 字段说明（所有字段都是可选的，不确定就不填）：
        - lens: 镜头建议，可选值：ultraWide, wide, telephoto, auto
        - brightness: 亮度偏好，可选值：auto, darker, brighter, preserveHighlights, night
        - motion: 运动优先级，可选值：freezeMotion, balanced, lowNoise
        - focus: 对焦偏好，可选值：auto, subjectLock, manual, macro
        - whiteBalance: 白平衡偏好，可选值：auto, warm, cool, natural
        - depth: 景深偏好，可选值：auto, shallow, deep

        判断规则参考：
        - 人像/特写 → telephoto + subjectLock + shallow
        - 风景/大场景 → ultraWide + auto + deep
        - 运动/抓拍 → freezeMotion + subjectLock
        - 夜景/暗光 → night + lowNoise
        - 美食/静物 → macro + shallow + natural
        - 黄金时刻/日落 → warm + preserveHighlights
        """
    }
    
    /// 根据构图结果构建用户 prompt
    private func buildPrompt(from result: CompositionResult) -> String {
        let person = result.person
        let breakdown = result.scoreBreakdown
        
        var prompt = "【当前画面分析数据】\n\n"
        
        // 总体评分
        prompt += "总体构图评分：\(result.score) / 100\n"
        prompt += "各维度得分：\n"
        prompt += "- 人物位置：\(breakdown.positionScore) 分\n"
        prompt += "- 人物大小：\(breakdown.sizeScore) 分\n"
        prompt += "- 头顶留白：\(breakdown.headRoomScore) 分\n"
        prompt += "- 边缘距离：\(breakdown.edgeDistanceScore) 分\n"
        prompt += "- 主体完整度：\(breakdown.subjectIntegrityScore) 分\n\n"
        
        // 人物检测
        if person.detected {
            prompt += "检测到人物：\(result.bodyCount) 个人体，\(result.faceCount) 张人脸\n"
            prompt += "人物位置：\(result.subjectPosition.displayName)\n"
            prompt += "人物占画面高度：\(Int(person.heightRatio * 100))%\n"
            prompt += "人物占画面宽度：\(Int(person.widthRatio * 100))%\n"
            prompt += "头顶留白比例：\(Int(person.headRoom * 100))%\n"
            prompt += "人物是否完整：\(person.isFullBody ? "是" : "否（被边缘裁切）")\n\n"
            prompt += "构图类型：\(result.compositionType.displayName)\n"
            prompt += "推荐移动方向：\(result.recommendedMove.displayName)\n"
            prompt += "推荐镜头：\(result.recommendedLens.displayName)\n"
            prompt += "推荐相机高度：\(result.recommendedCameraHeight.displayName)\n"
        } else {
            prompt += "⚠️ 没有检测到人物\n"
        }
        
        // 当前镜头信息
        prompt += "\n当前变焦：\(String(format: "%.1f", result.currentZoomFactor))x\n"
        if result.currentFocalLength > 0 {
            prompt += "等效焦距：\(result.currentFocalLength)mm\n"
        }
        
        prompt += "\n请根据以上数据，给用户一些摄影构图建议。"
        
        return prompt
    }
    
    // MARK: - 响应解析
    
    private func parseResponse(data: Data) throws -> AIAdviceResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DeepSeekError.parseFailed
        }
        
        // 先剔除给相机策略用的 ```json 代码块，否则 JSON 原文会被拼进建议文本展示给用户
        var displayContent = content
        if let blockRange = Self.cameraStrategyBlockRange(in: content) {
            displayContent = content.replacingCharacters(in: blockRange, with: "")
        }

        // 解析内容：第一行标题，中间建议，最后一行风格
        let lines = displayContent.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var title = "摄影建议"
        var style: String?
        var adviceLines: [String] = []
        
        for (index, line) in lines.enumerated() {
            if index == 0 && !line.hasPrefix("风格：") {
                title = line.replacingOccurrences(of: "标题：", with: "")
                    .replacingOccurrences(of: "【", with: "")
                    .replacingOccurrences(of: "】", with: "")
            } else if line.hasPrefix("风格：") {
                style = line.replacingOccurrences(of: "风格：", with: "")
            } else {
                // 去掉开头的序号（如 "1. "、"- "）
                let cleaned = line
                    .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression)
                if !cleaned.isEmpty {
                    adviceLines.append(cleaned)
                }
            }
        }
        
        let adviceText = adviceLines.joined(separator: "\n")
        
        // 解析 JSON 相机参数建议（Phase 5）
        let cameraStrategy = parseCameraStrategy(from: content)
        
        return AIAdviceResult(
            adviceText: adviceText,
            suggestedStyle: style,
            title: title,
            isRealAI: true,
            cameraStrategy: cameraStrategy
        )
    }
    
    // MARK: - 相机参数 JSON 解析（Phase 5）

    /// 定位回复中 ```json ... ``` 代码块（含围栏标记）的整体范围
    private static func cameraStrategyBlockRange(in content: String) -> Range<String.Index>? {
        let pattern = #"```(?:json)?\s*\n?[\s\S]*?\n?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) else {
            return nil
        }
        return Range(match.range, in: content)
    }

    /// 从 AI 回复文本中提取 ```json``` 代码块并解析为相机策略
    private func parseCameraStrategy(from content: String) -> CameraStrategySuggestion? {
        // 提取 ```json ... ``` 代码块
        let pattern = #"```(?:json)?\s*\n?([\s\S]*?)\n?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let jsonRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        
        let jsonString = String(content[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] else {
            return nil
        }
        
        var strategy = CameraStrategySuggestion()
        var hasAnyField = false
        
        // 镜头
        if let lensStr = jsonDict["lens"],
           let lens = LensPreference(rawValue: lensStr) {
            strategy.lensPreference = lens
            hasAnyField = true
        }
        
        // 亮度
        if let brightnessStr = jsonDict["brightness"],
           let brightness = BrightnessPreference(rawValue: brightnessStr) {
            strategy.brightnessPreference = brightness
            hasAnyField = true
        }
        
        // 运动
        if let motionStr = jsonDict["motion"],
           let motion = MotionPriority(rawValue: motionStr) {
            strategy.motionPriority = motion
            hasAnyField = true
        }
        
        // 对焦
        if let focusStr = jsonDict["focus"],
           let focus = FocusPreference(rawValue: focusStr) {
            strategy.focusPreference = focus
            hasAnyField = true
        }
        
        // 白平衡
        if let wbStr = jsonDict["whiteBalance"],
           let wb = WhiteBalancePreference(rawValue: wbStr) {
            strategy.whiteBalancePreference = wb
            hasAnyField = true
        }
        
        // 景深
        if let depthStr = jsonDict["depth"],
           let depth = DepthPreference(rawValue: depthStr) {
            strategy.depthPreference = depth
            hasAnyField = true
        }
        
        return hasAnyField ? strategy : nil
    }
}

// MARK: - 错误类型

enum DeepSeekError: Error {
    case noData
    case parseFailed
    case invalidAPIKey
    case invalidBaseURL
    case rateLimit
    case serverError(String)

    var localizedDescription: String {
        switch self {
        case .noData:
            return "服务器没有返回数据"
        case .parseFailed:
            return "解析 AI 响应失败"
        case .invalidAPIKey:
            return "API Key 无效"
        case .invalidBaseURL:
            return "接口地址无效（需要 https:// 开头）"
        case .rateLimit:
            return "请求太频繁，请稍后再试"
        case .serverError(let message):
            return "服务器错误：\(message)"
        }
    }
}
