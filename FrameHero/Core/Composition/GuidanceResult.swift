//
//  GuidanceResult.swift
//  FrameHero
//
//  实时引导结果
//  由 CompositionGuidanceEngine 每帧计算得出
//  告诉用户"现在应该怎么操作"以及"离目标还有多远"
//

import Foundation
import CoreGraphics

// MARK: - 引导状态

/// 引导状态：描述当前构图与目标的接近程度
enum GuidanceState {
    /// 调整中（距离目标还比较远）
    case adjusting
    /// 接近最佳（已经很接近了）
    case nearlyOptimal
    /// 达到最佳（可以拍了）
    case optimal
    
    /// 状态显示文字
    var displayText: String {
        switch self {
        case .adjusting: return "继续调整"
        case .nearlyOptimal: return "接近最佳"
        case .optimal: return "这个角度可以拍"
        }
    }
    
    /// 状态图标（SF Symbol）
    var iconName: String {
        switch self {
        case .adjusting: return "arrow.triangle.2.circlepath"
        case .nearlyOptimal: return "sparkles"
        case .optimal: return "checkmark.circle.fill"
        }
    }
}

/// 实时引导结果
///
/// 描述"用户现在应该怎么移动手机才能达到目标构图"
/// 由 CompositionGuidanceEngine 每帧计算
struct GuidanceResult: Equatable {
    
    // MARK: - 方向指引
    
    /// 水平方向指引
    var horizontalDirection: MoveDirection
    
    /// 垂直方向指引
    var verticalDirection: MoveDirection
    
    /// 距离方向指引（靠近/远离）
    var distanceDirection: MoveDirection
    
    // MARK: - 进度
    
    /// 当前进度 0-1
    /// 0 = 刚起步，1 = 完全达到目标
    var progress: CGFloat
    
    /// 当前总分 0-100
    var currentScore: Int
    
    /// 目标总分 0-100
    var targetScore: Int
    
    // MARK: - 对齐状态
    
    /// 是否达到目标（在容差范围内）
    var isAligned: Bool
    
    /// 保持对齐的持续时间（秒）
    var alignedDuration: TimeInterval
    
    /// 引导状态（根据进度自动判断）
    var state: GuidanceState {
        if isAligned && alignedDuration >= 0.5 {
            return .optimal
        } else if progress >= 0.85 {
            return .nearlyOptimal
        } else {
            return .adjusting
        }
    }
    
    // MARK: - 目标点位置
    
    /// 目标点在视图中的位置（points）
    /// 给魔法棒圆圈显示用
    var targetPointInView: CGPoint?
    
    // MARK: - 当前点位置
    
    /// 当前主体点在视图中的位置（points）
    /// 给魔法棒圆圈显示用
    var currentPointInView: CGPoint?
    
    // MARK: - 便捷属性
    
    /// 水平方向是否需要移动
    var needsHorizontalAdjustment: Bool {
        horizontalDirection != .stay
    }
    
    /// 垂直方向是否需要移动
    var needsVerticalAdjustment: Bool {
        verticalDirection != .stay
    }
    
    /// 距离是否需要调整
    var needsDistanceAdjustment: Bool {
        distanceDirection != .stay
    }
    
    /// 是否完全不需要调整
    var isPerfect: Bool {
        !needsHorizontalAdjustment && !needsVerticalAdjustment && !needsDistanceAdjustment
    }
    
    /// 进度百分比字符串（如 "78%"）
    var progressText: String {
        "\(Int(progress * 100))%"
    }
    
    // MARK: - 空状态
    
    /// 空的引导结果（还没有目标时用）
    static var empty: GuidanceResult {
        GuidanceResult(
            horizontalDirection: .unknown,
            verticalDirection: .unknown,
            distanceDirection: .unknown,
            progress: 0,
            currentScore: 0,
            targetScore: 0,
            isAligned: false,
            alignedDuration: 0,
            targetPointInView: nil,
            currentPointInView: nil
        )
    }
}
