//
//  AIAdviceProvider.swift
//  LiveCapture
//
//  AI 摄影建议提供者协议 —— 解耦 UI 与具体 AI 实现
//  未来接入 Qwen3-VL、本地 VLM 等，只需新增实现此协议的类
//

import Foundation

/// AI 生成的摄影建议结果
struct AIAdviceResult {
    /// 自然语言建议文本（直接显示给用户）
    let adviceText: String
    /// 建议的拍摄风格（如"电影感"、"氛围感"、"环境人像"）
    let suggestedStyle: String?
    /// 简短标题（用于 UI 顶部展示）
    let title: String
    /// 是否来自真实 AI（false 表示 Mock 模式）
    let isRealAI: Bool
    /// AI 推荐的结构化相机参数策略（Phase 5）
    /// 由云端 AI 解析生成，优先级高于本地引擎生成的策略
    var cameraStrategy: CameraStrategySuggestion?
}

/// AI 摄影建议提供者协议
///
/// 所有 AI 服务（DeepSeek、Qwen-VL、本地模型等）都必须实现此协议。
/// 上层（ViewModel / UI）只依赖协议，不依赖具体实现。
protocol AIAdviceProvider {
    
    /// 根据构图结果生成自然语言摄影建议
    /// - Parameters:
    ///   - compositionResult: 构图分析结果（结构化数据）
    ///   - completion: 完成回调，主线程调用
    func generateAdvice(
        for compositionResult: CompositionResult,
        completion: @escaping (Result<AIAdviceResult, Error>) -> Void
    )
    
    /// 取消当前正在进行的请求
    func cancel()
}

/// AI 服务类型
enum AIServiceType {
    case mock           // 本地模拟（无 API Key 时使用）
    case deepSeek       // DeepSeek API
    // 未来可扩展：qwenVL, localModel, gemini 等
}
