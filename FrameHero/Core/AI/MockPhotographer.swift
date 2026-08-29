//
//  MockPhotographer.swift
//  FrameHero
//
//  Mock 模式：本地模拟 AI 摄影师
//  没有 API Key 或离线时使用，保证 App 可以正常演示
//
//  特点：
//  - 纯本地计算，不联网
//  - 根据 CompositionResult 生成有针对性的建议
//  - 建议质量不如真实 AI，但能跑通完整流程
//

import Foundation

/// 本地模拟摄影师
///
/// 根据构图结果的结构化数据，用本地规则生成自然语言建议。
/// 用于没有 API Key 或离线时的演示和调试。
final class MockPhotographer: AIAdviceProvider {
    
    /// 模拟延迟（秒），让用户感觉"AI 在思考"
    private let simulatedDelay: TimeInterval = 0.8
    
    /// 当前的取消标记
    private var isCancelled = false
    
    func generateAdvice(
        for compositionResult: CompositionResult,
        completion: @escaping (Result<AIAdviceResult, Error>) -> Void
    ) {
        isCancelled = false
        
        // 模拟网络延迟
        DispatchQueue.global().asyncAfter(deadline: .now() + simulatedDelay) { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            
            let advice = self.buildAdvice(from: compositionResult)
            DispatchQueue.main.async {
                completion(.success(advice))
            }
        }
    }
    
    func cancel() {
        isCancelled = true
    }
    
    // MARK: - 内部逻辑
    
    private func buildAdvice(from result: CompositionResult) -> AIAdviceResult {
        let score = result.score
        let breakdown = result.scoreBreakdown
        
        // 如果没检测到人，给风景/建筑建议
        guard result.person.detected else {
            var strategy = CameraStrategySuggestion()
            strategy.lensPreference = .ultraWide
            strategy.depthPreference = .deep
            strategy.whiteBalancePreference = .natural
            
            return AIAdviceResult(
                adviceText: "试试三分法构图\n找条引导线增加纵深感",
                suggestedStyle: "风景",
                title: "试试这样拍",
                isRealAI: false,
                cameraStrategy: strategy
            )
        }
        
        // 找出分数最低的两个维度（最需要改进的）
        let dimensions = [
            ("position", breakdown.positionScore, positionAdvice(for:)),
            ("subjectIntegrity", breakdown.subjectIntegrityScore, subjectIntegrityAdvice(for:)),
            ("headRoom", breakdown.headRoomScore, headRoomAdvice(for:)),
            ("edgeDistance", breakdown.edgeDistanceScore, edgeDistanceAdvice(for:)),
            ("size", breakdown.sizeScore, sizeAdvice(for:))
        ]
        
        let sorted = dimensions.sorted { $0.1 < $1.1 }
        let worst = sorted[0]
        let secondWorst = sorted[1]
        
        // 标题用最核心的建议
        let title = coreTitle(for: worst.0, score: worst.1)
        
        // 核心建议（最需要改进的维度）
        let coreTip = worst.2(result)
        
        // 补充建议（第二差的维度，如果分数差太多才显示）
        var secondTip = ""
        if secondWorst.1 < 75 && secondWorst.1 < worst.1 + 15 {
            secondTip = secondWorst.2(result)
        } else if score >= 80 {
            secondTip = "换个角度增加层次感"
        } else {
            secondTip = "保持稳定再按快门"
        }
        
        let adviceText = secondTip.isEmpty ? coreTip : "\(coreTip)\n\(secondTip)"
        
        // 推荐风格
        let style = suggestedStyle(for: result)
        
        // 模拟 AI 相机参数建议（Phase 5）
        let cameraStrategy = mockCameraStrategy(for: result)
        
        return AIAdviceResult(
            adviceText: adviceText,
            suggestedStyle: style,
            title: title,
            isRealAI: false,
            cameraStrategy: cameraStrategy
        )
    }
    
    // MARK: - 各维度建议生成
    
    private func coreTitle(for dimension: String, score: Int) -> String {
        switch dimension {
        case "position":
            return score < 60 ? "先挪位置" : "微调位置"
        case "subjectIntegrity":
            return "退一点"
        case "headRoom":
            return "调头顶留白"
        case "edgeDistance":
            return "别贴边"
        case "size":
            return score < 60 ? "调距离" : "调大小"
        default:
            return "微调一下"
        }
    }
    
    private func positionAdvice(for result: CompositionResult) -> String {
        let move = result.recommendedMove
        
        switch move {
        case .moveLeft:    return "往左移一点"
        case .moveRight:   return "往右移一点"
        case .moveUp:      return "蹲低一点"
        case .moveDown:    return "举高一点"
        case .stay:        return "位置刚刚好"
        case .moveCloser:  return "走近一点"
        case .moveFarther: return "往后退两步"
        case .unknown:     return "左右挪一下"
        }
    }
    
    private func sizeAdvice(for result: CompositionResult) -> String {
        let size = result.person.heightRatio
        
        if size < 0.4 {
            return "用 2x 拉近"
        } else if size > 0.85 {
            return "换广角拍"
        } else {
            return "大小刚刚好"
        }
    }
    
    private func headRoomAdvice(for result: CompositionResult) -> String {
        let headRoom = result.person.headRoom
        
        if headRoom < 0.05 {
            return "手机举高点"
        } else if headRoom > 0.25 {
            return "手机压低点"
        } else {
            return "留白刚刚好"
        }
    }
    
    private func edgeDistanceAdvice(for result: CompositionResult) -> String {
        return "往中间挪挪"
    }
    
    private func subjectIntegrityAdvice(for result: CompositionResult) -> String {
        if !result.person.isFullBody {
            return "往后退一步"
        }
        return "人物完整"
    }
    
    private func suggestedStyle(for result: CompositionResult) -> String {
        let score = result.score
        if score >= 85 {
            return "电影感"
        } else if score >= 70 {
            return "氛围感"
        } else {
            return "小清新"
        }
    }
    
    // MARK: - 模拟 AI 相机参数策略（Phase 5）
    
    /// 根据构图结果生成模拟的 AI 相机策略
    ///
    /// 模拟真实 AI 的判断逻辑，便于没有 API Key 时也能演示完整功能。
    private func mockCameraStrategy(for result: CompositionResult) -> CameraStrategySuggestion {
        var strategy = CameraStrategySuggestion()
        let person = result.person
        
        // 镜头建议
        switch result.recommendedLens {
        case .ultraWide:
            strategy.lensPreference = .ultraWide
        case .wide:
            strategy.lensPreference = .wide
        case .telephoto2x, .telephoto3x, .telephoto5x:
            strategy.lensPreference = .telephoto
        case .keepCurrent, .unknown:
            break // 保持 auto
        }
        
        // 人像场景
        if person.detected {
            strategy.focusPreference = .subjectLock
            strategy.depthPreference = .shallow
            strategy.whiteBalancePreference = .natural
            
            // 根据构图类型微调
            switch result.compositionType {
            case .ruleOfThirds, .leadingRoom:
                strategy.brightnessPreference = .auto
            default:
                break
            }
        } else {
            // 风景/场景
            strategy.depthPreference = .deep
            strategy.whiteBalancePreference = .natural
        }
        
        // 人物占比很小 → 用长焦拉近
        if person.detected && person.heightRatio < 0.4 {
            strategy.lensPreference = .telephoto
        }
        
        return strategy
    }
}
