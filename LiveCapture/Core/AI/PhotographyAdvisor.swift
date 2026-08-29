//
//  PhotographyAdvisor.swift
//  LiveCapture
//
//  摄影顾问：协调 Vision 检测 → 构图评分 → AI 建议 的完整流程
//
//  这是 ViewModel 和底层服务之间的"协调层"。
//  ViewModel 只需要调用 analyzeFrame()，就能拿到完整的构图+AI建议结果。
//
//  数据流：
//  CVPixelBuffer
//    → AestheticCropDetector.detectPeople()
//    → RawDetections
//    → CompositionEngine.analyze()
//    → CompositionResult
//    → AIAdviceProvider.generateAdvice()
//    → AIAdviceResult
//

import Foundation
import UIKit

/// 完整的摄影分析结果（构图评分 + 目标构图 + AI 建议）
struct PhotographyAnalysisResult {
    /// 当前构图分析结果
    let composition: CompositionResult
    /// 目标构图（AI/引擎推荐的理想状态）
    let target: CompositionTarget
    /// AI 建议（可能还在加载中，所以是可选）
    let aiAdvice: AIAdviceResult?
    /// AI 推荐的相机参数策略（Phase 4）
    /// 只包含偏好建议，不含具体硬件参数
    var cameraStrategy: CameraStrategySuggestion = .init()
}

/// AI 推荐的相机策略建议（语义化偏好，不含硬件参数）
///
/// AI 根据构图分析结果和场景类型，
/// 推荐镜头、曝光、对焦、白平衡等偏好。
/// 最终是否应用由 ControlMode 决定。
struct CameraStrategySuggestion: Equatable {
    /// 推荐镜头
    var lensPreference: LensPreference = .auto
    /// 推荐亮度偏好
    var brightnessPreference: BrightnessPreference = .auto
    /// 推荐运动优先级
    var motionPriority: MotionPriority = .balanced
    /// 推荐对焦偏好
    var focusPreference: FocusPreference = .auto
    /// 推荐白平衡偏好
    var whiteBalancePreference: WhiteBalancePreference = .auto
    /// 推荐景深偏好
    var depthPreference: DepthPreference = .auto
    
    /// 用另一个策略合并当前策略（另一个优先级更高）
    ///
    /// 规则：只有当另一个策略的值不是"默认/自动"时才覆盖。
    /// 这样 AI 只需要返回它有明确判断的字段，
    /// 没提到的字段保留本地引擎的判断。
    mutating func merge(with other: CameraStrategySuggestion) {
        if other.lensPreference != .auto {
            lensPreference = other.lensPreference
        }
        if other.brightnessPreference != .auto {
            brightnessPreference = other.brightnessPreference
        }
        // motionPriority 默认是 balanced，不是 auto，所以用非默认判断
        if other.motionPriority != .balanced {
            motionPriority = other.motionPriority
        }
        if other.focusPreference != .auto {
            focusPreference = other.focusPreference
        }
        if other.whiteBalancePreference != .auto {
            whiteBalancePreference = other.whiteBalancePreference
        }
        if other.depthPreference != .auto {
            depthPreference = other.depthPreference
        }
    }
}

/// 摄影顾问
///
/// 负责协调 Vision 检测、构图评分和 AI 建议生成。
/// 上层 ViewModel 只需要和它打交道，不需要了解底层细节。
final class PhotographyAdvisor {
    
    // MARK: - 依赖
    
    private let detector: AestheticCropDetector
    private let compositionEngine: CompositionEngine
    private let aiProvider: AIAdviceProvider
    
    // MARK: - 状态
    
    /// 是否正在分析中（用于 UI 显示加载状态）
    private(set) var isAnalyzing = false
    
    /// 上一次的分析结果
    private(set) var lastResult: PhotographyAnalysisResult?
    
    /// AI 建议节流间隔（秒）—— 避免频繁调用 API
    private let aiThrottleInterval: TimeInterval = 3.0
    
    /// 上次 AI 请求时间
    private var lastAIRequestTime: Date?
    
    // MARK: - 初始化
    
    init(
        detector: AestheticCropDetector = AestheticCropDetector(),
        compositionEngine: CompositionEngine = CompositionEngine(),
        aiProvider: AIAdviceProvider? = nil
    ) {
        self.detector = detector
        self.compositionEngine = compositionEngine
        
        // 如果没传 aiProvider，自动根据配置选择
        if let provider = aiProvider {
            self.aiProvider = provider
        } else {
            let keyProvider = APIKeyProvider.shared
            if keyProvider.hasDeepSeekKey, let key = keyProvider.deepSeekAPIKey {
                self.aiProvider = DeepSeekService(apiKey: key)
            } else {
                self.aiProvider = MockPhotographer()
            }
        }
    }
    
    // MARK: - 公开方法
    
