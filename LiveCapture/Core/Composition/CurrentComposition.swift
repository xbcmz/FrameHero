//
//  CurrentComposition.swift
//  LiveCapture
//
//  当前构图状态
//  表示实时画面中主体的位置、大小、留白等信息
//  由 Vision 检测 + CompositionEngine 每帧计算得出
//

import Foundation
import CoreGraphics

/// 当前构图状态
///
/// 描述"现在画面的构图是什么样的"
/// 所有坐标和大小都是归一化值 [0, 1]，不依赖具体分辨率
struct CurrentComposition: Equatable {
    
    // MARK: - 主体位置
    
    /// 主体中心点 X [0, 1]
    var subjectCenterX: CGFloat
    
    /// 主体中心点 Y [0, 1]
    var subjectCenterY: CGFloat
    
    // MARK: - 主体大小
    
    /// 主体宽度占画面宽度比例 [0, 1]
    var subjectWidthRatio: CGFloat
    
    /// 主体高度占画面高度比例 [0, 1]
    var subjectHeightRatio: CGFloat
    
    // MARK: - 人脸信息（可选）
    
    /// 人脸中心点 X [0, 1]，没检测到为 nil
    var faceCenterX: CGFloat?
    
    /// 人脸中心点 Y [0, 1]，没检测到为 nil
    var faceCenterY: CGFloat?
    
    // MARK: - 头顶留白
    
    /// 头顶留白占画面高度比例 [0, 1]
    /// 从画面顶部到人脸/主体顶部的距离
    var headRoomRatio: CGFloat
    
    // MARK: - 边缘距离
    
    /// 主体到四边的最小边距 [0, 1]
    /// 值越小说明越贴边
    var minEdgeDistance: CGFloat
    
    // MARK: - 完整度
    
    /// 主体是否完整（没有被画面边缘裁切）
    var isSubjectComplete: Bool
    
    // MARK: - 分数
    
    /// 当前总分 0-100
    var overallScore: Int
    
    // MARK: - 位置描述
    
    /// 主体在画面中的位置分类
    var subjectPosition: SubjectPosition
    
    // MARK: - 便捷属性
    
    /// 主体中心点（归一化）
    var subjectCenter: CGPoint {
        CGPoint(x: subjectCenterX, y: subjectCenterY)
    }
    
    /// 是否检测到人脸
    var hasFace: Bool {
        faceCenterX != nil && faceCenterY != nil
    }
    
    // MARK: - 空状态
    
    /// 空的构图状态（没有检测到主体时用）
    static var empty: CurrentComposition {
        CurrentComposition(
            subjectCenterX: 0.5,
            subjectCenterY: 0.5,
            subjectWidthRatio: 0,
            subjectHeightRatio: 0,
            faceCenterX: nil,
            faceCenterY: nil,
            headRoomRatio: 0,
            minEdgeDistance: 0,
            isSubjectComplete: false,
            overallScore: 0,
            subjectPosition: .center
        )
    }
}
