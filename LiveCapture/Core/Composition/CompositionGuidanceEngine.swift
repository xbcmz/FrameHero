//
//  CompositionGuidanceEngine.swift
//  LiveCapture
//
//  构图引导引擎
//  输入：当前构图 + 目标构图
//  输出：实时引导结果（方向、进度、是否达标）
//
//  纯计算类，无副作用，可每帧调用
//

import Foundation
import CoreGraphics

/// 构图引导引擎
///
/// 负责比较"当前构图"和"目标构图"，计算出用户应该如何操作
/// 这是"实时导航层"的核心——AI 设定目标，引擎负责导航
///
/// 设计原则：
/// - 纯计算，不依赖任何外部状态
/// - 高性能，每帧调用也不卡
/// - 可测试，输入输出明确
final class CompositionGuidanceEngine {
    
    // MARK: - 配置参数
    
    /// 位置容差（归一化）
    /// 主体位置偏差小于这个值，就算"对齐了"
    var positionTolerance: CGFloat = 0.04  // 4% 的画面宽度/高度
    
    /// 大小容差（归一化）
    /// 主体大小偏差小于这个值，就算"合适了"
    var sizeTolerance: CGFloat = 0.06  // 6% 的画面高度
    
    /// 对齐锁定所需时间（秒）
    /// 保持对齐超过这个时间，才算"真正达标"
    var lockDuration: TimeInterval = 0.8
    
    // MARK: - 私有状态
    
    /// 对齐开始时间
    private var alignedStartTime: Date?
    
    // MARK: - 初始化
    
    init() {}
    
    // MARK: - 核心计算
    
    /// 计算引导结果
    /// - Parameters:
    ///   - current: 当前构图状态
    ///   - target: 目标构图状态
    ///   - viewSize: 视图大小（用于转换坐标）
    /// - Returns: 引导结果
    func compute(
        current: CurrentComposition,
        target: CompositionTarget,
        viewSize: CGSize
    ) -> GuidanceResult {
        
        // 1. 计算水平方向
        let dx = target.targetCenterX - current.subjectCenterX
        let horizontalDir = directionFor(delta: dx, tolerance: positionTolerance)
        
        // 2. 计算垂直方向
        let dy = target.targetCenterY - current.subjectCenterY
        let verticalDir = directionFor(delta: dy, tolerance: positionTolerance)
        
        // 3. 计算距离方向（基于高度差）
        let dHeight = target.targetHeightRatio - current.subjectHeightRatio
        let distanceDir = distanceDirectionFor(delta: dHeight, tolerance: sizeTolerance)
        
        // 4. 计算进度
        let progress = calculateProgress(
            current: current,
            target: target,
            dx: dx,
            dy: dy,
            dHeight: dHeight
        )
        
        // 5. 计算视图坐标
        let currentPoint = CGPoint(
            x: current.subjectCenterX * viewSize.width,
            y: current.subjectCenterY * viewSize.height
        )
        let targetPoint = CGPoint(
            x: target.targetCenterX * viewSize.width,
            y: target.targetCenterY * viewSize.height
        )
        
        // 6. 判断是否对齐
        let positionOk = abs(dx) < positionTolerance && abs(dy) < positionTolerance
        let sizeOk = abs(dHeight) < sizeTolerance
        let isAligned = positionOk && sizeOk
        
        // 7. 计算对齐持续时间
        let alignedDuration = calculateAlignedDuration(isAligned: isAligned)
        
        return GuidanceResult(
            horizontalDirection: horizontalDir,
            verticalDirection: verticalDir,
            distanceDirection: distanceDir,
            progress: progress,
            currentScore: current.overallScore,
            targetScore: target.targetScore,
            isAligned: isAligned,
            alignedDuration: alignedDuration,
            targetPointInView: targetPoint,
            currentPointInView: currentPoint
        )
    }
    
    /// 重置状态（切换目标时调用）
    func reset() {
        alignedStartTime = nil
    }
    
    // MARK: - 方向计算
    
    /// 根据偏差值计算方向
    private func directionFor(delta: CGFloat, tolerance: CGFloat) -> MoveDirection {
        if abs(delta) < tolerance {
            return .stay
        } else if delta > 0 {
            // 目标在当前位置的"正方向"
            // 对于 X：目标在右边 → 手机需要往右移（画面里的主体就往左移？不对...）
            // 注意：主体在画面中偏左，想让主体到右边，手机需要往左移
            // 但对用户来说，"向右移"更容易理解为"把主体移到右边"
            // 所以我们返回的是"主体需要移动的方向"，用户直觉上对应手机移动方向
            return .moveRight
        } else {
            return .moveLeft
        }
    }
    
    /// 计算距离方向（靠近/远离）
    private func distanceDirectionFor(delta: CGFloat, tolerance: CGFloat) -> MoveDirection {
        if abs(delta) < tolerance {
            return .stay
        } else if delta > 0 {
            // 目标更大 → 需要靠近
            return .moveCloser
        } else {
            // 目标更小 → 需要远离
            return .moveFarther
        }
    }
    
    // MARK: - 进度计算
    
    /// 计算整体进度 0-1
    private func calculateProgress(
        current: CurrentComposition,
        target: CompositionTarget,
        dx: CGFloat,
        dy: CGFloat,
        dHeight: CGFloat
    ) -> CGFloat {
        
        // 位置偏差（归一化到 0-1，0=完全对齐，1=差很远）
        let positionDistance = sqrt(dx * dx + dy * dy)
        let maxPositionDistance: CGFloat = 0.5  // 最大可能偏差（从一边到另一边）
        let positionProgress = 1.0 - min(1.0, positionDistance / maxPositionDistance)
        
        // 大小偏差（归一化）
        let sizeDistance = abs(dHeight)
        let maxSizeDistance: CGFloat = 0.6  // 最大可能大小偏差
        let sizeProgress = 1.0 - min(1.0, sizeDistance / maxSizeDistance)
        
        // 分数进度
        let scoreProgress: CGFloat
        if target.targetScore > 0 {
            scoreProgress = min(1.0, CGFloat(current.overallScore) / CGFloat(target.targetScore))
        } else {
            scoreProgress = 0
        }
        
        // 加权平均
        // 位置权重最高（因为这是用户最直观的调整）
        // 大小其次，分数作为参考
        let weightedProgress = positionProgress * 0.5 + sizeProgress * 0.3 + scoreProgress * 0.2
        
        return min(1.0, max(0.0, weightedProgress))
    }
    
    // MARK: - 对齐持续时间
    
    /// 计算对齐持续时间
    private func calculateAlignedDuration(isAligned: Bool) -> TimeInterval {
        if isAligned {
            if alignedStartTime == nil {
                alignedStartTime = Date()
            }
            return Date().timeIntervalSince(alignedStartTime ?? Date())
        } else {
            alignedStartTime = nil
            return 0
        }
    }
}

// MARK: - 便捷扩展

extension CompositionGuidanceEngine {
    
    /// 检查是否已锁定（保持对齐超过锁定时间）
    var isLocked: Bool {
        guard let startTime = alignedStartTime else { return false }
        return Date().timeIntervalSince(startTime) >= lockDuration
    }
}