    /// 分析一帧画面
    ///
    /// - Parameters:
    ///   - pixelBuffer: 视频帧
    ///   - orientation: 图像方向
    ///   - zoomFactor: 当前变焦倍率
    ///   - focalLength: 当前等效焦距（mm）
    ///   - completion: 完成回调，主线程调用
    func analyzeFrame(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        zoomFactor: CGFloat,
        focalLength: Int,
        completion: @escaping (PhotographyAnalysisResult) -> Void
    ) {
        isAnalyzing = true

        // Step 1: Vision 检测
        detector.detectPeople(in: pixelBuffer, orientation: orientation) { [weak self] rawDetections in
            guard let self = self else { return }

            // Step 2: 构图评分（必须把真实变焦传进去，
            // 否则 recommendedLens 永远基于默认的 1.0x 计算）
            var compositionResult = self.compositionEngine.analyze(
                detections: rawDetections,
                zoomFactor: zoomFactor,
                focalLength: focalLength
            )

            // 补充镜头信息
            compositionResult.currentZoomFactor = zoomFactor
            compositionResult.currentFocalLength = focalLength
            
            // Step 2.5: 生成目标构图
            let target = self.compositionEngine.generateTarget(from: compositionResult)
            
            // Step 3: AI 建议（节流控制）
            let shouldRequestAI = self.shouldRequestAI(for: compositionResult)
            
            if shouldRequestAI {
                self.lastAIRequestTime = Date()
                
                self.aiProvider.generateAdvice(for: compositionResult) { [weak self] result in
                    guard let self = self else { return }
                    
                    self.isAnalyzing = false
                    
                    switch result {
                    case .success(let advice):
                        // 用 AI 返回的文字更新 target 里的建议
                        var finalTarget = target
                        finalTarget.adviceTitle = advice.title
                        finalTarget.adviceText = advice.adviceText
                        finalTarget.suggestedStyle = advice.suggestedStyle ?? target.suggestedStyle
                        
                        var analysis = PhotographyAnalysisResult(
                            composition: compositionResult,
                            target: finalTarget,
                            aiAdvice: advice
                        )
                        // 先用本地引擎生成基础策略
                        analysis.cameraStrategy = self.generateCameraStrategySuggestion(for: compositionResult)
                        // 如果 AI 返回了结构化策略，合并进去（AI 优先级更高）
                        if let aiStrategy = advice.cameraStrategy {
                            analysis.cameraStrategy.merge(with: aiStrategy)
                        }
                        self.lastResult = analysis
                        completion(analysis)
                    case .failure:
                        // AI 失败时，只返回构图结果和引擎生成的目标
                        var analysis = PhotographyAnalysisResult(
                            composition: compositionResult,
                            target: target,
                            aiAdvice: nil
                        )
                        analysis.cameraStrategy = self.generateCameraStrategySuggestion(for: compositionResult)
                        self.lastResult = analysis
                        completion(analysis)
                    }
                }
            } else {
                // 不需要请求 AI，直接返回构图结果 + 上次的 AI 建议
                self.isAnalyzing = false
                
                // 用上次的 AI 建议更新 target（如果有的话）
                var finalTarget = target
                if let lastAdvice = self.lastResult?.aiAdvice {
                    finalTarget.adviceTitle = lastAdvice.title
                    finalTarget.adviceText = lastAdvice.adviceText
                    finalTarget.suggestedStyle = lastAdvice.suggestedStyle ?? target.suggestedStyle
                }
                
                var analysis = PhotographyAnalysisResult(
                    composition: compositionResult,
                    target: finalTarget,
                    aiAdvice: self.lastResult?.aiAdvice
                )
                analysis.cameraStrategy = self.generateCameraStrategySuggestion(for: compositionResult)
                self.lastResult = analysis
                completion(analysis)
            }
        }
    }
    
    /// 取消当前分析
    func cancel() {
        aiProvider.cancel()
        isAnalyzing = false
    }
    
    // MARK: - 内部逻辑
    
    /// 判断是否应该发起新的 AI 请求
    private func shouldRequestAI(for newResult: CompositionResult) -> Bool {
        let now = Date()

        // 第一次必须请求
        guard let lastTime = lastAIRequestTime else {
            return true
        }

        // 节流：距离上次请求不足间隔时间，不请求
        if now.timeIntervalSince(lastTime) < aiThrottleInterval {
            return false
        }

        // 检测状态变化（从有人到没人，或从没人到有人）优先于分数阈值——
        // 场景类型变了就该重新请求，即使分数没变多少
        let wasPersonDetected = lastResult?.composition.person.detected ?? false
        if wasPersonDetected != newResult.person.detected {
            return true
        }

        // 分数变化较大时才请求
        if let lastScore = lastResult?.composition.score {
            let scoreDiff = abs(newResult.score - lastScore)
            if scoreDiff < 5 {
                return false  // 分数变化小于 5 分，不请求
            }
        }

        return true
    }
    
    // MARK: - 相机策略建议（Phase 4）
    
    /// 根据构图分析结果生成相机策略建议
    ///
    /// 这是引擎级的策略建议（不依赖网络 AI），
    /// 基于构图类型、主体数量、推荐镜头等信息生成。
    /// 后续可以接入 DeepSeek AI 生成更精准的策略。
    func generateCameraStrategySuggestion(
        for composition: CompositionResult
    ) -> CameraStrategySuggestion {
        var strategy = CameraStrategySuggestion()
        
        // MARK: 镜头建议
        switch composition.recommendedLens {
        case .ultraWide:
            strategy.lensPreference = .ultraWide
        case .wide:
            strategy.lensPreference = .wide
        case .telephoto2x, .telephoto3x, .telephoto5x:
            strategy.lensPreference = .telephoto
        case .keepCurrent, .unknown:
            strategy.lensPreference = .auto
        }
        
        // MARK: 对焦建议
        if composition.person.detected {
            // 有人像时保持连续自动对焦。
            // 注意不要在这里建议 subjectLock——本地引擎没有真实对焦点
            // （focusPointOfInterest 只有用户点按时才有），
            // 无点的 subjectLock 会触发单次锁焦，之后画面就再也不重新对焦了
            strategy.focusPreference = .auto
            // 人像 → 浅景深偏好
            strategy.depthPreference = .shallow
        } else {
            // 风景/场景 → 深景深
            strategy.depthPreference = .deep
            strategy.focusPreference = .auto
        }
        
        // MARK: 曝光建议
        // 默认自动，后续可以根据场景加更多判断
        strategy.brightnessPreference = .auto
        strategy.motionPriority = .balanced
        
        // MARK: 白平衡建议
        strategy.whiteBalancePreference = .auto
        
        return strategy
    }
}
