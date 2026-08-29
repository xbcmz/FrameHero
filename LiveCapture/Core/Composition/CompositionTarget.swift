//
//  CompositionTarget.swift
//  LiveCapture
//
//  目标构图状态
//  由 AI / 构图引擎推荐的理想构图
//  生成后保持不变，直到下一次 AI 分析
//

import Foundation
import CoreGraphics

/// 目标构图状态
///
/// 描述"理想的构图应该是什么样的"
/// 由 AI + CompositionEngine 分析后生成
/// 生成后固定不变，作为魔法棒引导的"导航终点"
struct CompositionTarget: Equatable {
    
    // MARK: - 目标位置
    
    /// 目标主体中心点 X [0, 1]
    var targetCenterX: CGFloat
    
    /// 目标主体中心点 Y [0, 1]
    var targetCenterY: CGFloat
    
    // MARK: - 目标大小
    
    /// 目标主体宽度占比 [0, 1]
    var targetWidthRatio: CGFloat
    
    /// 目标主体高度占比 [0, 1]
    var targetHeightRatio: CGFloat
    
    // MARK: - 目标头顶留白
    
    /// 目标头顶留白比例 [0, 1]
    var targetHeadRoom: CGFloat
    
    // MARK: - 推荐镜头
    
    /// 推荐使用的镜头
    var preferredLens: LensRecommendation
    
    // MARK: - 构图风格
    
    /// 推荐的构图类型
    var compositionStyle: CompositionType
    
    // MARK: - 目标分数
    
    /// 预计可以达到的分数 0-100
    var targetScore: Int
    
    // MARK: - AI 自然语言建议
    
    /// 建议标题（简短，如"往左移一点"）
    var adviceTitle: String
    
    /// 建议正文（1-2 条核心建议）
    var adviceText: String
    
    /// 推荐的摄影风格（如"电影感"、"氛围感"）
    var suggestedStyle: String
    
    // MARK: - 便捷属性
    
    /// 目标中心点（归一化坐标）
    var targetCenter: CGPoint {
        CGPoint(x: targetCenterX, y: targetCenterY)
    }
    
    // MARK: - 空状态
    
    /// 空的目标（还没生成时用）
    static var empty: CompositionTarget {
        CompositionTarget(
            targetCenterX: 0.5,
            targetCenterY: 0.5,
            targetWidthRatio: 0.5,
            targetHeightRatio: 0.7,
            targetHeadRoom: 0.12,
            preferredLens: .keepCurrent,
            compositionStyle: .center,
            targetScore: 85,
            adviceTitle: "等待分析",
            adviceText: "正在分析画面构图...",
            suggestedStyle: ""
        )
    }
}
